-- SPDX-License-Identifier: MIT
--
-- Handles the quest remotes from the client: track, abandon, the quest state query, and
-- the ready signal that restores the session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestManager = require(ServerScriptService.modules.QuestServer)
local DataManager = require(ServerScriptService.modules.dataManager)
local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
local QuestActionRemote = ReplicatedStorage:WaitForChild("QuestSystem"):WaitForChild("QuestAction")
local QuestStateRequest = ReplicatedStorage:WaitForChild("QuestSystem")
	:WaitForChild("QuestStateRequest")

-- The client may only track and abandon. Starting and completing a quest are server
-- decisions: a client that could send them would skip the quest and take the rewards.
QuestActionRemote.OnServerEvent:Connect(function(player, action, questId)
	if action == "Track" then
		-- A nil questId untracks.
		QuestManager.SetTracked(player, questId)
	elseif action == "Abandon" then
		-- Class quests cannot be abandoned.
		local def = QuestConfig.Quests[questId]
		if def and def.ClassQuest then
			warn(`[QuestNetworkHandler] {player.Name} tried to abandon class quest {questId}.`)
			return
		end
		DataManager.ClearActiveQuest(player, questId, false)
		local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
		QuestUpdateRemote:FireClient(player, "Complete", { Id = questId })
		QuestUpdateRemote:FireClient(
			player,
			"ListUpdate",
			(function()
				local entries = DataManager.GetAllActiveQuests(player)
				local list = {}
				for _, entry in ipairs(entries) do
					local d = QuestConfig.Quests[entry.Id]
					if d then
						table.insert(list, { Id = entry.Id, Data = d, Progress = entry.Progress })
					end
				end
				return list
			end)()
		)
	end
end)

QuestStateRequest.OnServerInvoke = function(player, questId)
	local questData = DataManager.GetQuestData(player)
	if not questData then
		return { active = false, completed = false, progress = 0 }
	end

	local entry = DataManager.GetActiveQuestEntry(player, questId)
	local isActive = entry ~= nil
	local isDone = table.find(questData.Completed, questId) ~= nil

	return {
		active = isActive,
		completed = isDone,
		progress = entry and entry.Progress or 0,
	}
end

local QuestReadyRemote = ReplicatedStorage:WaitForChild("QuestSystem"):WaitForChild("QuestReady")

QuestReadyRemote.OnServerEvent:Connect(function(player)
	-- The client UI is ready, so the session can be restored.
	task.wait(0.1)
	QuestManager.RestoreSession(player)
end)
