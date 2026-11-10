-- Launch and static-fire sequences, ported from the mood study's updateSequence. Metres and seconds; tRel is the
-- time from T-0. The vehicle flies in the X-Y plane: +X downrange (east), pitch measured from vertical.

local Flight = {}

Flight.LEAD = 30
Flight.LENGTH = { static = 75, launch = 186 }
Flight.T_MECO, Flight.T_SEP, Flight.T_SES = 118, 121, 127

Flight.KICKER = {
	hold = "Pathfinder 1 · Orbital test flight",
	static = "Pathfinder 1 · Static fire test",
	launch = "Pathfinder 1 · Orbital test flight",
}

Flight.EVENTS = {
	hold = { { -1e9, "Propellant load in progress" } },
	static = {
		{ -1e9, "Terminal count" },
		{ -15, "Pad deluge armed" },
		{ -3, "Engine ignition sequence" },
		{ 0, "Full-duration static fire" },
		{ 6.3, "Engine shutdown · nominal" },
		{ 16, "Safing vehicle · data review" },
	},
	launch = {
		{ -1e9, "Terminal count" },
		{ -25, "Fuel arm retracting" },
		{ -10, "Go for launch" },
		{ -3, "Ignition" },
		{ 0, "Liftoff" },
		{ 8, "Pathfinder has cleared the tower" },
		{ 16, "Pitch program initiated" },
		{ 48, "Max-Q · peak aerodynamic pressure" },
		{ 64, "Through Max-Q · throttling up" },
		{ 118, "MECO · main engine cutoff" },
		{ 121, "Stage separation confirmed" },
		{ 127, "Second-stage ignition" },
		{ 136, "Stage 1 falling away" },
	},
}

local B_CG = Vector3.new(0, 25, 0) -- booster centre of mass, stack-local

-- Render origin, metres (the Director moves it). Roblox keeps positions in float32, which past 100 km out resolve
-- only a centimetre or so, enough to shake an onboard camera against the hull beside it. So the state keeps plain
-- numbers, and stack, upper and focus return frames relative to this origin, built before anything is rounded.
Flight.origin = Vector3.zero

local function at(x, y)
	local o = Flight.origin
	return CFrame.new(x - o.X, y - o.Y, -o.Z)
end

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
Flight.smooth = smooth

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function rotZ(v, a)
	return CFrame.Angles(0, 0, a):VectorToWorldSpace(v)
end

function Flight.thrustCurve(mode, tr)
	if mode == "hold" or tr < -3 then
		return 0
	end
	local th = tr < -2.4 and 0.12 * smooth(-3, -2.85, tr) or lerp(0.12, 1, smooth(-2.4, -0.6, tr))
	if mode == "static" then
		th *= 1 - smooth(5.5, 6.3, tr)
	elseif mode == "launch" then
		th *= 1 - smooth(Flight.T_MECO - 0.3, Flight.T_MECO + 0.4, tr)
	end
	return th
end

function Flight.new(mode)
	return {
		mode = mode,
		seqT = 0,
		tRel = mode == "hold" and -1e9 or -Flight.LEAD,
		thrust = 0,
		greenFlash = 0,
		armRetract = 0,
		ventLevel = 1,
		alt = 0,
		vel = 0,
		posX = 0,
		pitch = 0,
		rv = Vector3.zero,
		mecoDone = false,
		separated = false,
		sepBurst = false,
		bx = 0, -- booster and upper-stage positions once they fly apart (x, y; numbers, see Flight.origin)
		by = 0,
		ux = 0,
		uy = 0,
		bVel = Vector3.zero,
		uVel = Vector3.zero,
		bPitch = 0,
		uPitch = 0,
		bSpin = 0,
		s2Thrust = 0,
		rng = Random.new(1977),
	}
end

function Flight.step(st, dt)
	if st.mode == "hold" then
		st.thrust, st.ventLevel, st.armRetract, st.tRel = 0, 1, 0, -1e9
		return
	end
	st.seqT += dt
	local tr = st.seqT - Flight.LEAD
	st.tRel = tr
	st.thrust = Flight.thrustCurve(st.mode, tr)
	st.greenFlash = (tr > -2.9 and tr < -2.45) and math.sin((tr + 2.9) / 0.45 * math.pi) or 0
	st.armRetract = st.mode == "launch" and smooth(-25, -19, tr) or 0
	st.ventLevel = tr < -3 and 1 or (st.mode == "static" and smooth(8, 14, tr) or 0)

	if st.mode == "launch" and tr > 0 and tr < Flight.T_MECO then
		st.vel += (2.2 + 0.32 * tr) * dt
		st.pitch = tr < 12 and 0 or math.min(0.95, ((tr - 12) / 70) ^ 1.3 * 0.9)
		st.posX += st.vel * math.sin(st.pitch) * dt
		st.alt += st.vel * math.cos(st.pitch) * dt
		st.rv = Vector3.new(st.vel * math.sin(st.pitch), st.vel * math.cos(st.pitch), 0)
	elseif st.mode == "launch" and tr >= Flight.T_MECO then
		if not st.mecoDone then -- two free bodies from here: the booster about its centre of mass, and the upper stage
			st.mecoDone = true
			st.bPitch, st.uPitch = st.pitch, st.pitch
			local cg = rotZ(B_CG, -st.pitch)
			st.bx, st.by = st.posX + cg.X, st.alt + cg.Y
			st.bVel = st.rv
			st.ux, st.uy = st.posX, st.alt
			st.uVel = st.rv
		end
		st.bVel -= Vector3.new(0, 9.81 * dt, 0)
		st.bx += st.bVel.X * dt
		st.by += st.bVel.Y * dt
		local ax = Vector3.new(math.sin(st.uPitch), math.cos(st.uPitch), 0)
		if tr >= Flight.T_SEP then
			if not st.separated then
				st.separated, st.sepBurst = true, true
				st.uVel += ax * 1.6
				st.bVel -= ax
				st.bSpin = (st.rng:NextNumber() < 0.5 and -1 or 1) * (0.02 + st.rng:NextNumber() * 0.03)
			end
			st.bPitch += st.bSpin * dt
			st.s2Thrust = smooth(Flight.T_SES, Flight.T_SES + 1.5, tr)
			st.uVel += ax * 9.5 * st.s2Thrust * dt
			st.uVel -= Vector3.new(0, 2.5 * dt, 0)
			st.ux += st.uVel.X * dt
			st.uy += st.uVel.Y * dt
		else
			st.uVel = st.bVel
			local cg = rotZ(B_CG, -st.bPitch)
			st.ux, st.uy = st.bx - cg.X, st.by - cg.Y
		end
		st.alt, st.posX, st.vel, st.rv = st.uy, st.ux, st.uVel.Magnitude, st.uVel
	end
end

-- Stack (booster) and upper-stage frames, metres from Flight.origin. Parts are modelled in stack-local coordinates.
function Flight.stack(st)
	if st.mecoDone then
		local cg = rotZ(B_CG, -st.bPitch)
		return at(st.bx - cg.X, st.by - cg.Y) * CFrame.Angles(0, 0, -st.bPitch)
	end
	return at(st.posX, st.alt) * CFrame.Angles(0, 0, -st.pitch)
end

function Flight.upper(st)
	if st.separated then
		return at(st.ux, st.uy) * CFrame.Angles(0, 0, -st.uPitch)
	end
	return Flight.stack(st)
end

-- What the cameras frame: the stack, or the upper stage once it flies alone (the mission rides it).
function Flight.focus(st, y)
	if st.separated then
		return Flight.upper(st):PointToWorldSpace(Vector3.new(0, math.max(y, 58), 0))
	end
	return Flight.stack(st):PointToWorldSpace(Vector3.new(0, y, 0))
end

function Flight.eventIndex(st)
	local ev = Flight.EVENTS[st.mode]
	local i = 1
	while i < #ev and ev[i + 1][1] <= st.tRel do
		i += 1
	end
	return i, ev[i][2]
end

return Flight
