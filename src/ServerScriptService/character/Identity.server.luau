-- [[ IDENTITY SERVER ]]
-- Location: ServerScriptService (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local TitleManager = require(ServerScriptService.modules.TitleManager)

local SOUL_COLORS = {
	Color3.fromRGB(160, 40, 40),
	Color3.fromRGB(200, 180, 120),
	Color3.fromRGB(220, 220, 230),
	Color3.fromRGB(125, 147, 162),
	Color3.fromRGB(162, 135, 189),
}

local SOUL_FONTS = {
	--Enum.Font.Fondamento,
	--Enum.Font.Antique,
	Enum.Font.Merriweather,
}

local SPECIAL_TITLES = {
	[1526974131] = "THE PRIMAL MAW",
}

-- ── REMOTES ───────────────────────────────────────────────────────────────────

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

-- ── OVERHEAD TAG ──────────────────────────────────────────────────────────────

local function buildNameText(player)
	local displayName = player.DisplayName
	local title = player:GetAttribute("Title") or ""

	--local specialTitle = SPECIAL_TITLES[player.UserId]
	--if specialTitle then
	--	return displayName .. ", " .. specialTitle
	--end

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
	-- Character may have been removed/respawned while we waited.
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

-- ── PLAYER JOIN ───────────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	local randomColor = SOUL_COLORS[math.random(1, #SOUL_COLORS)]
	local randomFont = SOUL_FONTS[math.random(1, #SOUL_FONTS)]

	player:SetAttribute("SoulColor", randomColor)
	player:SetAttribute("SoulFont", randomFont.Name)

	-- Tracks the profile-load state so character handling can gate on it
	-- without racing the CharacterAdded connection.
	local profileReady = false

	local function handleCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		-- Only build the tag once the saved title is loaded, so it appears
		-- complete the first time instead of popping in name-only.
		if not profileReady then
			return
		end
		refreshOverhead(player, character)
		TitleManager.UpdateAura(player, player:GetAttribute("Title"))
	end

	-- Register BEFORE any yielding so a fast spawn can't slip past us.
	player.CharacterAdded:Connect(handleCharacter)

	-- Refresh tag when title attribute changes
	player:GetAttributeChangedSignal("Title"):Connect(function()
		TitleManager.UpdateAura(player, player:GetAttribute("Title"))
		local char = player.Character
		if char then
			refreshOverhead(player, char)
		end
		-- Tell all clients to update the leaderboard entry for this player
		TitleUpdated:FireAllClients(player.UserId, player:GetAttribute("Title"))
	end)

	-- Load saved title once profile is ready
	DataManager.YieldUntilLoaded(player)
	local savedTitle = DataManager.GetCurrentTitle(player)
	profileReady = true
	player:SetAttribute("Title", savedTitle or "")
	TitleManager.UpdateAura(player, player:GetAttribute("Title"))

	-- If the character spawned during the yield, its handleCharacter ran with
	-- profileReady == false and bailed. Build the tag now that data is in.
	-- If the title was actually non-empty, setting the attribute above already
	-- fired refreshOverhead via the changed signal, and the destroy-then-rebuild
	-- in refreshOverhead makes a second call harmless.
	if player.Character then
		refreshOverhead(player, player.Character)
	end
end)

-- ── REMOTES ───────────────────────────────────────────────────────────────────

SetTitleRemote.OnServerEvent:Connect(function(player, title)
	-- Allow clearing title with empty string
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
