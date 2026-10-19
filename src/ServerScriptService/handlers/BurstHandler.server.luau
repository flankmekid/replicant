-- SPDX-License-Identifier: MIT
--
-- Checks the mana cost and cooldown of Burst (T) on the server, then runs
-- SkillFunctions.Burst. Burst has its own handler instead of SkillHandler, because it
-- must work while stunned. The reasons are in docs/combat-design.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local SkillFunctions = require(ServerScriptService.modules.SkillFunctions)

local BurstRemote = ReplicatedStorage.remotes:WaitForChild("Burst")

-- The fraction of MaxMana that a burst costs.
local manaFraction = 0.5
-- The cooldown in seconds.
local COOLDOWN = 12

-- The os.clock() time when each player's burst is ready again.
local nextReady = setmetatable({}, { __mode = "k" })

local function reply(player, decision, cooldown)
	BurstRemote:FireClient(player, {
		Func = "BurstResponse",
		Decision = decision,
		Cooldown = cooldown, -- Only on Accepted.
	})
end

BurstRemote.OnServerEvent:Connect(function(player)
	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		reply(player, "Declined")
		return
	end

	-- Stunned is allowed, because Burst exists to break a stun. Downed is not.
	if char:GetAttribute("Downed") then
		reply(player, "Declined")
		return
	end

	-- CantAnything without Stunned means the user is in their own attack recovery, and
	-- Burst must not cancel that. Being hit (Stunned) and idle are both allowed.
	if char:GetAttribute("CantAnything") and not char:GetAttribute("Stunned") then
		reply(player, "Declined")
		return
	end

	local now = os.clock()
	if nextReady[player] and now < nextReady[player] then
		reply(player, "Declined")
		return
	end

	local stats = player:FindFirstChild("PlayerStats")
	local mana = stats and stats:FindFirstChild("Mana")
	local maxMana = stats and stats:FindFirstChild("MaxMana")
	if not mana or not maxMana or maxMana.Value <= 0 then
		reply(player, "Declined")
		return
	end
	local cost = maxMana.Value * manaFraction
	if mana.Value < cost then
		reply(player, "Declined")
		return
	end

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
