-- [[ VOID SPIRE REWARD HANDLER ]]
-- Location: ServerScriptService (Script)
-- Listens for QuestItemReward remote and gives the appropriate item.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager     = require(ServerScriptService.modules.dataManager)
local QuestItemReward = ReplicatedStorage.QuestSystem:WaitForChild("QuestItemReward")
local InventoryManager = require(ServerScriptService.modules:WaitForChild("inventoryManager"))

local ItemRewardManager = {}

local ITEM_HANDLERS = {
	VoidSpire = function(player)
		-- Check player doesn't already have one
		if DataManager.HasItem(player, "Void Spire") then
			return
		end
		

		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem("Void Spire", 1)
		end
		
		print(player.Name .. " received the Void Spire.")
	end,
	
	Lantern = function(player)
		-- Check player doesn't already have one
		if DataManager.HasItem(player, "Lantern") then
			return
		end


		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem("Lantern", 1)
		end

		print(player.Name .. " received the Void Spire.")
	end,
}

ItemRewardManager.GiveReward = function(player, itemName)
	local handler = ITEM_HANDLERS[itemName]
	if handler then handler(player) end
end

_G.ItemRewardManager = ItemRewardManager