--!strict
-- DayNightServer
-- Authoritative per-server time + moon phase. Writes Lighting.ClockTime and the
-- Sky's MoonTextureId. Both replicate on their own, so no remotes are needed.
-- Mood interpolation is handled client-side (see DayNightClient).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- === CONFIG ===
local CYCLE_SECONDS = 20 * 60      -- full 24h cycle in real seconds
local DAY_FRACTION  = 0.575        -- share of the cycle that is daytime (06-18). slight summer lean.

-- Moon phases, in display order for a no-new-moon loop.
-- Advances one step at each day->night boundary.
local MOON_PHASES = {
	"rbxassetid://115183707506411", -- full
	"rbxassetid://98566249817591",  -- waning gibbous
	"rbxassetid://72720763605036",  -- last quarter
	"rbxassetid://116282218634687", -- waning crescent
	"rbxassetid://79635214986055",  -- waxing crescent
	"rbxassetid://87549301799580",  -- first quarter
	"rbxassetid://99628020701653",  -- waxing gibbous
}

-- === DERIVED ===
-- We map normalized cycle progress p (0..1) to ClockTime (0..24) with an
-- asymmetric remap: the first DAY_FRACTION of the cycle covers the 6->18 daylight
-- band (12 hours of clock), the rest covers 18->6 (the other 12 hours, wrapping
-- through midnight). Day occupies more real time than night without changing the
-- clock geometry, so the sun lingers longer.
local function progressToClock(p: number): number
	if p < DAY_FRACTION then
		-- daylight band: 6 -> 18
		local local_p = p / DAY_FRACTION
		return 6 + local_p * 12
	else
		-- night band: 18 -> 30 (== 6 next day), wrapped with %24
		local local_p = (p - DAY_FRACTION) / (1 - DAY_FRACTION)
		return (18 + local_p * 12) % 24
	end
end

-- === STATE ===
local startTick = os.clock()
local lastWasNight = false
local phaseIndex = 1

local sky = Lighting:FindFirstChildOfClass("Sky")
local function applyMoon()
	sky = sky or Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.MoonTextureId = MOON_PHASES[phaseIndex]
	end
end

-- expose current phase index for clients (e.g. tiny full-moon brightness nudge)
Lighting:SetAttribute("MoonPhaseIndex", phaseIndex)
Lighting:SetAttribute("MoonPhaseCount", #MOON_PHASES)
applyMoon()

RunService.Heartbeat:Connect(function()
	local elapsed = os.clock() - startTick
	local p = (elapsed % CYCLE_SECONDS) / CYCLE_SECONDS
	local clock = progressToClock(p)
	Lighting.ClockTime = clock

	-- night is the part of the cycle past DAY_FRACTION
	local isNight = p >= DAY_FRACTION
	if isNight and not lastWasNight then
		-- crossed into night: advance moon phase
		phaseIndex = (phaseIndex % #MOON_PHASES) + 1
		Lighting:SetAttribute("MoonPhaseIndex", phaseIndex)
		applyMoon()
	end
	lastWasNight = isNight
end)
