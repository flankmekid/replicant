-- SPDX-License-Identifier: MIT
--
-- Owns every write to Humanoid.WalkSpeed. Other scripts request a speed
-- change here and never write WalkSpeed directly. The reasons are in
-- docs/combat-design.md.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local StatScaling = require(RS.modules.StatScaling)

local SpeedService = {}

-- Priority bands. The highest priority wins. Gaps leave room for new effects.
SpeedService.Priority = {
	PIN = 100, -- Downed or rooted, speed 0.
	STUN = 80, -- Stun and hitstop.
	SKILL = 60, -- Self-slow during a cast or windup.
	BLOCK = 50, -- Holding block.
	DEBUFF = 40, -- Slows from others, such as Null Gaze.
}

-- Layout: stacks[char][source] = { speed, priority, seq }.
local stacks = setmetatable({}, { __mode = "k" })
-- Ties go to the most recent push.
local seqCounter = 0

-- SpeedService.GetFullSpeed() - get a character's speed with no modifiers
-- @char: the character
--
-- This is the stamina-scaled base times the race SpeedBoost, the same value that
-- mainGameHandler treats as the default.
--
-- Return: the WalkSpeed.
function SpeedService.GetFullSpeed(char)
	local base = StatScaling.GetBaseWalkSpeed(char)
	local player = Players:GetPlayerFromCharacter(char)
	local statsFolder = player and player:FindFirstChild("PlayerStats")
	local boostVal = statsFolder and statsFolder:FindFirstChild("SpeedBoost")
	local boost = (boostVal and boostVal.Value and boostVal.Value > 0) and boostVal.Value or 1
	return base * boost
end

-- SpeedService.Resolve() - write the WalkSpeed from the live modifier stack
-- @char: the character
--
-- Push and Pop call this. Call it directly when the base speed changes.
--
-- Return: nothing.
function SpeedService.Resolve(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	local winner = nil
	local stack = stacks[char]
	if stack then
		for _, mod in pairs(stack) do
			if
				not winner
				or mod.priority > winner.priority
				or (mod.priority == winner.priority and mod.seq > winner.seq)
			then
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

-- SpeedService.Push() - add or refresh a speed modifier
-- @char: the character
-- @source: a stable key, such as "Block", "Stun", or "Hitstop"
-- @speed: the WalkSpeed while the modifier wins
-- @priority: a value from SpeedService.Priority
--
-- Pushing the same source again updates it and makes it the most recent.
--
-- Return: nothing.
function SpeedService.Push(char, source, speed, priority)
	if not char or not source then
		return
	end
	if not char:FindFirstChildOfClass("Humanoid") then
		return
	end
	if not stacks[char] then
		stacks[char] = {}
	end

	seqCounter += 1
	stacks[char][source] = { speed = speed, priority = priority, seq = seqCounter }
	SpeedService.Resolve(char)
end

-- SpeedService.Pop() - remove a speed modifier
-- @char: the character
-- @source: the key used in Push
--
-- Popping a source that is not there is safe, so a timer that fires after a manual
-- clear cannot set a wrong speed.
--
-- Return: nothing.
function SpeedService.Pop(char, source)
	if not char or not source then
		return
	end
	local stack = stacks[char]
	if stack then
		stack[source] = nil
		if next(stack) == nil then
			stacks[char] = nil
		end
	end
	SpeedService.Resolve(char)
end

-- SpeedService.Has() - check whether a modifier is active
-- @char: the character
-- @source: the key used in Push
--
-- Return: true if the modifier is active.
function SpeedService.Has(char, source)
	local stack = stacks[char]
	return stack ~= nil and stack[source] ~= nil
end

-- SpeedService.Clear() - drop every modifier of a character
-- @char: the character
--
-- Does not write WalkSpeed, because on respawn, death, or leave the humanoid is
-- usually gone.
--
-- Return: nothing.
function SpeedService.Clear(char)
	stacks[char] = nil
end

Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then
		SpeedService.Clear(plr.Character)
	end
end)

return SpeedService
