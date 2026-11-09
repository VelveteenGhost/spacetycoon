-- Time of day, sky and grade (PLAN.md phase 5), ported from the mood study's applySun and its post chain. One sun
-- elevation and one weather preset drive everything: sun colour and strength, sky fill, haze, clouds, exposure,
-- bloom and grade, and the pad's floodlights, which come on as the sun goes down.
--
-- Roblox places the sun from ClockTime and GeographicLatitude. At latitude 15.5 the sun rises at azimuth 98 (east
-- over the water, a little south), as in the mood study, and ClockTime then sets its elevation.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local S = 1 / 0.28

local Look = {}

Look.LATITUDE = 15.5
Look.EXPOSURE_BIAS = 1 -- stops: Realistic lighting at sunrise needs about one stop more than the mood study's curve
Look.PRESETS = { blue = -4, sunrise = 3, morning = 12 } -- sun elevation, degrees
Look.WX = {
	clear = { fog = 1, sun = 1, hemi = 1, glare = 1, haze = 1.5, cover = 0, cloudDensity = 0 },
	broken = { fog = 1.2, sun = 0.92, hemi = 1.05, glare = 0.85, haze = 1.8, cover = 0.62, cloudDensity = 0.55 },
	marine = { fog = 2.6, sun = 0.55, hemi = 1.2, glare = 0.45, haze = 3, cover = 0.75, cloudDensity = 0.85 },
}

-- Baked skies (tools/reference/bake_sky.py, then tools/sky_faces.py), by sun preset and weather. Broken weather
-- shows the clear sky under Roblox's cloud layer.
Look.SKIES = {
	sunrise_clear = {
		Ft = 74452865708429, Bk = 76395395920883, Lf = 125463061980066,
		Rt = 104748221518327, Up = 128230331054611, Dn = 71567945509173,
	},
	sunrise_marine = {
		Ft = 75295199837881, Bk = 83969054959625, Lf = 119212809721070,
		Rt = 108088757614601, Up = 140671860122825, Dn = 122569486126598,
	},
	morning_clear = {
		Ft = 94348730903564, Bk = 100311366876654, Lf = 88815821364390,
		Rt = 76544168503481, Up = 93938769047047, Dn = 120208560375831,
	},
	morning_marine = {
		Ft = 99914108142373, Bk = 138431261291023, Lf = 119214462142794,
		Rt = 95558103401701, Up = 120542799668619, Dn = 119126671791747,
	},
	blue_clear = {
		Ft = 75412030884892, Bk = 102513676718498, Lf = 97168747930666,
		Rt = 117543217177987, Up = 120942709483749, Dn = 91984109479355,
	},
	blue_marine = {
		Ft = 139294421549517, Bk = 135094528664117, Lf = 95171566630310,
		Rt = 136177695619367, Up = 138485525349648, Dn = 109081657162555,
	},
}

local function rgb(hex)
	return Color3.fromHex(hex)
end
local C = {
	sunLow = rgb("ff9a4d"),
	sunHigh = rgb("ffe8cc"),
	skyBlue = rgb("33476f"),
	skyDay = rgb("a3bcd9"),
	fogBlue = rgb("17203a"),
	fogDawn = rgb("9c7e72"),
	fogDay = rgb("94a3b4"),
	fogMarine = rgb("8d949a"),
	shiftLow = Color3.new(1, 0.3, 0.1), -- ColorShift_Top at sunrise
	shiftHigh = Color3.new(0.45, 0.35, 0.25), -- and by +18 degrees
	floodWarm = Color3.new(1, 0.9, 0.74),
	lensDay = rgb("3b3e43"),
}
Look.C = C

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function scale(c, k)
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

local skyKey
local function setSkybox(sun, wx)
	local key = sun .. "_" .. (wx == "marine" and "marine" or "clear")
	if key == skyKey then
		return
	end
	skyKey = key
	local faces = Look.SKIES[key] or Look.SKIES[sun .. "_clear"] or Look.SKIES.sunrise_clear
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	for face, id in faces do
		sky["Skybox" .. face] = "rbxassetid://" .. id
	end
	sky.CelestialBodiesShown = false -- the baked sky carries the mood study's sun
	sky.StarCount = 0
	sky.Parent = Lighting
end

local function ensure(parent, class, name)
	local i = parent:FindFirstChild(name)
	if not i then
		i = Instance.new(class)
		i.Name = name
		i.Parent = parent
	end
	return i
end

-- ClockTime for a morning sun at this elevation, found by bisection on Roblox's own sun model (cached).
local clockCache = {}
local function clockFor(elev)
	local key = math.floor(elev * 100 + 0.5)
	if clockCache[key] then
		return clockCache[key]
	end
	Lighting.GeographicLatitude = Look.LATITUDE
	local lo, hi = 3, 12
	for _ = 1, 28 do
		local mid = (lo + hi) / 2
		Lighting.ClockTime = mid
		if math.deg(math.asin(Lighting:GetSunDirection().Y)) < elev then
			lo = mid
		else
			hi = mid
		end
	end
	clockCache[key] = (lo + hi) / 2
	return clockCache[key]
end

-- Exposure: the mood study's curve (1.15 at night, 0.7 at sunrise, 0.48 by mid-morning) in stops about sunrise,
-- with the auto-iris dip while the engines burn (dip = what this camera hears times its glare factor). Cheap enough
-- to call every frame.
function Look.setExposure(e, wx, dip)
	local W = Look.WX[wx or "clear"]
	local night = 1 - smooth(-2, 10, e)
	local base = lerp(lerp(1.15, 0.7, smooth(-6, 3, e)), 0.48, smooth(3, 18, e)) * (1 + (1 - W.sun) * 0.7)
	local k = math.clamp(1 - (dip or 0) * (0.15 + 0.35 * night), 0.2, 1)
	Lighting.ExposureCompensation = Look.EXPOSURE_BIAS + math.log(base / 0.7 * k, 2)
end

-- state: sun (a PRESETS name), elev, wx ("clear" | "broken" | "marine"), camFog (the shot's haze multiplier), alt (vehicle altitude, m),
-- dip (0..1, how much the engines' glare stops the camera down), proxy (true while the far-camera copy shows)
function Look.apply(state)
	local e = state.elev or Look.PRESETS[state.sun or "sunrise"]
	local W = Look.WX[state.wx or "clear"]
	local up = smooth(-2.5, 4, e)
	local night = 1 - smooth(-2, 10, e)

	-- LightingStyle (Realistic) is a place setting: game scripts can't write it at runtime
	setSkybox(state.sun or "sunrise", state.wx or "clear")
	Lighting.GeographicLatitude = Look.LATITUDE
	-- Roblox darkens and tints the skybox as its sun sinks, past what the baked sky can make up for below the horizon
	-- (tools/sky_faces.py). The sun casts no light there anyway, so it waits at the morning angle, where the tint is
	-- neutral.
	Lighting.ClockTime = clockFor(e < -1 and Look.PRESETS.morning or e)
	Lighting.Brightness = 3.2 * up * lerp(0.62, 1, smooth(2, 22, e)) * W.sun
	local sunCol = C.sunLow:Lerp(C.sunHigh, smooth(0, 18, e))
	-- Under Realistic lighting this shifts Roblox's own sun colour rather than multiplying it, and a low Roblox sun is
	-- olive-yellow: a strong red shift with little green or blue is what turns it the mood study's peach (matched on
	-- the mount shot, Nov 9)
	Lighting.ColorShift_Top = scale(C.shiftLow:Lerp(C.shiftHigh, smooth(3, 18, e)), up)
	Lighting.ColorShift_Bottom = Color3.new()
	local hemiI = lerp(0.32, 0.6, smooth(-6, 16, e)) * lerp(0.7, 1, smooth(-4, 1, e)) * W.hemi
	local sky = C.skyBlue:Lerp(C.skyDay, smooth(-5, 16, e))
	Lighting.OutdoorAmbient = scale(sky, hemiI * 1.1)
	Lighting.Ambient = scale(sky, hemiI * 0.45)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true

	Look.setExposure(e, state.wx, state.dip)

	-- haze: clearer at night, thickest at dawn; each shot retunes it, and it thins fast with height
	local fogBase = lerp(lerp(0.0004, 0.00055, smooth(-6, 0, e)), 0.00036, smooth(0, 20, e)) * W.fog
	local thin = 1 / (1 + ((state.alt or 0) / 900) ^ 1.5)
	-- Below the horizon Roblox's sun waits at the morning angle (above), and Atmosphere would scatter that sunlight
	-- into the sky and the haze. So at blue hour the Atmosphere stands aside for Roblox's plain distance fog, reaching
	-- the same 63% as the mood study's exp2 fog at 1/density.
	local atm = Look.atmosphere or Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	Look.atmosphere = atm
	local parked = e < -1
	atm.Parent = if parked then nil else Lighting
	-- Roblox's density climbs much faster than the mood study's fog: linear up to the clear sunrise haze, then
	-- compressed, or marine weather whites out the near shots that the reference shows almost clear
	local ratio = (fogBase / 0.00046) * (state.camFog or 1) * thin
	local density = 0.34 * (if ratio <= 1.2 then ratio else 1.2 * (ratio / 1.2) ^ 0.35)
	if state.proxy then
		density = math.min(1, density * 1.8) -- the copy sits close, so it needs a denser haze to read as far away
	end
	atm.Density = math.clamp(density, 0, 1)
	atm.Offset = 0.2
	local fogCol = C.fogBlue:Lerp(C.fogDawn, smooth(-5, 2, e)):Lerp(C.fogDay, smooth(5, 20, e))
	if state.wx == "marine" then
		fogCol = fogCol:Lerp(scale(C.fogMarine, lerp(0.12, 1, smooth(-6, 8, e))), 0.45)
	end
	atm.Color = fogCol
	atm.Decay = scale(fogCol:Lerp(C.fogBlue, 0.35), 0.85)
	atm.Glare = 0.45 * W.glare * up
	atm.Haze = W.haze * lerp(0.6, 1, smooth(-4, 3, e))
	Lighting.FogColor = fogCol
	Lighting.FogStart = 0
	Lighting.FogEnd = if parked then 1.6 / (fogBase * (state.camFog or 1) * thin) * S else 1e6

	-- clouds: Roblox's dynamic cloud layer stands in for the mood study's cloud sprites
	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Parent = terrain
	clouds.Enabled = W.cover > 0
	clouds.Cover = W.cover
	clouds.Density = W.cloudDensity
	clouds.Color = Color3.new(1, 1, 1):Lerp(sunCol, 0.35 * up)

	-- grade: bloom, colour correction and sun rays as the port guide sets them
	local bloom = ensure(Lighting, "BloomEffect", "Bloom")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.6, 30, 0.95
	local cc = ensure(Lighting, "ColorCorrectionEffect", "Grade")
	cc.Contrast, cc.Saturation, cc.TintColor = 0.07, -0.1, Color3.fromRGB(255, 248, 235)
	local rays = ensure(Lighting, "SunRaysEffect", "SunRays")
	rays.Intensity, rays.Spread = 0.05 * W.glare * up, 0.7
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end

	-- floodlights: on below about +9 degrees, full by +1 (metal-halide warm white); setFloods applies it
	local flood = 1 - smooth(1, 9, e)
	Look.flood, Look.night, Look.elev = flood, night, e
	Look.fogDensity = fogBase * (state.camFog or 1) * thin -- the mood study's per-shot fog density, per metre
	return flood
end

-- Floodlights and lenses. active: the space on screen (the real site, or the far-camera copy while it shows), whose
-- lights burn at the flood level; parked: the other space, whose lights go off so they cost nothing. The lenses are
-- dark glass by day and lit warm white at night in both.
function Look.setFloods(flood, active, parked)
	local function each(roots, fn)
		for _, root in roots do
			local rig = root:FindFirstChild("Lights")
			if rig then
				for _, l in rig:GetDescendants() do
					if l:IsA("Light") then
						fn(l)
					end
				end
			end
		end
	end
	each(active, function(l)
		l.Enabled = flood > 0.01
		l.Brightness = flood * (l:GetAttribute("Brightness") or 1) * (l:GetAttribute("ProxyGain") or 1)
	end)
	each(parked, function(l)
		l.Enabled = false
	end)
	for _, roots in { active, parked } do
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if d.Name == "SITE_FloodPole_Lens" and d:IsA("BasePart") then
					local sa = d:FindFirstChildOfClass("SurfaceAppearance")
					if sa then
						sa.Color = C.lensDay:Lerp(Color3.new(1, 1, 1), flood)
						sa.EmissiveTint = C.floodWarm
						sa.EmissiveStrength = flood * 4
					end
				end
			end
		end
	end
end

Look.VIS = { clear = "VIS 9 SM", broken = "CEILING 6,500 FT", marine = "VIS 3 SM · HAZE" }

return Look
