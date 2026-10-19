-- SPDX-License-Identifier: MIT
--
-- Owns quests on the server: assignment, progress, completion, rewards, the tracked
-- quest, and the class quest and hybrid skill reconcilers. The reconciler design is
-- in docs/systems-design.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
local DataManager = require(ServerScriptService.modules.dataManager)

local QuestManager = {}

-- The Liturgy cost of completing a class quest, by milestone.
local CLASS_QUEST_LITURGY_COST = {
	[15] = 500,
	[20] = 750,
	[25] = 1000,
}

local function buildPayload(questId, progress)
	local def = QuestConfig.Quests[questId]
	if not def then
		return nil
	end
	return { Id = questId, Data = def, Progress = progress or 0 }
end

local function buildActiveList(player)
	local entries = DataManager.GetAllActiveQuests(player)
	local list = {}
	for _, entry in ipairs(entries) do
		local def = QuestConfig.Quests[entry.Id]
		if def then
			table.insert(list, { Id = entry.Id, Data = def, Progress = entry.Progress })
		end
	end
	return list
end

-- QuestManager.AssignQuest() - give a player a quest
-- @player: the player
-- @questId: the quest ID in QuestConfig
--
-- Does nothing if the quest is active, its prerequisite is not met, or it is a
-- completed quest that cannot repeat.
--
-- Return: nothing.
function QuestManager.AssignQuest(player, questId)
	local questDef = QuestConfig.Quests[questId]
	if not questDef then
		warn(`[QuestServer] Unknown quest ID {questId}.`)
		return
	end

	local questData = DataManager.GetQuestData(player)
	if not questData then
		return
	end

	if DataManager.IsQuestActive(player, questId) then
		return
	end

	if questDef.Prerequisite and not table.find(questData.Completed, questDef.Prerequisite) then
		return
	end

	if table.find(questData.Completed, questId) then
		if not questDef.Repeatable then
			return
		end
	end

	DataManager.SetActiveQuest(player, questId)

	local tracked = DataManager.GetTrackedQuest(player)

	QuestUpdateRemote:FireClient(player, "New", buildPayload(questId, 0))

	if tracked == questId or DataManager.GetTrackedQuest(player) == questId then
		QuestUpdateRemote:FireClient(player, "Tracked", buildPayload(questId, 0))
	end

	if questDef.ClassQuest then
		QuestUpdateRemote:FireClient(player, "ClassQuestUnlocked", {
			Id = questId,
			Data = questDef,
		})
	end

	QuestUpdateRemote:FireClient(player, "ListUpdate", buildActiveList(player))
end

-- QuestManager.IncrementProgress() - add progress to an active quest
-- @player: the player
-- @questId: the quest ID
-- @amount: the progress to add
--
-- Completes the quest when progress reaches MaxProgress.
--
-- Return: nothing.
function QuestManager.IncrementProgress(player, questId, amount)
	local questDef = QuestConfig.Quests[questId]
	if not questDef then
		return
	end
	if not DataManager.IsQuestActive(player, questId) then
		return
	end

	local newProgress = DataManager.UpdateQuestProgress(player, questId, amount)

	if newProgress > questDef.MaxProgress then
		local entry = DataManager.GetActiveQuestEntry(player, questId)
		if entry then
			entry.Progress = questDef.MaxProgress
		end
		newProgress = questDef.MaxProgress
	end

	if newProgress >= questDef.MaxProgress then
		QuestManager.CompleteQuest(player, questId)
	else
		QuestUpdateRemote:FireClient(player, "Update", {
			Id = questId,
			Progress = newProgress,
			Max = questDef.MaxProgress,
		})
	end
end

-- QuestManager.CompleteQuest() - complete an active quest and give its rewards
-- @player: the player
-- @questId: the quest ID
--
-- Class quests above milestone 10 cost Liturgy. If the player cannot pay, the quest
-- stays active. Yields 0.5 seconds before it opens the next quest.
--
-- Return: nothing.
function QuestManager.CompleteQuest(player, questId)
	if not DataManager.IsQuestActive(player, questId) then
		return
	end

	local questDef = QuestConfig.Quests[questId]
	if not questDef then
		return
	end

	if questDef.ClassQuest and questDef.Milestone and questDef.Milestone > 10 then
		local cost = CLASS_QUEST_LITURGY_COST[questDef.Milestone] or 0
		if cost > 0 then
			local success = DataManager.RemoveLiturgy(player, cost)
			if not success then
				QuestUpdateRemote:FireClient(player, "InsufficientFunds", {
					Required = cost,
					QuestId = questId,
				})
				return
			end
		end
	end

	if questDef.LiturgyReward and questDef.LiturgyReward > 0 then
		DataManager.AddLiturgy(player, questDef.LiturgyReward)
	end

	DataManager.ClearActiveQuest(player, questId, true)

	QuestUpdateRemote:FireClient(player, "Complete", { Id = questId })

	local newTracked = DataManager.GetTrackedQuest(player)
	if newTracked then
		local entry = DataManager.GetActiveQuestEntry(player, newTracked)
		QuestUpdateRemote:FireClient(
			player,
			"Tracked",
			buildPayload(newTracked, entry and entry.Progress or 0)
		)
	else
		QuestUpdateRemote:FireClient(player, "Tracked", nil)
	end

	QuestUpdateRemote:FireClient(player, "ListUpdate", buildActiveList(player))

	-- Class quests do not chain through NextQuest. The reconciler opens the next earned
	-- checkpoint.
	if questDef.ClassQuest and questDef.Weapon then
		task.wait(0.5)
		QuestManager.ReconcileClassQuests(player, questDef.Weapon)
	elseif questDef.NextQuest then
		local nextDef = QuestConfig.Quests[questDef.NextQuest]
		if not (nextDef and nextDef.ClassQuest) then
			task.wait(0.5)
			QuestManager.AssignQuest(player, questDef.NextQuest)
		end
	end

	if questDef.RewardItem then
		local irm = _G.ItemRewardManager
		if irm then
			irm.GiveReward(player, questDef.RewardItem)
		else
			warn(`[QuestServer] ItemRewardManager is missing, so {player.Name} got no reward.`)
		end
	end
end

-- QuestManager.SetTracked() - set the quest a player tracks
-- @player: the player
-- @questId: an active quest ID, or nil to track nothing
--
-- Return: nothing.
function QuestManager.SetTracked(player, questId)
	if questId ~= nil and not DataManager.IsQuestActive(player, questId) then
		return
	end
	DataManager.SetTrackedQuest(player, questId)

	if questId then
		local entry = DataManager.GetActiveQuestEntry(player, questId)
		QuestUpdateRemote:FireClient(
			player,
			"Tracked",
			buildPayload(questId, entry and entry.Progress or 0)
		)
	else
		QuestUpdateRemote:FireClient(player, "Tracked", nil)
	end
end

local CLASS_MILESTONES = { 10, 15, 20, 25 }

-- Returns the open class quest of a family, or nil. Only one is open at a time.
local function getActiveClassQuest(player, family)
	local entries = DataManager.GetAllActiveQuests(player)
	for _, entry in ipairs(entries) do
		local def = QuestConfig.Quests[entry.Id]
		if def and def.ClassQuest and def.Weapon == family then
			return entry.Id
		end
	end
	return nil
end

-- QuestManager.ReconcileClassQuests() - open the next earned class quest of a family
-- @player: the player
-- @family: the weapon family
--
-- Safe to call any number of times. Does nothing when nothing changed.
--
-- Return: nothing.
function QuestManager.ReconcileClassQuests(player, family)
	if not family then
		return
	end

	local questData = DataManager.GetQuestData(player)
	if not questData then
		return
	end

	-- One at a time: the player visits the trainer before the next one unlocks.
	if getActiveClassQuest(player, family) then
		return
	end

	local level = DataManager.GetWeaponLevel(player, family)
	if level <= 0 then
		return
	end

	-- The lowest milestone that the level has earned and that is not completed.
	for _, milestone in ipairs(CLASS_MILESTONES) do
		if level >= milestone then
			local questId = "ClassQuest_" .. family .. "_" .. milestone
			if QuestConfig.Quests[questId] and not table.find(questData.Completed, questId) then
				QuestManager.AssignQuest(player, questId)
				return
			end
		end
	end
end

-- QuestManager.ReconcileAllClassQuests() - reconcile every weapon family and hybrid
-- @player: the player
--
-- The login path. It recovers checkpoints stranded in an earlier session.
--
-- Return: nothing.
function QuestManager.ReconcileAllClassQuests(player)
	local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

	local seen = {}
	for _, family in pairs(SkillConfig.WeaponFamily) do
		if not seen[family] and not SkillConfig.HybridParents[family] then
			seen[family] = true
			QuestManager.ReconcileClassQuests(player, family)
		end
	end

	QuestManager.ReconcileHybrids(player)
end

-- QuestManager.ReconcileHybrids() - unlock the hybrid skills a player has earned
-- @player: the player
--
-- A hybrid skill unlocks when both parent families reach its threshold. Safe to call
-- any number of times.
--
-- Return: nothing.
function QuestManager.ReconcileHybrids(player)
	local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

	for hybridName, parents in pairs(SkillConfig.HybridParents) do
		-- The lower parent level decides.
		local lowest = math.huge
		for _, parentFamily in ipairs(parents) do
			local lvl = DataManager.GetWeaponLevel(player, parentFamily)
			if lvl < lowest then
				lowest = lvl
			end
		end
		if lowest == math.huge then
			lowest = 0
		end

		local skills = SkillConfig.WeaponSkills[hybridName]
		if skills then
			for slotIndex, threshold in pairs(SkillConfig.HybridSkillThresholds) do
				local skillName = skills[slotIndex]
				if
					skillName
					and lowest >= threshold
					and not DataManager.HasSpell(player, skillName)
				then
					DataManager.UnlockSpell(player, skillName)
					QuestUpdateRemote:FireClient(player, "HybridSkillUnlocked", {
						Weapon = hybridName,
						Skill = skillName,
						Slot = SkillConfig.SlotKeys[slotIndex],
					})
				end
			end
		end
	end
end

-- QuestManager.RestoreSession() - send a joining player their quests
-- @player: the player
--
-- Yields until the profile is loaded. Reconciles class quests first, so a stranded
-- checkpoint is in the list.
--
-- Return: nothing.
function QuestManager.RestoreSession(player)
	DataManager.YieldUntilLoaded(player)

	local questData = DataManager.GetQuestData(player)
	if not questData then
		return
	end

	-- Reconcile before building the list, so a recovered checkpoint is in it.
	QuestManager.ReconcileAllClassQuests(player)

	local activeList = buildActiveList(player)
	if #activeList == 0 then
		return
	end

	for _, entry in ipairs(activeList) do
		QuestUpdateRemote:FireClient(player, "New", buildPayload(entry.Id, entry.Progress))
		task.wait(0.05)
	end

	QuestUpdateRemote:FireClient(player, "ListUpdate", activeList)
	task.wait(0.1)

	local tracked = DataManager.GetTrackedQuest(player)
	if tracked then
		local entry = DataManager.GetActiveQuestEntry(player, tracked)
		if entry then
			QuestUpdateRemote:FireClient(player, "Tracked", buildPayload(tracked, entry.Progress))
		end
	end
end

_G.QuestManager = QuestManager
return QuestManager
