-- SpeedService: the single authority for a character's WalkSpeed.
--
-- The problem this replaces: every system that changed WalkSpeed (block, M1/M2/E
-- slow, stun, hitstop, skill self-slows, Null Gaze) did its own stash-and-restore
-- and restored to ITS OWN idea of "default" (a remembered value or GetBaseWalkSpeed).
-- Those stashes were single-slot and didn't know about each other, so layering two
-- effects (block under an M1, a hit while blocking, etc.) made whichever restore ran
-- last clobber the still-correct speed of the one still active. Symptoms: blocking at
-- full speed after an M1, returning to base (not block) after being hit mid-block.
--
-- The fix: nobody writes Humanoid.WalkSpeed directly for a transient effect anymore.
-- Each effect PUSHES a modifier (source key + priority + speed) and POPS it when done.
-- After every push/pop we RECOMPUTE the humanoid's WalkSpeed from the live stack, so
-- push/pop ORDER stops mattering: whoever runs last computes the same correct answer.
--
-- Resolution: highest priority wins (override semantics, NOT additive: a stun pins
-- you, it does not stack with block). Ties broken by most-recent push (handles
-- refresh/re-application like beam ticks). With no modifiers, speed is the live base
-- (GetBaseWalkSpeed * SpeedBoost), so stamina respecs and race boosts flow through
-- for free and there is never a stale "16" baked in anywhere.
--
-- SCOPE: this module owns WalkSpeed only. JumpPower / JumpHeight / AutoRotate stay
-- with their existing owners (hitstop, stun); far fewer writers touch them, so they
-- are not part of this race. Fold them in later if they ever start conflicting.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local StatScaling = require(RS.modules.StatScaling)

local SpeedService = {}

-- Priority bands. Higher wins. Leave gaps so new effects can slot between.
SpeedService.Priority = {
	PIN     = 100, -- Downed / hard root: absolute, speed 0
	STUN    = 80,  -- stun + hitstop: can't-walk-out hit reactions
	SKILL   = 60,  -- self-slow during a cast / skill windup
	BLOCK   = 50,  -- holding block
	DEBUFF  = 40,  -- external slows (Null Gaze etc.)
}

-- [char] = { [sourceKey] = { speed = n, priority = n, seq = n } }
local stacks = setmetatable({}, { __mode = "k" })
-- monotonic counter so ties resolve to the most recently pushed modifier
local seqCounter = 0

-- Live full speed for a character: stamina-scaled base * race SpeedBoost. This is
-- exactly what mainGameHandler.updateSpeed considers "default", so a character with
-- no active modifiers resolves to the same number that system would set.
function SpeedService.GetFullSpeed(char)
	local base = StatScaling.GetBaseWalkSpeed(char)
	local player = Players:GetPlayerFromCharacter(char)
	local statsFolder = player and player:FindFirstChild("PlayerStats")
	local boostVal = statsFolder and statsFolder:FindFirstChild("SpeedBoost")
	local boost = (boostVal and boostVal.Value and boostVal.Value > 0) and boostVal.Value or 1
	return base * boost
end

-- Compute the speed that SHOULD apply right now from the live stack, and write it.
-- Called after every push/pop; also safe to call on its own (e.g. when base speed
-- changes) to re-settle a character to the correct value.
function SpeedService.Resolve(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local winner = nil
	local stack = stacks[char]
	if stack then
		for _, mod in pairs(stack) do
			if not winner
				or mod.priority > winner.priority
				or (mod.priority == winner.priority and mod.seq > winner.seq) then
				winner = mod
			end
		end
	end

	if winner then
		hum.WalkSpeed = winner.speed
	else
		hum.WalkSpeed = SpeedService.GetFullSpeed(char)
	end
end

-- Push (or refresh) a modifier. source is a stable string key ("Block", "M1Slow",
-- "Stun", "Hitstop", "NullGaze", ...). Re-pushing the same source updates it in place
-- and bumps its recency, which is exactly the refresh semantics the beam ticks want.
function SpeedService.Push(char, source, speed, priority)
	if not char or not source then return end
	if not char:FindFirstChildOfClass("Humanoid") then return end
	if not stacks[char] then stacks[char] = {} end

	seqCounter += 1
	stacks[char][source] = { speed = speed, priority = priority, seq = seqCounter }
	SpeedService.Resolve(char)
end

-- Pop a modifier and re-settle. Popping a source that isn't present is a safe no-op,
-- so a double-clear (e.g. a timer firing after a manual clear) can't drive speed wrong.
function SpeedService.Pop(char, source)
	if not char or not source then return end
	local stack = stacks[char]
	if stack then
		stack[source] = nil
		if next(stack) == nil then stacks[char] = nil end
	end
	SpeedService.Resolve(char)
end

-- Is a given source currently applied?
function SpeedService.Has(char, source)
	local stack = stacks[char]
	return stack ~= nil and stack[source] ~= nil
end

-- Drop everything for a character (respawn / death / disconnect). Does NOT write speed
-- (the humanoid is usually gone); the fresh character starts with an empty stack.
function SpeedService.Clear(char)
	stacks[char] = nil
end

Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then SpeedService.Clear(plr.Character) end
end)

return SpeedService
