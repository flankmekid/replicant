-- SPDX-License-Identifier: MIT
--
-- The client copy of the server's parry cooldown (ParryService), for prediction and the
-- HUD. It stops the client from firing a parry the server would reject. Every weapon's
-- Block module uses this one timer. BASE and RESET must match ParryService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CooldownTracker = require(ReplicatedStorage.modules.CooldownTracker)

local ParryCooldownClient = {}

local BASE = 5
local RESET = 1

-- One timer, because the local player has one character.
local nextParryTime = 0

-- ParryCooldownClient.CanParry() - check whether the local player may parry
--
-- Return: true if the cooldown is over.
function ParryCooldownClient.CanParry()
	return os.clock() >= nextParryTime
end

-- ParryCooldownClient.StartCooldown() - start the full cooldown on a parry press
-- @weaponId: the CooldownTracker id, such as "Katana_Block", or nil for no HUD entry
--
-- Return: nothing.
function ParryCooldownClient.StartCooldown(weaponId)
	nextParryTime = os.clock() + BASE
	if weaponId then
		CooldownTracker.Register(weaponId, "Parry", BASE)
	end
end

-- ParryCooldownClient.Reset() - shorten the cooldown after a landed parry
-- @weaponId: the CooldownTracker id, or nil for no HUD entry
--
-- Never extends a cooldown that is already shorter.
--
-- Return: nothing.
function ParryCooldownClient.Reset(weaponId)
	local target = os.clock() + RESET
	if target < nextParryTime then
		nextParryTime = target
		if weaponId then
			CooldownTracker.Register(weaponId, "Parry", RESET)
		end
	end
end

-- ParryCooldownClient.GetRemaining() - get the time left on the cooldown
--
-- Return: the seconds left, or 0.
function ParryCooldownClient.GetRemaining()
	return math.max(0, nextParryTime - os.clock())
end

return ParryCooldownClient
