-- SPDX-License-Identifier: MIT
--
-- Owns title unlocks: kill, death, weapon mastery, skill, and developer titles, their
-- Liturgy rewards, and the title aura.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local DevConfig = require(ServerScriptService.modules.DevConfig)

local AurasFolder =
	ReplicatedStorage:WaitForChild("assets"):WaitForChild("auras"):WaitForChild("title")

local TitleManager = {}

-- Each title has a Liturgy reward and the unlock text shown to the player.

TitleManager.Titles = {

	-- Kill titles.
	["the Bully"] = { Liturgy = 300, Description = "Kill 10 players." },
	["the Butcher"] = { Liturgy = 300, Description = "Kill 50 players." },
	["the Ghost"] = { Liturgy = 1000, Description = "Kill 100 players." },
	["Hollow One"] = { Liturgy = 1500, Description = "Kill 500 players." },

	-- Death titles.
	["the Victim"] = { Liturgy = 50, Description = "Die once." },
	["the Hunted"] = { Liturgy = 150, Description = "Die 10 times." },
	["the Prey"] = { Liturgy = 500, Description = "Die 50 times." },
	["the Befallen"] = { Liturgy = 2000, Description = "Die 200 times." },
	["the Vengeful"] = { Liturgy = 1000, Description = "Die 500 times." },

	-- Weapon mastery titles.
	["the Hero"] = { Liturgy = 0, Description = "Reach level 25 with the Sword." },
	["the Berserker"] = { Liturgy = 0, Description = "Reach level 25 with the Greatsword." },
	["the Shade"] = { Liturgy = 0, Description = "Reach level 25 with the Dagger." },
	["the Ronin"] = { Liturgy = 0, Description = "Reach level 25 with the Katana." },
	["the Iron Fist"] = { Liturgy = 0, Description = "Reach level 25 with the Fists." },
	["the Oni"] = { Liturgy = 0, Description = "Obtain the skill Messatsu." },

	-- Progression titles.
	["the Unfound"] = { Liturgy = 0, Description = "Reach level 25 with any weapon." },
	["the Replicant"] = { Liturgy = 0, Description = "Reach level 25 with all weapons." },

	-- Developer titles, granted by UserId.
	["Angel's Thanatos"] = {
		Liturgy = 6700,
		Description = "???",
		UserId = DevConfig.UserIds.thanatos,
	},
	["the Primal Maw"] = {
		Liturgy = 6700,
		Description = "???",
		UserId = DevConfig.UserIds.primalMaw,
	},
	["the Unforgiven"] = {
		Liturgy = 6700,
		Description = "???",
		UserId = DevConfig.UserIds.unforgiven,
	},
	["the Dragon Knight"] = {
		Liturgy = 6700,
		Description = "???",
		UserId = DevConfig.UserIds.unforgiven,
	},
}

local killTitles = {
	{ Threshold = 10, Title = "the Butcher" },
	{ Threshold = 100, Title = "the Ghost" },
	{ Threshold = 250, Title = "the Wraith" },
	{ Threshold = 500, Title = "the Phantom" },
}

local deathTitles = {
	{ Threshold = 1, Title = "the Victim" },
	{ Threshold = 10, Title = "the Hunted" },
	{ Threshold = 50, Title = "the Prey" },
	{ Threshold = 200, Title = "the Befallen" },
	{ Threshold = 500, Title = "the Vengeful" },
}

local weaponTitles = {
	Sword = "the Hero",
	Greatsword = "the Berserker",
	Dagger = "the Shade",
	Katana = "the Ronin",
	Fists = "the Iron Fist",
}

local allWeapons = { "Sword", "Greatsword", "Dagger", "Katana", "Fists" }

local remotes = ReplicatedStorage:WaitForChild("remotes")

local TitleEarnedRemote = remotes:FindFirstChild("TitleEarned")
if not TitleEarnedRemote then
	TitleEarnedRemote = Instance.new("RemoteEvent")
	TitleEarnedRemote.Name = "TitleEarned"
	TitleEarnedRemote.Parent = remotes
end

local TitleUnlockedRemote = remotes:FindFirstChild("TitleUnlocked")
if not TitleUnlockedRemote then
	TitleUnlockedRemote = Instance.new("RemoteEvent")
	TitleUnlockedRemote.Name = "TitleUnlocked"
	TitleUnlockedRemote.Parent = remotes
end

local function grantTitle(player, titleName)
	local def = TitleManager.Titles[titleName]
	if not def then
		return
	end

	local isNew = DataManager.UnlockTitle(player, titleName)
	if not isNew then
		return
	end

	if def.Liturgy and def.Liturgy > 0 then
		DataManager.AddLiturgy(player, def.Liturgy)
	end

	-- The client shows this with the quest-complete UI.
	TitleEarnedRemote:FireClient(player, titleName, def.Liturgy or 0)

	-- Refreshes the title selector if it is open.
	TitleUnlockedRemote:FireClient(player, titleName)
end

-- TitleManager.CheckKills() - grant the kill titles a player has earned
-- @player: the player
--
-- Return: nothing.
function TitleManager.CheckKills(player)
	local kills = DataManager.GetKills(player)
	for _, entry in ipairs(killTitles) do
		if kills >= entry.Threshold then
			grantTitle(player, entry.Title)
		end
	end
end

-- TitleManager.CheckDeaths() - grant the death titles a player has earned
-- @player: the player
--
-- Return: nothing.
function TitleManager.CheckDeaths(player)
	local deaths = DataManager.GetDeaths(player)
	for _, entry in ipairs(deathTitles) do
		if deaths >= entry.Threshold then
			grantTitle(player, entry.Title)
		end
	end
end

-- TitleManager.CheckWeaponMastery() - grant the titles for a weapon at level 25
-- @player: the player
-- @weaponName: the weapon that reached level 25
--
-- Also grants the Unfound title, and the Replicant title when every seed weapon is at
-- level 25.
--
-- Return: nothing.
function TitleManager.CheckWeaponMastery(player, weaponName)
	local weaponTitle = weaponTitles[weaponName]
	if weaponTitle then
		grantTitle(player, weaponTitle)
	end

	grantTitle(player, "the Unfound")

	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end

	local allMax = true
	for _, wName in ipairs(allWeapons) do
		local wData = profile.Data.WeaponProgression[wName]
		if not wData or wData.Level < 25 then
			allMax = false
			break
		end
	end

	if allMax then
		grantTitle(player, "the Replicant")
	end
end

-- TitleManager.UpdateAura() - show the aura of the equipped title
-- @player: the player
-- @equippedTitleName: the equipped title
--
-- Removes any old title aura first. Only some titles have an aura.
--
-- Return: nothing.
function TitleManager.UpdateAura(player, equippedTitleName)
	local character = player.Character
	if not character then
		return
	end

	for _, child in ipairs(character:GetDescendants()) do
		if child.Name:match("_TitleAura$") then
			child:Destroy()
		end
	end

	if equippedTitleName ~= "Angel's Thanatos" and equippedTitleName ~= "the Primal Maw" then
		return
	end

	local auraFolder = AurasFolder:FindFirstChild(equippedTitleName)
	if not auraFolder then
		warn(`[TitleManager] No aura folder for title {equippedTitleName}.`)
		return
	end

	for _, partFolder in ipairs(auraFolder:GetChildren()) do
		local targetPart = character:FindFirstChild(partFolder.Name)

		if targetPart and targetPart:IsA("BasePart") then
			for _, visualElement in ipairs(partFolder:GetChildren()) do
				local clone = visualElement:Clone()
				clone.Name = clone.Name .. "_TitleAura"
				clone.Parent = targetPart
			end
		else
			warn(`[TitleManager] {player.Name} has no part {partFolder.Name} for the title aura.`)
		end
	end
end

-- TitleManager.CheckSpecUnlock() - grant the developer titles of a player
-- @player: the player
--
-- Return: nothing.
function TitleManager.CheckSpecUnlock(player)
	for titleName, def in pairs(TitleManager.Titles) do
		if def.UserId and def.UserId == player.UserId then
			grantTitle(player, titleName)
		end
	end
end

-- TitleManager.CheckSkillUnlock() - grant the title for a learned skill
-- @player: the player
-- @spellName: the skill the player learned
--
-- Return: nothing.
function TitleManager.CheckSkillUnlock(player, spellName)
	if spellName == "Messatsu" then
		grantTitle(player, "the Oni")
	end
end

_G.TitleManager = TitleManager
return TitleManager
