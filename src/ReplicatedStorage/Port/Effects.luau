-- Engine and pad effects (PLAN.md phase 6), ported from the mood study's updateExhaust, updateSteam and updateFrost
-- onto Roblox's own particles and beams:
--
-- - The flame is two fast emitters locked to the nozzle: a particle crosses the flame's length in its lifetime, so
--   colour over life becomes colour along the flame (white-hot at the exits, orange at the tail).
-- - The plume core and glow are Beams with the streak texture; nine short beams are the engine jets.
-- - Fire, vents and ice are world-space emitters whose rates and speeds follow the sequence.
-- - A flame light sits under the mount on the pad, then rides below the plume.
--
-- Real space only: the ground cloud, the contrail and the far cameras' flame are `Puffs`, which every camera sees.

local Workspace = game:GetService("Workspace")

local Flight = require(script.Parent.Flight)
local smooth = Flight.smooth

local Effects = {}
Effects.__index = Effects

local S = 1 / 0.28
local TEX = {
	glow = "rbxassetid://87877243907028",
	puff = "rbxassetid://102549625842700",
	flame = "rbxassetid://125011676503064",
	plume = "rbxassetid://119359214952709",
	ice = "rbxassetid://77986681991291",
}
local WIND = Vector3.new(0.7, 0, 2.6) -- m/s
local NOZZLE_Y = 8 -- m, the exit plane (VEH_S1_Body.Nozzles)
local VAC_Y = 50.7 -- m, the upper stage's vacuum nozzle exit (VEH_S2_Body.VacuumNozzleExit)
local COL = {
	core = Color3.new(1, 0.57, 0.24),
	glow = Color3.new(1, 0.4, 0.11),
	jet = Color3.new(1, 0.77, 0.46),
	fire = Color3.new(1, 0.42, 0.12),
	green = Color3.new(0.18, 1, 0.28),
	light = Color3.new(1, 0.56, 0.24),
	steam = Color3.new(1, 1, 1),
	ice = Color3.new(0.93, 0.95, 0.97),
}
-- engine bells: the centre one and eight around it, stack-local metres
local BELLS = { Vector2.zero }
for k = 0, 7 do
	local a = k * math.pi / 4 + math.pi / 8
	table.insert(BELLS, Vector2.new(math.cos(a), math.sin(a)) * 1.55)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- NumberSequence from { time, value } pairs (values already in their final units)
local function ns(points)
	local kp = {}
	for _, p in points do
		table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(kp)
end

local function quiet(p)
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
end

local function part(name, size, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	quiet(p)
	p.Parent = parent
	return p
end

local function attach(parent, name, cf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf or CFrame.identity
	a.Parent = parent
	return a
end

local function emitter(parent, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function beam(parent, name, a0, a1, props)
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0, b.Attachment1 = a0, a1
	b.Texture = TEX.plume
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	b.FaceCamera = true
	b.Segments = 1
	b.LightEmission = 1
	b.LightInfluence = 0
	for k, v in props do
		b[k] = v
	end
	b.Parent = parent
	return b
end

function Effects.new(port)
	local self = setmetatable({}, Effects)
	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	self.folder = folder
	self.emitters = {}

	-- Nozzle frame: moved each frame to the stack's exit plane; its -Y runs down the plume.
	local nozzle = part("Nozzle", Vector3.new(3.1, 0.2, 3.1) * S, folder)
	self.nozzle = nozzle
	local a0 = attach(nozzle, "Exit")
	self.coreEnd = attach(nozzle, "CoreEnd")
	self.glowEnd = attach(nozzle, "GlowEnd")
	self.core = beam(nozzle, "PlumeCore", a0, self.coreEnd, { Color = ColorSequence.new(COL.core), TextureSpeed = 0.35 })
	self.glowBeam = beam(nozzle, "PlumeGlow", a0, self.glowEnd, { Color = ColorSequence.new(COL.glow), TextureSpeed = 0.25 })
	self.jets = {}
	for i, b in BELLS do
		local top = attach(nozzle, "Jet" .. i, CFrame.new(b.X * S, 0, b.Y * S))
		local tip = attach(nozzle, "JetTip" .. i, CFrame.new(b.X * S, -3.4 * S, b.Y * S))
		table.insert(self.jets, { beam = beam(nozzle, "Jet" .. i, top, tip, {
			Color = ColorSequence.new(COL.jet),
			Width0 = 1 * S,
			Width1 = 1.24 * S,
			TextureSpeed = 0.5,
		}), tip = tip, x = b.X * S, z = b.Y * S })
	end

	-- the flame tongue: inner white-hot core and the wider orange sheath
	self.flameIn = emitter(nozzle, "FlameIn", {
		Texture = TEX.glow,
		LightEmission = 1,
		LightInfluence = 0,
		LockedToPart = true,
		EmissionDirection = Enum.NormalId.Bottom,
		Lifetime = NumberRange.new(0.12, 0.15),
		Size = ns({ { 0, 2.3 * S, 0.3 * S }, { 1, 1.6 * S, 0.3 * S } }),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 0.81, 0.5)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 0.6, 0.25)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 0.51, 0.16)),
		}),
		Transparency = ns({ { 0, 0.05 }, { 0.6, 0.45 }, { 1, 0.85 } }),
		Rotation = NumberRange.new(0, 360),
	})
	self.flameOut = emitter(nozzle, "FlameOut", {
		Texture = TEX.glow,
		LightEmission = 1,
		LightInfluence = 0,
		LockedToPart = true,
		EmissionDirection = Enum.NormalId.Bottom,
		Lifetime = NumberRange.new(0.18, 0.24),
		Size = ns({ { 0, 3.3 * S, 0.4 * S }, { 1, 5 * S, 0.6 * S } }),
		Color = ColorSequence.new(Color3.new(1, 0.5, 0.14), Color3.new(1, 0.38, 0.08)),
		Transparency = ns({ { 0, 0.5 }, { 0.5, 0.8 }, { 1, 0.98 } }),
		Rotation = NumberRange.new(0, 360),
	})
	-- shock diamonds (sea level only) and the warm halo around the base of the flame
	self.diamonds = {}
	for i, d in { 4.2, 7.4, 10.4, 13.2 } do
		local a = attach(nozzle, "Diamond" .. i)
		table.insert(self.diamonds, { att = a, d = d, e = emitter(a, "Diamond", {
			Texture = TEX.glow,
			LightEmission = 1,
			LightInfluence = 0,
			LockedToPart = true,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.05, 0.08),
			Size = NumberSequence.new((1.3 - i * 0.15) * S),
			Color = ColorSequence.new(Color3.new(1, 0.75, 0.45)),
			Transparency = NumberSequence.new(0.5),
		}) })
	end
	self.haloAtt = attach(nozzle, "Halo")
	self.halo = emitter(self.haloAtt, "Halo", {
		Texture = TEX.glow,
		LightEmission = 1,
		LightInfluence = 0,
		LockedToPart = true,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.25, 0.3),
		Size = NumberSequence.new(35 * S),
		Color = ColorSequence.new(Color3.new(1, 0.5, 0.2)),
		Transparency = NumberSequence.new(0.8),
	})

	-- fire tongues: straight down from the exits, and out along the trench once they hit it
	self.fireDown = emitter(nozzle, "FireDown", {
		Texture = TEX.puff,
		LightEmission = 1,
		LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Bottom,
		Speed = NumberRange.new(38 * S, 60 * S),
		SpreadAngle = Vector2.new(6, 6),
		Drag = 1.2,
		Size = ns({ { 0, 1.4 * S }, { 1, 5 * S, 1.5 * S } }),
		Color = ColorSequence.new(COL.fire),
		Transparency = ns({ { 0, 0.35 }, { 0.5, 0.7 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
	})
	local pad = part("PadFX", Vector3.new(1, 1, 1), folder)
	pad.CFrame = CFrame.new(0, 1.6 * S, 6 * S)
	self.fireTrench = emitter(pad, "FireTrench", {
		Texture = TEX.puff,
		LightEmission = 1,
		LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Back, -- +Z, down the trench
		Speed = NumberRange.new(40 * S, 65 * S),
		SpreadAngle = Vector2.new(8, 20),
		Drag = 1.2,
		Lifetime = NumberRange.new(0.5, 0.9),
		Size = ns({ { 0, 2 * S }, { 1, 6.5 * S, 2 * S } }),
		Color = ColorSequence.new(COL.fire),
		Transparency = ns({ { 0, 0.35 }, { 0.5, 0.75 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
	})

	-- steam vents: world positions and directions from the mood study, on the parts that carry them
	local veh, twr, padModel = port.VEH, port.TWR, port.PAD
	local VENTS = {
		{ host = veh:FindFirstChild("VEH_S2_Body", true), pos = Vector3.new(2.25, 57.5, 0.6), dir = Vector3.new(1, -0.12, 0.15),
			rate = 5.5, life = { 5, 8 }, size = { 1.2, 9 }, speed = 2.4, sink = -0.4, alpha = 0.42 },
		{ host = veh:FindFirstChild("VEH_S1_Body", true), pos = Vector3.new(2.1, 46.5, -1), dir = Vector3.new(0.85, -0.2, -0.35),
			rate = 4, life = { 5, 8 }, size = { 1, 8 }, speed = 2, sink = -0.35, alpha = 0.36 },
		{ host = padModel:FindFirstChild("PAD_Mount", true), pos = Vector3.new(0, 10.8, 7.5), dir = Vector3.new(0, -0.05, 1),
			rate = 5, life = { 8, 12 }, size = { 2.5, 15 }, speed = 1.5, sink = -0.04, alpha = 0.3, spread = 40 },
		{ host = twr:FindFirstChild("TWR_FuelArm", true), pos = Vector3.new(-2.6, 53.4, 0), dir = Vector3.new(-0.3, -0.4, 0.6),
			rate = 1.6, life = { 4, 6 }, size = { 0.8, 5 }, speed = 1.2, sink = -0.3, alpha = 0.32, arm = true },
	}
	self.vents = {}
	for i, v in VENTS do
		if v.host then
			local p = v.pos * S
			local a = Instance.new("Attachment")
			a.Name = "FX_Vent" .. i
			a.Parent = v.host
			a.WorldCFrame = CFrame.lookAt(p, p + v.dir.Unit) -- Front (-Z) along the vent
			local e = emitter(a, "Steam", {
				Texture = TEX.puff,
				LightEmission = 0,
				LightInfluence = 1,
				EmissionDirection = Enum.NormalId.Front,
				Speed = NumberRange.new(v.speed * 0.7 * S, v.speed * 1.3 * S),
				SpreadAngle = Vector2.new(v.spread or 12, v.spread or 12),
				Lifetime = NumberRange.new(v.life[1], v.life[2]),
				Size = ns({ { 0, v.size[1] * S, v.size[1] * 0.2 * S }, { 0.4, lerp(v.size[1], v.size[2], 0.65) * S }, { 1, v.size[2] * S, v.size[2] * 0.25 * S } }),
				Transparency = ns({ { 0, 1 }, { 0.12, 1 - v.alpha }, { 0.45, 1 - v.alpha }, { 1, 1 } }),
				Drag = 0.35,
				Acceleration = (WIND * 0.3 + Vector3.new(0, v.sink * 0.35, 0)) * S,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-15, 15),
				Color = ColorSequence.new(COL.steam),
			})
			table.insert(self.vents, { e = e, rate = v.rate, arm = v.arm })
		end
	end

	-- ice shed from the frost bands at ignition: flat sheets that flutter down on the wind
	self.iceBands = {}
	for _, band in { { y0 = 36.5, y1 = 47.9, share = 0.8 }, { y0 = 55.2, y1 = 59.4, share = 0.2 } } do
		local p = part("IceBand", Vector3.new(4.7, band.y1 - band.y0, 4.7) * S, folder)
		local e = emitter(p, "Ice", {
			Texture = TEX.ice,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.Random,
			LightEmission = 0,
			LightInfluence = 1,
			Shape = Enum.ParticleEmitterShape.Cylinder,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Speed = NumberRange.new(0.6 * S, 2.2 * S),
			Drag = 1.1,
			Acceleration = (WIND * 0.66 + Vector3.new(0, -9.81 * 0.55, 0)) * S,
			Lifetime = NumberRange.new(3, 6),
			Size = NumberSequence.new(0.55 * S, 0.45 * S),
			Squash = ns({ { 0, 0 }, { 0.15, 0.6 }, { 0.3, -0.4 }, { 0.45, 0.6 }, { 0.6, -0.4 }, { 0.8, 0.5 }, { 1, 0 } }),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			Color = ColorSequence.new(COL.ice),
			Transparency = ns({ { 0, 0.1 }, { 0.85, 0.15 }, { 1, 1 } }),
		})
		table.insert(self.iceBands, { part = p, e = e, mid = (band.y0 + band.y1) / 2, share = band.share })
	end

	-- the upper stage's vacuum engine: a small orange core and a huge milky bell that grows as it settles in
	local nozzle2 = part("Nozzle2", Vector3.new(1.2, 0.2, 1.2) * S, folder)
	self.nozzle2 = nozzle2
	self.vacCore = emitter(nozzle2, "VacCore", {
		Texture = TEX.glow,
		LightEmission = 1,
		LightInfluence = 0,
		LockedToPart = true,
		EmissionDirection = Enum.NormalId.Bottom,
		Lifetime = NumberRange.new(0.16, 0.2),
		Speed = NumberRange.new(26 / 0.2 * S * 0.9, 26 / 0.16 * S),
		Size = ns({ { 0, 1.2 * S, 0.2 * S }, { 0.4, 1.9 * S }, { 1, 3 * S, 0.5 * S } }),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 0.64, 0.27)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 0.5, 0.16)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 0.41, 0.1)),
		}),
		Transparency = ns({ { 0, 0.1 }, { 0.5, 0.5 }, { 1, 0.85 } }),
		Rotation = NumberRange.new(0, 360),
	})
	local v0 = attach(nozzle2, "VacExit")
	self.vacEnd = attach(nozzle2, "VacBellEnd")
	self.vacBell = beam(nozzle2, "VacBell", v0, self.vacEnd, {
		Color = ColorSequence.new(Color3.new(1, 0.88, 0.77)),
		LightEmission = 1,
		TextureSpeed = 0.1,
	})

	-- the flame light: under the mount on the pad, then riding below the plume
	self.lightPart = part("FlameLight", Vector3.one, folder)
	self.light = Instance.new("PointLight")
	self.light.Range = 120
	self.light.Shadows = true
	self.light.Enabled = false
	self.light.Parent = self.lightPart

	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(self.emitters, d)
		end
	end
	self.moving = { nozzle, self.lightPart, self.iceBands[1].part, self.iceBands[2].part, nozzle2 }
	self.cfs = {}
	folder.Parent = port
	return self
end

-- Clear every particle, for a new sequence or a seek.
function Effects:reset()
	for _, e in self.emitters do
		e:Clear()
	end
end

-- st: the Flight state; camPos in studs; mode: the live camera (the onboard camera hides the halo and glow beam).
function Effects:update(st, t, camPos, mode)
	local thrust, alt = st.thrust, st.alt
	local on = thrust > 0.01
	local onboard = mode == "onboard"
	local flick = 0.9 + math.sin(t * 47) * 0.05 + math.sin(t * 83.7) * 0.04 + (math.random() - 0.5) * 0.06
	local stack = Flight.stack(st)
	local nozzleCf = CFrame.new(stack:PointToWorldSpace(Vector3.new(0, NOZZLE_Y, 0)) * S) * stack.Rotation
	local down = -stack.UpVector

	-- the flame grows from a short blast on the pad to about a vehicle length once the air thins
	local startup = 0.35 + 0.65 * thrust
	local lenS = startup * (0.65 + 1.5 * smooth(60, 3000, alt)) * (1 + alt / 30000)
	local thin = 1 / (1 + alt / 9000)
	local hot = thrust * flick * thin
	local flameLen = 48 * lenS
	local ex, exG = 1 + alt / 6000, 1 + alt / 4500
	local green = st.greenFlash

	-- looking along the plume, the beams show their edges; the glows carry it alone there
	local endOn = math.abs(((nozzleCf.Position - camPos).Unit):Dot(down))
	local beamVis = on and 1 - smooth(0.45, 0.8, endOn) or 0

	self.coreEnd.Position = Vector3.new(0, -26 * lenS * flick * S, 0)
	self.glowEnd.Position = Vector3.new(0, -40 * lenS * S, 0)
	local core, glow = self.core, self.glowBeam
	core.Enabled, glow.Enabled = beamVis > 0.01, beamVis > 0.01 and not onboard
	core.Width0, core.Width1 = 4 * ex * S, 6 * ex * S
	glow.Width0, glow.Width1 = 4.6 * exG * S, 13 * exG * S
	core.Color = ColorSequence.new(COL.core:Lerp(COL.green, green))
	glow.Color = ColorSequence.new(COL.glow:Lerp(COL.green, green * 0.5))
	core.Brightness = 10 * thrust * flick * (0.35 + 0.65 * thin)
	glow.Brightness = 3 * thrust
	core.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.5 * beamVis), NumberSequenceKeypoint.new(1, 1) })
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - 0.22 / (1 + alt / 8000) * beamVis),
		NumberSequenceKeypoint.new(1, 1),
	})
	for k, j in self.jets do
		j.beam.Enabled = beamVis > 0.02
		j.tip.Position = Vector3.new(j.x, -3.4 * startup * (0.92 + math.sin(t * 61 + k * 1.7) * 0.08) * S, j.z)
		j.beam.Brightness = 12 * thrust * flick * (0.35 + 0.65 * thin)
		j.beam.Color = ColorSequence.new(COL.jet:Lerp(COL.green, green))
		j.beam.Transparency = NumberSequence.new(1 - 0.7 * beamVis)
	end

	-- flame tongue: speed sets its length, since each particle crosses it in its lifetime
	local inLen, outLen = 27 * lenS, 47 * lenS
	self.flameIn.Enabled, self.flameOut.Enabled = on, on
	self.flameIn.Speed = NumberRange.new(inLen / 0.15 * S * 0.9, inLen / 0.12 * S)
	self.flameOut.Speed = NumberRange.new(outLen / 0.24 * S * 0.9, outLen / 0.18 * S)
	self.flameIn.Rate = on and 220 or 0
	self.flameOut.Rate = on and 110 or 0
	-- HDR like the mood study's sprites (32 at the exits): bloom turns the overlapping glows white-hot
	self.flameIn.Brightness = 16 * hot
	self.flameOut.Brightness = 6 * hot
	local fc = Color3.new(1, 0.81, 0.5):Lerp(COL.green, green * 0.8)
	self.flameIn.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fc),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 0.6, 0.25):Lerp(COL.green, green * 0.8)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 0.51, 0.16):Lerp(COL.green, green * 0.8)),
	})
	local dia = 1 - smooth(1500, 6000, alt)
	for i, d in self.diamonds do
		d.att.Position = Vector3.new(0, -d.d * lenS * S, 0)
		d.e.Rate = (on and dia > 0) and 40 or 0
		d.e.Brightness = 10 * hot * dia * (0.75 + math.sin(t * 29 + i * 2.1) * 0.25)
	end
	self.haloAtt.Position = Vector3.new(0, -12 * lenS * S, 0)
	self.halo.Rate = (on and not onboard) and 10 or 0
	self.halo.Size = NumberSequence.new(math.min(75, 35 * (1 + alt / 9000)) * S)
	self.halo.Brightness = 3 * thrust / (1 + alt / 6000)

	-- fire: down from the exits, and along the trench while the flame still reaches it
	local fireK = thrust * (1 - smooth(150, 450, alt))
	self.fireDown.Rate = 30 * fireK
	self.fireDown.Lifetime = alt < 12 and NumberRange.new(0.14, 0.2) or NumberRange.new(0.5, 0.9)
	self.fireTrench.Rate = 28 * thrust * (1 - smooth(5, 25, alt))
	local fireCol = ColorSequence.new(COL.fire:Lerp(COL.green, green))
	self.fireDown.Color, self.fireTrench.Color = fireCol, fireCol
	self.fireDown.Brightness = 4 * math.max(thrust, green * 0.4)
	self.fireTrench.Brightness = self.fireDown.Brightness

	-- vents: until the count reaches T-3; the fuel arm's stops as it swings clear
	for _, v in self.vents do
		v.e.Rate = v.rate * st.ventLevel * (v.arm and (1 - st.armRetract) or 1)
	end

	-- ice: a heavy shower at ignition that tapers as vibration shakes the frost loose
	local iceRate = 0
	if thrust > 0.3 and (st.mode == "static" or alt < 500) then
		local burst = st.mode == "static" and 1 - smooth(1, 6, st.tRel) or 1 - smooth(0, 8, st.tRel)
		iceRate = 18 * thrust * (0.25 + 0.75 * burst) * (1 - smooth(150, 500, alt))
	end
	for _, b in self.iceBands do
		b.e.Rate = iceRate * b.share
	end

	-- flame light
	local lightPos
	if alt < 25 then
		lightPos = Vector3.new(st.posX, 4, 3) * S
	else
		lightPos = nozzleCf.Position + down * (8 + flameLen * 0.4) * S
	end
	self.light.Enabled = on
	self.light.Brightness = on and thrust * (3.2 + flick * 0.6) * (alt < 25 and 1 or 1.6) * 0.5 or 0
	self.light.Color = COL.light:Lerp(Color3.new(0.35, 1, 0.45), green)

	-- upper stage: the vacuum engine after separation, its bell growing as it settles in
	local s2 = st.s2Thrust
	local upper = Flight.upper(st)
	local nozzle2Cf = CFrame.new(upper:PointToWorldSpace(Vector3.new(0, VAC_Y, 0)) * S) * upper.Rotation
	local s2on = s2 > 0.01
	self.vacCore.Enabled = s2on
	self.vacCore.Rate = s2on and 120 or 0
	self.vacCore.Brightness = 8 * s2 * flick
	local rb = math.min(170, 26 + math.max(0, st.tRel - Flight.T_SES) * 9)
	local endOn2 = math.abs(((nozzle2Cf.Position - camPos).Unit):Dot(-upper.UpVector))
	local bellVis = s2on and not onboard and 1 - smooth(0.45, 0.8, endOn2) or 0
	self.vacBell.Enabled = bellVis > 0.01
	self.vacEnd.Position = Vector3.new(0, -rb * 2.4 * S, 0)
	self.vacBell.Width0, self.vacBell.Width1 = 0.024 * rb * S, 2 * rb * S
	self.vacBell.Brightness = 1.3 * s2
	self.vacBell.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - 0.1 * bellVis),
		NumberSequenceKeypoint.new(1, 1),
	})

	self.cfs[1] = nozzleCf
	self.cfs[2] = CFrame.new(lightPos)
	self.cfs[3] = CFrame.new(stack:PointToWorldSpace(Vector3.new(0, self.iceBands[1].mid, 0)) * S) * stack.Rotation
	self.cfs[4] = CFrame.new(stack:PointToWorldSpace(Vector3.new(0, self.iceBands[2].mid, 0)) * S) * stack.Rotation
	self.cfs[5] = nozzle2Cf
	Workspace:BulkMoveTo(self.moving, self.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

return Effects
