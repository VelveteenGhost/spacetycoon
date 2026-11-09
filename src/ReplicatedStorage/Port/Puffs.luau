-- Exhaust puffs every camera has to see from wherever it is (PLAN.md phases 6 and 7): the contrail, the separation
-- gas, and the ground cloud as the far cameras see it. They're simulated in Lua in true space, as the mood study does,
-- and drawn as billboards placed into whichever space is live: real near the camera, the far-camera copy beyond it.
-- True-space simulation keeps them continuous across cuts and through the copy's rescales, which Roblox particles,
-- emitted into one space, can't do. The near cameras see the ground cloud as particles instead (Effects).
--
-- Billboards ignore lighting and Atmosphere, so each puff is coloured here: sunlit by height (the sun sets later
-- the higher you are), shaded as one mass, warmed by the flame and the floods, and faded into the haze.
--
-- The far cameras also get the flame as a short chain of glows here, since its particles live in real space too.

local Workspace = game:GetService("Workspace")

local Flight = require(script.Parent.Flight)
local smooth = Flight.smooth

local Puffs = {}
Puffs.__index = Puffs

local S = 1 / 0.28
local BILLOWS = { "rbxassetid://92443369380936", "rbxassetid://84261181024933", "rbxassetid://99218850171999" }
local PUFF = "rbxassetid://102549625842700"
local GLOW = "rbxassetid://87877243907028"
local WIND = Vector3.new(0.7, 0, 2.6) -- m/s
local NOZZLE_Y = 8
-- contrail level of detail: as the trail ages every other puff fades out at each threshold and the survivors grow
-- to cover the gap, so the count stays flat while the trail lasts minutes
local TRAIL_TIERS, TRAIL_GROW = { 6, 16, 36, 70 }, 1.42
-- The mood study keeps 720 ground and 680 trail puffs; a phone gets fewer and bigger ones.
local CAPS = { ground = 140, trail = 200, gas = 60 }
local GROUND_K = 0.16 -- of the mood study's spawn rates, to fit the cap
local GROUND_GROW = 1.5 -- and bigger puffs to keep the mass

local C = {
	sunLow = Color3.fromHex("ff9a4d"),
	sunHigh = Color3.fromHex("ffe8cc"),
	floodWarm = Color3.new(1, 0.9, 0.74),
	smokeGlow = Color3.new(1, 0.46, 0.15),
}

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function add(a, b)
	return Color3.new(math.min(1, a.R + b.R), math.min(1, a.G + b.G), math.min(1, a.B + b.B))
end

local function scale(c, k)
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- the far cameras' flame, as the mood study builds it: { distance down the plume, size, HDR colour, opacity } at sea
-- level for a white-hot inner chain and a wider orange outer one, packed closer than their bright cores so they read
-- as one tongue, and the warm halo
local FLAME = {}
for i = 0, 12 do
	local u = i / 12
	table.insert(FLAME, { 0.4 + u * 27, lerp(4.6, 3.2, u),
		Color3.new(lerp(32, 9, u), lerp(26, 4.6, u * u * 0.6 + u * 0.4), lerp(16, 1.4, math.sqrt(u))), lerp(0.95, 0.55, u) })
end
for i = 0, 9 do
	local u = i / 9
	table.insert(FLAME, { 1 + u * 46, lerp(6.6, 10, u), Color3.new(lerp(10, 1.2, u), lerp(5, 0.45, u), lerp(1.4, 0.1, u)),
		lerp(0.5, 0.2, u) })
end
table.insert(FLAME, { 6, 70, Color3.new(3.4, 1.7, 0.7), 0.22, halo = true })

local function makePool(n, kind)
	local pool = {}
	for i = 1, n do
		local att = Instance.new("Attachment")
		att.Name = "Puff"
		local gui = Instance.new("BillboardGui")
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.ClipsDescendants = false
		gui.Enabled = false
		gui.Parent = att
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = kind == "gas" and PUFF or BILLOWS[(i - 1) % 3 + 1]
		img.Parent = gui
		att.Parent = Workspace.Terrain
		table.insert(pool, { att = att, gui = gui, img = img, on = false, pos = Vector3.zero, vel = Vector3.zero })
	end
	pool.cur = 0 -- the next slot to try; loops over a pool use ipairs to skip it
	return pool
end

function Puffs.new()
	local self = setmetatable({}, Puffs)
	self.ground = makePool(CAPS.ground, "ground")
	self.trail = makePool(CAPS.trail, "trail")
	self.gas = makePool(CAPS.gas, "gas")
	self.flame = makePool(#FLAME, "gas")
	for i, f in FLAME do
		local p = self.flame[i]
		p.img.Image = GLOW
		local m = math.max(f[3].R, f[3].G, f[3].B)
		p.d, p.s, p.col, p.peak, p.op, p.halo = f[1], f[2], Color3.new(f[3].R / m, f[3].G / m, f[3].B / m), m, f[4], f.halo
	end
	self.acc = { trench = 0, ring = 0, column = 0, side = 0, trail = 0 }
	self.trailIdx = 0
	self.rng = Random.new(1977)
	self.cloudC = Vector3.new(0, 20, 40)
	return self
end

function Puffs:reset()
	for _, pool in { self.ground, self.trail, self.gas } do
		for _, p in ipairs(pool) do
			p.on = false
			p.gui.Enabled = false
		end
	end
	for k in self.acc do
		self.acc[k] = 0
	end
end

local function take(pool)
	local n = #pool
	for _ = 1, n do
		pool.cur = pool.cur % n + 1
		local p = pool[pool.cur]
		if not p.on then
			return p
		end
	end
	-- full: recycle the oldest
	local best, bt = nil, -1
	for _, p in ipairs(pool) do
		local t = p.age / p.life
		if t > bt then
			best, bt = p, t
		end
	end
	return best
end

function Puffs:spawn(pool, pos, vel, s0, s1, life, a, lift, drag)
	local p = take(pool)
	local r = self.rng
	p.on, p.age, p.life = true, 0, life
	p.pos, p.vel = pos, vel
	p.s0, p.s1, p.a, p.lift, p.drag = s0, s1, a, lift or 0, drag or 0
	p.shade = 0.82 + r:NextNumber() * 0.18
	p.jit = (r:NextNumber() - 0.5) * 40
	p.lodG, p.dieAt = 1, -1
	if pool == self.trail then
		self.trailIdx += 1
		p.idx = self.trailIdx
	end
	return p
end

-- Exhaust lit by the sun as seen from height y (metres): the sun sets later the higher you are, so a twilight
-- contrail catches gold light over a dark pad.
function Puffs:sunlit(y, look)
	local e2 = look.elev + math.deg(math.sqrt(2 * math.max(y, 0) / 6.371e6))
	local li = smooth(-1.5, 2.5, e2) * lerp(2.2, 3.6, smooth(2, 22, e2)) * look.sun * (1 + 0.5 * smooth(300, 6000, y))
	return add(scale(C.sunLow:Lerp(C.sunHigh, smooth(0, 18, e2)), li * 0.46), look.amb)
end

-- st: the Flight state; dt: sim step; look: { elev, sun (weather's sun factor), amb (Color3), fog (per metre),
-- fogCol, flood, sunDir }; view: { camM (true camera, metres), place = function(pStuds) -> rendered studs, size factor,
-- far (the far-camera copy is live: show its ground cloud and flame), sunAngle (degrees, the sun's way on screen) }.
-- Without look and view it only simulates (a seek catches up this way, in coarse steps).
function Puffs:update(st, dt, t, look, view)
	local r = self.rng
	local thrust, alt = st.thrust, st.alt
	local stack = Flight.stack(st)
	local nozzle = stack:PointToWorldSpace(Vector3.new(0, NOZZLE_Y, 0))
	local down = -stack.UpVector
	local acc = self.acc

	if dt > 0 and thrust > 0.01 then
		-- ground cloud: the pad feeds it until the vehicle is a few hundred metres up
		local gf = thrust * (1 - smooth(110, 420, alt)) * GROUND_K
		local push = 1 + smooth(8, 30, alt) * 1.1
		acc.trench += dt * gf * 13
		acc.ring += dt * gf * 9
		acc.column += dt * (alt < 30 and gf * 6 or 0)
		acc.side += dt * gf * 6
		local G = GROUND_GROW
		while acc.trench >= 1 do
			acc.trench -= 1
			local z = 72 - r:NextNumber() ^ 2 * 58
			self:spawn(self.ground, Vector3.new((r:NextNumber() - 0.5) * 7, 2.5, z),
				Vector3.new((r:NextNumber() - 0.5) * 10, 1 + r:NextNumber() * 2.5, 20 + z / 72 * 32 + r:NextNumber() * 14),
				(11 + r:NextNumber() * 5) * G, (40 + r:NextNumber() * 26) * G, 30 + r:NextNumber() * 14, 0.96, 0.1 + r:NextNumber() * 0.3, 0.42)
		end
		while acc.ring >= 1 do
			acc.ring -= 1
			local a, sp = r:NextNumber() * math.pi * 2, (12 + r:NextNumber() * 14) * push
			self:spawn(self.ground, Vector3.new(st.posX + math.cos(a) * 10, 2.5, math.sin(a) * 10),
				Vector3.new(math.cos(a) * sp, 0.5 + r:NextNumber() * 2, math.sin(a) * sp),
				10 * G, (36 + r:NextNumber() * 24) * G, 28 + r:NextNumber() * 12, 0.95, 0.08 + r:NextNumber() * 0.25, 0.5)
		end
		while acc.column >= 1 do
			acc.column -= 1
			self:spawn(self.ground, Vector3.new((r:NextNumber() - 0.5) * 8, 5 + r:NextNumber() * 4, (r:NextNumber() - 0.5) * 8),
				Vector3.new((r:NextNumber() - 0.5) * 6, 2 + r:NextNumber() * 3, (r:NextNumber() - 0.5) * 6),
				6 * G, (26 + r:NextNumber() * 12) * G, 22 + r:NextNumber() * 10, 0.88, 0.5, 0.5)
		end
		while acc.side >= 1 do
			acc.side -= 1
			local sg = r:NextNumber() < 0.5 and 1 or -1
			self:spawn(self.ground, Vector3.new(st.posX + sg * 9, 2.5, (r:NextNumber() - 0.2) * 10),
				Vector3.new(sg * (18 + r:NextNumber() * 22), 0.5 + r:NextNumber() * 2, -4 + r:NextNumber() * 10),
				10 * G, (38 + r:NextNumber() * 26) * G, 30 + r:NextNumber() * 12, 0.95, 0.1 + r:NextNumber() * 0.3, 0.42)
		end
		-- contrail once the vehicle is off the pad, from where the flame ends
		if alt > 25 then
			local lenS = (0.35 + 0.65 * thrust) * (0.65 + 1.5 * smooth(60, 3000, alt)) * (1 + alt / 30000)
			local flameLen = 48 * lenS
			local s0 = 14 + alt * 0.004
			acc.trail += math.clamp(st.vel / (s0 * 0.3) + 8, 8, 18) * dt
			local side = stack.RightVector
			local zAxis = stack.LookVector
			while acc.trail >= 1 do
				acc.trail -= 1
				local a, back = r:NextNumber() * math.pi * 2, r:NextNumber() * st.vel * dt
				local pos = nozzle + down * (flameLen * 0.75 + r:NextNumber() * 6 + back)
					+ side * math.cos(a) * 1.5 + zAxis * math.sin(a) * 1.5
				local vel = down * (6 + r:NextNumber() * 6)
					+ Vector3.new(r:NextNumber() - 0.5, r:NextNumber() - 0.5, r:NextNumber() - 0.5) * 2
				self:spawn(self.trail, pos, vel, s0, 46 + alt * 0.022, 105 + r:NextNumber() * 30, 0.7, 0.25, 0.25)
			end
		end
	end

	-- separation: the pushers and pyros vent one fast ring of white gas from the interstage
	if st.sepBurst then
		st.sepBurst = false
		local axis = stack.UpVector
		for i = 1, 40 do
			local a = r:NextNumber() * math.pi * 2
			local radial = stack:VectorToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a)))
			local big = i <= 28
			local pos = stack:PointToWorldSpace(Vector3.new(math.cos(a) * (big and 2.4 or r:NextNumber() * 2), (big and 50.4 or 51) + r:NextNumber() * 3.6, math.sin(a) * (big and 2.4 or r:NextNumber() * 2)))
			local vel = (big and radial * (20 + r:NextNumber() * 30) + axis * (r:NextNumber() - 0.5) * 18
				or radial * (5 + r:NextNumber() * 10) - axis * (4 + r:NextNumber() * 10)) + st.bVel
			self:spawn(self.gas, pos, vel, big and 3 + r:NextNumber() * 3 or 2 + r:NextNumber() * 2,
				big and 30 + r:NextNumber() * 24 or 16 + r:NextNumber() * 12, big and 1.1 + r:NextNumber() * 1.3 or 1 + r:NextNumber(), big and 0.5 or 0.55)
		end
	end

	-- step and draw
	local drawing = view ~= nil
	local sunUp = drawing and smooth(-1, 3, look.elev) or 0
	local camM = drawing and view.camM
	local fog = drawing and look.fog
	local gSum, gN = Vector3.zero, 0
	local flamePos = alt < 25 and Vector3.new(st.posX, 4, 3) or nozzle + down * 20
	local glowI = thrust * (alt < 25 and 1 or 0.7)
	for _, kind in { "ground", "trail", "gas" } do
		local pool = self[kind]
		local show = drawing and (kind ~= "ground" or view.far)
		for _, p in ipairs(pool) do
			if not p.on then
				continue
			end
			p.age += dt
			local tt = p.age / p.life
			if tt >= 1 then
				p.on = false
				p.gui.Enabled = false
				continue
			end
			local drag = math.exp(-p.drag * dt)
			p.vel = Vector3.new(p.vel.X * drag, p.vel.Y * drag + p.lift * dt * (1 - tt), p.vel.Z * drag)
			local ww = smooth(0, 0.3, tt)
			local w = WIND
			if kind == "trail" then -- winds strengthen up to jet-stream height
				local hq = math.min(p.pos.Y, 12000)
				local m = 1 + hq / 800
				w = Vector3.new(WIND.X * m + math.sin(hq / 1800) * 6 * (hq / 3000), 0, WIND.Z * m)
			elseif kind == "gas" then
				w = Vector3.zero
			end
			p.pos += (p.vel + w * ww) * dt
			local lodA = 1
			if kind == "trail" then
				local tiers = 0
				for i, at in TRAIL_TIERS do
					if p.age < at then
						break
					end
					if p.idx % bit32.lshift(2, i - 1) ~= 0 then
						if p.dieAt < 0 then
							p.dieAt = p.age
						end
						break
					end
					tiers += 1
				end
				p.lodG += (TRAIL_GROW ^ tiers - p.lodG) * (1 - math.exp(-dt * 0.8))
				if p.dieAt >= 0 then
					lodA = 1 - smooth(0, 2.5, p.age - p.dieAt)
					if lodA <= 0 then
						p.on = false
						p.gui.Enabled = false
						continue
					end
				end
			end
			local size
			if kind == "gas" then
				size = lerp(p.s0, p.s1, 1 - (1 - tt) ^ 2)
			else
				size = lerp(p.s0, p.s1, 1 - (1 - tt) ^ 2.2) * p.lodG
			end
			local minY = kind == "trail" and size * 0.32 or (kind == "ground" and 1.5 + size * 0.17 or -1e9)
			if p.pos.Y < minY then
				p.pos = Vector3.new(p.pos.X, minY, p.pos.Z)
			end
			local opacity
			if kind == "gas" then
				opacity = p.a * smooth(0, 0.04, tt) * (1 - smooth(0.12, 1, tt))
			else
				opacity = p.a * lodA * smooth(0, kind == "trail" and 0.015 or 0.1, tt)
					* (1 - smooth(kind == "trail" and 0.55 or 0.5, 1, tt))
			end
			if kind == "ground" then
				gSum += p.pos
				gN += 1
			end
			if not show then
				p.gui.Enabled = false
				continue
			end

			-- colour: sunlit by height, the cloud's own shadow, the floods and the flame, then the haze
			local col = self:sunlit(p.pos.Y, look)
			if kind == "gas" then
				col = scale(col, 1.1)
			else
				col = scale(col, p.shade)
			end
			if kind == "ground" then
				local d = p.pos - self.cloudC
				local sunSide = d.Magnitude > 0.01 and math.clamp(d.Unit:Dot(look.sunDir) * 0.5 + 0.5, 0, 1) or 0.5
				local top = smooth(0, 40, p.pos.Y - self.cloudC.Y * 0.4)
				col = scale(col, lerp(1, lerp(0.55, 1.08, sunSide * 0.6 + top * 0.4), sunUp) * 1.35)
				if look.flood > 0 and p.pos.Y < 45 and p.pos.X ^ 2 + p.pos.Z ^ 2 < 9000 then
					col = add(col, scale(C.floodWarm, look.flood * 0.12))
				end
			end
			if glowI > 0 and kind ~= "gas" then
				local r2 = alt < 25 and 8100 or 6400
				local d2 = (p.pos - flamePos).Magnitude ^ 2
				col = add(col, scale(C.smokeGlow, glowI * 2 * r2 / (r2 + d2)))
			end
			local dist = (p.pos - camM).Magnitude
			col = col:Lerp(look.fogCol, 1 - math.exp(-(dist * fog) ^ 2))

			local pos, k = view.place(p.pos * S)
			p.att.WorldPosition = pos
			p.gui.Size = UDim2.new(size * S * k, 0, size * S * k, 0)
			p.img.ImageColor3 = col
			p.img.ImageTransparency = 1 - opacity
			p.img.Rotation = view.sunAngle + p.jit
			p.gui.Enabled = opacity > 0.004
		end
	end
	if gN > 0 then
		self.cloudC = gSum / gN
	end

	if not drawing then
		return
	end

	-- the far cameras' flame
	local on = view.far and thrust > 0.01
	local flick = 0.9 + math.sin(t * 47) * 0.05 + math.sin(t * 83.7) * 0.04
	local lenS = (0.35 + 0.65 * thrust) * (0.65 + 1.5 * smooth(60, 3000, alt)) * (1 + alt / 30000)
	local ex = math.min(1 + alt / 6000, 2)
	local hot = thrust * flick / (1 + alt / 9000)
	for _, f in ipairs(self.flame) do
		f.gui.Enabled = on
		if on then
			local pos, k = view.place((nozzle + down * f.d * (f.halo and 2 or 1) * lenS) * S)
			local size = f.halo and math.min(150, f.s * (1 + alt / 9000)) or f.s * ex * math.max(1, lenS * 0.5)
			f.att.WorldPosition = pos
			f.gui.Size = UDim2.new(size * S * k, 0, size * S * k, 0)
			f.img.ImageColor3 = f.col
			f.img.ImageTransparency = 1 - f.op
			f.gui.Brightness = f.peak * (f.halo and thrust / (1 + alt / 6000) or hot) * 0.25
		end
	end
end

return Puffs
