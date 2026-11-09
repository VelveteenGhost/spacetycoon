-- Edit-time builder for the Sunrise on the Pad set (PLAN.md phase 3). Re-runnable: it clears what it built, then
-- places the origin-modelled templates by the manifest's rules, strings the wires, and lays the ground and sea.
-- Positions are table metres (origin at the pad centre, +X east to the ocean, Y up), converted to studs here.
--
-- Run from Studio: require(game.ServerStorage.PortTools.SceneBuilder:Clone()).build()
-- Progress is written to Workspace.Port's BuildStatus attribute.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local S = 1 / 0.28 -- studs per metre
local SHORE = 470 -- metres; the mood study's shoreline

-- Ground and sea extents, metres. The sea is Terrain water; the land is flat parts, cheaper than Terrain this size.
local LAND_X0 = -12000
local LAND_Z = 10000
local DUNE_X0, DUNE_X1 = 441, 487 -- 46 m dune centred at SHORE - 6
local WET_X0, BEACH_X1 = 540, 560 -- sand to 540, wet sand to 560, then water
local COAST_Z = 10000
local SEA_X1 = SHORE + 6000

local COLORS = {
	ground = Color3.fromRGB(103, 102, 70), -- #676646
	asphalt = Color3.fromRGB(52, 53, 58), -- #34353a
	paint = Color3.fromRGB(201, 166, 64), -- #c9a640
	concrete = Color3.fromRGB(140, 135, 126), -- #8c877e
	rail = Color3.fromRGB(163, 165, 168), -- #a3a5a8
	conductor = Color3.fromRGB(28, 28, 30), -- #1c1c1e
	wire = Color3.fromRGB(69, 72, 77), -- #45484d
	sand = Color3.fromRGB(184, 168, 136), -- #b8a888
	wetSand = Color3.fromRGB(122, 109, 88), -- #7a6d58
	duneGreen = Color3.fromRGB(140, 138, 94), -- #8c8a5e
	water = Color3.fromRGB(29, 52, 70), -- #1d3446
}

-- SITE_Car's notes: six paints (tints for the paint map) and the fixed per-car mix.
local CAR_PAINTS = {
	Color3.fromRGB(247, 247, 242),
	Color3.fromRGB(35, 37, 40),
	Color3.fromRGB(144, 147, 154),
	Color3.fromRGB(104, 37, 34),
	Color3.fromRGB(40, 59, 86),
	Color3.fromRGB(212, 204, 188),
}
local CAR_MIX = "0210514023012504120310245102301420"
local CAR_PARK_TOP = 0.14

local MASTS = { { 52.99, 23.59 }, { -46.92, 34.09 }, { -6.06, -57.68 } }
local MAST_ANCHORS = { { 121.87, 54.26 }, { -107.92, 78.41 }, { -13.94, -132.67 } }
local FLOOD_POLES = { { 34, 34, 135 }, { -34, 34, 45 }, { 34, -34, -135 }, { -34, -34, -45 } }
local DISTANT_PADS = { { 320, -1900 }, { 160, 2300 }, { -700, -2800 } }

local SceneBuilder = {}

local port, templates, placed

local function status(text)
	port:SetAttribute("BuildStatus", text)
end

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function folder(name, parent)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent
	return f
end

local function place(name, x, z, yawDeg, parent)
	local m = templates[name]:Clone()
	m:PivotTo(CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	m.Parent = parent
	return m
end

local function setShadows(root, on)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = on
		end
	end
end

-- A flat slab with its top at topY (metres), tiled so no part exceeds Roblox's 2048-stud limit.
local function slab(name, x0, x1, z0, z1, topY, color, material, parent)
	local sx0, sx1, sz0, sz1 = x0 * S, x1 * S, z0 * S, z1 * S
	local thick = 0.4
	local x = sx0
	while x < sx1 - 1e-3 do
		local w = math.min(2048, sx1 - x)
		local z = sz0
		while z < sz1 - 1e-3 do
			local d = math.min(2048, sz1 - z)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = material
			p.Color = color
			p.Size = Vector3.new(w, thick, d)
			p.CFrame = CFrame.new(x + w / 2, topY * S - thick / 2, z + d / 2)
			p.Parent = parent
			z += d
		end
		x += w
	end
end

local function box(name, size, centre, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Material = material
	p.Color = color
	p.Size = size * S
	p.CFrame = CFrame.new(centre * S)
	p.Parent = parent
	return p
end

-- Point an attachment's primary axis straight down, so a beam's curve sags under gravity.
local function axisDown(att)
	att.CFrame = CFrame.fromMatrix(att.Position, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
end

local function wire(name, a0, a1, widthM, color, curve0, curve1, segments, parent)
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = widthM * S
	b.Width1 = widthM * S
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(0)
	b.LightEmission = 0
	b.LightInfluence = 1
	b.FaceCamera = true
	b.CurveSize0 = curve0 * S
	b.CurveSize1 = curve1 * S
	b.Segments = segments
	b.Parent = parent
	return b
end

local function anchorAt(name, x, z)
	local a = Instance.new("Attachment")
	a.Name = name
	a.WorldPosition = Vector3.new(x * S, 0, z * S)
	a.Parent = Workspace.Terrain
	return a
end

---------------------------------------------------------------------------------------------------------------
-- mulberry32, as the mood study's R(): JS int32 semantics on bit32's unsigned values.

local function imul(a, b)
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	return bit32.band(al * bl + bit32.lshift(bit32.band(ah * bl + al * bh, 0xFFFF), 16), 0xFFFFFFFF)
end

local function mulberry32(seed)
	local s = bit32.band(seed, 0xFFFFFFFF)
	return function()
		s = bit32.band(s + 0x6D2B79F5, 0xFFFFFFFF)
		local t = imul(bit32.bxor(s, bit32.rshift(s, 15)), bit32.bor(1, s))
		t = bit32.bxor(bit32.band(t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t)), 0xFFFFFFFF), t)
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
end
SceneBuilder.mulberry32 = mulberry32

---------------------------------------------------------------------------------------------------------------

local function buildProps()
	local masts = folder("Masts", placed)
	local tops = {}
	for i, p in MASTS do
		local m = place("SITE_Mast", p[1], p[2], 0, masts)
		local top = m.SITE_Mast.WireTop
		axisDown(top)
		tops[i] = top
	end
	local wires = folder("Wires", masts)
	for i = 1, 3 do
		local j = i % 3 + 1
		-- 14 m sag at mid-span: a cubic Bezier sags 0.75 x the curve size when both ends pull down
		wire("Catenary" .. i .. j, tops[i], tops[j], 0.28, COLORS.wire, 14 / 0.75, -14 / 0.75, 24, wires)
		-- guy to a ground anchor at 2.3x the mast position; only the top end bends (sag 0.375 x curve size)
		local a = anchorAt("MastAnchor" .. i, MAST_ANCHORS[i][1], MAST_ANCHORS[i][2])
		wire("Guy" .. i, tops[i], a, 0.28, COLORS.wire, 5 / 0.375, 0, 16, wires)
	end

	local floods = folder("FloodPoles", placed)
	for _, p in FLOOD_POLES do
		place("SITE_FloodPole", p[1], p[2], p[3], floods)
	end

	local distant = folder("DistantPads", placed)
	for _, p in DISTANT_PADS do
		setShadows(place("SITE_DistantPad", p[1], p[2], 0, distant), false)
	end

	local cars = folder("Cars", placed)
	for i = 0, 33 do
		local m = place("SITE_Car", -662 + (i % 17) * 2.7, 58 + math.floor(i / 17) * 13, 90, cars)
		m:PivotTo(m:GetPivot() + Vector3.new(0, CAR_PARK_TOP * S, 0))
		local paint = tonumber(string.sub(CAR_MIX, i + 1, i + 1)) :: number
		m.SITE_Car_Paint:FindFirstChildOfClass("SurfaceAppearance").Color = CAR_PAINTS[paint + 1]
		m.Name = "SITE_Car_" .. i
	end
	task.wait()

	-- Perimeter fence: 147 slots on the r 140 ring, minus the road gap on the -X side.
	local fence = folder("Fence", placed)
	local posts = {}
	for i = 0, 146 do
		local a = math.rad(i * 360 / 147)
		local x, z = 140 * math.cos(a), 140 * math.sin(a)
		if not (x < 0 and math.abs(z) < 6) then
			local m = place("SITE_FencePost", x, z, 0, fence)
			m.Name = "FencePost_" .. i
			setShadows(m, false)
			table.insert(posts, { i = i, part = m.SITE_FencePost })
		end
	end
	local rails = folder("Rails", fence)
	for k, p in posts do
		local q = posts[k % #posts + 1]
		if (p.i + 1) % 147 == q.i then -- no rail across the road gap
			for _, rail in { "RailLow", "RailHigh" } do
				wire(rail .. p.i, p.part[rail], q.part[rail], 0.07, COLORS.rail, 0, 0, 1, rails)
			end
		end
	end
	task.wait()

	-- Power line along the access road: 40 poles, three sagging conductors per span.
	local power = folder("PowerLine", placed)
	local poles = {}
	for k = 0, 39 do
		local m = place("SITE_PowerPole", -160 - 48 * k, 11, 0, power)
		m.Name = "PowerPole_" .. k
		for n = 0, 2 do
			axisDown(m.SITE_PowerPole["Conductor" .. n])
		end
		poles[k] = m.SITE_PowerPole
	end
	local conductors = folder("Conductors", power)
	for k = 0, 38 do
		for n = 0, 2 do
			local name = "Conductor" .. n
			wire(name .. "_" .. k, poles[k][name], poles[k + 1][name], 0.03, COLORS.conductor, 1.6, -1.6, 10, conductors)
		end
	end
	task.wait()
end

-- Scrub and palmetto: the mood study's rule and random stream (VEG_Scrub_A's notes), 1,600 instances.
local function buildVegetation()
	local veg = folder("Vegetation", placed)
	local R = mulberry32(1977)
	for _ = 1, 41992 do
		R()
	end
	local function native(name)
		local part = templates[name][name]
		return part, part.Size, part.Position -- template pivot is the origin, so Position is the centre offset
	end
	local scrubs = { { native("VEG_Scrub_A") }, { native("VEG_Scrub_B") }, { native("VEG_Scrub_C") } }
	local palms = { { native("VEG_Palmetto_A") }, { native("VEG_Palmetto_B") } }

	local nearProps = 0 -- placements the notes' fallback skips would have caught; 0 if the stream is the mood study's
	local count, batch = 0, Instance.new("Folder")
	while count < 1600 do
		local cr = 90 + math.sqrt(R()) * 900
		local ca = R() * math.pi * 2
		local cx, cz = math.cos(ca) * cr, math.sin(ca) * cr
		local n = 3 + math.floor(R() * 7)
		local k = 0
		while k < n and count < 1600 do
			k += 1
			local x = cx + (R() - 0.5) * 26
			local z = cz + (R() - 0.5) * 26
			local r = math.sqrt(x * x + z * z)
			local skip = x > SHORE - 32
				or r < 86
				or (math.abs(z) < 9 and x < -70)
				or (x < -120 and x > -205 and z < -45 and z > -95)
				or (x < -135 and x > -195 and z < 0 and z > -60)
				or (x < -585 and x > -695 and z > 14 and z < 88)
				or (math.abs(z - 11) < 2.5 and x < -150)
			if not skip then
				local sc = 1.1 + R() * 2.4
				local isPalm = R() < 0.35
				local yaw = R() * 6.28
				local f
				if isPalm then
					f = Vector3.new(sc, sc, sc)
				else
					local kx, ky, kz = 1 + R() * 0.6, 0.45 + R() * 0.35, 1 + R() * 0.6
					f = Vector3.new(sc * kx / 1.3, sc * (0.25 + 0.851 * ky) / 0.782, sc * kz / 1.3)
				end
				R() -- colour index: the mood study draws it, so the stream stays aligned
				local cm = 0.8 + R() * 0.4
				local variant = isPalm and palms[math.floor(2 * (cm - 0.8) / 0.4) + 1]
					or scrubs[math.floor(3 * (cm - 0.8) / 0.4) + 1]
				local part, size, offset = variant[1], variant[2], variant[3]
				local c = part:Clone()
				c.Size = size * f
				c.CFrame = CFrame.new(x * S, 0, z * S)
					* CFrame.Angles(0, yaw, 0)
					* CFrame.new(offset * f)
					* part.CFrame.Rotation
				c.CastShadow = false
				c.Parent = batch
				count += 1
				local dS0 = math.sqrt((x + 70) ^ 2 + (z - 58) ^ 2)
				local dS1 = math.sqrt((x + 88) ^ 2 + (z - 42) ^ 2)
				local dW = math.sqrt((x - 95) ^ 2 + (z + 85) ^ 2)
				if dS0 < 12 or dS1 < 12 or dW < 6 or (x > -76 and x < -48 and z > -64 and z < -44) then
					nearProps += 1
				end
				if count % 200 == 0 then
					batch.Parent = veg
					batch = Instance.new("Folder")
					task.wait()
				end
			end
		end
	end
	batch.Parent = veg
	veg:SetAttribute("NearPropPlacements", nearProps)
	return nearProps
end

local function buildGround()
	local ground = folder("Ground", port)
	local land = folder("Land", ground)
	slab("Land", LAND_X0, DUNE_X0, -LAND_Z, LAND_Z, 0, COLORS.ground, Enum.Material.Grass, land)
	task.wait()

	local roads = folder("Roads", ground)
	slab("AccessRoad", -2077, -77, -3.5, 3.5, 0.14, COLORS.asphalt, Enum.Material.Asphalt, roads)
	slab("SpurRoad", -170, -160, -54, -3.5, 0.14, COLORS.asphalt, Enum.Material.Asphalt, roads)
	slab("HangarApron", -188, -142, -54, -42, 0.14, COLORS.asphalt, Enum.Material.Asphalt, roads)
	slab("CarPark", -667, -613, 51, 81, CAR_PARK_TOP, COLORS.asphalt, Enum.Material.Asphalt, roads)
	local dashes = folder("CentreLine", roads)
	for i = 0, math.floor((2070 - 82) / 9) - 1 do
		local x = -82 - i * 9
		slab("Dash", x - 1.5, x + 1.5, -0.08, 0.08, 0.15, COLORS.paint, Enum.Material.SmoothPlastic, dashes)
	end
	-- two small pad-side service buildings the export doesn't include
	local service = folder("ServiceBuildings", ground)
	box("ServiceBuilding", Vector3.new(14, 5, 10), Vector3.new(46, 2.5, -48), COLORS.concrete, Enum.Material.Concrete, service)
	box("ServiceBuilding", Vector3.new(8, 4, 8), Vector3.new(-40, 2, -60), COLORS.concrete, Enum.Material.Concrete, service)
	task.wait()
end

-- Dune, beach and sea in Terrain. Voxels are 4 studs; occupancy carries the dune's sub-voxel crest.
local function buildCoast()
	local T = Workspace.Terrain
	T:Clear()
	T.Decoration = false
	T.WaterColor = COLORS.water
	T.WaterReflectance = 1
	T.WaterTransparency = 0.1
	T.WaterWaveSize = 0.12
	T.WaterWaveSpeed = 8
	T:SetMaterialColor(Enum.Material.Sand, COLORS.sand)
	T:SetMaterialColor(Enum.Material.Grass, COLORS.duneGreen)
	T:SetMaterialColor(Enum.Material.Mud, COLORS.wetSand)

	local vx0 = math.floor(DUNE_X0 * S / 4) * 4
	local vx1 = math.ceil(BEACH_X1 * S / 4) * 4
	local nx, ny = (vx1 - vx0) / 4, 4 -- layers y -4..12 studs
	local zMax = math.ceil(COAST_Z * S / 4) * 4
	local CH = 256 -- voxels along z per write
	local z0 = -zMax
	while z0 < zMax do
		local nz = math.min(CH, (zMax - z0) / 4)
		local mats, occ = {}, {}
		for ix = 1, nx do
			local xm = (vx0 + (ix - 0.5) * 4) / S
			local mx, ox = {}, {}
			for iy = 1, ny do
				mx[iy], ox[iy] = {}, {}
			end
			for iz = 1, nz do
				local zm = (z0 + (iz - 0.5) * 4) / S
				local h, mat
				if xm < DUNE_X1 then
					local u = (xm - DUNE_X0) / (DUNE_X1 - DUNE_X0)
					local crest = (1.7 + 0.8 * math.sin(zm * 0.011) + 0.55 * math.sin(zm * 0.037 + 1.3))
						* (1 - smooth(4500, 6000, math.abs(zm)))
					h = 0.1 + math.max(0, crest) * math.sin(math.pi * math.clamp(u, 0, 1)) ^ 1.6
					mat = u < 0.45 and Enum.Material.Grass or Enum.Material.Sand
				elseif xm < WET_X0 then
					h, mat = 0.06, Enum.Material.Sand
				else
					h, mat = 0.075, Enum.Material.Mud
				end
				local hs = h * S
				for iy = 1, ny do
					local bottom = -4 + (iy - 1) * 4
					local o = math.clamp((hs - bottom) / 4, 0, 1)
					ox[iy][iz] = o
					mx[iy][iz] = o > 0 and mat or Enum.Material.Air
				end
			end
			mats[ix], occ[ix] = mx, ox
		end
		local region = Region3.new(Vector3.new(vx0, -4, z0), Vector3.new(vx1, 12, z0 + nz * 4))
		T:WriteVoxels(region, 4, mats, occ)
		z0 += nz * 4
		task.wait()
	end
	status("coast: sea")
	local sx0 = vx1
	local sx1 = math.ceil(SEA_X1 * S / 4) * 4
	local x = sx0
	while x < sx1 do
		local x2 = math.min(x + 2048, sx1)
		local z = -zMax
		while z < zMax do
			local z2 = math.min(z + 2048, zMax)
			T:FillRegion(Region3.new(Vector3.new(x, -4, z), Vector3.new(x2, 0, z2)), 4, Enum.Material.Water)
			z = z2
		end
		x = x2
		task.wait()
	end
end

-- Floodlights (PLAN.md phase 5). Roblox lights reach at most 120 studs (34 m), and the mood study's floods sit
-- 49 m from the vehicle, so each pole's SpotLight moves in along its own beam to 30 m out; the poles stay as props.
-- A warm SurfaceLight under each pole makes the pool on the apron. Look sets their brightness by sun elevation,
-- from the Brightness attribute at full flood.
-- The floods. The mood study throws one wide cone per pole over the vehicle, the mount and the apron, but a Roblox
-- light reaches 120 studs (34 m) at most and has little left near the end of its range, so each pole gets three cones
-- from 16-18 m out, on the line from its lamps (the upper vehicle, the middle, and the lower vehicle with the mount),
-- plus a pool light over the apron. Look sets their brightness from the Brightness attributes. Realistic lighting is
-- steep: these are matched to the mood study's blue hour on the mount shot at quality level 15 (Nov 9).
local FLOOD_CONES = {
	{ name = "Upper", target = Vector3.new(0, 52, 0), dist = 16, angle = 90, brightness = 0.08, shadows = false },
	{ name = "Mid", target = Vector3.new(0, 30, 0), dist = 16, angle = 90, brightness = 0.08, shadows = false },
	{ name = "Lower", target = Vector3.new(0, 10, 0), dist = 18, angle = 100, brightness = 0.35, shadows = true },
}
local function lightHolder(name, cf, rig)
	local holder = Instance.new("Part")
	holder.Name = name
	holder.Size = Vector3.new(0.4, 0.4, 0.4)
	holder.Transparency = 1
	holder.Anchored, holder.CanCollide, holder.CanTouch, holder.CanQuery = true, false, false, false
	holder.CastShadow = false
	holder.CFrame = cf
	holder.Parent = rig
	return holder
end
local function buildLights()
	local rig = folder("Lights", port)
	for i, p in FLOOD_POLES do
		local lamp = Vector3.new(p[1], 22.4, p[2])
		for _, cone in FLOOD_CONES do
			local pos = cone.target + (lamp - cone.target).Unit * cone.dist
			local holder = lightHolder("Flood" .. cone.name .. i, CFrame.lookAt(pos * S, cone.target * S), rig)
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = 120
			spot.Angle = cone.angle
			spot.Color = Color3.new(1, 0.9, 0.74)
			spot.Shadows = cone.shadows and i <= 2 -- two shadow casters, as in the mood study
			spot:SetAttribute("Brightness", cone.brightness)
			spot.Parent = holder
		end
		-- the apron pool, high enough that its 120-stud reach covers the mood study's 52 m glow
		local pool = lightHolder("FloodPool" .. i, CFrame.new(p[1] * 0.78 * S, 12 * S, p[2] * 0.78 * S), rig)
		local surface = Instance.new("SurfaceLight")
		surface.Face = Enum.NormalId.Bottom
		surface.Range = 120
		surface.Angle = 150
		surface.Color = Color3.new(1, 0.9, 0.74)
		surface.Shadows = false
		surface:SetAttribute("Brightness", 0.6)
		surface.Parent = pool
	end
end
SceneBuilder.buildLights = function()
	port = Workspace:WaitForChild("Port")
	local old = port:FindFirstChild("Lights")
	if old then
		old:Destroy()
	end
	buildLights()
end

function SceneBuilder.clear()
	port = Workspace:WaitForChild("Port")
	for _, name in { "Ground", "Lights" } do
		local old = port:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local site = port:WaitForChild("SITE")
	local old = site:FindFirstChild("Placed")
	if old then
		old:Destroy()
	end
	for _, a in Workspace.Terrain:GetChildren() do
		if a:IsA("Attachment") and string.sub(a.Name, 1, 10) == "MastAnchor" then
			a:Destroy()
		end
	end
end

function SceneBuilder.build(opts)
	opts = opts or {}
	SceneBuilder.clear()
	templates = ServerStorage:WaitForChild("PortTemplates")
	placed = folder("Placed", port.SITE)
	setShadows(port.SITE.Belts, false)
	local t0 = os.clock()
	status("props")
	buildProps()
	status("vegetation")
	local near = buildVegetation()
	status("ground")
	buildGround()
	buildLights()
	if opts.coast ~= false then
		status("coast: dune and beach")
		buildCoast()
	end
	status(string.format("done in %.1f s; vegetation near props: %d", os.clock() - t0, near))
	return port:GetAttribute("BuildStatus")
end

return SceneBuilder
