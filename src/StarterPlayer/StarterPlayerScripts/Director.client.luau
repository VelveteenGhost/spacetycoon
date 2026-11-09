-- Client-side director for the art test (PLAN.md phase 4): runs the sequence, flies the vehicle, swings the fuel arm
-- and clamps, cuts between the ten broadcast cameras, waves the press-site flag and drives the HUD. All of it is
-- local to the viewer; nothing replicates.
--
-- Controls: the deck, or keys 1 prop load, 2 static fire, 3 launch, A auto camera, C next camera, H overlay.
-- Testing from Studio (Client datamodel), via Workspace.Port attributes: Sequence ("hold" | "static" | "launch"),
-- Camera ("auto" | a camera name), SeekT (jump to that tRel), Paused (freeze time), Motion (false turns off the
-- handheld drift, to compare with the mood study's reference frames) and Proxy (false shows the real complex to
-- the far cameras).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Port = ReplicatedStorage:WaitForChild("Port")
local Flight = require(Port:WaitForChild("Flight"))
local Cams = require(Port:WaitForChild("BroadcastCameras"))
local Hud = require(Port:WaitForChild("Hud"))
local FarProxy = require(Port:WaitForChild("FarProxy"))
local Look = require(Port:WaitForChild("Look"))
local Glows = require(Port:WaitForChild("Glows"))
local Effects = require(Port:WaitForChild("Effects"))
local Puffs = require(Port:WaitForChild("Puffs"))

local S = 1 / 0.28
local SEEK_STEP = 1 / 30

local port = Workspace:WaitForChild("Port")
local camera = Workspace.CurrentCamera

local function toStuds(cf)
	return CFrame.new(cf.Position * S) * cf.Rotation
end

-- Vehicle rig: every part's frame on the pad, split into the booster and the upper stage.
local UPPER = { VEH_S2_Body = true, VEH_MVac = true, VEH_MVac_Inner = true, VEH_Fairing_A = true, VEH_Fairing_B = true }
local vehParts, vehBase, vehUpper = {}, {}, {}
for _, p in port:WaitForChild("VEH"):GetDescendants() do
	if p:IsA("BasePart") then
		table.insert(vehParts, p)
		table.insert(vehBase, p.CFrame)
		table.insert(vehUpper, UPPER[p.Name] == true)
	end
end

-- Hinged parts turn about the axis through their Hinge0 and Hinge1 attachments.
local function hinge(part)
	local p0, p1 = part:WaitForChild("Hinge0").WorldPosition, part:WaitForChild("Hinge1").WorldPosition
	return { part = part, base = part.CFrame, origin = p0, axis = (p1 - p0).Unit }
end
local function swing(h, angle)
	return CFrame.new(h.origin) * CFrame.fromAxisAngle(h.axis, angle) * CFrame.new(-h.origin) * h.base
end
local fuelArm = hinge(port:WaitForChild("TWR"):WaitForChild("TWR_FuelArm"))
local clamps = {}
for k = 0, 3 do
	table.insert(clamps, hinge(port:WaitForChild("PAD"):WaitForChild("PAD_Clamp_" .. k)))
end

-- Press-site flag: a travelling sine wave along the fly, 1.5 s per cycle (SITE_Flag's notes).
local flagRoot = port:WaitForChild("SITE"):WaitForChild("Flag"):WaitForChild("RootPart")
local flagBones = {}
for k = 0, 5 do
	flagBones[k] = flagRoot:FindFirstChild("Fly" .. k, true)
end
local FLAG_A = { 0.08, 0.13, 0.18, 0.23, 0.28, 0.33 }
local function waveFlag(t)
	local prev = 0
	for k = 0, 5 do
		local a = FLAG_A[k + 1] * math.sin(2 * math.pi * t / 1.5 - 2 * math.pi * (k + 0.5) / 4.8)
		if flagBones[k] then
			flagBones[k].Transform = CFrame.Angles(0, 0, a - prev) -- each Transform is relative to its parent
		end
		prev = a
	end
end

-- The far cameras see a scaled copy of the complex, since phones don't draw the real one that far out.
local site = port:WaitForChild("SITE")
local proxy = FarProxy.new({
	{ model = port.VEH, name = "VEH" },
	{ model = port.PAD, name = "PAD" },
	{ model = port.TWR, name = "TWR" },
	{ model = site:WaitForChild("Structures"), name = "Structures" },
	{ model = site:WaitForChild("Placed"), name = "Placed" },
	{ model = site:WaitForChild("Belts"), name = "Belts" },
	{ model = site:WaitForChild("Flag"), name = "Flag" },
	{ model = port:WaitForChild("Ground"):WaitForChild("ServiceBuildings"), name = "ServiceBuildings" },
	{ model = port:WaitForChild("Lights"), name = "Lights" },
	{ model = port:WaitForChild("Surf"), name = "Surf" },
})
local glows = Glows.new(port)
local surf = {} -- the foam textures, scrolled toward the beach
for _, d in port.Surf:GetDescendants() do
	if d:IsA("Texture") then
		table.insert(surf, d)
	end
end
local effects = Effects.new(port) -- after the copy is made, which doesn't carry particles
local puffs = Puffs.new()

-- Thrust history: sound and shake reach each camera at the speed of sound.
local hist = {}
local function pushHist(time, th)
	table.insert(hist, { time, th })
	while #hist > 2 and hist[1][1] < time - 12 do
		table.remove(hist, 1)
	end
end
local function thrustAt(time)
	for i = #hist, 1, -1 do
		if hist[i][1] <= time then
			return hist[i][2]
		end
	end
	return 0
end

local function commas(n)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end
local function hms(c)
	return string.format("%02d:%02d:%02d", c // 3600, (c // 60) % 60, c % 60)
end

local st = Flight.new("launch")
local rig = Cams.new()
local autoCam, overlayOn, paused = true, true, false
local sunPreset, wxPreset = "sunrise", "clear"
local lookKey, lookT, floodKey = "", 0, ""
local t, holdT, hudT, countdown = 0, 0, 1, 34 * 60 + 12
local cutAlpha = 0
local hud

local function refreshDeck()
	hud:setDeck(st.mode, autoCam, sunPreset, wxPreset, rig.mode)
end

-- Floating origin (Flight.origin): above 6 km the camera stands about 4.5 km over a render origin that follows it in
-- 1 km steps, so the vehicle and everything placed around it keep full precision 100 km out. The site and terrain
-- stay where they are; from up there they're 4.5 km down, under the copy's ground.
local ORIGIN_ON, ORIGIN_OFF = 6000, 5500 -- m, true camera height
local ORIGIN_LIFT, ORIGIN_DRIFT, ORIGIN_GRID = 4500, 2500, 1024 -- m

local function setOrigin(o)
	if o ~= Flight.origin then
		Cams.shift(rig, Flight.origin - o)
		Flight.origin = o
	end
end

local function placeOrigin()
	local o = Flight.origin
	local cam = rig.pos -- last frame's, from the origin
	if not cam then
		return
	end
	local high = (cam + o).Y > (o == Vector3.zero and ORIGIN_ON or ORIGIN_OFF)
	if not high then
		setOrigin(Vector3.zero)
	elseif o == Vector3.zero or (cam - Vector3.new(0, ORIGIN_LIFT, 0)).Magnitude > ORIGIN_DRIFT then
		local want, g = cam + o - Vector3.new(0, ORIGIN_LIFT, 0), ORIGIN_GRID
		setOrigin(Vector3.new(math.round(want.X / g) * g, math.round(want.Y / g) * g, math.round(want.Z / g) * g))
	end
end

local function startSeq(mode)
	st = Flight.new(mode)
	setOrigin(Vector3.zero)
	effects:reset()
	puffs:reset()
	hist = {}
	rig.aimSnap = true
	holdT = 0
	refreshDeck()
end

local function setSun(name)
	if Look.PRESETS[name] then
		sunPreset, lookKey = name, ""
		refreshDeck()
	end
end

local function setSky(name)
	if Look.WX[name] then
		wxPreset, lookKey = name, ""
		hud:setVisibility(Look.VIS[name])
		refreshDeck()
	end
end

local function seek(target)
	startSeq(st.mode)
	local since = 0
	while st.tRel < target do
		local step = math.min(SEEK_STEP, target - st.tRel)
		Flight.step(st, step)
		since += step
		if since >= 0.25 or st.sepBurst then -- the puffs catch up in coarse steps, so the contrail is there
			puffs:update(st, since, 0)
			since = 0
		end
	end
	rig.aimSnap = true
end

local function setCamera(mode)
	autoCam = mode == "auto"
	if not autoCam then
		Cams.set(rig, mode)
	end
	refreshDeck()
end

local function nextCamera()
	local i = table.find(Cams.LIST, rig.mode) or 0
	setCamera(Cams.LIST[i % #Cams.LIST + 1])
end

local function toggleOverlay()
	overlayOn = not overlayOn
	hud:setOverlayVisible(overlayOn)
end

hud = Hud.new(Players.LocalPlayer:WaitForChild("PlayerGui"), {
	onSequence = startSeq,
	onCamera = function(which)
		if which == "next" then
			nextCamera()
		else
			setCamera(which)
		end
	end,
	onToggleOverlay = toggleOverlay,
	onSun = setSun,
	onSky = setSky,
})
refreshDeck()

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.One then
		startSeq("hold")
	elseif k == Enum.KeyCode.Two then
		startSeq("static")
	elseif k == Enum.KeyCode.Three then
		startSeq("launch")
	elseif k == Enum.KeyCode.A then
		setCamera("auto")
	elseif k == Enum.KeyCode.C then
		nextCamera()
	elseif k == Enum.KeyCode.H then
		toggleOverlay()
	end
end)

port:GetAttributeChangedSignal("Sequence"):Connect(function()
	local m = port:GetAttribute("Sequence")
	if m == "hold" or Flight.LENGTH[m] then
		startSeq(m)
	end
end)
port:GetAttributeChangedSignal("Camera"):Connect(function()
	local m = port:GetAttribute("Camera")
	if m == "auto" or Cams.CAMS[m] then
		setCamera(m)
	end
end)
port:GetAttributeChangedSignal("SeekT"):Connect(function()
	local target = port:GetAttribute("SeekT")
	if typeof(target) == "number" and st.mode ~= "hold" then
		seek(target)
	end
end)
port:GetAttributeChangedSignal("Sun"):Connect(function()
	setSun(port:GetAttribute("Sun"))
end)
port:GetAttributeChangedSignal("Sky"):Connect(function()
	setSky(port:GetAttribute("Sky"))
end)
port:GetAttributeChangedSignal("Paused"):Connect(function()
	paused = port:GetAttribute("Paused") == true
end)

RunService:BindToRenderStep("PortDirector", Enum.RenderPriority.Camera.Value + 1, function(rawDt)
	local dt = paused and 0 or math.min(0.05, rawDt)
	t += dt
	holdT += dt
	countdown -= dt
	Flight.step(st, dt)

	-- Both sequences run their full length, then start again.
	local endT = st.mode ~= "hold" and Flight.LENGTH[st.mode] - Flight.LEAD
	if endT then
		cutAlpha = Flight.smooth(endT - 0.55, endT, st.tRel)
		if st.tRel > endT then
			startSeq(st.mode)
			cutAlpha = 0
		end
	else
		cutAlpha = 0
	end
	pushHist(t, st.thrust)
	if autoCam then
		local want = Cams.directorPick(st, holdT)
		if want ~= rig.mode then
			Cams.set(rig, want)
			refreshDeck()
		end
	end
	placeOrigin()
	local origin = Flight.origin * S -- studs
	local trueAlt = function(v) -- metres above the ground, for a point given from the origin
		return v.Y + Flight.origin.Y
	end

	-- vehicle, fuel arm and clamps
	local stack, upper = toStuds(Flight.stack(st)), toStuds(Flight.upper(st))
	local cfs = table.create(#vehParts)
	for i, base in vehBase do
		cfs[i] = (vehUpper[i] and upper or stack) * base
	end
	Workspace:BulkMoveTo(vehParts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	fuelArm.part.CFrame = swing(fuelArm, -1.25 * st.armRetract)
	local clampAngle = st.mode == "launch" and math.rad(25) * Flight.smooth(0, 0.4, st.tRel) or 0
	for _, c in clamps do
		c.part.CFrame = swing(c, clampAngle)
	end

	-- camera
	local nozzle = Flight.stack(st):PointToWorldSpace(Vector3.new(0, 8, 0))
	local heard = rig.mode == "onboard" and st.thrust or thrustAt(t - ((rig.pos or nozzle) - nozzle).Magnitude / 343)
	local vp = camera.ViewportSize
	local motion = port:GetAttribute("Motion") ~= false
	rig.minSpan = port:GetAttribute("MinSpan") -- test override for Cams.MIN_SPAN
	local cf, fov, label = Cams.update(rig, st, t, dt, heard, vp.X / math.max(vp.Y, 1), motion)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fov
	camera.CFrame = toStuds(cf)
	if port:GetAttribute("Proxy") ~= false then
		proxy:setGroundGlow(trueAlt(rig.lensPos or rig.pos) > Look.SPACE_ALT)
		proxy:update(camera.CFrame.Position, -origin, rig.mode, stack.Position, origin)
	elseif proxy.active then
		proxy:deactivate()
	end
	if rig.mode == "press" then
		waveFlag(t)
	end
	for _, tex in surf do
		tex.OffsetStudsV = (t * tex:GetAttribute("Speed")) % tex.StudsPerTileV
	end
	if proxy.active then
		for _, x in proxy.textures do
			x.tex.OffsetStudsV = (t * x.tex:GetAttribute("Speed")) % x.v * proxy.scale
		end
	end
	effects:update(st, t, camera.CFrame.Position, rig.mode)

	-- look: a full re-apply when the sun, sky, shot or proxy changes, and a few times a second for the haze thinning
	-- with altitude; the exposure dip follows the engines every frame
	local cc = Cams.CAMS[rig.mode]
	local key = sunPreset .. wxPreset .. rig.mode .. tostring(proxy.active)
		.. tostring(trueAlt(rig.lensPos or rig.pos) > Look.SPACE_ALT)
	lookT += rawDt
	if key ~= lookKey or lookT > 0.25 then
		lookKey, lookT = key, 0
		local flood = Look.apply({
			sun = sunPreset,
			camAlt = trueAlt(rig.lensPos or rig.pos),
			elev = Look.PRESETS[sunPreset],
			wx = wxPreset,
			camFog = cc.fog,
			alt = st.alt,
			dip = heard * cc.prox,
			proxy = proxy.active,
		})
		local fk = string.format("%.3f", flood) .. tostring(proxy.active)
		if fk ~= floodKey then
			floodKey = fk
			if proxy.active then
				Look.setFloods(flood, { proxy.root }, { port })
			else
				Look.setFloods(flood, { port }, { proxy.root })
			end
		end
	else
		Look.setExposure(Look.PRESETS[sunPreset], wxPreset, heard * cc.prox)
	end
	glows:update(t, camera.CFrame.Position, proxy.active and proxy.scale or nil, Look.flood, Look.elev, Look.fogDensity, origin)

	-- exhaust puffs, simulated in true space: real within the copy's hole around the camera, in the copy beyond it
	local camPos = camera.CFrame.Position
	local sc = proxy.active and proxy.scale or nil
	local sunCam = camera.CFrame:VectorToObjectSpace(Look.sunDir)
	puffs:update(st, dt, t, {
		elev = Look.elev,
		sun = Look.sunFactor,
		amb = Look.smokeAmb,
		fog = Look.fogDensity,
		fogCol = Look.fogColor,
		flood = Look.flood,
		sunDir = Look.sunDir,
	}, {
		camM = (camPos + origin) / S,
		place = function(p)
			p -= origin
			if sc and (p - camPos).Magnitude > FarProxy.HOLE then
				return camPos + (p - camPos) * sc, sc
			end
			return p, 1
		end,
		far = proxy.active,
		sunAngle = Look.elev > -1 and math.deg(math.atan2(sunCam.X, sunCam.Y)) or 0,
	})

	-- HUD
	hud:layout(vp)
	hud:setCut(cutAlpha)
	local _, event = Flight.eventIndex(st)
	hud:setEvent(Flight.KICKER[st.mode], event)
	hudT += rawDt
	if hudT > 0.2 then
		hudT = 0
		local pos, aim = (rig.lensPos or rig.pos) + Flight.origin, rig.aim + Flight.origin
		local hdg = math.round((math.deg(math.atan2(aim.X - pos.X, -(aim.Z - pos.Z))) + 360) % 360) % 360
		local rng = math.sqrt((pos.X - st.posX) ^ 2 + pos.Z ^ 2) / 1852
		local altFt = math.round(pos.Y * 3.281 / 10) * 10
		local focal = math.round(12 / math.tan(math.rad((rig.lensFov or fov) / 2)))
		local telemetry = string.format("ALT %s FT · HDG %03d° · RNG %.2f NM · %s MM", commas(altFt), hdg, rng, commas(focal))
		local clockLabel, clock, vtel
		if st.mode == "hold" then
			clockLabel, clock = "Propellant load", "T−" .. hms(math.max(0, math.round(countdown)))
		else
			clockLabel = st.tRel < 0 and "Terminal count" or (st.mode == "static" and "Static fire" or "Mission elapsed")
			local c = math.abs(st.tRel < 0 and math.ceil(st.tRel) or math.floor(st.tRel))
			clock = "T" .. (st.tRel < 0 and "−" or "+") .. hms(c)
		end
		if st.mode == "launch" and st.tRel > 0 then
			vtel = string.format("%s%s KM/H · %.1f KM", st.separated and "STAGE 2 · " or "", commas(math.round(st.vel * 3.6)), st.alt / 1000)
		elseif st.mode == "static" and st.thrust > 0.02 then
			vtel = string.format("THRUST %d%% · HELD DOWN", math.round(st.thrust * 100))
		else
			vtel = ""
		end
		hud:update(t, label, telemetry, clockLabel, clock, vtel)
	end
end)
