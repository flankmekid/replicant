--!strict
-- DayNightClient
-- Reads Lighting.ClockTime every frame and interpolates mood properties between
-- keyframes. Visibility is held flat across the whole cycle (night reads through
-- colour/atmosphere only, never reduced light) per design.
--
-- Tune the look by editing KEYFRAMES below. Each keyframe is anchored to a clock
-- hour; the system finds the two surrounding keyframes and lerps between them.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")

-- === KEYFRAMES ===
-- hour: clock time this frame is anchored to (0..24)
-- Daytime values (dawn/noon/dusk) seeded from the existing tuned look.
-- Midnight is bright-but-blue: ambient stays high so visibility never drops.
local KEYFRAMES = {
	{ -- midnight (cool, void-blue, still bright)
		hour = 0,
		outdoorAmbient = Color3.fromRGB(58, 64, 92),
		ambient        = Color3.fromRGB(78, 82, 110),
		ccTint         = Color3.fromRGB(176, 196, 255),
		ccBrightness   = 0.02,
		ccContrast     = 0.18,
		atmosColor     = Color3.fromRGB(96, 110, 150),
		atmosDensity   = 0.42,
		atmosHaze      = 1.1,
		fogColor       = Color3.fromRGB(96, 110, 150),
	},
	{ -- dawn (warm transition)
		hour = 6,
		outdoorAmbient = Color3.fromRGB(120, 114, 100),
		ambient        = Color3.fromRGB(132, 124, 110),
		ccTint         = Color3.fromRGB(255, 224, 196),
		ccBrightness   = 0.04,
		ccContrast     = 0.20,
		atmosColor     = Color3.fromRGB(168, 140, 130),
		atmosDensity   = 0.40,
		atmosHaze      = 0.95,
		fogColor       = Color3.fromRGB(180, 165, 158),
	},
	{ -- noon (exact current tuned look)
		hour = 12,
		outdoorAmbient = Color3.fromRGB(72, 71, 63),
		ambient        = Color3.fromRGB(118, 117, 107),
		ccTint         = Color3.fromRGB(255, 245, 228),
		ccBrightness   = 0.05,
		ccContrast     = 0.20,
		atmosColor     = Color3.fromRGB(149, 126, 126),
		atmosDensity   = 0.393,
		atmosHaze      = 0.80,
		fogColor       = Color3.fromRGB(192, 192, 192),
	},
	{ -- dusk (warm transition, mirror of dawn)
		hour = 18,
		outdoorAmbient = Color3.fromRGB(72, 71, 63),
		ambient        = Color3.fromRGB(126, 116, 104),
		ccTint         = Color3.fromRGB(255, 214, 184),
		ccBrightness   = 0.04,
		ccContrast     = 0.20,
		atmosColor     = Color3.fromRGB(170, 132, 124),
		atmosDensity   = 0.41,
		atmosHaze      = 0.95,
		fogColor       = Color3.fromRGB(182, 158, 150),
	},
}
-- keyframes loop: hour 24 wraps back to the hour-0 frame.

-- tiny brightness nudge for a full moon (phase index 1). kept small so it never
-- breaks the flat-visibility rule. set to 0 to disable entirely.
local FULL_MOON_BRIGHTNESS_BONUS = 0.015

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- find the two keyframes bracketing the given hour and the blend factor
local function bracket(hour: number)
	local n = #KEYFRAMES
	for i = 1, n do
		local a = KEYFRAMES[i]
		local b = KEYFRAMES[(i % n) + 1]
		local aH = a.hour
		local bH = b.hour
		if bH <= aH then bH = bH + 24 end -- wrap (e.g. 18 -> 24/0)
		local h = hour
		if h < aH then h = h + 24 end
		if h >= aH and h <= bH then
			local span = bH - aH
			local t = span > 0 and (h - aH) / span or 0
			return a, b, t
		end
	end
	return KEYFRAMES[1], KEYFRAMES[1], 0
end

RunService.RenderStepped:Connect(function()
	local hour = Lighting.ClockTime
	local a, b, t = bracket(hour)

	Lighting.OutdoorAmbient = a.outdoorAmbient:Lerp(b.outdoorAmbient, t)
	Lighting.Ambient = a.ambient:Lerp(b.ambient, t)

	if cc then
		cc.TintColor = a.ccTint:Lerp(b.ccTint, t)
		local brightness = lerp(a.ccBrightness, b.ccBrightness, t)
		-- full-moon nudge, scaled by how deep into night we are (near midnight)
		local phaseIndex = Lighting:GetAttribute("MoonPhaseIndex")
		if phaseIndex == 1 and FULL_MOON_BRIGHTNESS_BONUS > 0 then
			local nightness = math.clamp(1 - math.abs(((hour + 12) % 24) - 12) / 12, 0, 1)
			-- nightness peaks at midnight, 0 at noon
			local darkness = 1 - math.clamp(math.abs(((hour) % 24) - 12) / 12, 0, 1)
			brightness = brightness + FULL_MOON_BRIGHTNESS_BONUS * darkness
		end
		cc.Brightness = brightness
		cc.Contrast = lerp(a.ccContrast, b.ccContrast, t)
	end

	if atmos then
		atmos.Color = a.atmosColor:Lerp(b.atmosColor, t)
		atmos.Density = lerp(a.atmosDensity, b.atmosDensity, t)
		atmos.Haze = lerp(a.atmosHaze, b.atmosHaze, t)
	end

	Lighting.FogColor = a.fogColor:Lerp(b.fogColor, t)
end)
