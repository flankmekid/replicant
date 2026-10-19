local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuestUpdateRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
local QuestActionRemote = ReplicatedStorage.QuestSystem:WaitForChild("QuestAction")
local QuestStateRequest = ReplicatedStorage.QuestSystem:WaitForChild("QuestStateRequest")
local QuestConfig = require(ReplicatedStorage.QuestSystem.QuestConfig)
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ── GUI References ────────────────────────────────────────────────────────────

local GUI = PlayerGui:WaitForChild("QuestGUI")
local TrackerFrame = GUI:WaitForChild("TrackerFrame")
local TrackerTitle = TrackerFrame:WaitForChild("QuestTitle")
local TrackerProgress = TrackerFrame:WaitForChild("QuestProgress")
local TrackerType = TrackerFrame:WaitForChild("QuestType")
local MinimiseBtn = TrackerFrame:WaitForChild("MinimiseButton")

local JournalFrame = GUI:WaitForChild("JournalFrame")
local QuestListFrame = JournalFrame:WaitForChild("QuestList")
local QuestDetailFrame = JournalFrame:WaitForChild("QuestDetail")
local DetailTitle = QuestDetailFrame:WaitForChild("DetailTitle")
local DetailType = QuestDetailFrame:WaitForChild("DetailType")
local DetailDesc = QuestDetailFrame:WaitForChild("DetailDescription")
local DetailProgress = QuestDetailFrame:WaitForChild("DetailProgress")
local TrackToggleBtn = QuestDetailFrame:WaitForChild("TrackButton")
local AbandonBtn = QuestDetailFrame:WaitForChild("AbandonButton")
local EmptyLabel = QuestListFrame:WaitForChild("EmptyLabel")

local JournalCloseBtn = JournalFrame:WaitForChild("CloseButton")

local CompleteFrame = GUI:WaitForChild("QuestCompleteFrame")
local CompleteName = CompleteFrame:WaitForChild("CompleteName")
local CompleteReward = CompleteFrame:WaitForChild("CompleteReward")
local CompleteSound = CompleteFrame:WaitForChild("CompleteSound")

local ClassQuestBanner = GUI:WaitForChild("ClassQuestBanner")
local BannerTitle = ClassQuestBanner:WaitForChild("BannerTitle")
local BannerSub = ClassQuestBanner:WaitForChild("BannerSub")

-- ── Constants ─────────────────────────────────────────────────────────────────

local COLOR_MAIN = Color3.fromRGB(212, 175, 55)
local COLOR_SIDE = Color3.fromRGB(180, 180, 180)
local COLOR_TRACKED_BG = Color3.fromRGB(50, 45, 35)
local COLOR_DEFAULT_BG = Color3.fromRGB(109, 90, 84)

local TWEEN_FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SLIDE = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local COMPLETE_SLIDE = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local COMPLETE_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OFFSCREEN_POS = UDim2.new(0.5, 0, 1.3, 0)
local ONSCREEN_POS = UDim2.new(0.5, 0, 0.82, 0)

-- ── State ─────────────────────────────────────────────────────────────────────

local activeQuests = {}
local trackedId = nil
local selectedId = nil
local trackerMinimised = false
local activeMarker = nil
local questButtons = {}
local journalOpen = false
local bannerQueue = {}
local bannerPlaying = false
local completeQueue = {}
local completePlaying = false

-- ─────────────────────────────────────────────────────────────────────────────
-- QUEST OBJECTIVE MARKER
-- ─────────────────────────────────────────────────────────────────────────────

local function destroyMarker()
	if activeMarker then
		activeMarker:Destroy()
		activeMarker = nil
	end
end

local function createMarker(partName, questType)
	destroyMarker()
	local target = Workspace:FindFirstChild(partName, true)
	if not target then
		return
	end

	local bbGui = Instance.new("BillboardGui")
	bbGui.Name = "QuestMarker"
	bbGui.Adornee = target
	bbGui.Size = UDim2.new(0, 60, 0, 60)
	bbGui.AlwaysOnTop = true
	bbGui.Parent = PlayerGui

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://17426600101"
	icon.ImageColor3 = questType == "Main" and COLOR_MAIN or COLOR_SIDE
	icon.Parent = bbGui

	activeMarker = bbGui
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TRACKER
-- ─────────────────────────────────────────────────────────────────────────────

local function updateTracker()
	if not trackedId or not activeQuests[trackedId] then
		TrackerFrame.Visible = false
		destroyMarker()
		return
	end

	if trackerMinimised then
		TrackerFrame.Visible = false
		return
	end

	local entry = activeQuests[trackedId]
	local def = entry.Data

	TrackerFrame.Visible = true
	TrackerTitle.Text = def.Title
	TrackerType.Text = def.Type == "Main" and "MAIN QUEST" or "SIDE QUEST"
	TrackerType.TextColor3 = def.Type == "Main" and Color3.fromRGB(255, 0, 0)
		or Color3.fromRGB(150, 150, 150)

	if def.MaxProgress > 1 then
		TrackerProgress.Visible = true
		TrackerProgress.Text = entry.Progress .. " / " .. def.MaxProgress
	else
		TrackerProgress.Visible = false
	end

	if def.TargetPartName then
		createMarker(def.TargetPartName, def.Type)
	else
		destroyMarker()
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- JOURNAL
-- ─────────────────────────────────────────────────────────────────────────────

local function clearQuestList()
	for _, btn in pairs(questButtons) do
		btn:Destroy()
	end
	questButtons = {}
end

local function selectQuestInJournal(questId)
	selectedId = questId
	local entry = activeQuests[questId]
	if not entry then
		return
	end

	local def = entry.Data

	DetailTitle.Text = def.Title
	DetailType.Text = def.Type == "Main" and "MAIN QUEST" or "SIDE QUEST"
	DetailType.TextColor3 = def.Type == "Main" and COLOR_MAIN or COLOR_SIDE
	DetailDesc.Text = def.Description

	if def.MaxProgress > 1 then
		DetailProgress.Visible = true
		DetailProgress.Text = entry.Progress .. " / " .. def.MaxProgress
	else
		DetailProgress.Visible = false
	end

	TrackToggleBtn.Text = (trackedId == questId) and "Untrack" or "Track"
	AbandonBtn.Visible = not (def.ClassQuest == true)

	for id, btn in pairs(questButtons) do
		btn.BackgroundColor3 = (id == questId) and COLOR_TRACKED_BG or COLOR_DEFAULT_BG
	end

	QuestDetailFrame.Visible = true
end

local function rebuildQuestList()
	clearQuestList()

	local hasQuests = next(activeQuests) ~= nil
	EmptyLabel.Visible = not hasQuests
	EmptyLabel.TextTransparency = hasQuests and 1 or 0

	if not hasQuests then
		QuestDetailFrame.Visible = false
		return
	end

	local sortedIds = {}
	for id in pairs(activeQuests) do
		table.insert(sortedIds, id)
	end
	table.sort(sortedIds, function(a, b)
		local typeA = activeQuests[a].Data.Type or "Side"
		local typeB = activeQuests[b].Data.Type or "Side"
		if typeA == typeB then
			return a < b
		end
		return typeA == "Main"
	end)

	for _, questId in ipairs(sortedIds) do
		local entry = activeQuests[questId]
		local def = entry.Data

		local btn = ReplicatedStorage.assets.UI.QuestButton:Clone()
		btn.Name = questId
		btn.BackgroundColor3 = (questId == selectedId) and COLOR_TRACKED_BG or COLOR_DEFAULT_BG
		btn.Text = def.Title
		btn.TextColor3 = def.Type == "Main" and COLOR_MAIN or COLOR_SIDE
		btn.Parent = QuestListFrame

		if questId == trackedId then
			local dot = btn:FindFirstChild("ActiveDot")
			if dot then
				dot.Transparency = 0.5
				dot.BackgroundColor3 = COLOR_MAIN
			end
		end

		btn.MouseButton1Click:Connect(function()
			selectQuestInJournal(questId)
		end)

		questButtons[questId] = btn
	end

	if selectedId and activeQuests[selectedId] then
		selectQuestInJournal(selectedId)
	else
		QuestDetailFrame.Visible = false
		selectedId = nil
	end
end

local function setJournalOpen(open)
	journalOpen = open
	JournalFrame.Visible = open

	if open then
		rebuildQuestList()
		local hasQuests = next(activeQuests) ~= nil
		if not hasQuests then
			EmptyLabel.Font = Enum.Font.Fondamento
			EmptyLabel.TextColor3 = COLOR_MAIN
			EmptyLabel.TextTransparency = 1
			EmptyLabel.Visible = true
			TweenService:Create(EmptyLabel, TWEEN_FADE, { TextTransparency = 0 }):Play()
		else
			EmptyLabel.Visible = false
			EmptyLabel.TextTransparency = 1
		end
	else
		EmptyLabel.Visible = false
		EmptyLabel.TextTransparency = 1
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BANNER (class quest unlocked)
-- ─────────────────────────────────────────────────────────────────────────────

local function playBanner(questId, def)
	BannerTitle.Text = def.Title
	BannerSub.Text = "New quest available. Check your journal."

	ClassQuestBanner.Position = UDim2.new(0.144, 0, -0.1, 0)
	ClassQuestBanner.Visible = true

	TweenService:Create(ClassQuestBanner, TWEEN_SLIDE, {
		Position = UDim2.new(0.144, 0, 0.196, 0),
	}):Play()

	task.wait(3.5)

	local out = TweenService:Create(ClassQuestBanner, TWEEN_SLIDE, {
		Position = UDim2.new(0.144, 0, -0.1, 0),
	})
	out:Play()
	out.Completed:Wait()
	ClassQuestBanner.Visible = false
end

local function queueBanner(questId, def)
	table.insert(bannerQueue, { questId = questId, def = def })
	if bannerPlaying then
		return
	end
	bannerPlaying = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local next = table.remove(bannerQueue, 1)
			playBanner(next.questId, next.def)
			task.wait(0.3)
		end
		bannerPlaying = false
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLETE UI
-- ─────────────────────────────────────────────────────────────────────────────

local function playCompleteUI(questName, liturgyReward)
	CompleteName.Text = questName
	CompleteReward.Text = "+" .. liturgyReward .. " Liturgy"

	CompleteFrame.Position = OFFSCREEN_POS
	CompleteFrame.Visible = true
	CompleteFrame.GroupTransparency = 0

	CompleteSound:Play()

	TweenService:Create(CompleteFrame, COMPLETE_SLIDE, { Position = ONSCREEN_POS }):Play()

	task.wait(0.4 + 5.5)

	if not CompleteFrame.Parent then
		return
	end

	local fade = TweenService:Create(CompleteFrame, COMPLETE_FADE, { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	CompleteFrame.Visible = false
end

local function queueCompleteUI(questName, liturgyReward)
	table.insert(completeQueue, { name = questName, reward = liturgyReward })
	if completePlaying then
		return
	end
	completePlaying = true
	task.spawn(function()
		while #completeQueue > 0 do
			local next = table.remove(completeQueue, 1)
			playCompleteUI(next.name, next.reward)
			task.wait(0.3)
		end
		completePlaying = false
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NPC AVAILABILITY ICON SYSTEM
-- ─────────────────────────────────────────────────────────────────────────────

local SHOW_DIST = 100
local HIDE_DIST = 110

local QuestBillboardTemplate = ReplicatedStorage:WaitForChild("assets")
	:WaitForChild("QuestBillboard")

-- npcIcons[key] = { part, billboard, shown (bool), available (bool) }
local npcIcons = {}

local function getPlayerHRP()
	local char = Player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function hasLOS(fromPos, toPart)
	local toPos = toPart.Position
	local dir = toPos - fromPos
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { Player.Character, toPart.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(fromPos, dir, params)
	if not result then
		return true
	end
	return (result.Position - fromPos).Magnitude >= dir.Magnitude - 2
end

local function registerIcon(key, part)
	if npcIcons[key] or not part then
		return
	end
	local bb = QuestBillboardTemplate:Clone()
	bb.Adornee = part
	bb.AlwaysOnTop = false
	bb.Enabled = false
	bb.Parent = part
	npcIcons[key] = { part = part, billboard = bb, shown = false, available = true }
end

local function setShown(key, show)
	local entry = npcIcons[key]
	if not entry or entry.shown == show then
		return
	end
	entry.shown = show
	entry.billboard.Enabled = show
end

RunService.Heartbeat:Connect(function()
	local hrp = getPlayerHRP()
	if not hrp then
		return
	end
	local playerPos = hrp.Position

	for key, entry in pairs(npcIcons) do
		if not entry.part or not entry.part.Parent then
			entry.billboard:Destroy()
			npcIcons[key] = nil
			continue
		end

		if not entry.available then
			setShown(key, false)
			continue
		end

		local dist = (entry.part.Position - playerPos).Magnitude
		if dist <= SHOW_DIST then
			setShown(key, hasLOS(playerPos, entry.part))
		elseif dist >= HIDE_DIST then
			setShown(key, false)
		end
		-- 100–110 stud band: hysteresis, keep current state
	end
end)

-- ── Availability logic ────────────────────────────────────────────────────────

local function getQuestState(questId)
	local ok, result = pcall(function()
		return QuestStateRequest:InvokeServer(questId)
	end)
	return (ok and result) or { active = false, completed = false }
end

local function trainerHasSomething(weaponKey, skillWeaponKey)
	local stats = Player:FindFirstChild("PlayerStats")
	if not stats then
		return false
	end

	local weaponData = stats:FindFirstChild("WeaponData")
	local levelObj = weaponData and weaponData:FindFirstChild(weaponKey)
	levelObj = levelObj and levelObj:FindFirstChild("Level")
	if not levelObj or levelObj.Value < 15 then
		return false
	end

	local unlockedSkills = stats:FindFirstChild("UnlockedSkills")
	if not unlockedSkills then
		return false
	end

	for _, skillName in ipairs(SkillConfig.WeaponSkills[skillWeaponKey] or {}) do
		if not unlockedSkills:FindFirstChild(skillName) then
			return true
		end
	end

	return false
end

-- ── NPC definitions ───────────────────────────────────────────────────────────

local NPC_DEFS = {
	{
		key = "arc",
		hrpPath = function()
			local m = Workspace:FindFirstChild("arc")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			local s = getQuestState("ArcQuest1")
			return not s.active and not s.completed
		end,
	},
	{
		key = "aldric",
		hrpPath = function()
			local m = Workspace:FindFirstChild("Aldric")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return not getQuestState("Delivery1").active
				and not getQuestState("Delivery2").active
				and not getQuestState("Delivery3").active
		end,
	},
	{
		key = "samurai3",
		hrpPath = function()
			local m = Workspace:FindFirstChild("Samurai3")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return not getQuestState("Samurai3").active
		end,
	},
	{
		key = "knight1",
		hrpPath = function()
			local m = Workspace:FindFirstChild("KnightQuest")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return not getQuestState("Knight1").active
		end,
	},
	{
		key = "sidurgu",
		hrpPath = function()
			local m = Workspace:FindFirstChild("sidurgu")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			local s = getQuestState("SidurguErrand")
			return not s.active and not s.completed
		end,
	},
	{
		key = "oniTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("oniTrainer")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Fists", "Shackles")
		end,
	},
	{
		key = "monkTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("monkTrainer")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Fists", "Caestus")
		end,
	},
	{
		key = "vermTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("Swordsmaster")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Katana", "Vermillion")
		end,
	},
	{
		key = "excaliburTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("Jeanne")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Sword", "Excalibur")
		end,
	},
	{
		key = "dslayerTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("guts")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Greatsword", "Dragon Slayer")
		end,
	},
	{
		key = "tantoTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("yue")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Dagger", "Tanto")
		end,
	},
	{
		key = "guandaoTrainer",
		hrpPath = function()
			local m = Workspace:FindFirstChild("Xin")
			return m and m:FindFirstChild("HumanoidRootPart")
		end,
		isAvailable = function()
			return trainerHasSomething("Guandao", "Guandao")
		end,
	},
}

-- Re-evaluates availability for all registered icons and hides any that are
-- no longer available. Heartbeat handles showing when back in range.
local function reEvalAll()
	for _, def in ipairs(NPC_DEFS) do
		local entry = npcIcons[def.key]
		if not entry then
			continue
		end
		local ok, result = pcall(def.isAvailable)
		local available = ok and result or false
		entry.available = available
		if not available then
			setShown(def.key, false)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(2)
		reEvalAll()
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- BUTTON CONNECTIONS
-- ─────────────────────────────────────────────────────────────────────────────

TrackToggleBtn.MouseButton1Click:Connect(function()
	if not selectedId then
		return
	end

	if trackedId == selectedId then
		local fallback = nil
		for id in pairs(activeQuests) do
			if id ~= selectedId then
				fallback = id
				break
			end
		end

		if fallback then
			trackedId = fallback
			QuestActionRemote:FireServer("Track", fallback)
		else
			trackedId = nil
			trackerMinimised = true
			MinimiseBtn.Text = "+"
			QuestActionRemote:FireServer("Track", nil)
		end
	else
		trackedId = selectedId
		trackerMinimised = false
		MinimiseBtn.Text = "-"
		QuestActionRemote:FireServer("Track", selectedId)
	end

	updateTracker()
	rebuildQuestList()

	if selectedId then
		TrackToggleBtn.Text = (trackedId == selectedId) and "Untrack" or "Track"
	end
end)

AbandonBtn.MouseButton1Click:Connect(function()
	if not selectedId then
		return
	end
	local def = activeQuests[selectedId] and activeQuests[selectedId].Data
	if def and def.ClassQuest then
		return
	end
	QuestActionRemote:FireServer("Abandon", selectedId)
end)

MinimiseBtn.MouseButton1Click:Connect(function()
	trackerMinimised = not trackerMinimised
	updateTracker()
	MinimiseBtn.Text = trackerMinimised and "+" or "-"
end)

local CloseTitlePanelBindable =
	game:GetService("ReplicatedStorage"):WaitForChild("remotes"):WaitForChild("CloseTitlePanel")
JournalCloseBtn.MouseButton1Click:Connect(function()
	setJournalOpen(false)
	-- also close the Titles panel (it no longer has its own X)
	CloseTitlePanelBindable:Fire()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.J then
		setJournalOpen(not journalOpen)
	end
end)

-- LiturgyDisplay button also opens journal
task.spawn(function()
	local masteryGui = PlayerGui:WaitForChild("LiturgyDisplay", 20)
	if masteryGui then
		local displayBtn = masteryGui:WaitForChild("ImageButton", 20)
		if displayBtn then
			displayBtn.MouseButton1Click:Connect(function()
				setJournalOpen(not journalOpen)
			end)
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- REMOTE HANDLER
-- ─────────────────────────────────────────────────────────────────────────────

QuestUpdateRemote.OnClientEvent:Connect(function(action, payload)
	if action == "New" then
		if not payload then
			return
		end
		activeQuests[payload.Id] = { Data = payload.Data, Progress = payload.Progress or 0 }
		if journalOpen then
			rebuildQuestList()
		end
		-- Immediately hide NPC icon for this quest giver
		reEvalAll()
	elseif action == "Tracked" then
		if payload then
			trackedId = payload.Id
			if activeQuests[payload.Id] then
				activeQuests[payload.Id].Progress = payload.Progress or 0
			end
		else
			trackedId = nil
		end
		updateTracker()
		if journalOpen then
			rebuildQuestList()
		end
	elseif action == "Update" then
		if not payload or not payload.Id then
			return
		end
		if activeQuests[payload.Id] then
			activeQuests[payload.Id].Progress = payload.Progress
			if payload.Data and payload.Data.TargetPartName then
				activeQuests[payload.Id].Data.TargetPartName = payload.Data.TargetPartName
			end
		end
		if trackedId == payload.Id then
			if payload.Max > 1 then
				TrackerProgress.Visible = true
				TrackerProgress.Text = payload.Progress .. " / " .. payload.Max
			end
			local entry = activeQuests[payload.Id]
			if entry and entry.Data.TargetPartName then
				createMarker(entry.Data.TargetPartName, entry.Data.Type)
			end
		end
		if journalOpen and selectedId == payload.Id then
			selectQuestInJournal(payload.Id)
		end
	elseif action == "Complete" then
		if not payload or not payload.Id then
			return
		end

		local completedEntry = activeQuests[payload.Id]
		local questName = completedEntry and completedEntry.Data.Title or "Quest Complete"
		local liturgyReward = completedEntry and completedEntry.Data.LiturgyReward or 0

		activeQuests[payload.Id] = nil

		if trackedId == payload.Id then
			trackedId = nil
			destroyMarker()
		end
		if selectedId == payload.Id then
			selectedId = nil
			QuestDetailFrame.Visible = false
		end

		updateTracker()
		if journalOpen then
			rebuildQuestList()
		end

		queueCompleteUI(questName, liturgyReward)

		-- Re-eval after brief wait so repeatable quests can become available again
		task.delay(0.5, reEvalAll)
	elseif action == "ListUpdate" then
		if not payload then
			return
		end
		activeQuests = {}
		for _, entry in ipairs(payload) do
			activeQuests[entry.Id] = { Data = entry.Data, Progress = entry.Progress or 0 }
		end
		if journalOpen then
			rebuildQuestList()
		end
		updateTracker()
	elseif action == "ClassQuestUnlocked" then
		if not payload then
			return
		end
		queueBanner(payload.Id, payload.Data)
	elseif action == "InsufficientFunds" then
		if payload then
			warn("Not enough Liturgy. Required: " .. tostring(payload.Required))
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- INIT
-- ─────────────────────────────────────────────────────────────────────────────

TrackerFrame.Visible = false
JournalFrame.Visible = false
QuestDetailFrame.Visible = false
ClassQuestBanner.Visible = false
EmptyLabel.Visible = false
CompleteFrame.Visible = false

local QuestReadyRemote = ReplicatedStorage:WaitForChild("QuestSystem"):WaitForChild("QuestReady")
QuestReadyRemote:FireServer()

-- Register NPC icons after a brief wait for world + data to load
task.spawn(function()
	task.wait(1.5)
	for _, def in ipairs(NPC_DEFS) do
		local part = def.hrpPath()
		if part then
			registerIcon(def.key, part)
		end
	end
	reEvalAll()
end)
