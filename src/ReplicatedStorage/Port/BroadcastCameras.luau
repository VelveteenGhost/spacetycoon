-- The ten broadcast cameras and the auto director, ported from the mood study's updateCamera. Metres and degrees;
-- the Director converts to studs. Roblox clamps FieldOfView to 1-120 degrees, so a narrower lens moves the camera
-- closer along the same line of sight instead (port guide, Cameras and sequencing).

local Flight = require(script.Parent.Flight)
local smooth = Flight.smooth

local Cams = {}

Cams.LIST = { "onboard", "mount", "pad", "drone", "long", "press", "coast", "wide", "tracker" }
Cams.CAMS = {
	onboard = { fov = 96, label = "Cam 12 · Onboard", shake = 0.32, prox = 0.8 },
	mount = { fov = 42, label = "Cam 9 · Launch mount", shake = 1, prox = 1 },
	pad = { fov = 38, label = "Cam 7 · Pad perimeter", shake = 0.5, prox = 1 },
	drone = { fov = 16, label = "Cam 3 · Aerial", shake = 0.03, prox = 0.6 },
	long = { fov = 4.4, label = "Cam 1 · Long lens", shake = 0.06, prox = 0.5 },
	press = { fov = 14, label = "Cam 6 · Press site", shake = 0, prox = 0.35 },
	coast = { fov = 6, label = "Cam 5 · Coastline, 3 km", shake = 0, prox = 0.35 },
	wide = { fov = 8, label = "Cam 4 · Wide, 4 km", shake = 0, prox = 0.3 },
	tracker = { fov = 2, label = "Cam 2 · Tracker, 11 km", shake = 0, prox = 0.25 },
}

Cams.CUTS = {
	static = {
		{ -1e9, "wide" }, { -20, "long" }, { -14, "onboard" }, { -8, "mount" }, { 2.5, "pad" },
		{ 8, "press" }, { 16, "coast" }, { 24, "drone" }, { 34, "wide" },
	},
	launch = {
		{ -1e9, "wide" }, { -24, "drone" }, { -18, "long" }, { -12, "onboard" }, { -6, "mount" },
		{ 1.6, "pad" }, { 6, "long" }, { 11, "press" }, { 21, "wide" }, { 30, "coast" }, { 38, "onboard" },
		{ 48, "tracker" }, { 66, "onboard" }, { 78, "tracker" }, { 100, "onboard" }, { 136, "tracker" }, { 148, "onboard" },
	},
}
Cams.HOLD_CYCLE = { "drone", "wide", "long", "press", "coast", "pad", "onboard", "mount", "tracker" }

local PRESS = Vector3.new(-2500, 1.8, -1300)
Cams.PRESS = PRESS

local rad, deg = math.rad, math.deg

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function hypot(x, z)
	return math.sqrt(x * x + z * z)
end

function Cams.new()
	return { mode = "drone", orbitA = 3.95, aim = Vector3.new(0, 46, 0), aimSnap = true, onbView = nil }
end

function Cams.set(rig, mode)
	rig.mode, rig.aimSnap, rig.onbView = mode, true, nil
	rig.label = Cams.CAMS[mode].label
end

function Cams.directorPick(st, holdT)
	if st.mode == "hold" then
		return Cams.HOLD_CYCLE[math.floor(math.max(0, holdT) / 12) % #Cams.HOLD_CYCLE + 1]
	end
	local cuts = Cams.CUTS[st.mode]
	local i = 1
	while i < #cuts and cuts[i + 1][1] <= st.tRel do
		i += 1
	end
	return cuts[i][2]
end

-- Once the vehicle climbs, aim a little below it so it sits in the upper third with the trail below.
local function trailRoom(st, camPos, d, fovDeg)
	local room = smooth(30, 400, st.alt) * (st.separated and 0 or 1)
	if room <= 0 or st.rv.Magnitude < 1e-6 then
		return d
	end
	local dist = (camPos - d).Magnitude
	return d - st.rv.Unit * (dist * math.tan(rad(fovDeg / 2)) * 0.38 * room)
end

-- Returns the camera frame in metres, the vertical field of view and the on-screen label.
function Cams.update(rig, st, t, dt, heard, aspect, motion)
	local w = motion and 1 or 0
	local cc = Cams.CAMS[rig.mode]
	local k, maxEl, fov, lead = 2, rad(80), cc.fov, 1
	local pos, desired
	local mode = rig.mode
	local focus = function(y)
		return Flight.focus(st, y)
	end

	if mode == "drone" then
		if motion then
			rig.orbitA += dt * (math.pi * 2 / 220)
		end
		local r, climb = 430, math.min(700, st.alt * 0.22)
		pos = Vector3.new(
			math.cos(rig.orbitA) * r + math.sin(t * 0.37) * 1.3 * w,
			74 + climb + math.sin(t * 0.53) * 1.1 * w,
			math.sin(rig.orbitA) * r + math.cos(t * 0.29) * 1.3 * w
		)
		desired = focus(46)
			+ Vector3.new(math.sin(t * 0.41) * 0.35 * w, math.sin(t * 0.33) * 0.45 * w, math.cos(t * 0.47) * 0.35 * w)
		k = 2.4
		fov = math.clamp(2 * deg(math.atan(115 / (pos - desired).Magnitude)), 4.5, 16)
	elseif mode == "long" then
		pos = Vector3.new(500 + math.sin(t * 0.11) * 2 * w, 9, -1300 + math.sin(t * 0.07) * 3 * w) -- press riser on the beach
		desired = focus(38) + Vector3.new(0, math.sin(t * 0.9) * 0.06 * w, 0)
		k = 2.2
		fov = math.clamp(2 * deg(math.atan(150 / (pos - desired).Magnitude)), 1.1, 4.4)
		desired = trailRoom(st, pos, desired, fov)
	elseif mode == "coast" then
		pos = Vector3.new(530, 7, 3000) -- tripod on the north beach
		desired = focus(34)
		k = 1.1
		fov = math.clamp(2 * deg(math.atan(200 / (pos - desired).Magnitude)), 2.4, 9)
		desired = trailRoom(st, pos, desired, fov)
	elseif mode == "wide" then
		-- locked off 4 km inland; eases out to hold the whole arc, pad to vehicle, in frame
		pos = Vector3.new(-2600, 14, -2900)
		local padV, vehV = Vector3.new(0, 20, 0) - pos, focus(30) - pos
		local function az(v)
			return math.atan2(v.X, v.Z)
		end
		local function el(v)
			return math.atan2(v.Y, hypot(v.X, v.Z))
		end
		local ePad, eVeh = el(padV), el(vehV)
		local dAz = az(vehV) - az(padV)
		dAz = ((dAz + math.pi * 3) % (math.pi * 2)) - math.pi
		local vNeed = (eVeh - ePad) / 0.74
		local vFromH = 2 * math.atan(math.tan(math.abs(dAz) / 0.8 / 2) / aspect)
		fov = math.clamp(deg(math.max(vNeed, vFromH)), 8, 66)
		local eC = ePad - 0.14 * rad(fov) + rad(fov) / 2 -- pad near the bottom edge, vehicle near the top
		local aC = az(padV) + dAz / 2
		desired = pos + Vector3.new(math.sin(aC) * math.cos(eC), math.sin(eC), math.cos(aC) * math.cos(eC)) * 1000
		k, lead = 1.2, 0
	elseif mode == "press" then
		-- low on the grass, the range flag in the foreground; tilts up once the vehicle climbs out of the frame
		pos = PRESS
		local padAz = math.atan2(-PRESS.X, -PRESS.Z)
		local v = focus(40) - PRESS
		local vEl = math.atan2(v.Y, hypot(v.X, v.Z))
		local follow = smooth(rad(20), rad(30), vEl)
		local el = math.clamp(vEl - rad(3), rad(5), lerp(rad(22), rad(70), follow))
		local az = lerp(padAz + rad(4.5), math.atan2(v.X, v.Z), lerp(0.35, 1, follow))
		desired = PRESS + Vector3.new(math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el)) * 1000
		k, lead = 0.9, 0
	elseif mode == "tracker" then
		pos = Vector3.new(-3000, 30, -11000) -- tracking mount 11 km inland
		desired = focus(st.alt > 30 and 20 or 38)
		k = 2
		fov = math.clamp(2 * deg(math.atan(240 / (pos - desired).Magnitude)), 0.16, 4.4)
		desired = trailRoom(st, pos, desired, fov)
	elseif mode == "pad" then
		pos = Vector3.new(-46 + math.sin(t * 0.045) * 7 * w, 2.4, 54 + math.cos(t * 0.045) * 3 * w)
		desired = focus(47)
		k, maxEl = 1.6, rad(74)
	elseif mode == "mount" then
		pos = Vector3.new(34 + math.sin(t * 0.05) * 0.3 * w, 1.8, 10 + math.cos(t * 0.04) * 0.3 * w)
		desired = focus(16)
		k, maxEl = 1.4, rad(62)
	else -- onboard: Cam 12 on the booster, then Cam 14 under stage 2 after separation
		local view = st.separated and "engine" or "booster"
		if view ~= rig.onbView then
			rig.onbView = view
			rig.label = st.separated and "Cam 14 · Stage 2 engine" or cc.label
		end
		if not st.separated then
			-- a stabilised pod near the top of the booster, looking aft and outward past the body
			local a = rad(-20)
			local ox, oz = math.cos(a), math.sin(a)
			local stack = Flight.stack(st)
			pos = stack:PointToWorldSpace(Vector3.new(ox * 2.92, 47, oz * 2.92))
			desired = stack:PointToWorldSpace(Vector3.new(ox * (2.92 + 19), 47 - 28.5, oz * (2.92 + 19)))
			fov = 96
		else
			local upper = Flight.upper(st)
			pos = upper:PointToWorldSpace(Vector3.new(2.05, 54.05, 0.55))
			desired = upper:PointToWorldSpace(Vector3.new(0.2, 44, 0.05))
			fov = 104
		end
		rig.aimSnap, maxEl = true, math.pi
	end

	if mode ~= "onboard" then
		desired += st.rv * (lead / k) -- operators lead the vehicle instead of chasing it
	end
	local d = desired - pos
	local hz = hypot(d.X, d.Z)
	if math.atan2(d.Y, hz) > maxEl then
		desired = pos + Vector3.new(d.X, math.tan(maxEl) * hz, d.Z)
	end
	if rig.aimSnap then
		rig.aim, rig.aimSnap = desired, false
	else
		rig.aim = rig.aim:Lerp(desired, 1 - math.exp(-k * dt))
	end

	-- Narrower than Roblox's 1 degree: keep the framing by moving in along the line of sight.
	rig.lensFov = fov -- the real lens, for the telemetry's focal length
	if fov < 1 then
		pos = rig.aim + (pos - rig.aim) * (math.tan(rad(fov / 2)) / math.tan(rad(0.5)))
		fov = 1
	end

	local cf = CFrame.lookAt(pos, rig.aim, Vector3.yAxis)
	if mode == "drone" then
		cf *= CFrame.Angles(0, 0, math.sin(t * 0.23) * 0.005 * w)
	end
	local amp = cc.shake * heard * 0.006
	if amp > 0 then
		cf *= CFrame.Angles((math.sin(t * 37) + math.sin(t * 53.3) * 0.6) * amp, 0, 0)
		cf *= CFrame.Angles(0, (math.sin(t * 41.7) + math.sin(t * 29.1) * 0.6) * amp, 0)
	end
	rig.pos, rig.fov = pos, fov
	return cf, fov, rig.label or cc.label
end

return Cams
