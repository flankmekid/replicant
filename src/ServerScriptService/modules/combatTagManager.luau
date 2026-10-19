-- SPDX-License-Identifier: MIT
--
-- Owns the combat tag of each player: who attacked them, when the tag expires, and the
-- CombatLogExpiry attribute and HUD state that other scripts read.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatManager = {}
local ActiveTags = {}
local TAG_DURATION = 30

-- Create the HUD remote if the place does not have it.
local Events = ReplicatedStorage:FindFirstChild("remotes")
if not Events then
	Events = Instance.new("Folder")
	Events.Name = "remotes"
	Events.Parent = ReplicatedStorage
end
local CombatEvent = Events:FindFirstChild("CombatTagUpdate")
if not CombatEvent then
	CombatEvent = Instance.new("RemoteEvent")
	CombatEvent.Name = "CombatTagUpdate"
	CombatEvent.Parent = Events
end

-- Clears the table entry, the attribute, the HUD, and the character flag.
local function clearTag(victim)
	ActiveTags[victim] = nil
	if victim then
		CombatEvent:FireClient(victim, false)
		victim:SetAttribute("CombatLogExpiry", nil)
		if victim.Character then
			victim.Character:SetAttribute("InCombat", nil)
		end
	end
end

-- CombatManager.TagPlayer() - tag a player as in combat
-- @victim: the player who was hit
-- @attacker: the player who hit them, or nil
--
-- Refreshes the expiry if the victim is already tagged.
--
-- Return: nothing.
function CombatManager.TagPlayer(victim, attacker)
	if not victim or not victim:IsA("Player") then
		return
	end

	local expiryTime = os.clock() + TAG_DURATION
	local currentTag = ActiveTags[victim]

	if currentTag then
		-- Already tagged: refresh the expiry and add this attacker.
		currentTag.Expiry = expiryTime
		if attacker and attacker:IsA("Player") and attacker ~= victim then
			currentTag.Attackers[attacker] = true
		end
	else
		local attackers = {}
		if attacker and attacker:IsA("Player") and attacker ~= victim then
			attackers[attacker] = true
		end
		ActiveTags[victim] = {
			Expiry = expiryTime,
			Attackers = attackers,
		}
	end

	-- DataManager reads this attribute, so it does not need this module.
	victim:SetAttribute("CombatLogExpiry", expiryTime)

	CombatEvent:FireClient(victim, true, TAG_DURATION)

	-- Other scripts and NPCs read InCombat.
	if victim.Character then
		victim.Character:SetAttribute("InCombat", true)
	end
end

-- CombatManager.SetTagDuration() - shorten a player's combat tag
-- @player: the tagged player
-- @duration: the new time left in seconds
--
-- Never extends the tag.
--
-- Return: nothing.
function CombatManager.SetTagDuration(player, duration)
	local currentTag = ActiveTags[player]
	if currentTag then
		local newExpiry = os.clock() + duration
		if newExpiry < currentTag.Expiry then
			currentTag.Expiry = newExpiry
			player:SetAttribute("CombatLogExpiry", newExpiry)
			CombatEvent:FireClient(player, true, duration)
		end
	end
end

-- Removes a single attacker from every victim's set.
-- Fully untags a victim only if that leaves the set empty.
local function removeAttackerFromAll(attacker)
	for victim, data in pairs(ActiveTags) do
		if data.Attackers[attacker] then
			data.Attackers[attacker] = nil
			if next(data.Attackers) == nil then
				clearTag(victim)
			end
		end
	end
end

-- CombatManager.UntagIfAttackerDied() - remove a dead player as an attacker
-- @deadPlayer: the player who died
--
-- Untags a victim only when no other attacker is left.
--
-- Return: nothing.
function CombatManager.UntagIfAttackerDied(deadPlayer)
	removeAttackerFromAll(deadPlayer)
end

-- CombatManager.ClearPlayerTag() - clear a player's own combat tag
-- @player: the player
--
-- Called on death, so dying ends combat at once: combat music, InCombat, and aggro.
--
-- Return: nothing.
function CombatManager.ClearPlayerTag(player)
	-- This also resets the HUD and the attributes when there is no table entry.
	clearTag(player)
end

-- CombatManager.HandlePlayerLeft() - clean up after a player leaves
-- @player: the player who left
--
-- DataManager calls this from its own PlayerRemoving handler to avoid a race.
--
-- Return: nothing.
function CombatManager.HandlePlayerLeft(player)
	removeAttackerFromAll(player)
	if ActiveTags[player] then
		ActiveTags[player] = nil
	end
end

-- CombatManager.ClearMyTags() - remove every tag a player handed out
-- @player: the player who typed "mb" in chat
--
-- Does not touch the player's own tag.
--
-- Return: nothing.
function CombatManager.ClearMyTags(player)
	removeAttackerFromAll(player)
end

-- Clear expired tags once per second.
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, data in pairs(ActiveTags) do
			if now >= data.Expiry then
				clearTag(player)
			end
		end
	end
end)

return CombatManager
