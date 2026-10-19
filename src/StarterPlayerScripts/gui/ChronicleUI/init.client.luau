-- SPDX-License-Identifier: MIT
--
-- The Chronicle panel, toggled with M: the level and XP of each weapon family.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerStats = player:WaitForChild("PlayerStats", 10)
local weaponData = playerStats:WaitForChild("WeaponData", 10)

local uiTheme = {
	BackgroundColor = Color3.fromRGB(15, 15, 15),
	ItemColor = Color3.fromRGB(30, 30, 30),
	TextColor = Color3.fromRGB(220, 220, 220),
	BarBackground = Color3.fromRGB(60, 60, 60),
	BarFill = Color3.fromRGB(200, 180, 120), -- The Leaderboard accent.
	Accent = Color3.fromRGB(200, 180, 120),
	Transparency = 0.6,
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WeaponChronicle"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 450)
mainFrame.Position = UDim2.new(0.9, -175, 0.5, -225)
mainFrame.BackgroundColor3 = uiTheme.BackgroundColor
mainFrame.BackgroundTransparency = uiTheme.Transparency
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = screenGui

local topStroke = Instance.new("Frame")
topStroke.Size = UDim2.new(1, 0, 0, 2)
topStroke.BackgroundColor3 = uiTheme.Accent
topStroke.BorderSizePixel = 0
topStroke.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Text = "WEAPON MASTERY"
title.Size = UDim2.new(1, 0, 0, 50)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Fantasy
title.TextSize = 22
title.TextColor3 = uiTheme.TextColor
title.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -60)
scrollFrame.Position = UDim2.new(0, 10, 0, 55)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 2
scrollFrame.ScrollBarImageColor3 = uiTheme.Accent
scrollFrame.Parent = mainFrame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.Name
layout.Parent = scrollFrame

local function createWeaponEntry(weaponFolder)
	local weaponName = weaponFolder.Name
	local currentXP = weaponFolder:WaitForChild("CurrentXP")
	local maxXP = weaponFolder:WaitForChild("MaxXP")
	local level = weaponFolder:WaitForChild("Level")

	local entry = Instance.new("Frame")
	entry.Name = weaponName
	entry.Size = UDim2.new(1, -5, 0, 60)
	entry.BackgroundColor3 = uiTheme.ItemColor
	entry.BackgroundTransparency = 0.5
	entry.BorderSizePixel = 0
	entry.Parent = scrollFrame

	local deco = Instance.new("Frame")
	deco.Size = UDim2.new(0, 3, 1, 0)
	deco.BackgroundColor3 = uiTheme.Accent
	deco.BorderSizePixel = 0
	deco.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Text = string.upper(weaponName)
	nameLabel.Size = UDim2.new(1, -20, 0, 25)
	nameLabel.Position = UDim2.new(0, 15, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Fantasy
	nameLabel.TextSize = 18
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = uiTheme.TextColor
	nameLabel.Parent = entry

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Text = "Lv." .. level.Value
	levelLabel.Size = UDim2.new(0, 80, 0, 25)
	levelLabel.Position = UDim2.new(1, -85, 0, 5)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.RobotoMono
	levelLabel.TextSize = 16
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.TextColor3 = uiTheme.TextColor
	levelLabel.Parent = entry

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -30, 0, 8)
	barBg.Position = UDim2.new(0, 15, 0, 40)
	barBg.BackgroundColor3 = uiTheme.BarBackground
	barBg.BorderSizePixel = 0
	barBg.Parent = entry

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = uiTheme.BarFill
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.Parent = barBg

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Size = UDim2.new(1, 0, 0, 15)
	xpLabel.Position = UDim2.new(0, 0, 1, 2)
	xpLabel.BackgroundTransparency = 1
	xpLabel.Text = currentXP.Value .. " / " .. maxXP.Value
	xpLabel.Font = Enum.Font.RobotoMono
	xpLabel.TextSize = 10
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	xpLabel.Parent = barBg

	local function updateDisplay()
		local cur = currentXP.Value
		local max = maxXP.Value
		local lvl = level.Value

		levelLabel.Text = "Lv." .. lvl
		xpLabel.Text = cur .. " / " .. max

		local percent = 0
		if max > 0 then
			percent = math.clamp(cur / max, 0, 1)
		end

		TweenService:Create(barFill, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {
			Size = UDim2.new(percent, 0, 1, 0),
		}):Play()
	end

	currentXP.Changed:Connect(updateDisplay)
	maxXP.Changed:Connect(updateDisplay)
	level.Changed:Connect(updateDisplay)

	updateDisplay()
end

if weaponData then
	for _, folder in pairs(weaponData:GetChildren()) do
		createWeaponEntry(folder)
	end
	weaponData.ChildAdded:Connect(createWeaponEntry)
end

local function ToggleUI()
	mainFrame.Visible = not mainFrame.Visible
	script.pageFlip:Play()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		ToggleUI()
	end
end)
