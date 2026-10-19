-- SPDX-License-Identifier: MIT
--
-- The spire client: attune and rest prompts on the spire parts, the rest menu, and its
-- panels for travel, stat points, the spellbook, and the armory. The server owns every
-- action. The panels render the snapshots it returns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SpireConfig = require(ReplicatedStorage.SpireSystem.SpireConfig)
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)
local EquipSkillAction = ReplicatedStorage.SpireSystem:WaitForChild("EquipSkillAction")
local SpireRemote = ReplicatedStorage.SpireSystem:WaitForChild("SpireAction")
local SpireUpdate = ReplicatedStorage.SpireSystem:WaitForChild("SpireUpdate")
local ArmorAction = ReplicatedStorage.SpireSystem:WaitForChild("ArmorAction")
local ArmorConfig = require(ReplicatedStorage.modules:WaitForChild("ArmorConfig"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local SpireGui = PlayerGui:WaitForChild("SpireGui")
local MapFrame = SpireGui:WaitForChild("MapFrame")
local SpireList = MapFrame:WaitForChild("SpireList")
local CloseButton = MapFrame:WaitForChild("Header"):WaitForChild("CloseButton")
local Footer = MapFrame:WaitForChild("Footer")
local TeleportButton = Footer:WaitForChild("TeleportButton")
local SelectedLabel = Footer:WaitForChild("SelectedLabel")
local CostLabel = Footer:WaitForChild("CostLabel")
local ErrorLabel = Footer:WaitForChild("ErrorLabel")
local AttunementToast = SpireGui:WaitForChild("AttunementToast")
local ToastLabel = AttunementToast:WaitForChild("Inner"):WaitForChild("ToastLabel")

local COLOR_GOLD = Color3.fromRGB(212, 175, 55)
local COLOR_GOLD_DIM = Color3.fromRGB(140, 110, 35)
local COLOR_WHITE = Color3.fromRGB(235, 225, 205)
local COLOR_MUTED = Color3.fromRGB(140, 128, 108)
local COLOR_UNATTUNED = Color3.fromRGB(60, 55, 48)
local COLOR_BTN_NORMAL = Color3.fromRGB(38, 30, 18)
local COLOR_BTN_SELECT = Color3.fromRGB(60, 50, 30)
local COLOR_BTN_HOVER = Color3.fromRGB(48, 40, 24)

local FADE_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TOAST_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TOAST_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local attunedSpires = {}
local selectedSpireId = nil
local mapOpen = false
local listButtons = {}
local toastPlaying = false
local toastQueue = {}

local StatAction = ReplicatedStorage.SpireSystem:WaitForChild("StatAction")

local character = player.Character or player.CharacterAdded:Wait()
local resting = false
local currentRestSpireId = nil

-- Stat metadata for the level-up panel.
local STAT_ORDER = { "Vitality", "Stamina", "Strength", "Dexterity", "Magic" }
local STAT_DESC = {
	Vitality = "Max HP",
	Stamina = "Movement & dashes",
	Strength = "Weapon damage",
	Dexterity = "Skill damage",
	Magic = "Mana & racial power",
}
-- Player-facing wording for server reason codes.
local REASON_TEXT = {
	NotEnoughLiturgy = "Not enough Liturgy",
	MaxStat = "Stat is maxed",
	NothingToRespec = "No points to respec",
	MustRest = "You must rest first",
	BadStat = "Invalid stat",
	BadAction = "Invalid action",
	NoProfile = "Data not loaded",
	NoStats = "No stats found",
}
local function reasonText(code)
	return REASON_TEXT[code] or tostring(code)
end

-- The resting animation, shared with the bonfire system.
local REST_ANIM_ID = "rbxassetid://133831523774694"
local restTrack = nil
local function loadRestAnim()
	local hum = character and character:FindFirstChild("Humanoid")
	local animator = hum and hum:FindFirstChild("Animator")
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = REST_ANIM_ID
	restTrack = animator:LoadAnimation(anim)
end

-- The rest GUI, built in code by buildRestGui.
local restGui, restPanel, statPanel, restDim
local statRows = {}
local liturgyLabel, nextCostLabel
local skillPointLabel, availableLabel, buySkillBtn
local localOwned, localAvailable, localMaxSP, localNextCost = 0, 0, 150, 0
-- The last stats the server sent.
local localStats = {}
-- Forward declarations for the rest-menu buttons built above their definitions.
local openMap, closeMap
local openStatPanel, buildStatPanel, refreshStatPanel, applySnapshot, doRespec, requestEndRest, beginRestLocal, endRestLocal
local openSpellbookPanel, buildSpellbookPanel, refreshSpellbookPanel
local spellPanel
local openArmoryPanel, buildArmoryPanel, refreshArmoryPanel
local armoryPanel

local function makeButton(parent, text, order)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 40)
	b.BackgroundColor3 = COLOR_BTN_NORMAL
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = text
	b.TextColor3 = COLOR_WHITE
	b.TextSize = 15
	b.Font = Enum.Font.Merriweather
	b.LayoutOrder = order or 0
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = COLOR_BTN_HOVER
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = COLOR_BTN_NORMAL
	end)
	return b
end

local function buildRestGui()
	if restGui then
		return
	end
	restGui = Instance.new("ScreenGui")
	restGui.Name = "RestMenuGui"
	restGui.ResetOnSpawn = false
	restGui.IgnoreGuiInset = true
	restGui.Enabled = false
	restGui.Parent = PlayerGui

	-- A full-screen dim behind the panels.
	restDim = Instance.new("Frame")
	restDim.Name = "Dim"
	restDim.Size = UDim2.new(1, 0, 1, 0)
	restDim.Position = UDim2.new(0, 0, 0, 0)
	restDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	-- Tweened to about 0.45 during a rest.
	restDim.BackgroundTransparency = 1
	restDim.BorderSizePixel = 0
	restDim.ZIndex = 0
	restDim.Parent = restGui

	restPanel = Instance.new("Frame")
	restPanel.Name = "RestPanel"
	restPanel.AnchorPoint = Vector2.new(0, 0.5)
	restPanel.Position = UDim2.new(0.04, 0, 0.5, 0)
	restPanel.Size = UDim2.new(0, 240, 0, 380)
	restPanel.BackgroundColor3 = Color3.fromRGB(18, 15, 10)
	restPanel.BackgroundTransparency = 0.08
	restPanel.BorderSizePixel = 0
	restPanel.Parent = restGui
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 10)
	rc.Parent = restPanel
	local rstroke = Instance.new("UIStroke")
	rstroke.Color = COLOR_GOLD_DIM
	rstroke.Thickness = 1
	rstroke.Parent = restPanel
	local rpad = Instance.new("UIPadding")
	rpad.PaddingTop = UDim.new(0, 16)
	rpad.PaddingBottom = UDim.new(0, 16)
	rpad.PaddingLeft = UDim.new(0, 16)
	rpad.PaddingRight = UDim.new(0, 16)
	rpad.Parent = restPanel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "Rest"
	title.TextColor3 = COLOR_GOLD
	title.TextSize = 20
	title.Font = Enum.Font.Merriweather
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = restPanel

	local list = Instance.new("Frame")
	list.Name = "Buttons"
	list.Position = UDim2.new(0, 0, 0, 44)
	list.Size = UDim2.new(1, 0, 1, -44)
	list.BackgroundTransparency = 1
	list.Parent = restPanel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 10)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list

	local travelBtn = makeButton(list, "Travel", 1)
	local levelBtn = makeButton(list, "Level Up", 2)
	local spellbookBtn = makeButton(list, "Spellbook", 3)
	local armoryBtn = makeButton(list, "Armory", 4)
	local respecBtn = makeButton(list, "Respec", 5)
	local leaveBtn = makeButton(list, "Leave", 6)
	leaveBtn.BackgroundColor3 = Color3.fromRGB(50, 24, 18)

	travelBtn.MouseButton1Click:Connect(function()
		openMap()
	end)
	levelBtn.MouseButton1Click:Connect(function()
		openStatPanel()
	end)
	spellbookBtn.MouseButton1Click:Connect(function()
		openSpellbookPanel()
	end)
	armoryBtn.MouseButton1Click:Connect(function()
		openArmoryPanel()
	end)
	respecBtn.MouseButton1Click:Connect(function()
		doRespec()
	end)
	leaveBtn.MouseButton1Click:Connect(function()
		requestEndRest()
	end)

	buildStatPanel()
	buildSpellbookPanel()
	buildArmoryPanel()
end

local attunementSound = Instance.new("Sound")
attunementSound.SoundId = "rbxassetid://6895079185"
attunementSound.Volume = 0.8
attunementSound.Parent = PlayerGui

local function playToast(text)
	ToastLabel.Text = text
	AttunementToast.GroupTransparency = 1
	AttunementToast.Visible = true
	AttunementToast.Position = UDim2.new(0.5, 0, 0.85, 0)

	TweenService:Create(AttunementToast, TOAST_IN, {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0.82, 0),
	}):Play()

	task.wait(0.35 + 2.2)
	if not AttunementToast.Parent then
		return
	end

	local out = TweenService:Create(AttunementToast, TOAST_OUT, {
		GroupTransparency = 1,
	})
	out:Play()
	out.Completed:Wait()
	AttunementToast.Visible = false
end

local function queueToast(text)
	table.insert(toastQueue, text)
	if toastPlaying then
		return
	end
	toastPlaying = true
	task.spawn(function()
		while #toastQueue > 0 do
			playToast(table.remove(toastQueue, 1))
			task.wait(0.2)
		end
		toastPlaying = false
	end)
end

local function playAttunementEffect(spirePartName)
	local part = Workspace:FindFirstChild(spirePartName, true)
	if not part then
		return
	end

	attunementSound:Play()

	local light = Instance.new("PointLight")
	light.Brightness = 0
	light.Color = Color3.fromRGB(180, 220, 255)
	light.Range = 0
	light.Parent = part

	TweenService
		:Create(light, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 5,
			Range = 30,
		})
		:Play()

	task.wait(0.4)

	local out = TweenService:Create(
		light,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			Brightness = 0,
			Range = 0,
		}
	)
	out:Play()
	out.Completed:Wait()
	light:Destroy()
end

local function selectEntry(spireId)
	selectedSpireId = spireId

	for id, btn in pairs(listButtons) do
		btn.BackgroundColor3 = (id == spireId) and COLOR_BTN_SELECT or COLOR_BTN_NORMAL
	end

	local spireDef = nil
	for _, s in ipairs(SpireConfig.Spires) do
		if s.Id == spireId then
			spireDef = s
			break
		end
	end

	if spireDef then
		SelectedLabel.Text = spireDef.Name
		SelectedLabel.TextColor3 = COLOR_GOLD
		CostLabel.Text = SpireConfig.TeleportCost .. " L"
		CostLabel.Visible = true
		ErrorLabel.Visible = false
		TeleportButton.Visible = true
	end
end

local function buildList()
	for _, child in ipairs(SpireList:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	listButtons = {}

	for i, spire in ipairs(SpireConfig.Spires) do
		local isAttuned = attunedSpires[spire.Id] == true

		local btn = Instance.new("TextButton")
		btn.Name = spire.Id
		btn.Size = UDim2.new(1, 0, 0, 52)
		btn.BackgroundColor3 = (spire.Id == selectedSpireId) and COLOR_BTN_SELECT
			or COLOR_BTN_NORMAL
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.Active = isAttuned
		btn.Parent = SpireList

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 6, 0, 6)
		pip.Position = UDim2.new(0, 14, 0.5, -3)
		pip.BackgroundColor3 = isAttuned and COLOR_GOLD or COLOR_UNATTUNED
		pip.BorderSizePixel = 0
		pip.Parent = btn
		local pipCorner = Instance.new("UICorner")
		pipCorner.CornerRadius = UDim.new(1, 0)
		pipCorner.Parent = pip

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -40, 0, 26)
		nameLbl.Position = UDim2.new(0, 30, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = spire.Name
		nameLbl.TextColor3 = isAttuned and COLOR_WHITE or COLOR_UNATTUNED
		nameLbl.TextSize = 13
		nameLbl.Font = Enum.Font.Merriweather
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = btn

		local zoneLbl = Instance.new("TextLabel")
		zoneLbl.Size = UDim2.new(1, -40, 0, 16)
		zoneLbl.Position = UDim2.new(0, 30, 0, 30)
		zoneLbl.BackgroundTransparency = 1
		zoneLbl.Text = spire.Zone
		zoneLbl.TextColor3 = isAttuned and COLOR_MUTED or COLOR_UNATTUNED
		zoneLbl.TextSize = 11
		zoneLbl.Font = Enum.Font.Merriweather
		zoneLbl.TextXAlignment = Enum.TextXAlignment.Left
		zoneLbl.Parent = btn

		-- A lock icon on an unattuned spire.
		if not isAttuned then
			local lockLbl = Instance.new("TextLabel")
			lockLbl.Size = UDim2.new(0, 20, 0, 20)
			lockLbl.Position = UDim2.new(1, -28, 0.5, -10)
			lockLbl.BackgroundTransparency = 1
			lockLbl.Text = "X"
			lockLbl.TextSize = 14
			lockLbl.TextColor3 = COLOR_UNATTUNED
			lockLbl.Font = Enum.Font.Merriweather
			lockLbl.Parent = btn
		end

		if isAttuned then
			btn.MouseButton1Click:Connect(function()
				selectEntry(spire.Id)
			end)

			btn.MouseEnter:Connect(function()
				if spire.Id ~= selectedSpireId then
					btn.BackgroundColor3 = COLOR_BTN_HOVER
				end
			end)

			btn.MouseLeave:Connect(function()
				if spire.Id ~= selectedSpireId then
					btn.BackgroundColor3 = COLOR_BTN_NORMAL
				end
			end)
		end

		listButtons[spire.Id] = btn
	end
end

buildStatPanel = function()
	if statPanel then
		return
	end
	statPanel = Instance.new("Frame")
	statPanel.Name = "StatPanel"
	statPanel.AnchorPoint = Vector2.new(0, 0.5)
	-- To the right of the rest panel.
	statPanel.Position = UDim2.new(0.04, 256, 0.5, 0)
	statPanel.Size = UDim2.new(0, 300, 0, 430)
	statPanel.BackgroundColor3 = Color3.fromRGB(18, 15, 10)
	statPanel.BackgroundTransparency = 0.08
	statPanel.BorderSizePixel = 0
	statPanel.Visible = false
	statPanel.Parent = restGui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = statPanel
	local st = Instance.new("UIStroke")
	st.Color = COLOR_GOLD_DIM
	st.Thickness = 1
	st.Parent = statPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = statPanel

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, 0, 0, 24)
	hdr.BackgroundTransparency = 1
	hdr.Text = "Level Up"
	hdr.TextColor3 = COLOR_GOLD
	hdr.TextSize = 18
	hdr.Font = Enum.Font.Merriweather
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Parent = statPanel

	liturgyLabel = Instance.new("TextLabel")
	liturgyLabel.Size = UDim2.new(1, 0, 0, 18)
	liturgyLabel.Position = UDim2.new(0, 0, 0, 26)
	liturgyLabel.BackgroundTransparency = 1
	liturgyLabel.Text = "Liturgy: --"
	liturgyLabel.TextColor3 = COLOR_MUTED
	liturgyLabel.TextSize = 12
	liturgyLabel.Font = Enum.Font.RobotoMono
	liturgyLabel.TextXAlignment = Enum.TextXAlignment.Left
	liturgyLabel.Parent = statPanel

	nextCostLabel = Instance.new("TextLabel")
	nextCostLabel.Size = UDim2.new(1, 0, 0, 18)
	nextCostLabel.Position = UDim2.new(0, 0, 0, 44)
	nextCostLabel.BackgroundTransparency = 1
	nextCostLabel.Text = ""
	nextCostLabel.TextColor3 = COLOR_GOLD_DIM
	nextCostLabel.TextSize = 12
	nextCostLabel.Font = Enum.Font.RobotoMono
	nextCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	nextCostLabel.Parent = statPanel

	local rows = Instance.new("Frame")
	rows.Position = UDim2.new(0, 0, 0, 70)
	rows.Size = UDim2.new(1, 0, 1, -160)
	rows.BackgroundTransparency = 1
	rows.Parent = statPanel
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 8)
	rl.Parent = rows

	for i, stat in ipairs(STAT_ORDER) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundColor3 = COLOR_BTN_NORMAL
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = rows
		local rcc = Instance.new("UICorner")
		rcc.CornerRadius = UDim.new(0, 6)
		rcc.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.55, 0, 0, 22)
		nameLbl.Position = UDim2.new(0, 10, 0, 3)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = stat
		nameLbl.TextColor3 = COLOR_WHITE
		nameLbl.TextSize = 14
		nameLbl.Font = Enum.Font.Merriweather
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = row

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.55, 0, 0, 14)
		descLbl.Position = UDim2.new(0, 10, 0, 25)
		descLbl.BackgroundTransparency = 1
		descLbl.Text = STAT_DESC[stat] or ""
		descLbl.TextColor3 = COLOR_MUTED
		descLbl.TextSize = 10
		descLbl.Font = Enum.Font.RobotoMono
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Parent = row

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(0, 36, 1, 0)
		valLbl.Position = UDim2.new(1, -86, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = "0"
		valLbl.TextColor3 = COLOR_GOLD
		valLbl.TextSize = 18
		valLbl.Font = Enum.Font.RobotoMono
		valLbl.Parent = row

		local plus = Instance.new("TextButton")
		plus.Size = UDim2.new(0, 40, 0, 32)
		plus.Position = UDim2.new(1, -46, 0.5, -16)
		plus.BackgroundColor3 = COLOR_BTN_SELECT
		plus.BorderSizePixel = 0
		plus.AutoButtonColor = true
		plus.Text = "+"
		plus.TextColor3 = COLOR_WHITE
		plus.TextSize = 20
		plus.Font = Enum.Font.Merriweather
		plus.Parent = row
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 6)
		pc.Parent = plus

		plus.MouseButton1Click:Connect(function()
			-- Assigning a stat point costs nothing but an available skill point.
			local result = StatAction:InvokeServer("Assign", stat)
			if result and result.ok then
				applySnapshot(result)
			elseif result then
				nextCostLabel.Text = "Cannot assign: " .. reasonText(result.reason)
				nextCostLabel.TextColor3 = Color3.fromRGB(200, 80, 70)
			end
		end)

		statRows[stat] = valLbl
	end

	local bottom = Instance.new("Frame")
	bottom.Name = "SkillPointBar"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, 0, 1, 0)
	bottom.Size = UDim2.new(1, 0, 0, 78)
	bottom.BackgroundColor3 = Color3.fromRGB(28, 23, 14)
	bottom.BorderSizePixel = 0
	bottom.Parent = statPanel
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = bottom
	local bpad = Instance.new("UIPadding")
	bpad.PaddingTop = UDim.new(0, 8)
	bpad.PaddingBottom = UDim.new(0, 8)
	bpad.PaddingLeft = UDim.new(0, 10)
	bpad.PaddingRight = UDim.new(0, 10)
	bpad.Parent = bottom

	skillPointLabel = Instance.new("TextLabel")
	skillPointLabel.Size = UDim2.new(1, 0, 0, 18)
	skillPointLabel.BackgroundTransparency = 1
	skillPointLabel.Text = "Skill Points: 0 / 150"
	skillPointLabel.TextColor3 = COLOR_GOLD
	skillPointLabel.TextSize = 14
	skillPointLabel.Font = Enum.Font.Merriweather
	skillPointLabel.TextXAlignment = Enum.TextXAlignment.Left
	skillPointLabel.Parent = bottom

	availableLabel = Instance.new("TextLabel")
	availableLabel.Size = UDim2.new(1, 0, 0, 14)
	availableLabel.Position = UDim2.new(0, 0, 0, 19)
	availableLabel.BackgroundTransparency = 1
	availableLabel.Text = "Available to spend: 0"
	availableLabel.TextColor3 = COLOR_MUTED
	availableLabel.TextSize = 11
	availableLabel.Font = Enum.Font.RobotoMono
	availableLabel.TextXAlignment = Enum.TextXAlignment.Left
	availableLabel.Parent = bottom

	buySkillBtn = Instance.new("TextButton")
	buySkillBtn.Size = UDim2.new(1, 0, 0, 30)
	buySkillBtn.Position = UDim2.new(0, 0, 1, -30)
	buySkillBtn.AnchorPoint = Vector2.new(0, 1)
	buySkillBtn.Position = UDim2.new(0, 0, 1, 0)
	buySkillBtn.BackgroundColor3 = COLOR_BTN_SELECT
	buySkillBtn.BorderSizePixel = 0
	buySkillBtn.AutoButtonColor = true
	buySkillBtn.Text = "Buy Skill Point"
	buySkillBtn.TextColor3 = COLOR_WHITE
	buySkillBtn.TextSize = 13
	buySkillBtn.Font = Enum.Font.Merriweather
	buySkillBtn.Parent = bottom
	local bbc = Instance.new("UICorner")
	bbc.CornerRadius = UDim.new(0, 6)
	bbc.Parent = buySkillBtn

	buySkillBtn.MouseButton1Click:Connect(function()
		local result = StatAction:InvokeServer("BuySkill")
		if result and result.ok then
			applySnapshot(result)
		elseif result then
			nextCostLabel.Text = "Cannot buy: " .. reasonText(result.reason)
			nextCostLabel.TextColor3 = Color3.fromRGB(200, 80, 70)
		end
	end)
end

-- The family and the slot options come from the server, from CurrentWeapon, so the
-- panel works whether the weapon is held or sheathed.
local currentSnapshot = nil

local spellHeader, spellSubHeader, spellSlotsFrame, spellEmptyLabel
-- Layout: spellRowRefs[slotKey] = { options = { [skillName] = button }, container = frame }.
local spellRowRefs = {}

buildSpellbookPanel = function()
	if spellPanel then
		return
	end
	spellPanel = Instance.new("Frame")
	spellPanel.Name = "SpellbookPanel"
	spellPanel.AnchorPoint = Vector2.new(0, 0.5)
	spellPanel.Position = UDim2.new(0.04, 256, 0.5, 0)
	spellPanel.Size = UDim2.new(0, 320, 0, 430)
	spellPanel.BackgroundColor3 = Color3.fromRGB(18, 15, 10)
	spellPanel.BackgroundTransparency = 0.08
	spellPanel.BorderSizePixel = 0
	spellPanel.Visible = false
	spellPanel.Parent = restGui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = spellPanel
	local st = Instance.new("UIStroke")
	st.Color = COLOR_GOLD_DIM
	st.Thickness = 1
	st.Parent = spellPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = spellPanel

	spellHeader = Instance.new("TextLabel")
	spellHeader.Size = UDim2.new(1, 0, 0, 24)
	spellHeader.BackgroundTransparency = 1
	spellHeader.Text = "Spellbook"
	spellHeader.TextColor3 = COLOR_GOLD
	spellHeader.TextSize = 18
	spellHeader.Font = Enum.Font.Merriweather
	spellHeader.TextXAlignment = Enum.TextXAlignment.Left
	spellHeader.Parent = spellPanel

	spellSubHeader = Instance.new("TextLabel")
	spellSubHeader.Size = UDim2.new(1, 0, 0, 16)
	spellSubHeader.Position = UDim2.new(0, 0, 0, 26)
	spellSubHeader.BackgroundTransparency = 1
	spellSubHeader.Text = ""
	spellSubHeader.TextColor3 = COLOR_MUTED
	spellSubHeader.TextSize = 12
	spellSubHeader.Font = Enum.Font.RobotoMono
	spellSubHeader.TextXAlignment = Enum.TextXAlignment.Left
	spellSubHeader.Parent = spellPanel

	spellEmptyLabel = Instance.new("TextLabel")
	spellEmptyLabel.Size = UDim2.new(1, 0, 0, 60)
	spellEmptyLabel.Position = UDim2.new(0, 0, 0, 60)
	spellEmptyLabel.BackgroundTransparency = 1
	spellEmptyLabel.Text = "Equip a weapon to view its skills."
	spellEmptyLabel.TextWrapped = true
	spellEmptyLabel.TextColor3 = COLOR_MUTED
	spellEmptyLabel.TextSize = 13
	spellEmptyLabel.Font = Enum.Font.Merriweather
	spellEmptyLabel.Visible = false
	spellEmptyLabel.Parent = spellPanel

	spellSlotsFrame = Instance.new("ScrollingFrame")
	spellSlotsFrame.Position = UDim2.new(0, 0, 0, 50)
	spellSlotsFrame.Size = UDim2.new(1, 0, 1, -50)
	spellSlotsFrame.BackgroundTransparency = 1
	spellSlotsFrame.BorderSizePixel = 0
	spellSlotsFrame.ScrollBarThickness = 4
	spellSlotsFrame.ScrollBarImageColor3 = COLOR_GOLD_DIM
	spellSlotsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	spellSlotsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	spellSlotsFrame.Parent = spellPanel
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 12)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = spellSlotsFrame
end

-- Rebuilds the slot rows from a server snapshot. Each slot is a header with the equipped
-- skill that expands to the owned skills for the slot. One slot is open at a time.
local expandedSlot = nil

refreshSpellbookPanel = function(snap)
	if not spellPanel then
		return
	end
	currentSnapshot = snap
	expandedSlot = nil

	for _, child in ipairs(spellSlotsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	spellRowRefs = {}

	local family = snap and snap.family
	if not family then
		spellSubHeader.Text = ""
		spellSlotsFrame.Visible = false
		spellEmptyLabel.Text = "You don't have a weapon equipped."
		spellEmptyLabel.Visible = true
		return
	end

	spellSubHeader.Text = family .. " family"
	spellSlotsFrame.Visible = true
	spellEmptyLabel.Visible = false

	-- Height of one option, and the gap between options.
	local OPT_H = 32
	local OPT_PAD = 4
	local EXPAND_TW = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	-- Collapses every open slot except keep.
	local collapseFns = {}
	local function collapseAllExcept(keep)
		for k, fn in pairs(collapseFns) do
			if k ~= keep then
				fn()
			end
		end
	end

	for slotIdx = 1, 3 do
		local slotKey = SkillConfig.SlotKeys[slotIdx]
		local slotData = (snap.slots or {})[slotKey] or { owned = {}, equipped = nil }
		local owned = slotData.owned or {}
		local equipped = slotData.equipped

		local group = Instance.new("Frame")
		group.Name = "Slot_" .. slotKey
		group.Size = UDim2.new(1, -4, 0, 0)
		group.AutomaticSize = Enum.AutomaticSize.Y
		group.BackgroundTransparency = 1
		group.LayoutOrder = slotIdx
		group.Parent = spellSlotsFrame
		local gl = Instance.new("UIListLayout")
		gl.Padding = UDim.new(0, OPT_PAD)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = group

		-- The header shows the key, the equipped skill, and a chevron.
		local header = Instance.new("TextButton")
		header.Size = UDim2.new(1, 0, 0, 40)
		header.BackgroundColor3 = COLOR_BTN_NORMAL
		header.BorderSizePixel = 0
		header.AutoButtonColor = false
		header.Text = ""
		header.LayoutOrder = 0
		header.Parent = group
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 6)
		hc.Parent = header

		local slotTag = Instance.new("TextLabel")
		slotTag.Size = UDim2.new(0, 28, 1, 0)
		slotTag.Position = UDim2.new(0, 10, 0, 0)
		slotTag.BackgroundTransparency = 1
		slotTag.Text = slotKey
		slotTag.TextColor3 = COLOR_GOLD
		slotTag.TextSize = 16
		slotTag.Font = Enum.Font.Merriweather
		slotTag.TextXAlignment = Enum.TextXAlignment.Left
		slotTag.Parent = header

		local eqLbl = Instance.new("TextLabel")
		eqLbl.Size = UDim2.new(1, -90, 1, 0)
		eqLbl.Position = UDim2.new(0, 44, 0, 0)
		eqLbl.BackgroundTransparency = 1
		eqLbl.Text = equipped or "Empty"
		eqLbl.TextColor3 = equipped and COLOR_WHITE or COLOR_MUTED
		eqLbl.TextSize = 14
		eqLbl.Font = Enum.Font.Merriweather
		eqLbl.TextXAlignment = Enum.TextXAlignment.Left
		eqLbl.TextTruncate = Enum.TextTruncate.AtEnd
		eqLbl.Parent = header

		local chevron = Instance.new("TextLabel")
		chevron.Size = UDim2.new(0, 24, 1, 0)
		chevron.Position = UDim2.new(1, -30, 0, 0)
		chevron.BackgroundTransparency = 1
		chevron.Text = "v"
		chevron.TextColor3 = COLOR_GOLD_DIM
		chevron.TextSize = 14
		chevron.Font = Enum.Font.Merriweather
		chevron.Parent = header

		-- The options are clipped, and their height is tweened.
		local optWrap = Instance.new("Frame")
		optWrap.Name = "Options"
		optWrap.Size = UDim2.new(1, 0, 0, 0)
		optWrap.BackgroundTransparency = 1
		optWrap.ClipsDescendants = true
		optWrap.LayoutOrder = 1
		optWrap.Parent = group
		local owl = Instance.new("UIListLayout")
		owl.Padding = UDim.new(0, OPT_PAD)
		owl.SortOrder = Enum.SortOrder.LayoutOrder
		owl.Parent = optWrap

		spellRowRefs[slotKey] = { options = {}, header = eqLbl }

		header.MouseEnter:Connect(function()
			if expandedSlot ~= slotKey then
				header.BackgroundColor3 = COLOR_BTN_HOVER
			end
		end)
		header.MouseLeave:Connect(function()
			if expandedSlot ~= slotKey then
				header.BackgroundColor3 = COLOR_BTN_NORMAL
			end
		end)

		if #owned == 0 then
			-- With no owned skills, the header is inactive and shows a muted note.
			eqLbl.Text = "No skills unlocked"
			eqLbl.TextColor3 = COLOR_MUTED
			chevron.Visible = false
		else
			local fullHeight = 0
			for i, skillName in ipairs(owned) do
				local isEq = (skillName == equipped)
				local optBtn = Instance.new("TextButton")
				optBtn.Size = UDim2.new(1, 0, 0, OPT_H)
				optBtn.BackgroundColor3 = isEq and COLOR_BTN_SELECT or COLOR_BTN_NORMAL
				optBtn.BorderSizePixel = 0
				optBtn.AutoButtonColor = false
				optBtn.Text = "    " .. skillName
				optBtn.TextColor3 = isEq and COLOR_GOLD or COLOR_WHITE
				optBtn.TextSize = 13
				optBtn.Font = Enum.Font.Merriweather
				optBtn.TextXAlignment = Enum.TextXAlignment.Left
				optBtn.LayoutOrder = i
				optBtn.Parent = optWrap
				local oc = Instance.new("UICorner")
				oc.CornerRadius = UDim.new(0, 6)
				oc.Parent = optBtn

				local pip = Instance.new("Frame")
				pip.Size = UDim2.new(0, 6, 0, 6)
				pip.Position = UDim2.new(1, -16, 0.5, -3)
				pip.BackgroundColor3 = COLOR_GOLD
				pip.BorderSizePixel = 0
				pip.Visible = isEq
				pip.Parent = optBtn
				local pc = Instance.new("UICorner")
				pc.CornerRadius = UDim.new(1, 0)
				pc.Parent = pip

				spellRowRefs[slotKey].options[skillName] = { button = optBtn, pip = pip }

				local function isEquipped()
					local sd = currentSnapshot
						and currentSnapshot.slots
						and currentSnapshot.slots[slotKey]
					return sd and sd.equipped == skillName
				end
				optBtn.MouseEnter:Connect(function()
					if not isEquipped() then
						optBtn.BackgroundColor3 = COLOR_BTN_HOVER
					end
				end)
				optBtn.MouseLeave:Connect(function()
					if not isEquipped() then
						optBtn.BackgroundColor3 = COLOR_BTN_NORMAL
					end
				end)

				local capturedSkill = skillName
				optBtn.MouseButton1Click:Connect(function()
					local result =
						EquipSkillAction:InvokeServer("Equip", family, slotKey, capturedSkill)
					if result and result.ok then
						if
							currentSnapshot
							and currentSnapshot.slots
							and currentSnapshot.slots[slotKey]
						then
							currentSnapshot.slots[slotKey].equipped = capturedSkill
						end
						for name, refs in pairs(spellRowRefs[slotKey].options) do
							local on = (name == capturedSkill)
							refs.button.BackgroundColor3 = on and COLOR_BTN_SELECT
								or COLOR_BTN_NORMAL
							refs.button.TextColor3 = on and COLOR_GOLD or COLOR_WHITE
							refs.pip.Visible = on
						end
						eqLbl.Text = capturedSkill
						eqLbl.TextColor3 = COLOR_WHITE
					end
				end)

				fullHeight = fullHeight + OPT_H + (i > 1 and OPT_PAD or 0)
			end

			local function collapse()
				if expandedSlot == slotKey then
					expandedSlot = nil
				end
				chevron.Text = "v"
				header.BackgroundColor3 = COLOR_BTN_NORMAL
				TweenService:Create(optWrap, EXPAND_TW, { Size = UDim2.new(1, 0, 0, 0) }):Play()
			end
			collapseFns[slotKey] = collapse

			local function expand()
				collapseAllExcept(slotKey)
				expandedSlot = slotKey
				chevron.Text = "^"
				header.BackgroundColor3 = COLOR_BTN_SELECT
				TweenService:Create(optWrap, EXPAND_TW, { Size = UDim2.new(1, 0, 0, fullHeight) })
					:Play()
			end

			header.MouseButton1Click:Connect(function()
				if expandedSlot == slotKey then
					collapse()
				else
					expand()
				end
			end)
		end
	end
end

openSpellbookPanel = function()
	if not spellPanel then
		buildSpellbookPanel()
	end
	if statPanel then
		statPanel.Visible = false
	end
	if armoryPanel then
		armoryPanel.Visible = false
	end
	local snap = EquipSkillAction:InvokeServer("Query")
	refreshSpellbookPanel(snap)
	spellPanel.Visible = true
	spellPanel.Position = UDim2.new(0.04, 180, 0.5, 0)
	TweenService
		:Create(spellPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.04, 256, 0.5, 0),
		})
		:Play()
end

-- The armory: browse owned armors on a stand, then Equip (stats and looks) or Transmog
-- (looks only). The server, through ArmorAction, filters the snapshot by ownership, and
-- the panel queries it again after each action.
local armoryListFrame, armoryDetail, armoryCurrentLbl
local armoryViewport, armoryWorldModel
local armoryDetailTitle, armoryDetailStats, armoryEquipBtn, armoryTransmogBtn
local armorySnapshot = nil
-- The armor shown in the detail view.
local armorySelected = nil
-- Layout: armoryListButtons[armorName] = button.
local armoryListButtons = {}

-- Width of the list.
local ARM_LIST_W = 150
local ARM_TW = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- Builds the armor stand in the viewport once: a copy of the template rig and a camera
-- in front of it.
local function ensureArmoryStand()
	if armoryWorldModel and armoryWorldModel.Parent then
		return
	end
	local template = ReplicatedStorage.assets:FindFirstChild("ArmorTemplate")
	if not template then
		return
	end
	armoryWorldModel = template:Clone()
	armoryWorldModel.Parent = armoryViewport

	local cam = Instance.new("Camera")
	cam.Parent = armoryViewport
	armoryViewport.CurrentCamera = cam
	local prim = armoryWorldModel.PrimaryPart
		or armoryWorldModel:FindFirstChild("HumanoidRootPart", true)
		or armoryWorldModel:FindFirstChildWhichIsA("BasePart", true)
	if prim then
		local center = prim.Position
		-- A rig faces -Z, so the camera sits on the -Z side to show the front.
		cam.CFrame = CFrame.new(center + Vector3.new(0, 0.5, -6), center + Vector3.new(0, 0.5, 0))
	end
end

-- Puts the clothing of an armor on the stand.
local function dressStand(armorName)
	if not armoryWorldModel then
		return
	end
	local cfg = ArmorConfig.Armors[armorName]
	if not cfg then
		return
	end
	local armorModel = armoryWorldModel:FindFirstChild("Armor")
	local target = armorModel or armoryWorldModel
	local shirt = target:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Parent = target
	end
	shirt.ShirtTemplate = cfg.ShirtID
	local pants = target:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Parent = target
	end
	pants.PantsTemplate = cfg.PantsID
end

-- Shows the names of the stats armor and the looks armor.
local function refreshArmoryCurrent()
	if not armoryCurrentLbl or not armorySnapshot then
		return
	end
	local statsName = armorySnapshot.currentArmor or "Rags"
	local vanityName = armorySnapshot.currentVanity or statsName
	local statsDisp = (
		armorySnapshot.armors[statsName] and armorySnapshot.armors[statsName].DisplayName
	) or statsName
	local vanDisp = (
		armorySnapshot.armors[vanityName] and armorySnapshot.armors[vanityName].DisplayName
	) or vanityName
	if vanityName == statsName then
		armoryCurrentLbl.Text = "Worn: " .. statsDisp
	else
		armoryCurrentLbl.Text = "Stats: " .. statsDisp .. "   |   Vanity: " .. vanDisp
	end
end

-- Enables or greys out Equip and Transmog for the selected armor.
local function refreshArmoryButtons()
	if not armorySelected or not armorySnapshot then
		return
	end
	local isStats = (armorySnapshot.currentArmor == armorySelected)
	local vanity = armorySnapshot.currentVanity or armorySnapshot.currentArmor
	local isVanity = (vanity == armorySelected)

	-- Equip does nothing only when this armor gives the stats and no transmog covers it.
	local equipRedundant = isStats and (armorySnapshot.currentVanity == nil)
	if equipRedundant then
		armoryEquipBtn.Text = "Equipped"
		armoryEquipBtn.AutoButtonColor = false
		armoryEquipBtn.BackgroundColor3 = COLOR_BTN_NORMAL
		armoryEquipBtn.TextColor3 = COLOR_MUTED
	else
		armoryEquipBtn.Text = "Equip"
		armoryEquipBtn.AutoButtonColor = true
		armoryEquipBtn.BackgroundColor3 = COLOR_BTN_SELECT
		armoryEquipBtn.TextColor3 = COLOR_WHITE
	end

	if isVanity then
		armoryTransmogBtn.Text = "Worn"
		armoryTransmogBtn.AutoButtonColor = false
		armoryTransmogBtn.BackgroundColor3 = COLOR_BTN_NORMAL
		armoryTransmogBtn.TextColor3 = COLOR_MUTED
	else
		armoryTransmogBtn.Text = "Transmog"
		armoryTransmogBtn.AutoButtonColor = true
		armoryTransmogBtn.BackgroundColor3 = COLOR_BTN_SELECT
		armoryTransmogBtn.TextColor3 = COLOR_WHITE
	end
end

-- Opens the detail view of an armor: the list slides left and the detail fills in.
local function selectArmor(armorName)
	armorySelected = armorName
	local info = armorySnapshot and armorySnapshot.armors[armorName]
	if not info then
		return
	end

	for name, btn in pairs(armoryListButtons) do
		btn.BackgroundColor3 = (name == armorName) and COLOR_BTN_SELECT or COLOR_BTN_NORMAL
	end

	armoryDetailTitle.Text = info.DisplayName or armorName
	armoryDetailStats.Text = string.format(
		"HP   x%.2f\nDef  x%.2f\nDmg  x%.2f",
		info.HPBuff or 1,
		info.DefBuff or 1,
		info.DmgBuff or 1
	)
	ensureArmoryStand()
	dressStand(armorName)
	refreshArmoryButtons()

	TweenService:Create(armoryListFrame, ARM_TW, { Position = UDim2.new(0, 0, 0, 40) }):Play()
	armoryDetail.Visible = true
	armoryDetail.GroupTransparency = 1
	TweenService:Create(armoryDetail, ARM_TW, { GroupTransparency = 0 }):Play()
end

buildArmoryPanel = function()
	if armoryPanel then
		return
	end
	armoryPanel = Instance.new("Frame")
	armoryPanel.Name = "ArmoryPanel"
	armoryPanel.AnchorPoint = Vector2.new(0, 0.5)
	armoryPanel.Position = UDim2.new(0.04, 256, 0.5, 0)
	armoryPanel.Size = UDim2.new(0, 470, 0, 430)
	armoryPanel.BackgroundColor3 = Color3.fromRGB(18, 15, 10)
	armoryPanel.BackgroundTransparency = 0.08
	armoryPanel.BorderSizePixel = 0
	armoryPanel.Visible = false
	armoryPanel.Parent = restGui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = armoryPanel
	local st = Instance.new("UIStroke")
	st.Color = COLOR_GOLD_DIM
	st.Thickness = 1
	st.Parent = armoryPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = armoryPanel

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, 0, 0, 24)
	hdr.BackgroundTransparency = 1
	hdr.Text = "Armory"
	hdr.TextColor3 = COLOR_GOLD
	hdr.TextSize = 18
	hdr.Font = Enum.Font.Merriweather
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Parent = armoryPanel

	armoryCurrentLbl = Instance.new("TextLabel")
	armoryCurrentLbl.Size = UDim2.new(1, 0, 0, 16)
	armoryCurrentLbl.Position = UDim2.new(0, 0, 0, 24)
	armoryCurrentLbl.BackgroundTransparency = 1
	armoryCurrentLbl.Text = ""
	armoryCurrentLbl.TextColor3 = COLOR_MUTED
	armoryCurrentLbl.TextSize = 12
	armoryCurrentLbl.Font = Enum.Font.RobotoMono
	armoryCurrentLbl.TextXAlignment = Enum.TextXAlignment.Left
	armoryCurrentLbl.Parent = armoryPanel

	armoryListFrame = Instance.new("ScrollingFrame")
	armoryListFrame.Name = "ArmorList"
	-- The list is centered by refreshArmoryPanel and moved to x = 0 by selectArmor.
	armoryListFrame.Position = UDim2.new(0, 0, 0, 40)
	armoryListFrame.Size = UDim2.new(0, ARM_LIST_W, 1, -50)
	armoryListFrame.BackgroundTransparency = 1
	armoryListFrame.BorderSizePixel = 0
	armoryListFrame.ScrollBarThickness = 4
	armoryListFrame.ScrollBarImageColor3 = COLOR_GOLD_DIM
	armoryListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	armoryListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	armoryListFrame.Parent = armoryPanel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = armoryListFrame

	-- The detail view is hidden until an armor is picked.
	armoryDetail = Instance.new("CanvasGroup")
	armoryDetail.Name = "ArmorDetail"
	armoryDetail.Position = UDim2.new(0, ARM_LIST_W + 14, 0, 40)
	armoryDetail.Size = UDim2.new(1, -(ARM_LIST_W + 14), 1, -50)
	armoryDetail.BackgroundTransparency = 1
	armoryDetail.BorderSizePixel = 0
	armoryDetail.Visible = false
	armoryDetail.Parent = armoryPanel

	armoryDetailTitle = Instance.new("TextLabel")
	armoryDetailTitle.Size = UDim2.new(1, 0, 0, 24)
	armoryDetailTitle.BackgroundTransparency = 1
	armoryDetailTitle.Text = ""
	armoryDetailTitle.TextColor3 = COLOR_GOLD
	armoryDetailTitle.TextSize = 16
	armoryDetailTitle.Font = Enum.Font.Merriweather
	armoryDetailTitle.TextXAlignment = Enum.TextXAlignment.Left
	armoryDetailTitle.Parent = armoryDetail

	armoryViewport = Instance.new("ViewportFrame")
	armoryViewport.Position = UDim2.new(0, 0, 0, 30)
	armoryViewport.Size = UDim2.new(1, 0, 0, 190)
	armoryViewport.BackgroundColor3 = Color3.fromRGB(10, 8, 5)
	armoryViewport.BackgroundTransparency = 0.2
	armoryViewport.BorderSizePixel = 0
	armoryViewport.Parent = armoryDetail
	local vc = Instance.new("UICorner")
	vc.CornerRadius = UDim.new(0, 8)
	vc.Parent = armoryViewport

	armoryDetailStats = Instance.new("TextLabel")
	armoryDetailStats.Position = UDim2.new(0, 0, 0, 228)
	armoryDetailStats.Size = UDim2.new(1, 0, 0, 70)
	armoryDetailStats.BackgroundTransparency = 1
	armoryDetailStats.Text = ""
	armoryDetailStats.TextColor3 = COLOR_WHITE
	armoryDetailStats.TextSize = 14
	armoryDetailStats.Font = Enum.Font.RobotoMono
	armoryDetailStats.TextXAlignment = Enum.TextXAlignment.Left
	armoryDetailStats.TextYAlignment = Enum.TextYAlignment.Top
	armoryDetailStats.Parent = armoryDetail

	armoryEquipBtn = Instance.new("TextButton")
	armoryEquipBtn.AnchorPoint = Vector2.new(0, 1)
	armoryEquipBtn.Position = UDim2.new(0, 0, 1, 0)
	armoryEquipBtn.Size = UDim2.new(0.5, -6, 0, 36)
	armoryEquipBtn.BackgroundColor3 = COLOR_BTN_SELECT
	armoryEquipBtn.BorderSizePixel = 0
	armoryEquipBtn.Text = "Equip"
	armoryEquipBtn.TextColor3 = COLOR_WHITE
	armoryEquipBtn.TextSize = 14
	armoryEquipBtn.Font = Enum.Font.Merriweather
	armoryEquipBtn.Parent = armoryDetail
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0, 6)
	ec.Parent = armoryEquipBtn

	armoryTransmogBtn = Instance.new("TextButton")
	armoryTransmogBtn.AnchorPoint = Vector2.new(1, 1)
	armoryTransmogBtn.Position = UDim2.new(1, 0, 1, 0)
	armoryTransmogBtn.Size = UDim2.new(0.5, -6, 0, 36)
	armoryTransmogBtn.BackgroundColor3 = COLOR_BTN_SELECT
	armoryTransmogBtn.BorderSizePixel = 0
	armoryTransmogBtn.Text = "Transmog"
	armoryTransmogBtn.TextColor3 = COLOR_WHITE
	armoryTransmogBtn.TextSize = 14
	armoryTransmogBtn.Font = Enum.Font.Merriweather
	armoryTransmogBtn.Parent = armoryDetail
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 6)
	tc.Parent = armoryTransmogBtn

	armoryEquipBtn.MouseButton1Click:Connect(function()
		if not armorySelected then
			return
		end
		local snap = ArmorAction:InvokeServer("Equip", armorySelected)
		if snap and snap.ok then
			armorySnapshot = snap
			refreshArmoryCurrent()
			refreshArmoryButtons()
		end
	end)
	armoryTransmogBtn.MouseButton1Click:Connect(function()
		if not armorySelected then
			return
		end
		local snap = ArmorAction:InvokeServer("Transmog", armorySelected)
		if snap and snap.ok then
			armorySnapshot = snap
			refreshArmoryCurrent()
			refreshArmoryButtons()
		end
	end)
end

-- Rebuilds the owned-armor list from a snapshot.
refreshArmoryPanel = function(snap)
	if not armoryPanel then
		return
	end
	armorySnapshot = snap
	armorySelected = nil
	armoryListButtons = {}

	for _, child in ipairs(armoryListFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- With no pick, the list is centered under the header.
	armoryDetail.Visible = false
	armoryListFrame.Position = UDim2.new(0.5, -ARM_LIST_W / 2, 0, 40)

	refreshArmoryCurrent()

	local owned = (snap and snap.owned) or {}
	for i, name in ipairs(owned) do
		local info = snap.armors[name]
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(1, -4, 0, 36)
		btn.BackgroundColor3 = COLOR_BTN_NORMAL
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Text = "  " .. ((info and info.DisplayName) or name)
		btn.TextColor3 = COLOR_WHITE
		btn.TextSize = 13
		btn.Font = Enum.Font.Merriweather
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		btn.LayoutOrder = i
		btn.Parent = armoryListFrame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = btn

		btn.MouseEnter:Connect(function()
			if armorySelected ~= name then
				btn.BackgroundColor3 = COLOR_BTN_HOVER
			end
		end)
		btn.MouseLeave:Connect(function()
			if armorySelected ~= name then
				btn.BackgroundColor3 = COLOR_BTN_NORMAL
			end
		end)
		btn.MouseButton1Click:Connect(function()
			selectArmor(name)
		end)

		armoryListButtons[name] = btn
	end
end

openArmoryPanel = function()
	if not armoryPanel then
		buildArmoryPanel()
	end
	if statPanel then
		statPanel.Visible = false
	end
	if spellPanel then
		spellPanel.Visible = false
	end
	local snap = ArmorAction:InvokeServer("Query")
	refreshArmoryPanel(snap)
	armoryPanel.Visible = true
	armoryPanel.Position = UDim2.new(0.04, 180, 0.5, 0)
	TweenService
		:Create(armoryPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.04, 256, 0.5, 0),
		})
		:Play()
end

-- Applies a server snapshot to every part of the panel.
applySnapshot = function(snap)
	if not statPanel or not snap then
		return
	end
	if snap.stats then
		localStats = snap.stats
	end
	localOwned = snap.owned or localOwned
	localAvailable = snap.available or 0
	localMaxSP = snap.maxSkillPoints or localMaxSP
	localNextCost = snap.nextCost or localNextCost

	for stat, lbl in pairs(statRows) do
		lbl.Text = tostring(localStats[stat] or 0)
	end
	if snap.liturgy then
		liturgyLabel.Text = "Liturgy: " .. tostring(snap.liturgy)
	end

	if skillPointLabel then
		skillPointLabel.Text = string.format("Skill Points: %d / %d", localOwned, localMaxSP)
	end
	if availableLabel then
		availableLabel.Text = "Available to spend: " .. tostring(localAvailable)
	end
	if buySkillBtn then
		if localOwned >= localMaxSP then
			buySkillBtn.Text = "Skill Points Maxed"
			buySkillBtn.AutoButtonColor = false
			buySkillBtn.BackgroundColor3 = COLOR_BTN_NORMAL
		else
			buySkillBtn.Text = string.format("Buy Skill Point  (%d L)", localNextCost)
			buySkillBtn.AutoButtonColor = true
			buySkillBtn.BackgroundColor3 = COLOR_BTN_SELECT
		end
	end
	-- A good refresh clears any error text.
	if snap.ok and nextCostLabel then
		nextCostLabel.Text = ""
	end
end

refreshStatPanel = function(liturgy, nextCost)
	applySnapshot({ liturgy = liturgy, nextCost = nextCost, ok = true })
end

openStatPanel = function()
	if not statPanel then
		buildStatPanel()
	end
	if spellPanel then
		spellPanel.Visible = false
	end
	if armoryPanel then
		armoryPanel.Visible = false
	end
	local result = StatAction:InvokeServer("Query")
	if result and result.ok then
		applySnapshot(result)
	end
	-- Slide the panel in from behind the rest panel.
	statPanel.Visible = true
	statPanel.Position = UDim2.new(0.04, 180, 0.5, 0)
	TweenService
		:Create(statPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.04, 256, 0.5, 0),
		})
		:Play()
end

-- Respecs after the player confirms.
local function performRespec()
	local result = StatAction:InvokeServer("Respec")
	if result and result.ok then
		if not statPanel then
			buildStatPanel()
		end
		statPanel.Visible = true
		applySnapshot(result)
		nextCostLabel.Text = "All skill points freed"
		nextCostLabel.TextColor3 = COLOR_GOLD
	elseif result and statPanel then
		nextCostLabel.Text = "Respec failed: " .. reasonText(result.reason)
		nextCostLabel.TextColor3 = Color3.fromRGB(200, 80, 70)
	end
end

-- Asks the player to confirm a respec.
local respecConfirm
doRespec = function()
	if respecConfirm then
		respecConfirm:Destroy()
		respecConfirm = nil
	end
	respecConfirm = Instance.new("Frame")
	respecConfirm.AnchorPoint = Vector2.new(0.5, 0.5)
	respecConfirm.Position = UDim2.new(0.5, 0, 0.5, 0)
	respecConfirm.Size = UDim2.new(0, 300, 0, 150)
	respecConfirm.BackgroundColor3 = Color3.fromRGB(18, 15, 10)
	respecConfirm.BorderSizePixel = 0
	respecConfirm.ZIndex = 50
	respecConfirm.Parent = restGui
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = respecConfirm
	local cs = Instance.new("UIStroke")
	cs.Color = COLOR_GOLD_DIM
	cs.Thickness = 1
	cs.Parent = respecConfirm

	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, -24, 0, 70)
	msg.Position = UDim2.new(0, 12, 0, 14)
	msg.BackgroundTransparency = 1
	msg.Text =
		"Respec all stats? This frees every assigned skill point so you can redistribute them. You keep all the skill points you've bought."
	msg.TextWrapped = true
	msg.TextColor3 = COLOR_WHITE
	msg.TextSize = 14
	msg.Font = Enum.Font.Merriweather
	msg.ZIndex = 51
	msg.Parent = respecConfirm

	local yes = Instance.new("TextButton")
	yes.Size = UDim2.new(0.5, -18, 0, 38)
	yes.Position = UDim2.new(0, 12, 1, -50)
	yes.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
	yes.BorderSizePixel = 0
	yes.Text = "Yes"
	yes.TextColor3 = COLOR_WHITE
	yes.TextSize = 15
	yes.Font = Enum.Font.Merriweather
	yes.ZIndex = 51
	yes.Parent = respecConfirm
	local yc = Instance.new("UICorner")
	yc.CornerRadius = UDim.new(0, 6)
	yc.Parent = yes

	local no = Instance.new("TextButton")
	no.Size = UDim2.new(0.5, -18, 0, 38)
	no.Position = UDim2.new(0.5, 6, 1, -50)
	no.BackgroundColor3 = Color3.fromRGB(60, 30, 24)
	no.BorderSizePixel = 0
	no.Text = "No"
	no.TextColor3 = COLOR_WHITE
	no.TextSize = 15
	no.Font = Enum.Font.Merriweather
	no.ZIndex = 51
	no.Parent = respecConfirm
	local nc = Instance.new("UICorner")
	nc.CornerRadius = UDim.new(0, 6)
	nc.Parent = no

	yes.MouseButton1Click:Connect(function()
		respecConfirm:Destroy()
		respecConfirm = nil
		performRespec()
	end)
	no.MouseButton1Click:Connect(function()
		respecConfirm:Destroy()
		respecConfirm = nil
	end)
end

local REST_DIM = 0.45

-- Plays the rest effect (LevelUpParticle) and the rest sound at the character.
local function playRestFX()
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local template = ReplicatedStorage.assets.FX:FindFirstChild("LevelUpParticle")
	if template then
		local fx = template:Clone()
		fx.Anchored = true
		fx.CanCollide = false
		fx.Transparency = 1
		fx.CFrame = root.CFrame
		fx.Parent = workspace
		-- No weld: the player is anchored while resting.
		for _, em in ipairs(fx:GetDescendants()) do
			if em:IsA("ParticleEmitter") then
				em.Enabled = true
				em:Emit(20)
			end
		end
		game:GetService("Debris"):AddItem(fx, 3)
	end
	attunementSound:Play()
end

beginRestLocal = function(spireId)
	resting = true
	currentRestSpireId = spireId
	buildRestGui()
	if not restTrack then
		loadRestAnim()
	end
	if restTrack then
		restTrack:Play(0.2)
	end
	if statPanel then
		statPanel.Visible = false
	end
	if spellPanel then
		spellPanel.Visible = false
	end
	if armoryPanel then
		armoryPanel.Visible = false
	end

	restGui.Enabled = true

	restDim.BackgroundTransparency = 1
	TweenService:Create(restDim, FADE_IN, { BackgroundTransparency = REST_DIM }):Play()

	restPanel.Position = UDim2.new(-0.3, 0, 0.5, 0)
	TweenService
		:Create(restPanel, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.04, 0, 0.5, 0),
		})
		:Play()

	playRestFX()
end

endRestLocal = function()
	resting = false
	currentRestSpireId = nil
	if restTrack then
		restTrack:Stop(0.2)
	end
	if statPanel then
		statPanel.Visible = false
	end
	if spellPanel then
		spellPanel.Visible = false
	end
	if armoryPanel then
		armoryPanel.Visible = false
	end
	if mapOpen then
		closeMap()
	end
	if restGui then
		local out = TweenService:Create(restDim, FADE_OUT, { BackgroundTransparency = 1 })
		out:Play()
		TweenService:Create(restPanel, FADE_OUT, { Position = UDim2.new(-0.3, 0, 0.5, 0) }):Play()
		out.Completed:Connect(function()
			if not resting then
				restGui.Enabled = false
			end
		end)
	end
end

requestEndRest = function()
	SpireRemote:FireServer("EndRest")
end

openMap = function()
	mapOpen = true
	selectedSpireId = nil
	TeleportButton.Visible = false
	SelectedLabel.Text = "Select a destination."
	SelectedLabel.TextColor3 = COLOR_MUTED
	CostLabel.Visible = false
	ErrorLabel.Visible = false

	buildList()

	MapFrame.GroupTransparency = 1
	MapFrame.Visible = true

	TweenService:Create(MapFrame, FADE_IN, {
		GroupTransparency = 0,
	}):Play()
end

closeMap = function()
	mapOpen = false
	local out = TweenService:Create(MapFrame, FADE_OUT, {
		GroupTransparency = 1,
	})
	out:Play()
	out.Completed:Wait()
	MapFrame.Visible = false
end

local OpenMapBindable = Instance.new("BindableFunction")
OpenMapBindable.Name = "OpenSpireMap"
OpenMapBindable.Parent = ReplicatedStorage.SpireSystem

OpenMapBindable.OnInvoke = function()
	if mapOpen then
		closeMap()
	else
		openMap()
	end
end

TeleportButton.MouseButton1Click:Connect(function()
	if not selectedSpireId then
		return
	end
	ErrorLabel.Visible = false
	SpireRemote:FireServer("Teleport", selectedSpireId)
end)

CloseButton.MouseButton1Click:Connect(function()
	closeMap()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- E during a rest ends it. This runs before the gameProcessed check, because the
	-- prompt may or may not take the key during a rest. EndRest is idempotent on the
	-- server, so a double send is harmless.
	if input.KeyCode == Enum.KeyCode.E and resting then
		SpireRemote:FireServer("EndRest")
		return
	end

	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and mapOpen then
		closeMap()
	end
end)

local function setupSpirePrompts()
	for _, spire in ipairs(SpireConfig.Spires) do
		local part = Workspace:FindFirstChild(spire.PartName, true)
		if not part then
			continue
		end

		local existing = part:FindFirstChild("AttunePrompt")
		if not existing then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "AttunePrompt"
			prompt.ObjectText = spire.Zone
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 16
			prompt.RequiresLineOfSight = false
			prompt.Parent = part

			local spireId = spire.Id

			prompt.Triggered:Connect(function()
				-- Using the prompt during a rest ends the rest.
				if resting then
					SpireRemote:FireServer("EndRest")
					return
				end
				if attunedSpires[spireId] then
					-- Attuned: rest here. The server opens the menu through RestStarted.
					SpireRemote:FireServer("Rest", spireId)
				else
					-- Not attuned: attune, and the server starts a rest.
					SpireRemote:FireServer("Attune", spireId)
				end
			end)
		end
	end
end

local function refreshPromptLabels()
	for _, spire in ipairs(SpireConfig.Spires) do
		local part = Workspace:FindFirstChild(spire.PartName, true)
		if part then
			local prompt = part:FindFirstChild("AttunePrompt")
			if prompt then
				-- TODO: label the prompt by attunement. Nothing sets ActionText yet.
			end
		end
	end
end

SpireUpdate.OnClientEvent:Connect(function(action, payload)
	if action == "Restore" then
		attunedSpires = {}
		for _, id in ipairs(payload) do
			attunedSpires[id] = true
		end
		refreshPromptLabels()
		if mapOpen then
			buildList()
		end
	elseif action == "Attuned" then
		local spireId = payload
		attunedSpires[spireId] = true

		local spireDef = nil
		for _, s in ipairs(SpireConfig.Spires) do
			if s.Id == spireId then
				spireDef = s
				break
			end
		end

		if spireDef then
			task.spawn(playAttunementEffect, spireDef.PartName)
			queueToast("Attuned: " .. spireDef.Name)
		end

		refreshPromptLabels()
		if mapOpen then
			buildList()
		end
	elseif action == "RestStarted" then
		local spireId = payload and payload.spireId
		local wasNew = payload and payload.wasNew
		if wasNew then
			-- A new attunement plays the world effect and the toast.
			local spireDef = nil
			for _, sp in ipairs(SpireConfig.Spires) do
				if sp.Id == spireId then
					spireDef = sp
					break
				end
			end
			if spireDef then
				attunedSpires[spireId] = true
				task.spawn(playAttunementEffect, spireDef.PartName)
				refreshPromptLabels()
			end
		end
		beginRestLocal(spireId)
	elseif action == "RestFailed" then
		queueToast(tostring(payload) or "Cannot rest right now.")
	elseif action == "RestEnded" then
		endRestLocal()
	elseif action == "TeleportSuccess" then
		-- Travel leaves the spire: the server ended the rest, so close the rest UI.
		endRestLocal()
		local sound = Instance.new("Sound")
		sound.Parent = workspace
		sound.SoundId = "rbxassetid://133431816965147"
		sound:Play()
	elseif action == "TeleportFailed" then
		ErrorLabel.Text = payload or "Teleportation failed."
		ErrorLabel.Visible = true
		CostLabel.Visible = false
	end
end)

MapFrame.Visible = false
AttunementToast.Visible = false

task.spawn(setupSpirePrompts)

-- On respawn, keep the new character, reload the rest animation, and end a stale rest.
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	restTrack = nil
	if resting then
		endRestLocal()
	end
end)
