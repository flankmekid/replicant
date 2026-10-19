-- [[ VOID SHARD PICKUP HANDLER ]]
-- Location: ServerScriptService (Script)
-- Handles the ShardPickup remote, validates quest state,
-- and increments progress to step 1.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestManager  = _G.QuestManager
local DataManager   = require(ServerScriptService.modules.dataManager)

-- Ensure remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "remotes"
	remotes.Parent = ReplicatedStorage
end

local PickupRemote = remotes:FindFirstChild("YunaInteraction")

PickupRemote.OnServerEvent:Connect(function(player, questId)
	if questId ~= "Lantern" then return end

	-- Validate quest is active and at progress 0
	local questData = DataManager.GetQuestData(player)
	if not questData then return end

	local entry = DataManager.GetActiveQuestEntry(player, questId)
	if not entry then return end
	if entry.Progress ~= 0 then return end

	-- Wait for QuestManager to be available via _G
	local attempts = 0
	while not _G.QuestManager and attempts < 10 do
		task.wait(0.5)
		attempts += 1
	end

	local qm = _G.QuestManager
	if not qm then
		warn("QuestManager not available.")
		return
	end

	-- Increment to step 1 — shard collected, now return to Sidurgu
	qm.IncrementProgress(player, questId, 1)

	-- Update the quest marker to point at Sidurgu now
	local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
	local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
	local def = QuestConfig.Quests[questId]

	if def then
		local updatedDef = {}
		for k, v in pairs(def) do updatedDef[k] = v end
		updatedDef.TargetPartName = "SaruMarker2"

		QuestUpdateRemote:FireClient(player, "Update", {
			Id       = questId,
			Progress = 1,
			Max      = def.MaxProgress,
			Data     = updatedDef,
		})
	end

	print(player.Name .. " progressed quest.")
end)