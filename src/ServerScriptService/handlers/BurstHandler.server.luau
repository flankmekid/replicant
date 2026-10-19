-- BurstHandler: the universal combo-breaker "burst" (bound to T on the client).
-- Server-authoritative mana + cooldown gate, then runs SkillFunctions.Burst.
--
-- Why this is its own handler and not a SkillConfig entry routed through
-- SkillHandler:
--   * Burst is universal (owned by everyone), so it fails SkillHandler's
--     ownership verification by design.
--   * Its cost is a PERCENTAGE of MaxMana (50%), which SkillConfig's flat Mana
--     field can't express.
--   * Crucially, it must be castable WHILE STUNNED -- that is the entire point
--     of a combo-breaker. SkillHandler rejects casts while Stunned; this handler
--     deliberately allows it, and only blocks Downed / an in-progress burst.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local SkillFunctions = require(ServerScriptService.modules.SkillFunctions)

local BurstRemote = ReplicatedStorage.remotes:WaitForChild("Burst")

-- [[ TUNING ]]
local MANA_FRACTION = 0.5   -- fraction of MaxMana spent per burst
local COOLDOWN      = 12     -- seconds, server-authoritative

-- os.clock() timestamp per player of when burst is next ready
local nextReady = setmetatable({}, { __mode = "k" })

local function reply(player, decision, cooldown)
	BurstRemote:FireClient(player, {
		Func = "BurstResponse",
		Decision = decision,
		Cooldown = cooldown, -- present only on Accepted
	})
end

BurstRemote.OnServerEvent:Connect(function(player)
	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		reply(player, "Declined")
		return
	end

	-- State gate. Unlike skills, Stunned is ALLOWED (burst exists to break stun).
	-- Downed cannot burst (revive owns that state). We reject Downed here explicitly;
	-- the mid-action (CantAnything-without-Stunned) gate follows below.
	if char:GetAttribute("Downed") then
		reply(player, "Declined")
		return
	end

	-- Mid-action gate. CantAnything means "locked in an action's recovery"; Stunned
	-- means "being combo'd". Burst is meant to break OUT of a combo (Stunned) or fire
	-- when nothing is happening, NOT to cancel the user's OWN attack recovery. The
	-- one case that is CantAnything-without-Stunned is exactly the user mid-M1 (their
	-- own swing's lock), so reject that. Every other combination passes: Stunned alone
	-- (being hit) and Stunned+CantAnything (hit while their own action lingered) are
	-- both legitimate breaks, and neither-set (idle) is fine.
	if char:GetAttribute("CantAnything") and not char:GetAttribute("Stunned") then
		reply(player, "Declined")
		return
	end

	-- Cooldown check
	local now = os.clock()
	if nextReady[player] and now < nextReady[player] then
		reply(player, "Declined")
		return
	end

	-- Resource check: 50% of MaxMana
	local stats = player:FindFirstChild("PlayerStats")
	local mana = stats and stats:FindFirstChild("Mana")
	local maxMana = stats and stats:FindFirstChild("MaxMana")
	if not mana or not maxMana or maxMana.Value <= 0 then
		reply(player, "Declined")
		return
	end
	local cost = maxMana.Value * MANA_FRACTION
	if mana.Value < cost then
		reply(player, "Declined")
		return
	end

	-- Commit: spend, arm cooldown, confirm, then run.
	mana.Value = mana.Value - cost
	nextReady[player] = now + COOLDOWN
	reply(player, "Accepted", COOLDOWN)

	task.spawn(function()
		SkillFunctions.Burst(player)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	nextReady[plr] = nil
end)
