local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestConfig         = require(ReplicatedStorage.QuestSystem.QuestConfig)
local QuestUpdateRemote   = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
local DataManager         = require(ServerScriptService.modules.dataManager)

local QuestManager = {}

local CLASS_QUEST_LITURGY_COST = {
	[15] = 500,
	[20] = 750,
	[25] = 1000,
}

local function buildPayload(questId, progress)
	local def = QuestConfig.Quests[questId]
	if not def then return nil end
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

function QuestManager.AssignQuest(player, questId)
	local questDef = QuestConfig.Quests[questId]
	if not questDef then warn("Invalid Quest ID: " .. tostring(questId)) return end

	local questData = DataManager.GetQuestData(player)
	if not questData then return end

	if DataManager.IsQuestActive(player, questId) then return end

	if questDef.Prerequisite and not table.find(questData.Completed, questDef.Prerequisite) then
		print("Prerequisite not met for: " .. questId)
		return
	end

	if table.find(questData.Completed, questId) then
		if not questDef.Repeatable then
			print("Already completed non-repeatable quest: " .. questId)
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
			Id   = questId,
			Data = questDef,
		})
	end

	QuestUpdateRemote:FireClient(player, "ListUpdate", buildActiveList(player))

	print(player.Name .. " started quest: " .. questId)
end

function QuestManager.IncrementProgress(player, questId, amount)
	local questDef = QuestConfig.Quests[questId]
	if not questDef then return end
	if not DataManager.IsQuestActive(player, questId) then return end

	local newProgress = DataManager.UpdateQuestProgress(player, questId, amount)

	if newProgress > questDef.MaxProgress then
		local entry = DataManager.GetActiveQuestEntry(player, questId)
		if entry then entry.Progress = questDef.MaxProgress end
		newProgress = questDef.MaxProgress
	end

	if newProgress >= questDef.MaxProgress then
		QuestManager.CompleteQuest(player, questId)
	else
		QuestUpdateRemote:FireClient(player, "Update", {
			Id       = questId,
			Progress = newProgress,
			Max      = questDef.MaxProgress,
		})
	end
end

function QuestManager.CompleteQuest(player, questId)
	if not DataManager.IsQuestActive(player, questId) then return end

	local questDef = QuestConfig.Quests[questId]
	if not questDef then return end

	if questDef.ClassQuest and questDef.Milestone and questDef.Milestone > 10 then
		local cost = CLASS_QUEST_LITURGY_COST[questDef.Milestone] or 0
		if cost > 0 then
			local success = DataManager.RemoveLiturgy(player, cost)
			if not success then
				QuestUpdateRemote:FireClient(player, "InsufficientFunds", {
					Required = cost,
					QuestId  = questId,
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
		QuestUpdateRemote:FireClient(player, "Tracked", buildPayload(newTracked, entry and entry.Progress or 0))
	else
		QuestUpdateRemote:FireClient(player, "Tracked", nil)
	end

	QuestUpdateRemote:FireClient(player, "ListUpdate", buildActiveList(player))

	-- Class quests do NOT chain via NextQuest. Completing one hands control back to
	-- the reconciler, which re-reads mastery and opens the next earned checkpoint.
	-- This is what makes "complete _10 at mastery 22" immediately surface _15, and
	-- then _20, rather than stranding them behind a level-up that already happened.
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
	
	print("[QuestServer] Completing quest: " .. questId)
	print("[QuestServer] RewardItem: " .. tostring(questDef.RewardItem))
	print("[QuestServer] ItemRewardManager: " .. tostring(_G.ItemRewardManager))

	if questDef.RewardItem then
		local irm = _G.ItemRewardManager
		if irm then
			print("[QuestServer] Calling GiveReward...")
			irm.GiveReward(player, questDef.RewardItem)
		else
			warn("[QuestServer] ItemRewardManager is nil — reward not given.")
		end
	end
end

function QuestManager.SetTracked(player, questId)
	if questId ~= nil and not DataManager.IsQuestActive(player, questId) then return end
	DataManager.SetTrackedQuest(player, questId)

	if questId then
		local entry = DataManager.GetActiveQuestEntry(player, questId)
		QuestUpdateRemote:FireClient(player, "Tracked", buildPayload(questId, entry and entry.Progress or 0))
	else
		QuestUpdateRemote:FireClient(player, "Tracked", nil)
	end
end

-- ── CLASS QUEST RECONCILER ────────────────────────────────────────────────────
-- Quest state is a FUNCTION OF THE PROFILE, not a reaction to a level-up event.
--
-- The old TriggerClassQuest fired off `levelsGained` inside AddWeaponXP. That is a
-- one-shot signal, so two things went wrong:
--   1. Crossing 10 and 15 in a single XP award assigned _15 while _10 was still
--      Active. The Prerequisite check in AssignQuest silently dropped it, and
--      nothing ever re-fired it. The checkpoint was gone for good.
--   2. Completing _10 at mastery 22 never surfaced _15 or _20, because the
--      level-ups that would have triggered them were long past.
--
-- The reconciler instead asks the profile: "given this family's mastery and the set
-- of class quests already completed, what is the lowest unearned checkpoint at or
-- below the current level?" Run it on login, on mastery gain, and on quest
-- completion, and no checkpoint can be skipped or stranded, in any order.

local CLASS_MILESTONES = { 10, 15, 20, 25 }

-- Is a class quest for this family already open? Only one per family at a time.
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

-- Evaluates one weapon family and assigns the correct next class quest, if any.
-- Safe to call as often as you like; a no-op when nothing has changed.
function QuestManager.ReconcileClassQuests(player, family)
	if not family then return end

	local questData = DataManager.GetQuestData(player)
	if not questData then return end

	-- One at a time. If a checkpoint is open, the player owes the trainer a visit
	-- before the next one unlocks.
	if getActiveClassQuest(player, family) then return end

	local level = DataManager.GetWeaponLevel(player, family)
	if level <= 0 then return end

	-- Lowest milestone that is earned by level and not yet completed.
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

-- Sweeps every weapon family. This is the login path: it recovers anything left
-- stranded by an earlier session, including checkpoints missed under the old code.
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

-- ── HYBRID RECONCILER ─────────────────────────────────────────────────────────
-- Hybrids (Guandao, Scythe) have NO class quests and NO XP bar of their own. Their
-- three skills are gated on BOTH parent families reaching a threshold: 15/15 for Z,
-- 20/20 for X, 25/25 for C. The weapon itself is handed over by the hybrid trainer,
-- who is world-discovered; the reconciler does not grant it. A player holding a
-- Guandao has already run eight class quests and does not need a marker.
--
-- UnlockSpell is idempotent and auto-equips into the family slot, so calling this
-- repeatedly is harmless.
function QuestManager.ReconcileHybrids(player)
	local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

	for hybridName, parents in pairs(SkillConfig.HybridParents) do
		-- The LOWER of the two parent levels gates everything.
		local lowest = math.huge
		for _, parentFamily in ipairs(parents) do
			local lvl = DataManager.GetWeaponLevel(player, parentFamily)
			if lvl < lowest then lowest = lvl end
		end
		if lowest == math.huge then lowest = 0 end

		local skills = SkillConfig.WeaponSkills[hybridName]
		if skills then
			for slotIndex, threshold in pairs(SkillConfig.HybridSkillThresholds) do
				local skillName = skills[slotIndex]
				if skillName and lowest >= threshold and not DataManager.HasSpell(player, skillName) then
					DataManager.UnlockSpell(player, skillName)
					QuestUpdateRemote:FireClient(player, "HybridSkillUnlocked", {
						Weapon = hybridName,
						Skill  = skillName,
						Slot   = SkillConfig.SlotKeys[slotIndex],
					})
				end
			end
		end
	end
end

--[[
local function RestoreSession(player)
	DataManager.YieldUntilLoaded(player)

	local questData = DataManager.GetQuestData(player)
	if not questData then return end

	local activeList = buildActiveList(player)
	if #activeList == 0 then return end

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
]]

function QuestManager.RestoreSession(player)
	DataManager.YieldUntilLoaded(player)

	local questData = DataManager.GetQuestData(player)
	if not questData then return end

	-- Reconcile BEFORE building the list. This is the recovery path: any checkpoint
	-- stranded in a previous session (missed because it fired while another quest
	-- was active, or because the player levelled past it) gets picked up here and
	-- assigned, then shows up in the list we send down. Without this, a player who
	-- lost a checkpoint under the old event-driven code would never get it back.
	QuestManager.ReconcileAllClassQuests(player)

	local activeList = buildActiveList(player)
	if #activeList == 0 then return end

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

--[[
Players.PlayerAdded:Connect(function(player)
	task.wait(1) 
	RestoreSession(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		RestoreSession(player)
	end)
end)
]]

_G.QuestManager = QuestManager
return QuestManager