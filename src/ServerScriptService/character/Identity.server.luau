-- SPDX-License-Identifier: MIT
--
-- Gives each player a random soul color and font, builds the overhead name tag with
-- their title, and handles the title remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local TitleManager = require(ServerScriptService.modules.TitleManager)

local soulColors = {
	Color3.fromRGB(160, 40, 40),
	Color3.fromRGB(200, 180, 120),
	Color3.fromRGB(220, 220, 230),
	Color3.fromRGB(125, 147, 162),
	Color3.fromRGB(162, 135, 189),
}

local soulFonts = {
	Enum.Font.Merriweather,
}

local specialTitles = {
	[1526974131] = "THE PRIMAL MAW",
}

local remotes = ReplicatedStorage:WaitForChild("remotes")

local SetTitleRemote = remotes:FindFirstChild("SetTitle")
if not SetTitleRemote then
	SetTitleRemote = Instance.new("RemoteEvent")
	SetTitleRemote.Name = "SetTitle"
	SetTitleRemote.Parent = remotes
end

local RequestTitlesRemote = remotes:FindFirstChild("RequestTitles")
if not RequestTitlesRemote then
	RequestTitlesRemote = Instance.new("RemoteFunction")
	RequestTitlesRemote.Name = "RequestTitles"
	RequestTitlesRemote.Parent = remotes
end

local TitleUpdated = remotes:FindFirstChild("TitleUpdated")
if not TitleUpdated then
	TitleUpdated = Instance.new("RemoteEvent")
	TitleUpdated.Name = "TitleUpdated"
	TitleUpdated.Parent = remotes
end

local function buildNameText(player)
	local displayName = player.DisplayName
	local title = player:GetAttribute("Title") or ""

	if title ~= "" then
		return displayName .. ", " .. title
	end

	return displayName
end

local function refreshOverhead(player, character)
	if not character or not character.Parent then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head then
		head = character:WaitForChild("Head", 10)
	end
	-- The character may have been removed or respawned during the wait.
	if not head or not head.Parent or character.Parent == nil then
		return
	end
	if player.Character ~= character then
		return
	end

	local existing = head:FindFirstChild("ReplicantTag")
	if existing then
		existing:Destroy()
	end

	local color = player:GetAttribute("SoulColor") or Color3.new(1, 1, 1)
	local fontName = player:GetAttribute("SoulFont") or "Fantasy"
	local font = Enum.Font[fontName] or Enum.Font.Fantasy

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ReplicantTag"
	billboard.Size = UDim2.new(0, 220, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 100
	billboard.PlayerToHideFrom = player
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = buildNameText(player)
	nameLabel.TextColor3 = color
	nameLabel.Font = font
	nameLabel.TextSize = 24
	nameLabel.TextStrokeTransparency = 0.6
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.Parent = billboard
end

Players.PlayerAdded:Connect(function(player)
	local randomColor = soulColors[math.random(1, #soulColors)]
	local randomFont = soulFonts[math.random(1, #soulFonts)]

	player:SetAttribute("SoulColor", randomColor)
	player:SetAttribute("SoulFont", randomFont.Name)

	-- Whether the profile has loaded. Character handling checks it, so it does not race
	-- the CharacterAdded connection.
	local profileReady = false

	local function handleCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		-- Build the tag only after the saved title loads, so it does not appear without
		-- the title first.
		if not profileReady then
			return
		end
		refreshOverhead(player, character)
		TitleManager.UpdateAura(player, player:GetAttribute("Title"))
	end

	-- Connect before anything yields, so a fast spawn is not missed.
	player.CharacterAdded:Connect(handleCharacter)

	player:GetAttributeChangedSignal("Title"):Connect(function()
		TitleManager.UpdateAura(player, player:GetAttribute("Title"))
		local char = player.Character
		if char then
			refreshOverhead(player, char)
		end
		-- Update this player's leaderboard entry on every client.
		TitleUpdated:FireAllClients(player.UserId, player:GetAttribute("Title"))
	end)

	DataManager.YieldUntilLoaded(player)
	local savedTitle = DataManager.GetCurrentTitle(player)
	profileReady = true
	player:SetAttribute("Title", savedTitle or "")
	TitleManager.UpdateAura(player, player:GetAttribute("Title"))

	-- A character that spawned during the wait skipped its tag, so build it now. A second
	-- build is harmless, because refreshOverhead replaces the old tag.
	if player.Character then
		refreshOverhead(player, player.Character)
	end
end)

SetTitleRemote.OnServerEvent:Connect(function(player, title)
	-- An empty string clears the title.
	if title ~= "" and not DataManager.HasTitle(player, title) then
		return
	end
	DataManager.SetCurrentTitle(player, title)
	TitleManager.UpdateAura(player, title)
end)

RequestTitlesRemote.OnServerInvoke = function(player)
	DataManager.YieldUntilLoaded(player)
	return {
		Unlocked = DataManager.GetUnlockedTitles(player),
		Current = DataManager.GetCurrentTitle(player),
	}
end
