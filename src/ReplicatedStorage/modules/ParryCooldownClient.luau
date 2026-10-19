--[[
	ParryCooldownClient
	Client-side mirror of the server's ParryService cooldown.

	This is the LOCAL prediction + UI feed. The server (ParryService) is the real
	authority; this exists so the client doesn't fire a parry the server will reject,
	and so the CooldownTracker sweep matches what the server is actually doing.

	Single source of truth for the client parry cooldown across all 14 weapons, so
	weapon Block modules and the replication dispatcher all read/write the same state
	instead of each Block keeping its own trapped local.

	Numbers must match ParryService on the server:
		BASE  = 5   (full lockout on a parry press)
		RESET = 1   (partial reset when a parry lands)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CooldownTracker = require(ReplicatedStorage.modules.CooldownTracker)

local ParryCooldownClient = {}

local BASE = 5
local RESET = 1

-- single local timer for the local player (one character, one parry cooldown)
local nextParryTime = 0

-- weaponId: the CooldownTracker id, e.g. "Katana_Block". Passed in so the UI entry
-- matches the per-weapon id the Block modules already use.

function ParryCooldownClient.CanParry()
	return os.clock() >= nextParryTime
end

-- Called on parry PRESS. Starts the full local lockout and shows it on the UI.
function ParryCooldownClient.StartCooldown(weaponId)
	nextParryTime = os.clock() + BASE
	if weaponId then
		CooldownTracker.Register(weaponId, "Parry", BASE)
	end
end

-- Called when the local player LANDS a parry (told by the server via the dispatcher).
-- Shortens the local timer to the partial reset and refreshes the UI entry in place.
-- Only ever shortens, never extends.
function ParryCooldownClient.Reset(weaponId)
	local target = os.clock() + RESET
	if target < nextParryTime then
		nextParryTime = target
		if weaponId then
			CooldownTracker.Register(weaponId, "Parry", RESET)
		end
	end
end

function ParryCooldownClient.GetRemaining()
	return math.max(0, nextParryTime - os.clock())
end

return ParryCooldownClient
