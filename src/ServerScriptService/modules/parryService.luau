-- SPDX-License-Identifier: MIT
--
-- Owns the parry cooldown on the server. Clients keep a local copy only for input
-- feel. The cooldown model is in docs/combat-design.md.

local Players = game:GetService("Players")

local ParryService = {}

-- Every parry press starts the full cooldown. A landed parry shortens it.
local baseCooldown = 5
local resetCooldown = 1

-- The os.clock() time when each player may parry again.
local nextParryTime = {}

-- ParryService.CanParry() - check whether a player may parry now
-- @plr: the player
--
-- Return: true if the cooldown is over, false otherwise or when plr is nil.
function ParryService.CanParry(plr)
	if not plr then
		return false
	end
	local readyAt = nextParryTime[plr]
	if not readyAt then
		return true
	end
	return os.clock() >= readyAt
end

-- ParryService.StartCooldown() - start the full cooldown on a parry press
-- @plr: the player who pressed parry
--
-- Return: nothing.
function ParryService.StartCooldown(plr)
	if not plr then
		return
	end
	nextParryTime[plr] = os.clock() + baseCooldown
end

-- ParryService.ResetParry() - shorten the cooldown after a landed parry
-- @plr: the player whose parry landed
--
-- Never extends a cooldown that is already shorter.
--
-- Return: nothing.
function ParryService.ResetParry(plr)
	if not plr then
		return
	end
	local target = os.clock() + resetCooldown
	local current = nextParryTime[plr]
	if not current or target < current then
		nextParryTime[plr] = target
	end
end

-- ParryService.GetRemaining() - get the time left on a player's cooldown
-- @plr: the player
--
-- Return: the seconds left, or 0.
function ParryService.GetRemaining(plr)
	if not plr then
		return 0
	end
	local readyAt = nextParryTime[plr]
	if not readyAt then
		return 0
	end
	return math.max(0, readyAt - os.clock())
end

Players.PlayerRemoving:Connect(function(plr)
	nextParryTime[plr] = nil
end)

return ParryService
