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

local S = 1 / 0.28
local PAD_SET_END = 34 -- the launch loops here until the altitude set (phase 7) takes over at about T+25
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
})

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
local t, holdT, hudT, countdown = 0, 0, 1, 34 * 60 + 12
local cutAlpha = 0
local hud

local function startSeq(mode)
	st = Flight.new(mode)
	hist = {}
	rig.aimSnap = true
	holdT = 0
	hud:setDeck(mode, autoCam)
end

local function seek(target)
	startSeq(st.mode)
	while st.tRel < target do
		Flight.step(st, math.min(SEEK_STEP, target - st.tRel))
	end
	rig.aimSnap = true
end

local function setCamera(mode)
	autoCam = mode == "auto"
	if not autoCam then
		Cams.set(rig, mode)
	end
	hud:setDeck(st.mode, autoCam)
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
		if which == "auto" then
			setCamera("auto")
		else
			nextCamera()
		end
	end,
	onToggleOverlay = toggleOverlay,
})
hud:setDeck(st.mode, autoCam)

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
port:GetAttributeChangedSignal("Paused"):Connect(function()
	paused = port:GetAttribute("Paused") == true
end)

RunService:BindToRenderStep("PortDirector", Enum.RenderPriority.Camera.Value + 1, function(rawDt)
	local dt = paused and 0 or math.min(0.05, rawDt)
	t += dt
	holdT += dt
	countdown -= dt
	Flight.step(st, dt)

	-- The launch loops at the pad set's limit for now; the static fire runs its full length.
	local endT = st.mode == "launch" and PAD_SET_END or (st.mode == "static" and Flight.LENGTH.static - Flight.LEAD)
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
		end
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
	local cf, fov, label = Cams.update(rig, st, t, dt, heard, vp.X / math.max(vp.Y, 1), motion)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fov
	camera.CFrame = toStuds(cf)
	if port:GetAttribute("Proxy") ~= false then
		proxy:update(camera.CFrame.Position, Vector3.zero, rig.mode, stack.Position)
	elseif proxy.active then
		proxy:deactivate()
	end
	if rig.mode == "press" then
		waveFlag(t)
	end

	-- HUD
	hud:layout(vp)
	hud:setCut(cutAlpha)
	local _, event = Flight.eventIndex(st)
	hud:setEvent(Flight.KICKER[st.mode], event)
	hudT += rawDt
	if hudT > 0.2 then
		hudT = 0
		local pos, aim = rig.pos, rig.aim
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
