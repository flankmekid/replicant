--!strict
-- SPDX-License-Identifier: MIT
--
-- Owns the server time of day and the moon phase. It writes Lighting.ClockTime and the
-- Sky's MoonTextureId, which replicate on their own. DayNightClient blends the mood
-- on the client.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- A full 24-hour cycle in real seconds.
local cycleSeconds = 20 * 60
-- The share of the cycle that is daytime (06:00 to 18:00), so days run a bit longer.
local dayFraction = 0.575

-- Moon phases in display order, with no new moon. The phase advances at each nightfall.
local moonPhases = {
	"rbxassetid://115183707506411", -- Full.
	"rbxassetid://98566249817591", -- Waning gibbous.
	"rbxassetid://72720763605036", -- Last quarter.
	"rbxassetid://116282218634687", -- Waning crescent.
	"rbxassetid://79635214986055", -- Waxing crescent.
	"rbxassetid://87549301799580", -- First quarter.
	"rbxassetid://99628020701653", -- Waxing gibbous.
}

-- Maps cycle progress (0 to 1) to ClockTime. The first dayFraction of the cycle covers
-- 06:00 to 18:00 and the rest covers 18:00 to 06:00, so the day takes more real time
-- than the night without changing the clock.
local function progressToClock(p: number): number
	if p < dayFraction then
		local local_p = p / dayFraction
		return 6 + local_p * 12
	else
		-- 18:00 to 30:00, which wraps to 06:00.
		local local_p = (p - dayFraction) / (1 - dayFraction)
		return (18 + local_p * 12) % 24
	end
end

local startTick = os.clock()
local lastWasNight = false
local phaseIndex = 1

local sky = Lighting:FindFirstChildOfClass("Sky")
local function applyMoon()
	sky = sky or Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.MoonTextureId = moonPhases[phaseIndex]
	end
end

-- Clients read the phase, for example to brighten a full moon a little.
Lighting:SetAttribute("MoonPhaseIndex", phaseIndex)
Lighting:SetAttribute("MoonPhaseCount", #moonPhases)
applyMoon()

RunService.Heartbeat:Connect(function()
	local elapsed = os.clock() - startTick
	local p = (elapsed % cycleSeconds) / cycleSeconds
	local clock = progressToClock(p)
	Lighting.ClockTime = clock

	local isNight = p >= dayFraction
	if isNight and not lastWasNight then
		phaseIndex = (phaseIndex % #moonPhases) + 1
		Lighting:SetAttribute("MoonPhaseIndex", phaseIndex)
		applyMoon()
	end
	lastWasNight = isNight
end)
