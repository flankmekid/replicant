--[[
	ParryService
	Server-authoritative parry cooldown.

	Model:
	- Pressing parry starts the FULL cooldown immediately (BASE_COOLDOWN).
	- Landing a parry shortens it to RESET_COOLDOWN (partial reset, keeps the dance going).
	- A whiffed parry never gets shortened, so it stays at the full lockout. No whiff
	  detection needed: the lockout is just the default that a land pulls back.
	- Getting parried does NOT touch your cooldown. That is the trade.

	Authority lives here. Clients keep a local mirror for input feel only.
]]

local Players = game:GetService("Players")

local ParryService = {}

local BASE_COOLDOWN = 5    -- full lockout, applied on every parry press
local RESET_COOLDOWN = 1   -- partial reset applied when a parry lands

-- per-player timestamp (os.clock based) of when the player may parry again
local nextParryTime = {}

-- Returns true if the player is allowed to parry right now.
function ParryService.CanParry(plr)
	if not plr then return false end
	local readyAt = nextParryTime[plr]
	if not readyAt then return true end
	return os.clock() >= readyAt
end

-- Called when a parry is ATTEMPTED (on press). Starts the full cooldown.
function ParryService.StartCooldown(plr)
	if not plr then return end
	nextParryTime[plr] = os.clock() + BASE_COOLDOWN
end

-- Called when a parry LANDS. Shortens the cooldown to the partial reset.
-- Only ever shortens; never extends an already-shorter cooldown.
function ParryService.ResetParry(plr)
	if not plr then return end
	local target = os.clock() + RESET_COOLDOWN
	local current = nextParryTime[plr]
	if not current or target < current then
		nextParryTime[plr] = target
	end
end

-- Optional helper for the client mirror / UI if you ever want to query remaining time.
function ParryService.GetRemaining(plr)
	if not plr then return 0 end
	local readyAt = nextParryTime[plr]
	if not readyAt then return 0 end
	return math.max(0, readyAt - os.clock())
end

Players.PlayerRemoving:Connect(function(plr)
	nextParryTime[plr] = nil
end)

return ParryService
