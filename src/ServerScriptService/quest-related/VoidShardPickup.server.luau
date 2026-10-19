-- SPDX-License-Identifier: MIT
--
-- Handles the Void-stone shard pickup of the SidurguErrand quest: moves the quest to
-- step 1 and points the quest marker back at Sidurgu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestManager = _G.QuestManager
local DataManager = require(ServerScriptService.modules.dataManager)

-- Create the remotes if the place does not have them.
local remotes = ReplicatedStorage:FindFirstChild("remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "remotes"
	remotes.Parent = ReplicatedStorage
end

local PickupRemote = remotes:FindFirstChild("ShardPickup")
if not PickupRemote then
	PickupRemote = Instance.new("RemoteEvent")
	PickupRemote.Name = "ShardPickup"
	PickupRemote.Parent = remotes
end

PickupRemote.OnServerEvent:Connect(function(player, questId)
	if questId ~= "SidurguErrand" then
		return
	end

	-- The quest must be active and at step 0.
	local questData = DataManager.GetQuestData(player)
	if not questData then
		return
	end

	local entry = DataManager.GetActiveQuestEntry(player, questId)
	if not entry then
		return
	end
	if entry.Progress ~= 0 then
		return
	end

	-- QuestServer sets _G.QuestManager, which may not exist yet.
	local attempts = 0
	while not _G.QuestManager and attempts < 10 do
		task.wait(0.5)
		attempts += 1
	end

	local qm = _G.QuestManager
	if not qm then
		warn("[VoidShardPickup] _G.QuestManager is not available.")
		return
	end

	qm.IncrementProgress(player, questId, 1)

	-- Point the quest marker at Sidurgu.
	local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
	local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
	local def = QuestConfig.Quests[questId]

	if def then
		local updatedDef = {}
		for k, v in pairs(def) do
			updatedDef[k] = v
		end
		updatedDef.TargetPartName = "SidurguMarker"

		QuestUpdateRemote:FireClient(player, "Update", {
			Id = questId,
			Progress = 1,
			Max = def.MaxProgress,
			Data = updatedDef,
		})
	end
end)
