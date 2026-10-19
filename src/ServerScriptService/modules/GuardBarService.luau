-- GuardBarService — server-authoritative guard meter.
--
-- The value lives as a character attribute "GuardBar" (0..MAX) so clients read it
-- via GetAttribute with no cross-VM Lua-table desync (the GuardBarController
-- LocalScript only ever reads this attribute; it never writes). All mutation of the
-- bar goes through this module, and every blocked-hit site will route through
-- BlockResolver (Phase 2), which calls the functions here — so there is exactly one
-- writer.
--
-- BLOCK BREAK escape: block-break locks the victim with StateHandler.SetStun(...).
-- The universal combo-breaker (T -> SkillFunctions.Burst) begins by calling
-- SetStun(char, false), so pressing T already bursts out of a block-break for free,
-- gated by the player's normal Burst mana/cooldown. No separate BurstOut path exists
-- or is needed here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RP = game:GetService("ReplicatedStorage")

local StateHandler = require(RP.modules.stateHandler)
local AnimationHandler = require(RP.modules.animationHandler)

local GuardBarService = {}

-- ------------------------------------------------------------------ tuning ----
local MAX = 100
local BLOCK_BREAK_ANIM = "rbxassetid://131056155810963"
local BLOCK_BREAK_DURATION = 1.0 -- hard stun + CantAnything lockout on break
local BLOCK_BREAK_STUNSPEED = 2 -- WalkSpeed while guard-broken

-- After the stun ends, the guard is still "recovering": the bar sits full at the
-- moment of break and drains full -> empty over this window, during which the
-- player cannot block. Block becomes available again the instant it hits empty.
local GUARD_RECOVERY_DURATION = 5.0

-- Fill applied to the BLOCKER's bar when a hit is blocked, keyed by attack class.
-- M2 is 0 because M2 guardbreaks (it never interacts with the bar on a normal
-- block; it bypasses straight to a guard break, handled in BlockResolver).
local FILL = {
	M1 = 18,
	M2 = 0,
	E = 22,
	Skill = 20,
	Default = 18,
}

-- Drain applied when the guarding player does something that relieves pressure.
local DRAIN_ON_PARRY = 40 -- a successful parry
local DRAIN_ON_HIT = 12 -- landing your own hit while the bar is up

-- Passive regen: after REGEN_DELAY seconds without taking a blocked hit, the bar
-- bleeds down at REGEN_RATE/sec.
local REGEN_RATE = 8
local REGEN_DELAY = 3

-- ------------------------------------------------------------------ state -----
local lastFillClock = {} -- [char] = os.clock() of last fill, for regen gating
local recoveryToken = {} -- [char] = incrementing id, cancels stale break recoveries

local function get(char)
	return char:GetAttribute("GuardBar") or 0
end

local function set(char, v)
	char:SetAttribute("GuardBar", math.clamp(v, 0, MAX))
end

-- Expose MAX so the GUI controller can normalise without hardcoding.
GuardBarService.MAX = MAX

-- ------------------------------------------------------------------ api -------

-- Call on spawn (mainGameHandler.HandleCharacterLoad). Establishes the attribute
-- so the controller can read it and the regen loop will service this character.
function GuardBarService.Init(char)
	if not char then
		return
	end
	set(char, 0)
	char:SetAttribute("GuardBroken", false)
	recoveryToken[char] = nil
end

-- Returns true if the character is currently in the post-break recovery window
-- (bar draining full -> empty; blocking is disabled during this time).
function GuardBarService.IsGuardBroken(char)
	return char and char:GetAttribute("GuardBroken") == true or false
end

-- The BLOCKER blocked a non-guardbreak hit.
-- Semantics (locked with author): break fires the moment the fill REACHES max
-- (no grace hit). Returns true if this hit triggered a guard break.
function GuardBarService.AddOnBlock(char, attackClass)
	if not char then
		return false
	end
	lastFillClock[char] = os.clock()

	-- Already recovering from a break: ignore (they shouldn't be blocking anyway).
	if GuardBarService.IsGuardBroken(char) then
		return false
	end

	local amount = FILL[attackClass] or FILL.Default
	local cur = get(char)
	if cur + amount >= MAX then
		GuardBarService.Break(char)
		return true
	end

	set(char, cur + amount)
	return false
end

function GuardBarService.Drain(char, amount)
	if not char then
		return
	end
	set(char, get(char) - amount)
end

function GuardBarService.DrainOnParry(char)
	GuardBarService.Drain(char, DRAIN_ON_PARRY)
end

function GuardBarService.DrainOnHit(char)
	GuardBarService.Drain(char, DRAIN_ON_HIT)
end

-- The unified guard-break entry point (both bar-fill breaks AND attack guardbreaks
-- route here). Applies a 1s hard stun + CantAnything lockout, plays the break anim,
-- then leaves the bar FULL and drains it full -> empty over GUARD_RECOVERY_DURATION.
-- Blocking is disabled for the whole recovery (see IsGuardBroken).
function GuardBarService.Break(char)
	if not char then
		return
	end

	StateHandler.RemoveStates(char, "Blocking")
	StateHandler.SetStun(char, true, BLOCK_BREAK_DURATION, BLOCK_BREAK_STUNSPEED)
	StateHandler.SetState(char, "CantAnything", true, BLOCK_BREAK_DURATION)
	AnimationHandler.StopAnim(char, "ALL")
	AnimationHandler.LoadAnim(char, "GuardBreak", BLOCK_BREAK_ANIM, nil, false)

	-- Enter recovery: bar sits full, then bleeds down over the recovery window.
	set(char, MAX)
	char:SetAttribute("GuardBroken", true)

	-- Token guards against overlapping recoveries (a re-break restarts cleanly)
	-- and against the char respawning mid-drain.
	local token = (recoveryToken[char] or 0) + 1
	recoveryToken[char] = token
	lastFillClock[char] = nil -- recovery owns the drain; keep passive regen off it

	task.spawn(function()
		local elapsed = 0
		while elapsed < GUARD_RECOVERY_DURATION do
			local dt = task.wait()
			-- Bail if superseded (re-break) or the char is gone.
			if recoveryToken[char] ~= token then
				return
			end
			if not char.Parent then
				recoveryToken[char] = nil
				return
			end
			elapsed += dt
			local ratio = math.clamp(1 - elapsed / GUARD_RECOVERY_DURATION, 0, 1)
			set(char, MAX * ratio)
		end
		if recoveryToken[char] ~= token then
			return
		end
		set(char, 0)
		char:SetAttribute("GuardBroken", false)
		recoveryToken[char] = nil
	end)
end

-- ------------------------------------------------------------------ regen -----
RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		-- Skip broken chars: the recovery drain owns their bar for the window.
		if
			char
			and char:GetAttribute("GuardBar") ~= nil
			and not GuardBarService.IsGuardBroken(char)
		then
			local v = get(char)
			if v > 0 then
				local last = lastFillClock[char]
				if not last or (os.clock() - last) >= REGEN_DELAY then
					set(char, v - REGEN_RATE * dt)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	local char = plr.Character
	if char then
		lastFillClock[char] = nil
		recoveryToken[char] = nil
	end
end)

return GuardBarService
