-- SPDX-License-Identifier: MIT
--
-- Gives quest reward items. QuestServer calls _G.ItemRewardManager.GiveReward when a
-- quest with a RewardItem completes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local QuestItemReward = ReplicatedStorage.QuestSystem:WaitForChild("QuestItemReward")
local InventoryManager = require(ServerScriptService.modules:WaitForChild("inventoryManager"))

local ItemRewardManager = {}

local ITEM_HANDLERS = {
	VoidSpire = function(player)
		-- Only one per player.
		if DataManager.HasItem(player, "Void Spire") then
			return
		end

		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem("Void Spire", 1)
		end
	end,

	Lantern = function(player)
		-- Only one per player.
		if DataManager.HasItem(player, "Lantern") then
			return
		end

		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem("Lantern", 1)
		end
	end,
}

-- ItemRewardManager.GiveReward() - give a player a quest reward item
-- @player: the player
-- @itemName: the RewardItem key, "VoidSpire" or "Lantern"
--
-- Does nothing for an unknown item or one the player already has.
--
-- Return: nothing.
ItemRewardManager.GiveReward = function(player, itemName)
	local handler = ITEM_HANDLERS[itemName]
	if handler then
		handler(player)
	end
end

_G.ItemRewardManager = ItemRewardManager
