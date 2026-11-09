-- Aviation obstruction lights and flood-lamp glows (PLAN.md phase 5), ported from the mood study's beacons and
-- updateBeacons. Each beacon is a small bulb with a red glow, steady or flashing on its own clock; each flood lamp has
-- a tight bar glow plus a soft halo that only swells when there's haze to scatter in.
--
-- The glows are BillboardGuis on Terrain attachments, placed every frame: at the real spot for the near cameras, or
-- at the same spot in the far-camera copy (C + s(P - C), at s times the size) while it shows, so they sit in front
-- of and behind the same things either way. Billboards ignore Atmosphere, so the haze fades them here instead.

local Workspace = game:GetService("Workspace")

local Glows = {}
Glows.__index = Glows

local S = 1 / 0.28
local GLOW = "rbxassetid://87877243907028"
local TX, HW, TH = -11.6, 3.6, 88 -- service tower centre x, half width and roof height, metres
local RED = Color3.new(1, 0.045, 0.018)
local BULB_ON, BULB_OFF = Color3.new(1, 0.05, 0.02), Color3.new(0.12, 0.015, 0.01)
local FLOOD_WARM = Color3.new(1, 0.9, 0.74)
local FLOOD_POLES = { { 34, 34 }, { -34, 34 }, { 34, -34 }, { -34, -34 } }
local LAMP_HEIGHTS = { 16, 18.4, 20.8, 23.2 }

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Table metres, as the mood study places them.
local function beaconList()
	local rng = Random.new(1977)
	local list = {}
	local function beacon(x, y, z, mode, period)
		table.insert(list, {
			pos = Vector3.new(x, y, z),
			mode = mode,
			period = period or 1.2 + rng:NextNumber() * 0.7,
			phase = rng:NextNumber() * 8,
		})
	end
	beacon(TX, TH + 16.6, 0, "flash", 1.5)
	local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
	for _, c in corners do
		beacon(TX + c[1] * HW, TH + 0.6, c[2] * HW, "steady")
	end
	for i, c in corners do
		if i % 2 == 1 then -- every other corner, part way up
			local x, z = TX + c[1] * HW, c[2] * HW
			beacon(x + math.sign(x - TX) * 0.5, 44, z + math.sign(z) * 0.5, "steady")
		end
	end
	for _, deg in { 24, 144, 264 } do -- lightning masts
		local a = math.rad(deg)
		local x, z = math.cos(a) * 58, math.sin(a) * 58
		beacon(x, 118.6, z, "flash")
		beacon(x, 60, z + 0.8, "steady")
	end
	beacon(95, 60.4, -85, "steady") -- water tower
	for _, p in { { 320, -1900 }, { 160, 2300 }, { -700, -2800 } } do -- the distant pads' towers
		beacon(p[1] - 11, 82.6, p[2], "flash")
	end
	return list
end

local function billboard(name, w, h, color)
	local att = Instance.new("Attachment")
	att.Name = name
	local gui = Instance.new("BillboardGui")
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.ResetOnSpawn = false
	gui.Size = UDim2.new(w * S, 0, h * S, 0)
	gui.Parent = att
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = GLOW
	img.ImageColor3 = color
	img.Parent = gui
	return { att = att, gui = gui, w = w, h = h }
end

function Glows.new(parent)
	local self = setmetatable({}, Glows)
	local folder = Instance.new("Folder")
	folder.Name = "Glows"
	self.folder, self.items = folder, {}

	for _, b in beaconList() do
		local bulb = Instance.new("Part")
		bulb.Name = "BeaconBulb"
		bulb.Shape = Enum.PartType.Ball
		bulb.Size = Vector3.one * 0.52 * S
		bulb.Material = Enum.Material.Neon
		bulb.Color = BULB_OFF
		bulb.Anchored, bulb.CanCollide, bulb.CanTouch, bulb.CanQuery = true, false, false, false
		bulb.CastShadow = false
		bulb.Position = b.pos * S
		bulb.Parent = folder
		local g = billboard("BeaconGlow", 3.2, 3.2, RED)
		g.kind, g.pos, g.beacon, g.bulb = "beacon", b.pos, b, bulb
		table.insert(self.items, g)
	end

	for _, p in FLOOD_POLES do
		local toPad = -Vector3.new(p[1], 0, p[2]).Unit
		for _, hy in LAMP_HEIGHTS do
			local pos = Vector3.new(p[1], hy, p[2]) + toPad * 1.4 -- the lens face, off its bracket
			local bar = billboard("LampGlow", 3.2, 1.3, FLOOD_WARM)
			bar.kind, bar.pos = "lamp", pos
			local halo = billboard("LampHalo", 1, 1, FLOOD_WARM)
			halo.kind, halo.pos = "halo", pos
			table.insert(self.items, bar)
			table.insert(self.items, halo)
		end
	end

	for _, g in self.items do
		g.gui.Enabled = false
		g.att.Parent = Workspace.Terrain
	end
	folder.Parent = parent
	return self
end

-- camPos in studs; scale: the far-camera copy's scale while it shows, else nil. flood: 0..1, elev: sun elevation in
-- degrees, fog: the shot's haze density per metre (Look.fogDensity).
function Glows:update(time, camPos, scale, flood, elev, fog)
	local camM = camPos / S
	local night = 1 - smooth(-3, 12, elev)
	local hz = math.clamp((fog - 0.0003) / 0.001, 0, 1)
	local s = scale or 1
	for _, g in self.items do
		local d = (g.pos - camM).Magnitude
		local fade = math.exp(-(d * fog) ^ 2)
		local level, w, h
		if g.kind == "beacon" then
			local b = g.beacon
			local v = 1
			if b.mode == "flash" then -- filament warm-up and slow fade
				local ph = ((time + b.phase) % b.period) / b.period
				v = smooth(0, 0.05, ph) * (1 - smooth(0.28, 0.55, ph))
			end
			g.bulb.Color = BULB_OFF:Lerp(BULB_ON, v)
			level = 2.2 * v * fade * (0.3 + 0.7 * night)
			w, h = g.w, g.h
		else
			local grow = 1 + d / 900 -- a little bigger with distance, so it never vanishes
			if g.kind == "lamp" then
				level = flood * 1.3 * fade
				w, h = g.w * grow, g.h * grow
			else
				level = flood * (0.07 + 0.22 * hz) * fade * (0.4 + 0.6 * smooth(20, 150, d)) -- softer up close
				local size = (7 + 11 * hz) * math.min(grow, 3)
				w, h = size, size
			end
		end
		local on = level > 0.004
		g.gui.Enabled = on
		if on then
			-- a touch toward the camera, so the bulb or lamp housing doesn't cut the glow in half
			local p = g.pos * S
			p += (camPos - p).Unit * math.min(0.6 * S, (camPos - p).Magnitude * 0.5)
			g.att.WorldPosition = scale and camPos + (p - camPos) * s or p
			g.gui.Size = UDim2.new(w * S * s, 0, h * S * s, 0)
			g.gui.Brightness = level
		end
	end
end

return Glows
