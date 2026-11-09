-- Far-camera proxy (PLAN.md phase 4b). Roblox stops drawing objects beyond a quality-dependent distance (the
-- complex is gone by about 2,000 studs at the lowest level and 6,000 at level 10; distant ground tiles go too), so
-- from the far cameras the launch site vanishes on phones. While such a camera is live, this shows a client-side
-- copy of the site scaled about the camera: each point P maps to C + s(P - C). From C it looks identical, the same
-- size and place on screen, but it sits within draw distance. The real parts are hidden meanwhile; their CFrames
-- still drive the copy, so animation carries over.
--
-- The ground is copied as flat bands (land, sand, wet sand, sea) with a square hole around the camera, so the real
-- ground and surf stay in the foreground. A real ground point at distance r and its copy line up on screen, so the
-- hole's edge has no seam. Anything standing in the hole must come from the copy too (the press-site flag): the
-- copied ground passes in front of real objects just below eye level, however big the hole.

local Workspace = game:GetService("Workspace")

local FarProxy = {}
FarProxy.__index = FarProxy

FarProxy.FAR = 700 -- studs: the copy's farthest site content sits this far from the camera
FarProxy.NEAR = 800 -- studs: cameras closer than this to the pad see the real site
FarProxy.HOLE = 400 -- studs: the real ground stays real within this half-width square around the camera
local RESCALE = 0.2 -- rescale only when the ideal scale drifts by this fraction (sizes are costly to rewrite)
local MIN_LIGHT_RANGE = 5 -- studs: Roblox draws nothing from a light with a range of a couple of studs (Nov 9)
local PROXY_LIGHT_GAIN = 6 -- the copy's floods, reaching only a few studs, need this much more to read from afar
local S = 1 / 0.28

-- Ground bands along x, table metres, matching SceneBuilder's land, beach and sea. They reach at least 40 km from
-- the camera, and six times its height once it climbs with the vehicle, so the edge stays near the horizon. Smooth
-- plastic throughout: material textures are sized in studs, so on the scaled copy they would show 1/s too large.
local GROUND_REACH, GROUND_REACH_MAX = 40000, 600000
local HIGH = 2000 -- studs: above this the real ground is out of reach, so the copy has no hole under the camera
local GROUND_BANDS = {
	{ -math.huge, 441, Color3.fromRGB(103, 102, 70), Enum.Material.SmoothPlastic },
	{ 441, 540, Color3.fromRGB(184, 168, 136), Enum.Material.SmoothPlastic },
	{ 540, 560, Color3.fromRGB(122, 109, 88), Enum.Material.SmoothPlastic },
	{ 560, math.huge, Color3.fromRGB(29, 52, 70), Enum.Material.SmoothPlastic },
}

-- Above the sky (Look.SPACE_ALT) Realistic lighting has no sky left to light distant ground, and a sunrise sun only
-- grazes it, so the bands glow instead, in their colours seen through the haze.
local HAZE = Color3.new(0.55, 0.63, 0.75)

function FarProxy:setGroundGlow(on)
	if on ~= self.groundGlow then
		self.groundGlow = on
		self.holeCentre = nil -- rebuild
	end
end

local function groundReach(camPos)
	return math.clamp(6 * camPos.Y / S, GROUND_REACH, GROUND_REACH_MAX) * S
end

local function quiet(part)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.CastShadow = false -- shadows would land on the real ground under the copy, in the wrong place
end

-- sources: { { model = Instance, name = string } }; the group named "VEH" stays real for the onboard camera.
function FarProxy.new(sources)
	local self = setmetatable({}, FarProxy)
	local root = Instance.new("Model")
	root.Name = "FarProxy"
	self.root, self.entries, self.groups = root, {}, {}
	self.attachments, self.beams, self.realBeams, self.bones, self.lights = {}, {}, {}, {}, {}
	self.textures = {}
	self.groundEntries = {}

	for _, src in sources do
		local index = 0
		for _, d in src.model:GetDescendants() do
			if d:IsA("BasePart") then
				index += 1
				d:SetAttribute("ProxyIndex", index)
			elseif d:IsA("Beam") then
				table.insert(self.realBeams, d)
			end
		end
		local copy = src.model:Clone()
		copy.Parent = root
		local group = { name = src.name, reals = {}, proxies = {} }
		local byIndex, realBones = {}, {}
		for _, d in src.model:GetDescendants() do
			if d:IsA("BasePart") then
				byIndex[d:GetAttribute("ProxyIndex")] = d
				table.insert(group.reals, d)
			elseif d:IsA("Bone") then
				realBones[d.Name] = d
			end
		end
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				quiet(d)
				table.insert(self.entries, { proxy = d, real = byIndex[d:GetAttribute("ProxyIndex")], size = d.Size })
				table.insert(group.proxies, d)
			elseif d:IsA("Attachment") then
				table.insert(self.attachments, { att = d, pos = d.Position }) -- bones too: their offsets scale with the mesh
				if d:IsA("Bone") and realBones[d.Name] then
					table.insert(self.bones, { proxy = d, real = realBones[d.Name] }) -- the flag's wave carries over
				end
			elseif d:IsA("Beam") then
				table.insert(self.beams, { beam = d, w0 = d.Width0, w1 = d.Width1, c0 = d.CurveSize0, c1 = d.CurveSize1 })
			elseif d:IsA("Texture") then
				table.insert(self.textures, { tex = d, u = d.StudsPerTileU, v = d.StudsPerTileV }) -- the surf
			elseif d:IsA("Light") then
				d.Shadows = false -- a shadow map can't resolve the copy's few-stud geometry
				d:SetAttribute("ProxyGain", PROXY_LIGHT_GAIN) -- Look.setFloods applies it (matched on the wide shot)
				table.insert(self.lights, { light = d, range = d.Range }) -- the floods light the copy at its own scale
			end
		end
		self.groups[src.name] = group
	end

	-- Beams anchored outside the copied models (the mast guys end on Terrain attachments) get a stand-in anchor part.
	for _, b in self.beams do
		for _, key in { "Attachment0", "Attachment1" } do
			local a = b.beam[key]
			if a and not a:IsDescendantOf(root) then
				local part = Instance.new("Part")
				part.Name = "ProxyAnchor"
				part.Size = Vector3.new(0.1, 0.1, 0.1)
				part.Transparency = 1
				quiet(part)
				part.CFrame = CFrame.new(a.WorldPosition)
				part.Parent = root
				local stand = Instance.new("Attachment")
				stand.CFrame = a.WorldCFrame.Rotation -- at the part's centre, which sits on the anchor
				stand.Parent = part
				b.beam[key] = stand
				table.insert(self.entries, { proxy = part, base = part.CFrame, size = part.Size })
			end
		end
	end

	self.active, self.scale, self.exclude, self.holeCentre = false, nil, nil, nil
	self:rebuildArrays()
	return self
end

function FarProxy:rebuildArrays()
	self.all, self.proxyParts, self.cfs = {}, {}, {}
	for _, list in { self.entries, self.groundEntries } do
		for _, e in list do
			table.insert(self.all, e)
			table.insert(self.proxyParts, e.proxy)
		end
	end
end

-- The ground copy: each band minus the hole, tiled so no scaled tile passes Roblox's 2048-stud limit.
function FarProxy:buildGround(camPos)
	for _, e in self.groundEntries do
		e.proxy:Destroy()
	end
	self.groundEntries = {}
	local s = self.scale
	local tile = 2000 / s
	local thick = 0.05 / s
	local h = camPos.Y < HIGH and FarProxy.HOLE or 0
	local hx0, hx1, hz0, hz1 = camPos.X - h, camPos.X + h, camPos.Z - h, camPos.Z + h
	local reach = groundReach(camPos)
	self.groundReach = reach
	local function rect(x0, x1, z0, z1, color, material)
		local x = x0
		while x < x1 - 1e-3 do
			local w = math.min(tile, x1 - x)
			local z = z0
			while z < z1 - 1e-3 do
				local d = math.min(tile, z1 - z)
				local p = Instance.new("Part")
				p.Name = "ProxyGround"
				if self.groundGlow then
					local c = color:Lerp(HAZE, 0.35) -- Neon is steep: 0.7 of this reads as daylight through haze (Nov 9)
					p.Color, p.Material = Color3.new(c.R * 0.7, c.G * 0.7, c.B * 0.7), Enum.Material.Neon
				else
					p.Color, p.Material = color, material
				end
				quiet(p)
				local size = Vector3.new(w, thick, d)
				p.Size = size * s
				p.Parent = self.root
				table.insert(self.groundEntries, { proxy = p, base = CFrame.new(x + w / 2, -thick / 2, z + d / 2), size = size })
				z += d
			end
			x += w
		end
	end
	local z0, z1 = camPos.Z - reach, camPos.Z + reach
	for _, band in GROUND_BANDS do
		local x0, x1 = math.max(band[1] * S, camPos.X - reach), math.min(band[2] * S, camPos.X + reach)
		local color, material = band[3], band[4]
		if x1 <= x0 then
			continue
		elseif h == 0 or hx1 <= x0 or hx0 >= x1 then
			rect(x0, x1, z0, z1, color, material)
		else
			local cx0, cx1 = math.max(x0, hx0), math.min(x1, hx1)
			if x0 < cx0 then
				rect(x0, cx0, z0, z1, color, material)
			end
			if cx1 < x1 then
				rect(cx1, x1, z0, z1, color, material)
			end
			rect(cx0, cx1, z0, hz0, color, material)
			rect(cx0, cx1, hz1, z1, color, material)
		end
	end
	self.holeCentre = camPos
	self:rebuildArrays()
end

local function setHidden(group, hidden)
	local v = hidden and 1 or 0
	for _, p in group.reals do
		p.LocalTransparencyModifier = v
	end
end

function FarProxy:setScale(s)
	self.scale = s
	for _, e in self.entries do
		e.proxy.Size = e.size * s
	end
	for _, a in self.attachments do
		a.att.Position = a.pos * s
	end
	for _, b in self.beams do
		b.beam.Width0, b.beam.Width1 = b.w0 * s, b.w1 * s
		b.beam.CurveSize0, b.beam.CurveSize1 = b.c0 * s, b.c1 * s
	end
	for _, l in self.lights do
		l.light.Range = math.max(l.range * s, MIN_LIGHT_RANGE)
	end
	for _, x in self.textures do
		x.tex.StudsPerTileU, x.tex.StudsPerTileV = x.u * s, x.v * s
	end
end

function FarProxy:activate(exclude)
	for name, group in self.groups do
		local useProxy = name ~= exclude
		setHidden(group, useProxy)
		for _, p in group.proxies do
			p.LocalTransparencyModifier = useProxy and 0 or 1
		end
	end
	for _, b in self.realBeams do
		b.Enabled = false
	end
	self.root.Parent = Workspace
	self.active, self.exclude = true, exclude
end

function FarProxy:deactivate()
	for _, group in self.groups do
		setHidden(group, false)
	end
	for _, b in self.realBeams do
		b.Enabled = true
	end
	self.root.Parent = nil
	self.active, self.exclude, self.holeCentre = false, nil, nil
end

-- Call every frame after the real parts are placed. camPos and pad are in studs.
function FarProxy:update(camPos, pad, mode, vehiclePos)
	if (camPos - pad).Magnitude <= FarProxy.NEAR then
		if self.active then
			self:deactivate()
		end
		return
	end
	local exclude = mode == "onboard" and "VEH" or nil
	if not self.active or exclude ~= self.exclude then
		self:activate(exclude)
	end
	-- The farthest site content: range ops, the distant pads and the tree belts reach about 6 km from the pad,
	-- plus wherever the vehicle has climbed to.
	local maxD = math.max((camPos - pad).Magnitude + 23000, (camPos - vehiclePos).Magnitude + 300)
	local ideal = FarProxy.FAR / maxD
	local rescaled = false
	if not self.scale or math.abs(ideal / self.scale - 1) > RESCALE then
		self:setScale(ideal)
		rescaled = true
	end
	local flat = Vector3.new(camPos.X, 0, camPos.Z)
	local reachDrift = self.groundReach and math.abs(groundReach(camPos) / self.groundReach - 1) > 0.25
	if rescaled or reachDrift or not self.holeCentre
		or (flat - self.holeCentre * Vector3.new(1, 0, 1)).Magnitude
			> (camPos.Y < HIGH and FarProxy.HOLE / 3 or self.groundReach * 0.1)
	then
		self:buildGround(camPos)
	end
	local s = self.scale
	local offset = camPos * (1 - s)
	for i, e in self.all do
		local cf = e.real and e.real.CFrame or e.base
		self.cfs[i] = CFrame.new(cf.Position * s + offset) * cf.Rotation
	end
	Workspace:BulkMoveTo(self.proxyParts, self.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	for _, b in self.bones do
		b.proxy.Transform = b.real.Transform
	end
end

return FarProxy
