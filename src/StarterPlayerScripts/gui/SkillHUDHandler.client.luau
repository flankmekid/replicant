local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)
local TriggerCooldownEvent = ReplicatedStorage.remotes:WaitForChild("TriggerCooldown")

-- Key Mapping for Display
local KEY_NAMES = { [1] = "Z", [2] = "X", [3] = "C", [4] = "V" }

-- [[ GUI CREATION ]] --
local playerGui = player:WaitForChild("PlayerGui")

if playerGui:FindFirstChild("WeaponSkillHUD") then
	playerGui.WeaponSkillHUD:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WeaponSkillHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0.5, 1) 
container.Position = UDim2.new(0.5, 0, 0.89, 0)
container.Size = UDim2.new(0, 0, 0, 0)
container.AutomaticSize = Enum.AutomaticSize.XY
container.BackgroundTransparency = 1
container.Parent = screenGui

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = container
listLayout.FillDirection = Enum.FillDirection.Horizontal 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8) 

local activeSkillFrames = {}

-- [[ STATE TRACKING ]] --
-- This table remembers cooldowns even if the UI is deleted/refreshed
-- Format: { [skillName] = { endTime = number, totalDuration = number } }
local activeCooldowns = {} 

-- [[ FUNCTIONS ]] --

local function createSkillBar(skillName, slotIndex, isRace)
	local frame = Instance.new("Frame")
	frame.Name = skillName
	frame.Size = UDim2.new(0, 160, 0, 30) 
	frame.BackgroundColor3 = isRace and Color3.fromRGB(50, 40, 60) or Color3.fromRGB(36, 36, 36)
	frame.BackgroundTransparency = 0.4 
	frame.BorderSizePixel = 0
	frame.LayoutOrder = slotIndex
	frame.ClipsDescendants = true 

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 6)
	uiCorner.Parent = frame

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = isRace and Color3.fromRGB(100, 80, 120) or Color3.fromRGB(50, 50, 50)
	uiStroke.Thickness = 1
	uiStroke.Transparency = 0.5
	uiStroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = string.format("[%s] %s", KEY_NAMES[slotIndex] or "?", skillName)
	label.Font = Enum.Font.RobotoMono 
	label.TextSize = 14 
	label.TextColor3 = Color3.fromRGB(230, 230, 230)
	label.TextXAlignment = Enum.TextXAlignment.Center 
	label.ZIndex = 5 
	label.Parent = frame

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Transparency = 0.8
	textStroke.Parent = label

	local cdBar = Instance.new("Frame")
	cdBar.Name = "CooldownBar"
	cdBar.Size = UDim2.new(0, 0, 1, 0) -- Starts empty (visuals only appear when CD active)
	cdBar.BackgroundColor3 = isRace and Color3.fromRGB(120, 60, 180) or Color3.fromRGB(180, 40, 40)
	cdBar.BackgroundTransparency = 0.6 
	cdBar.BorderSizePixel = 0
	cdBar.ZIndex = 2
	cdBar.Parent = frame

	local cdCorner = Instance.new("UICorner")
	cdCorner.CornerRadius = UDim.new(0, 6)
	cdCorner.Parent = cdBar

	return frame, cdBar
end

-- Helper to apply the tween logic to a specific bar
local function ApplyCooldownAnimation(bar, remainingTime, totalDuration)
	-- Calculate percentage left (e.g., 0.5 = 50% width)
	local scale = remainingTime / totalDuration

	-- Snap size immediately to current progress
	bar.Size = UDim2.new(scale, 0, 1, 0)

	-- Tween to 0
	local tweenInfo = TweenInfo.new(remainingTime, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(bar, tweenInfo, {Size = UDim2.new(0, 0, 1, 0)})
	tween:Play()
end

local function RefreshHUD()
	-- Clear existing GUI
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	activeSkillFrames = {}

	local char = player.Character
	if not char then return end

	-- 1. WEAPON SKILLS (Slots 1-3)
	-- Read the player's equipped loadout per family (set in the spellbook), not the
	-- static branch list, so spellbook swaps and newly-learned skills show correctly.
	local tool = char:FindFirstChildWhichIsA("Tool")
	if tool then
		local family = SkillConfig.WeaponFamily[tool.Name]
		local stats = player:FindFirstChild("PlayerStats")
		local equippedFolder = stats and stats:FindFirstChild("EquippedSkills")
		local famFolder = family and equippedFolder and equippedFolder:FindFirstChild(family)

		if famFolder then
			for index = 1, 3 do
				local slotKey = SkillConfig.SlotKeys[index]
				local slotVal = famFolder:FindFirstChild(slotKey)
				local skillName = slotVal and slotVal.Value
				if skillName and skillName ~= "" then
					local frame, cdBar = createSkillBar(skillName, index, false)
					frame.Parent = container
					activeSkillFrames[skillName] = cdBar
				end
			end
		end
	end

	-- 2. RACE SKILL (Slot 4 - "V")
	local stats = player:FindFirstChild("PlayerStats")
	local raceVal = stats and stats:FindFirstChild("Race") and stats.Race.Value
	if raceVal then
		local raceSkillName = SkillConfig.RaceSkills[raceVal]
		if raceSkillName then
			local frame, cdBar = createSkillBar(raceSkillName, 4, true)
			frame.Parent = container
			activeSkillFrames[raceSkillName] = cdBar
		end
	end

	-- 3. RESUME ANIMATIONS (The Fix)
	-- Loop through active frames and check if we have a saved cooldown for them
	for skillName, bar in pairs(activeSkillFrames) do
		local cdData = activeCooldowns[skillName]
		if cdData then
			local remaining = cdData.endTime - os.clock()

			if remaining > 0 then
				-- It's still on cooldown, resume animation
				ApplyCooldownAnimation(bar, remaining, cdData.totalDuration)
			else
				-- It expired while the UI was refreshing/gone
				activeCooldowns[skillName] = nil
				bar.Size = UDim2.new(0, 0, 1, 0)
			end
		end
	end
end

local function OnCooldownTriggered(skillName, duration)
	-- 1. Save State
	activeCooldowns[skillName] = {
		endTime = os.clock() + duration,
		totalDuration = duration
	}

	-- 2. Animate if visible
	local bar = activeSkillFrames[skillName]
	if bar then
		ApplyCooldownAnimation(bar, duration, duration)
	end
end

-- [[ CONNECTIONS ]] --

TriggerCooldownEvent.Event:Connect(OnCooldownTriggered)

-- Refresh the HUD whenever the equipped loadout changes (spellbook swap or a
-- newly-learned skill auto-equipping). Connected once; the folder persists across
-- respawns so we don't re-hook per character.
local equippedHooked = false
local function hookEquippedSkills()
	if equippedHooked then return end
	local stats = player:FindFirstChild("PlayerStats") or player:WaitForChild("PlayerStats", 10)
	local equippedFolder = stats and (stats:FindFirstChild("EquippedSkills") or stats:WaitForChild("EquippedSkills", 10))
	if not equippedFolder then return end
	equippedHooked = true
	RefreshHUD()

	local function watchSlot(sv)
		if sv:IsA("StringValue") then
			sv:GetPropertyChangedSignal("Value"):Connect(RefreshHUD)
		end
	end
	-- Existing family folders + their slot values.
	for _, famFolder in ipairs(equippedFolder:GetChildren()) do
		for _, sv in ipairs(famFolder:GetChildren()) do watchSlot(sv) end
		famFolder.ChildAdded:Connect(watchSlot)
	end
	-- Family folders created later (first skill in a new family).
	equippedFolder.ChildAdded:Connect(function(famFolder)
		for _, sv in ipairs(famFolder:GetChildren()) do watchSlot(sv) end
		famFolder.ChildAdded:Connect(watchSlot)
		RefreshHUD()
	end)
end

local function hookCharacter(char)
	if not char then return end

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then RefreshHUD() end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then RefreshHUD() end
	end)

	task.spawn(hookEquippedSkills)
	RefreshHUD()
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then hookCharacter(player.Character) end