--!strict
-- SPDX-License-Identifier: MIT
--
-- Blends the lighting mood between keyframes by Lighting.ClockTime, which the server
-- sets. Visibility stays flat over the whole cycle: night shows only through color and
-- atmosphere, never through less light. Tune the look in KEYFRAMES.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")

-- Each keyframe is anchored to a clock hour (0 to 24), and the mood lerps between the
-- two around the current time. Midnight is blue but bright, so visibility never drops.
local KEYFRAMES = {
	-- Midnight: cool and blue, still bright.
	{
		hour = 0,
		outdoorAmbient = Color3.fromRGB(58, 64, 92),
		ambient = Color3.fromRGB(78, 82, 110),
		ccTint = Color3.fromRGB(176, 196, 255),
		ccBrightness = 0.02,
		ccContrast = 0.18,
		atmosColor = Color3.fromRGB(96, 110, 150),
		atmosDensity = 0.42,
		atmosHaze = 1.1,
		fogColor = Color3.fromRGB(96, 110, 150),
	},
	-- Dawn: a warm transition.
	{
		hour = 6,
		outdoorAmbient = Color3.fromRGB(120, 114, 100),
		ambient = Color3.fromRGB(132, 124, 110),
		ccTint = Color3.fromRGB(255, 224, 196),
		ccBrightness = 0.04,
		ccContrast = 0.20,
		atmosColor = Color3.fromRGB(168, 140, 130),
		atmosDensity = 0.40,
		atmosHaze = 0.95,
		fogColor = Color3.fromRGB(180, 165, 158),
	},
	-- Noon.
	{
		hour = 12,
		outdoorAmbient = Color3.fromRGB(72, 71, 63),
		ambient = Color3.fromRGB(118, 117, 107),
		ccTint = Color3.fromRGB(255, 245, 228),
		ccBrightness = 0.05,
		ccContrast = 0.20,
		atmosColor = Color3.fromRGB(149, 126, 126),
		atmosDensity = 0.393,
		atmosHaze = 0.80,
		fogColor = Color3.fromRGB(192, 192, 192),
	},
	-- Dusk: a warm transition, the mirror of dawn.
	{
		hour = 18,
		outdoorAmbient = Color3.fromRGB(72, 71, 63),
		ambient = Color3.fromRGB(126, 116, 104),
		ccTint = Color3.fromRGB(255, 214, 184),
		ccBrightness = 0.04,
		ccContrast = 0.20,
		atmosColor = Color3.fromRGB(170, 132, 124),
		atmosDensity = 0.41,
		atmosHaze = 0.95,
		fogColor = Color3.fromRGB(182, 158, 150),
	},
}
-- The keyframes loop: hour 24 wraps to the hour-0 keyframe.

-- A small brightness boost for a full moon (phase 1), small enough to keep visibility
-- flat. Set it to 0 to turn it off.
local fullMoonBrightnessBonus = 0.015

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Returns the two keyframes around an hour and the blend factor between them.
local function bracket(hour: number)
	local n = #KEYFRAMES
	for i = 1, n do
		local a = KEYFRAMES[i]
		local b = KEYFRAMES[(i % n) + 1]
		local aH = a.hour
		local bH = b.hour
		-- Wrap past midnight, for example from 18 to 24.
		if bH <= aH then
			bH = bH + 24
		end
		local h = hour
		if h < aH then
			h = h + 24
		end
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
		-- The full-moon boost grows toward midnight.
		local phaseIndex = Lighting:GetAttribute("MoonPhaseIndex")
		if phaseIndex == 1 and fullMoonBrightnessBonus > 0 then
			local nightness = math.clamp(1 - math.abs(((hour + 12) % 24) - 12) / 12, 0, 1)
			local darkness = 1 - math.clamp(math.abs((hour % 24) - 12) / 12, 0, 1)
			brightness = brightness + fullMoonBrightnessBonus * darkness
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
