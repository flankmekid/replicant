-- SPDX-License-Identifier: MIT
--
-- Handles the talk with Yuna in the Lantern quest: moves the quest to step 1 and points
-- the quest marker at SaruMarker2.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestManager = _G.QuestManager
local DataManager = require(ServerScriptService.modules.dataManager)

-- Create the remotes folder if the place does not have it.
local remotes = ReplicatedStorage:FindFirstChild("remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "remotes"
	remotes.Parent = ReplicatedStorage
end

local PickupRemote = remotes:FindFirstChild("YunaInteraction")

-- Latency slack on top of the reach of Yuna's prompt.
local talkSlack = 6

-- Each client moves Yuna up or down on its own screen, so only her horizontal position
-- is the same on the server.
local function isNearYuna(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local yuna = workspace:FindFirstChild("Yuna")
	local torso = yuna and yuna:FindFirstChild("Torso")
	local prompt = torso and torso:FindFirstChildWhichIsA("ProximityPrompt")
	if not root or not torso or not prompt then
		return false
	end
	local offset = root.Position - torso.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	return flat.Magnitude <= prompt.MaxActivationDistance + talkSlack
end

PickupRemote.OnServerEvent:Connect(function(player, questId)
	if questId ~= "Lantern" then
		return
	end
	if not isNearYuna(player) then
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
		warn("[YunaInteraction] _G.QuestManager is not available.")
		return
	end

	qm.IncrementProgress(player, questId, 1)

	-- Point the quest marker at the next step.
	local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
	local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
	local def = QuestConfig.Quests[questId]

	if def then
		local updatedDef = {}
		for k, v in pairs(def) do
			updatedDef[k] = v
		end
		updatedDef.TargetPartName = "SaruMarker2"

		QuestUpdateRemote:FireClient(player, "Update", {
			Id = questId,
			Progress = 1,
			Max = def.MaxProgress,
			Data = updatedDef,
		})
	end
end)
