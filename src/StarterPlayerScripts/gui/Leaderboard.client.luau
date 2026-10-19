-- [[ LEADERBOARD CLIENT ]]
-- Location: StarterPlayerScripts

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local remotes = ReplicatedStorage:WaitForChild("remotes")
local TitleUpdated = remotes:WaitForChild("TitleUpdated")

-- ── GUI ───────────────────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReplicantLeaderboard"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -20, 0, 20)
container.Size = UDim2.new(0, 250, 0, 400)
container.BackgroundTransparency = 1
container.Parent = screenGui

local header = Instance.new("TextLabel")
header.Text = "INDEX:"
header.Size = UDim2.new(1, 0, 0, 30)
header.Font = Enum.Font.Merriweather
header.TextColor3 = Color3.fromRGB(234, 234, 234)
header.BackgroundTransparency = 1
header.TextSize = 22
header.Parent = container

local listFrame = Instance.new("ScrollingFrame")
listFrame.Position = UDim2.new(0, 0, 0, 35)
listFrame.Size = UDim2.new(1, 0, 1, -35)
listFrame.BackgroundTransparency = 1
listFrame.ScrollBarThickness = 2
listFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
listFrame.Parent = container

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 5)
layout.Parent = listFrame

-- ── ENTRY BUILDER ─────────────────────────────────────────────────────────────

local function buildDisplayText(player)
	local title = player:GetAttribute("Title") or ""
	if title ~= "" then
		return player.DisplayName .. ", " .. title
	end
	return player.DisplayName
end

local function addPlayerEntry(player)
	if not player:GetAttribute("SoulColor") then
		player:GetAttributeChangedSignal("SoulColor"):Wait()
	end

	local soulColor = player:GetAttribute("SoulColor") or Color3.new(1, 1, 1)
	local fontName = player:GetAttribute("SoulFont") or "Fantasy"
	local soulFont = Enum.Font[fontName] or Enum.Font.Fantasy

	local entry = Instance.new("Frame")
	entry.Name = player.Name
	entry.Size = UDim2.new(1, -10, 0, 30)
	entry.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	entry.BackgroundTransparency = 0.6
	entry.BorderSizePixel = 0
	entry.Parent = listFrame

	local deco = Instance.new("Frame")
	deco.Size = UDim2.new(0, 3, 1, 0)
	deco.BackgroundColor3 = soulColor
	deco.BorderSizePixel = 0
	deco.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -15, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = buildDisplayText(player)
	nameLabel.Font = soulFont
	nameLabel.TextColor3 = soulColor
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = entry

	-- Update label when this player's title changes
	player:GetAttributeChangedSignal("Title"):Connect(function()
		nameLabel.Text = buildDisplayText(player)
	end)
end

-- ── LIST MANAGEMENT ───────────────────────────────────────────────────────────

local function updateList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(addPlayerEntry, p)
	end
end

Players.PlayerAdded:Connect(updateList)
Players.PlayerRemoving:Connect(updateList)

updateList()
