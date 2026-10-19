-- SPDX-License-Identifier: MIT
--
-- Owns player save data through ProfileStore: loading and saving profiles, the
-- PlayerStats folder that mirrors the data for other scripts and the client, and the
-- API for currency, stats, appearance, armor, weapons, skills, quests, and titles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local ProfileStore = require(game.ServerScriptService.modules:WaitForChild("ProfileStore"))
local StatScaling = require(game.ReplicatedStorage.modules:WaitForChild("StatScaling"))

local module = {}

local DATA_STORE_NAME = "Apocrypha_Data_v6_TESTING"
local CURRENCY_NAME = "Liturgy"
local MAX_LEVEL = 25
local WEAPON_TYPES = { "Fists", "Katana", "Sword", "Dagger", "Greatsword" }
local DROP_LIFETIME = 180
local DEATH_DROP_AMOUNT = 200
local DEFAULT_WEAPON = "Fists"

local assets = ReplicatedStorage:WaitForChild("assets")
local fxFolder = assets:WaitForChild("FX")
local liturgyTemplate = fxFolder:WaitForChild("Liturgy")
local facesFolder = ReplicatedStorage:WaitForChild("faces")

-- A new profile gets a random eye color from this list.
local REALISTIC_EYE_COLORS = {
	{ R = 89, G = 59, B = 32 }, -- Dark brown.
	{ R = 139, G = 69, B = 19 }, -- Brown.
	{ R = 99, G = 78, B = 52 }, -- Hazel.
	{ R = 45, G = 87, B = 139 }, -- Deep blue.
	{ R = 95, G = 140, B = 178 }, -- Light blue.
	{ R = 62, G = 107, B = 64 }, -- Green.
	{ R = 128, G = 128, B = 128 }, -- Grey.
	{ R = 48, G = 48, B = 48 }, -- Black.
	{ R = 138, G = 119, B = 78 }, -- Amber.
}

-- The default profile. ProfileStore adds missing keys to old profiles with Reconcile.
local ProfileTemplate = {
	Liturgy = 0,
	Spins = 100,
	Pity = 0,
	Race = "Human",
	TutorialComplete = false,
	WeaponProgression = {},

	UnlockedSpells = {},
	-- The spellbook loadout: EquippedSkills[family] = { Z, X, C }.
	EquippedSkills = {},

	Inventory = {},

	InventoryData = {
		-- Items: { Id = "uuid", Name = "ItemName", Amount = 1 }.
		Items = {},
		-- Hotbar: slot index (1 to 9) to item.
		Hotbar = {},
		Equipment = {
			Head = nil,
			Torso = nil,
			Legs = nil,
			Back = nil,
		},
	},

	EyeColor = nil,
	Face = nil,
	Hair = { 0, 0, 0 },
	Gender = "Male",
	ArmorColor = nil,

	MaxHP = 100,
	MaxMana = 100,
	HPBoost = 1,
	ManaBoost = 1,
	SpeedBoost = 1,
	DamageBoost = 1,
	DefenseBoost = 1,
	RegenMultiplier = 1,
	LiturgyMultiplier = 1,
	JumpBoost = 1,
	DashDuration = 0.2,
	SlideDuration = 2.0,

	-- Invested stat points, 0 to 50 each.
	Stats = {
		Vitality = 0,
		Stamina = 0,
		Strength = 0,
		Dexterity = 0,
		Magic = 0,
	},
	-- Skill points bought with Liturgy (0 to 150, never decreases). Assigning one to a
	-- stat is free, so the available points are SkillPointsOwned minus the sum of all
	-- stats.
	SkillPointsOwned = 0,

	CurrentArmor = "Rags",
	OwnedArmors = { "Rags" },
	-- The transmog. nil means the vanity follows CurrentArmor. Stats always come from
	-- CurrentArmor.
	CurrentVanity = nil,

	Quest = {
		-- Active: an array of { Id = string, Progress = number }.
		Active = {},
		-- Tracked: the quest ID in the HUD tracker. See SetTrackedQuest.
		Tracked = nil,
		Completed = {},
		Cooldowns = {},
	},

	Attuned = {},

	UnlockedTitles = {},
	CurrentTitle = "",
	PlayerKills = 0,
	PlayerDeaths = 0,

	-- The last saved position as { X, Y, Z }.
	LastPosition = nil,
}

for _, weapon in ipairs(WEAPON_TYPES) do
	ProfileTemplate.WeaponProgression[weapon] = { XP = 0, Level = 1 }
end

local GameProfileStore = ProfileStore.New(DATA_STORE_NAME, ProfileTemplate)
local Profiles = {}

local function GetRandomFaceForRace(raceName)
	local targetFolder = facesFolder:FindFirstChild(string.lower(raceName))
	if not targetFolder or #targetFolder:GetChildren() == 0 then
		targetFolder = facesFolder:FindFirstChild("default")
	end
	if targetFolder then
		local faces = targetFolder:GetChildren()
		if #faces > 0 then
			local randomDecal = faces[math.random(1, #faces)]
			if randomDecal:IsA("Decal") then
				return randomDecal.Texture
			end
		end
	end
	return "rbxassetid://0"
end

-- The total XP needed to reach a level, rounded up to a multiple of 25.
local function GetXPThreshold(targetLevel)
	if targetLevel <= 1 then
		return 0
	end
	local xpNeeded = math.floor((50 * (targetLevel ^ 1.2)) + (targetLevel * 25))
	return math.ceil(xpNeeded / 25) * 25
end

-- dataManager.CreateSessionStats() - create the PlayerStats folder of a player
-- @player: the player
-- @profile: the loaded profile
--
-- Other scripts and the client read the data from this folder. Writing a mirrored
-- value writes it back to the profile.
--
-- Return: nothing.
function module.CreateSessionStats(player, profile)
	local data = profile.Data

	local playerStats = Instance.new("Folder")
	playerStats.Name = "PlayerStats"

	local liturgyVal = Instance.new("IntValue")
	liturgyVal.Name = CURRENCY_NAME
	liturgyVal.Value = data.Liturgy
	liturgyVal.Parent = playerStats
	liturgyVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Liturgy = val
		end
	end)

	local spinsVal = Instance.new("IntValue")
	spinsVal.Name = "Spins"
	spinsVal.Value = data.Spins
	spinsVal.Parent = playerStats
	spinsVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Spins = val
		end
	end)

	local pityVal = Instance.new("IntValue")
	pityVal.Name = "Pity"
	pityVal.Value = data.Pity
	pityVal.Parent = playerStats
	pityVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Pity = val
		end
	end)

	local raceVal = Instance.new("StringValue")
	raceVal.Name = "Race"
	raceVal.Value = data.Race
	raceVal.Parent = playerStats
	raceVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Race = val
		end
	end)

	local armorFolder = Instance.new("Folder")
	armorFolder.Name = "ArmorBuffs"
	armorFolder.Parent = playerStats

	local function createArmorStat(name, default)
		local val = Instance.new("NumberValue")
		val.Name = name
		val.Value = default
		val.Parent = armorFolder
		return val
	end

	createArmorStat("HPBuff", 1)
	createArmorStat("DefenseBuff", 1)
	createArmorStat("DamageBuff", 1)

	local function createStat(name, defaultVal)
		local val = Instance.new("NumberValue")
		val.Name = name
		val.Value = defaultVal
		val.Parent = playerStats
		val.Changed:Connect(function(v)
			if Profiles[player] then
				Profiles[player].Data[name] = v
			end
		end)
		return val
	end

	createStat("HPBoost", data.HPBoost)
	createStat("ManaBoost", data.ManaBoost)
	createStat("SpeedBoost", data.SpeedBoost)
	createStat("DamageBoost", data.DamageBoost)
	createStat("DefenseBoost", data.DefenseBoost)
	createStat("RegenMultiplier", data.RegenMultiplier)
	createStat("LiturgyMultiplier", data.LiturgyMultiplier)
	createStat("JumpBoost", data.JumpBoost)
	createStat("DashDuration", data.DashDuration)
	createStat("SlideDuration", data.SlideDuration)

	-- The client UI and damageCalculator read the invested points.
	local statsFolder = Instance.new("Folder")
	statsFolder.Name = "Stats"
	statsFolder.Parent = playerStats

	if not data.Stats then
		data.Stats = { Vitality = 0, Stamina = 0, Strength = 0, Dexterity = 0, Magic = 0 }
	end
	for _, statName in ipairs({ "Vitality", "Stamina", "Strength", "Dexterity", "Magic" }) do
		local v = Instance.new("IntValue")
		v.Name = statName
		v.Value = data.Stats[statName] or 0
		v.Parent = statsFolder
		v.Changed:Connect(function(val)
			if Profiles[player] then
				Profiles[player].Data.Stats[statName] = val
			end
		end)
	end

	-- Display-only copies of the skill-point budget. The server owns the real values.
	local ownedVal = Instance.new("IntValue")
	ownedVal.Name = "SkillPointsOwned"
	ownedVal.Value = data.SkillPointsOwned or 0
	ownedVal.Parent = statsFolder

	local availVal = Instance.new("IntValue")
	availVal.Name = "SkillPointsAvailable"
	local assigned = 0
	for _, stn in ipairs({ "Vitality", "Stamina", "Strength", "Dexterity", "Magic" }) do
		assigned = assigned + ((data.Stats and data.Stats[stn]) or 0)
	end
	availVal.Value = (data.SkillPointsOwned or 0) - assigned
	availVal.Parent = statsFolder

	-- MaxMana includes the flat mana bonus from Magic.
	local magicManaBonus = StatScaling.GetManaBonus(data.Stats.Magic or 0)
	local calculatedMaxMana = (data.MaxMana * data.ManaBoost) + magicManaBonus
	local manaVal = Instance.new("NumberValue", playerStats)
	manaVal.Name = "Mana"
	manaVal.Value = calculatedMaxMana

	local maxManaVal = Instance.new("NumberValue", playerStats)
	maxManaVal.Name = "MaxMana"
	maxManaVal.Value = calculatedMaxMana

	local weaponDataFolder = Instance.new("Folder")
	weaponDataFolder.Name = "WeaponData"
	weaponDataFolder.Parent = playerStats

	local skillsFolder = Instance.new("Folder")
	skillsFolder.Name = "UnlockedSkills"
	skillsFolder.Parent = playerStats

	-- Spells are StringValues, not tools.
	if data.UnlockedSpells then
		for _, spellName in ipairs(data.UnlockedSpells) do
			local val = Instance.new("StringValue")
			val.Name = spellName
			val.Parent = skillsFolder
		end
	end

	-- The client reads the loadout from PlayerStats.EquippedSkills.<Family>, with a
	-- StringValue per slot (Z, X, C).
	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
	if not data.EquippedSkills then
		data.EquippedSkills = {}
	end

	-- An old profile with unlocked spells and no loadout gets one: each spell goes into
	-- its family slot, and the last one per slot wins.
	if next(data.EquippedSkills) == nil and data.UnlockedSpells and #data.UnlockedSpells > 0 then
		for _, spellName in ipairs(data.UnlockedSpells) do
			local fam, slotIdx = SkillConfig.FindSkillSlot(spellName)
			if fam and slotIdx then
				data.EquippedSkills[fam] = data.EquippedSkills[fam] or {}
				data.EquippedSkills[fam][SkillConfig.SlotKeys[slotIdx]] = spellName
			end
		end
	end

	local equippedFolder = Instance.new("Folder")
	equippedFolder.Name = "EquippedSkills"
	equippedFolder.Parent = playerStats
	for fam, slots in pairs(data.EquippedSkills) do
		local famFolder = Instance.new("Folder")
		famFolder.Name = fam
		famFolder.Parent = equippedFolder
		for _, slotKey in pairs(SkillConfig.SlotKeys) do
			local sv = Instance.new("StringValue")
			sv.Name = slotKey
			sv.Value = slots[slotKey] or ""
			sv.Parent = famFolder
		end
	end

	for _, weaponName in ipairs(WEAPON_TYPES) do
		local savedStats = data.WeaponProgression[weaponName]
		if not savedStats then
			savedStats = { XP = 0, Level = 1 }
		end
		local thisWeapon = Instance.new("Folder")
		thisWeapon.Name = weaponName
		thisWeapon.Parent = weaponDataFolder

		local xpVal = Instance.new("IntValue", thisWeapon)
		xpVal.Name = "CurrentXP"
		xpVal.Value = savedStats.XP

		local lvlVal = Instance.new("IntValue", thisWeapon)
		lvlVal.Name = "Level"
		lvlVal.Value = savedStats.Level

		local maxXPVal = Instance.new("IntValue", thisWeapon)
		maxXPVal.Name = "MaxXP"
		maxXPVal.Value = GetXPThreshold(savedStats.Level + 1)
	end

	playerStats.Parent = player
end

-- Regenerates 1 mana per second, or every 0.5 seconds with Excalibur, until the player
-- leaves.
local function startManaRegeneration(player)
	task.spawn(function()
		while player and player.Parent do
			local stats = player:FindFirstChild("PlayerStats")
			if stats then
				local mana = stats:FindFirstChild("Mana")
				local maxMana = stats:FindFirstChild("MaxMana")
				if mana and maxMana and mana.Value < maxMana.Value then
					mana.Value = math.min(mana.Value + 1, maxMana.Value)
				end
			end
			if player and player.StarterGear:FindFirstChild("Excalibur") then
				task.wait(0.5)
			else
				task.wait(1)
			end
		end
	end)
end

-- dataManager.PlayerAdded() - load the profile of a joining player
-- @player: the player
--
-- Migrates old data, sets defaults for a new player, and creates PlayerStats. Kicks
-- the player if the profile cannot load.
--
-- Return: nothing. Yields until the session starts.
function module.PlayerAdded(player)
	local profile = GameProfileStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		if not profile.Data.Attuned then
			profile.Data.Attuned = {}
		end

		if profile.Data.PlayerKills == nil then
			profile.Data.PlayerKills = 0
		end
		if profile.Data.PlayerDeaths == nil then
			profile.Data.PlayerDeaths = 0
		end

		if not profile.Data.UnlockedTitles then
			profile.Data.UnlockedTitles = {}
		end
		if profile.Data.CurrentTitle == nil then
			profile.Data.CurrentTitle = ""
		end

		-- Migrate the old quest format to the array format.
		local q = profile.Data.Quest
		if q then
			-- The old format had Active as a string or nil and Progress as a number.
			if type(q.Active) ~= "table" then
				local oldId = type(q.Active) == "string" and q.Active or nil
				local oldProgress = type(q.Progress) == "number" and q.Progress or 0
				q.Active = {}
				if oldId then
					table.insert(q.Active, { Id = oldId, Progress = oldProgress })
				end
				q.Progress = nil
			end
			-- Track the first active quest only when Tracked was never set (nil). false means the
			-- player untracked on purpose, so a rejoin must not track a quest again.
			if q.Tracked == nil and #q.Active > 0 then
				q.Tracked = q.Active[1].Id
			end
			if not q.Completed then
				q.Completed = {}
			end
			if not q.Cooldowns then
				q.Cooldowns = {}
			end
		end

		if not profile.Data.InventoryData then
			profile.Data.InventoryData = { Items = {}, Hotbar = {}, Equipment = {} }
		end

		-- Migrate the old Inventory list to InventoryData.
		if profile.Data.Inventory and #profile.Data.Inventory > 0 then
			if #profile.Data.InventoryData.Items == 0 then
				for _, toolName in ipairs(profile.Data.Inventory) do
					table.insert(profile.Data.InventoryData.Items, {
						Id = game:GetService("HttpService"):GenerateGUID(false),
						Name = toolName,
						Amount = 1,
					})
				end
			end
			profile.Data.Inventory = nil
		end

		-- A new player gets the default weapon in hotbar slot 1.
		local invData = profile.Data.InventoryData
		local isInventoryEmpty = #invData.Items == 0
		local isHotbarEmpty = true

		for i = 1, 9 do
			if invData.Hotbar[tostring(i)] or invData.Hotbar[i] then
				isHotbarEmpty = false
				break
			end
		end

		if isInventoryEmpty and isHotbarEmpty then
			local defaultItem = {
				Id = game:GetService("HttpService"):GenerateGUID(false),
				Name = DEFAULT_WEAPON,
				Amount = 1,
			}
			invData.Hotbar["1"] = defaultItem
		end

		if profile.Data.CurrentWeapon == nil or profile.Data.CurrentWeapon == "" then
			profile.Data.CurrentWeapon = DEFAULT_WEAPON
		end

		if profile.Data.EyeColor == nil then
			local rand = REALISTIC_EYE_COLORS[math.random(1, #REALISTIC_EYE_COLORS)]
			profile.Data.EyeColor = { R = rand.R, G = rand.G, B = rand.B }
		end

		if profile.Data.Face == nil or profile.Data.Face == "" then
			local race = profile.Data.Race or "Human"
			profile.Data.Face = GetRandomFaceForRace(race)
		end

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick("Profile session released.")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile
			module.CreateSessionStats(player, profile)
			startManaRegeneration(player)
		else
			profile:EndSession()
		end
	else
		player:Kick("Data could not be loaded. Please rejoin.")
	end
end

-- The Liturgy a player drops for leaving during combat.
local LOG_PENALTY_AMOUNT = 500

-- dataManager.PlayerRemoving() - save and release the profile of a leaving player
-- @player: the player
--
-- A player who leaves during combat drops LOG_PENALTY_AMOUNT Liturgy.
--
-- Return: nothing.
function module.PlayerRemoving(player)
	local combatExpiry = player:GetAttribute("CombatLogExpiry")

	if combatExpiry and os.clock() < combatExpiry then
		local success = module.RemoveLiturgy(player, LOG_PENALTY_AMOUNT)

		if success then
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				module.CreateDrop(char.HumanoidRootPart.Position, LOG_PENALTY_AMOUNT)
			end
		end
	end

	-- Remove the leaver as an attacker from everyone they tagged, and drop their own tag,
	-- so no victim stays in combat. combatTagManager expects this call here.
	local okTag, TagManager =
		pcall(require, game:GetService("ServerScriptService").modules.combatTagManager)
	if okTag and TagManager then
		TagManager.HandlePlayerLeft(player)
	end

	local profile = Profiles[player]
	if profile then
		profile:EndSession()
	end
end

-- dataManager.GetProfile() - get the loaded profile of a player
-- @player: the player
--
-- Return: the profile, or nil.
function module.GetProfile(player)
	return Profiles[player]
end

local VALID_STATS =
	{ Vitality = true, Stamina = true, Strength = true, Dexterity = true, Magic = true }

-- dataManager.GetStat() - get a player's invested points in a stat
-- @player: the player
-- @statName: Vitality, Stamina, Strength, Dexterity, or Magic
--
-- Return: the points, or 0.
function module.GetStat(player, statName)
	local p = Profiles[player]
	if not p or not p.Data.Stats then
		return 0
	end
	return p.Data.Stats[statName] or 0
end

-- The sum of all assigned stat points, which is the number of skill points spent.
local function sumStats(p)
	local total = 0
	if p.Data.Stats then
		for stat in pairs(VALID_STATS) do
			total = total + (p.Data.Stats[stat] or 0)
		end
	end
	return total
end

-- dataManager.GetSkillPointsOwned() - get the skill points a player bought
-- @player: the player
--
-- Return: the number of skill points.
function module.GetSkillPointsOwned(player)
	local p = Profiles[player]
	return p and (p.Data.SkillPointsOwned or 0) or 0
end

-- dataManager.GetAvailableSkillPoints() - get the skill points a player can assign
-- @player: the player
--
-- Return: the owned points minus the assigned points.
function module.GetAvailableSkillPoints(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	return (p.Data.SkillPointsOwned or 0) - sumStats(p)
end

-- Copies a stat and the skill-point counters to the PlayerStats.Stats folder.
local function pushStat(player, statName)
	local p = Profiles[player]
	if not p then
		return
	end
	local stats = player:FindFirstChild("PlayerStats")
	if not stats then
		return
	end
	local folder = stats:FindFirstChild("Stats")
	if not folder then
		return
	end
	if statName then
		local obj = folder:FindFirstChild(statName)
		if obj then
			obj.Value = p.Data.Stats[statName] or 0
		end
	end
	local owned = folder:FindFirstChild("SkillPointsOwned")
	if owned then
		owned.Value = p.Data.SkillPointsOwned or 0
	end
	local avail = folder:FindFirstChild("SkillPointsAvailable")
	if avail then
		avail.Value = (p.Data.SkillPointsOwned or 0) - sumStats(p)
	end
end

-- dataManager.BuySkillPoint() - buy one skill point with Liturgy
-- @player: the player
--
-- The cost rises with each point, up to StatScaling.MAX_SKILL_POINTS.
--
-- Return: true and the cost on success. false and a reason ("NoProfile",
-- "MaxSkillPoints", or "NotEnoughLiturgy") on failure.
function module.BuySkillPoint(player)
	local p = Profiles[player]
	if not p then
		return false, "NoProfile"
	end

	local owned = p.Data.SkillPointsOwned or 0
	if owned >= StatScaling.MAX_SKILL_POINTS then
		return false, "MaxSkillPoints"
	end

	local cost = StatScaling.GetNextSkillPointCost(owned)
	if p.Data.Liturgy < cost then
		return false, "NotEnoughLiturgy"
	end

	p.Data.Liturgy -= cost
	p.Data.SkillPointsOwned = owned + 1

	local s2 = player:FindFirstChild("PlayerStats")
	if s2 and s2:FindFirstChild(CURRENCY_NAME) then
		s2[CURRENCY_NAME].Value = p.Data.Liturgy
	end
	pushStat(player, nil)
	return true, cost
end

-- dataManager.AssignStatPoint() - assign one available skill point to a stat
-- @player: the player
-- @statName: Vitality, Stamina, Strength, Dexterity, or Magic
--
-- Assigning is free. A stat is capped at StatScaling.MAX_STAT.
--
-- Return: true on success. false and a reason ("NoProfile", "BadStat", "MaxStat", or
-- "NoSkillPoints") on failure.
function module.AssignStatPoint(player, statName)
	local p = Profiles[player]
	if not p then
		return false, "NoProfile"
	end
	if not VALID_STATS[statName] then
		return false, "BadStat"
	end
	if not p.Data.Stats then
		p.Data.Stats = { Vitality = 0, Stamina = 0, Strength = 0, Dexterity = 0, Magic = 0 }
	end

	local current = p.Data.Stats[statName] or 0
	if current >= StatScaling.MAX_STAT then
		return false, "MaxStat"
	end

	local available = (p.Data.SkillPointsOwned or 0) - sumStats(p)
	if available <= 0 then
		return false, "NoSkillPoints"
	end

	p.Data.Stats[statName] = current + 1
	pushStat(player, statName)
	return true
end

-- dataManager.RespecStats() - unassign every stat point
-- @player: the player
--
-- The player keeps the skill points they bought and can assign them again. Costs no
-- Liturgy.
--
-- Return: true on success. false and a reason ("NoProfile", "NoStats", or
-- "NothingToRespec") on failure.
function module.RespecStats(player)
	local p = Profiles[player]
	if not p then
		return false, "NoProfile"
	end
	if not p.Data.Stats then
		return false, "NoStats"
	end
	if sumStats(p) <= 0 then
		return false, "NothingToRespec"
	end

	for stat in pairs(VALID_STATS) do
		p.Data.Stats[stat] = 0
	end

	for stat in pairs(VALID_STATS) do
		pushStat(player, stat)
	end
	pushStat(player, nil)
	return true
end

-- dataManager.GetNextSkillPointCost() - get the Liturgy cost of the next skill point
-- @player: the player
--
-- Return: the cost.
function module.GetNextSkillPointCost(player)
	return StatScaling.GetNextSkillPointCost(module.GetSkillPointsOwned(player))
end

-- dataManager.GetEyeColor() - get a player's eye color
-- @player: the player
--
-- Return: the color, or black when there is no profile.
function module.GetEyeColor(player)
	local p = Profiles[player]
	if p and p.Data.EyeColor then
		local c = p.Data.EyeColor
		return Color3.fromRGB(c.R, c.G, c.B)
	end
	return Color3.new(0, 0, 0)
end

-- dataManager.GetFace() - get a player's face texture
-- @player: the player
--
-- Return: the texture ID, or "rbxassetid://0".
function module.GetFace(player)
	local p = Profiles[player]
	return p and p.Data.Face or "rbxassetid://0"
end

-- dataManager.SetFace() - set a player's face texture
-- @player: the player
-- @textureId: the texture ID
--
-- Return: nothing.
function module.SetFace(player, textureId)
	local p = Profiles[player]
	if p then
		p.Data.Face = textureId
	end
end

-- dataManager.GetAppearance() - get a player's hair, gender, and armor color
-- @player: the player
--
-- Return: { Hair, Gender, ArmorColor }, or nil when there is no profile.
function module.GetAppearance(player)
	local p = Profiles[player]
	if not p then
		return nil
	end

	if not p.Data.Hair then
		p.Data.Hair = { 0, 0, 0 }
	end
	if not p.Data.Gender then
		p.Data.Gender = "Male"
	end

	local armorCol = nil
	if p.Data.ArmorColor then
		local c = p.Data.ArmorColor
		armorCol = Color3.fromRGB(c.R, c.G, c.B)
	end

	return {
		Hair = p.Data.Hair,
		Gender = p.Data.Gender,
		ArmorColor = armorCol,
	}
end

-- dataManager.SetHair() - set one hair slot
-- @player: the player
-- @slot: the hair slot, 1 to 3
-- @id: the hair asset ID
--
-- Return: nothing.
function module.SetHair(player, slot, id)
	local p = Profiles[player]
	if p then
		if not p.Data.Hair then
			p.Data.Hair = { 0, 0, 0 }
		end
		p.Data.Hair[slot] = id
	end
end

-- dataManager.ResetHair() - clear every hair slot
-- @player: the player
--
-- Return: nothing.
function module.ResetHair(player)
	local p = Profiles[player]
	if p then
		p.Data.Hair = { 0, 0, 0 }
	end
end

-- dataManager.SetGender() - set a player's gender
-- @player: the player
-- @gender: the gender
--
-- Return: nothing.
function module.SetGender(player, gender)
	local p = Profiles[player]
	if p then
		p.Data.Gender = gender
	end
end

-- dataManager.SetArmorColor() - set a player's armor color
-- @player: the player
-- @color: the Color3
--
-- Return: nothing.
function module.SetArmorColor(player, color)
	local p = Profiles[player]
	if p then
		p.Data.ArmorColor = {
			R = math.floor(color.R * 255),
			G = math.floor(color.G * 255),
			B = math.floor(color.B * 255),
		}
	end
end

-- dataManager.GetLiturgy() - get a player's Liturgy
-- @player: the player
--
-- Return: the amount.
function module.GetLiturgy(player)
	local p = Profiles[player]
	return p and p.Data.Liturgy or 0
end

-- dataManager.AddLiturgy() - give a player Liturgy
-- @player: the player
-- @amount: the amount before the player's LiturgyMultiplier
--
-- Return: nothing.
function module.AddLiturgy(player, amount)
	local p = Profiles[player]
	if p then
		local mult = p.Data.LiturgyMultiplier or 1
		p.Data.Liturgy += math.floor(amount * mult)

		local s = player:FindFirstChild("PlayerStats")
		if s and s:FindFirstChild(CURRENCY_NAME) then
			s[CURRENCY_NAME].Value = p.Data.Liturgy
		end
	end
end

-- dataManager.RemoveLiturgy() - take Liturgy from a player
-- @player: the player
-- @amount: the amount
--
-- Return: true if the player had enough, false otherwise.
function module.RemoveLiturgy(player, amount)
	local p = Profiles[player]
	if p and p.Data.Liturgy >= amount then
		p.Data.Liturgy -= amount
		local s = player:FindFirstChild("PlayerStats")
		if s and s:FindFirstChild(CURRENCY_NAME) then
			s[CURRENCY_NAME].Value = p.Data.Liturgy
		end
		return true
	end
	return false
end

-- dataManager.GetCurrentArmor() - get the armor that sets a player's stats
-- @player: the player
--
-- Return: the armor name, "Rags" by default.
function module.GetCurrentArmor(player)
	local profile = Profiles[player]
	return profile and profile.Data.CurrentArmor or "Rags"
end

-- dataManager.SetCurrentArmor() - set the armor that sets a player's stats
-- @player: the player
-- @armorName: the armor name
--
-- Return: nothing.
function module.SetCurrentArmor(player, armorName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentArmor = armorName
	end
end

-- dataManager.OwnsArmor() - check whether a player owns an armor
-- @player: the player
-- @armorName: the armor name
--
-- Return: true if the player owns it.
function module.OwnsArmor(player, armorName)
	local profile = Profiles[player]
	if not profile then
		return false
	end
	return table.find(profile.Data.OwnedArmors, armorName) ~= nil
end

-- dataManager.AddArmor() - give a player an armor
-- @player: the player
-- @armorName: the armor name
--
-- Return: nothing.
function module.AddArmor(player, armorName)
	local profile = Profiles[player]
	if profile then
		if not table.find(profile.Data.OwnedArmors, armorName) then
			table.insert(profile.Data.OwnedArmors, armorName)
		end
	end
end

-- dataManager.GetCurrentVanity() - get the armor that a player shows
-- @player: the player
--
-- Return: the transmog armor, or the current armor when there is no transmog.
function module.GetCurrentVanity(player)
	local profile = Profiles[player]
	if not profile then
		return "Rags"
	end
	return profile.Data.CurrentVanity or profile.Data.CurrentArmor or "Rags"
end

-- dataManager.SetCurrentVanity() - set the transmog armor
-- @player: the player
-- @armorName: the armor to show, or nil to show the current armor
--
-- Return: nothing.
function module.SetCurrentVanity(player, armorName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentVanity = armorName
	end
end

-- dataManager.GetPity() - get a player's race spin pity counter
-- @player: the player
--
-- Return: the counter.
function module.GetPity(player)
	local p = Profiles[player]
	return p and p.Data.Pity or 0
end

-- dataManager.UpdatePity() - add to or reset the pity counter
-- @player: the player
-- @amount: the amount to add
-- @reset: true to set the counter to 0 instead
--
-- Return: nothing.
function module.UpdatePity(player, amount, reset)
	local p = Profiles[player]
	if p then
		if reset then
			p.Data.Pity = 0
		else
			p.Data.Pity += amount
		end
		local s = player:FindFirstChild("PlayerStats")
		if s and s:FindFirstChild("Pity") then
			s.Pity.Value = p.Data.Pity
		end
	end
end

-- dataManager.GetSpins() - get a player's race spins
-- @player: the player
--
-- Return: the number of spins.
function module.GetSpins(player)
	local p = Profiles[player]
	return p and p.Data.Spins or 0
end

-- dataManager.UpdateSpins() - add race spins
-- @player: the player
-- @amount: the number of spins to add, negative to use them
--
-- Return: nothing.
function module.UpdateSpins(player, amount)
	local p = Profiles[player]
	if p then
		p.Data.Spins += amount
		local s = player:FindFirstChild("PlayerStats")
		if s and s:FindFirstChild("Spins") then
			s.Spins.Value = p.Data.Spins
		end
	end
end

-- dataManager.SetRaceStats() - set a player's race and its stat boosts
-- @player: the player
-- @raceName: the race name
-- @statsTable: the Stats table of the race in RaceConfig
--
-- Return: nothing.
function module.SetRaceStats(player, raceName, statsTable)
	local p = Profiles[player]
	if not p then
		return
	end

	p.Data.Race = raceName
	p.Data.HPBoost = statsTable.HPBoost or 0
	p.Data.DefenseBoost = statsTable.DefenseBoost or 1
	p.Data.LiturgyMultiplier = statsTable.LiturgyMultiplier or 1
	p.Data.RegenMultiplier = statsTable.RegenMultiplier or 1
	p.Data.JumpBoost = statsTable.JumpBoost or 1
	p.Data.DashDuration = statsTable.DashDuration or 0.2
	p.Data.SlideDuration = statsTable.SlideDuration or 2.0

	local s = player:FindFirstChild("PlayerStats")
	if s and s:FindFirstChild("Race") then
		s.Race.Value = raceName
	end
end

-- dataManager.YieldUntilLoaded() - wait for a player's profile to load
-- @player: the player
--
-- Return: nothing. Yields for at most 15 seconds.
function module.YieldUntilLoaded(player)
	if Profiles[player] then
		return
	end
	local t = tick()
	repeat
		task.wait(0.1)
	until Profiles[player] or tick() - t > 15
end

-- dataManager.EquipLoadout() - give a player the tools from their saved inventory
-- @player: the player
-- @character: not used
--
-- Clears the Backpack and StarterGear, then gives each item from the grid, hotbar,
-- and equipment once.
--
-- Return: nothing.
function module.EquipLoadout(player, character)
	local profile = Profiles[player]
	if not profile then
		return
	end

	local data = profile.Data
	local invData = data.InventoryData or { Items = {}, Hotbar = {}, Equipment = {} }
	local currentWeapon = data.CurrentWeapon

	local weaponsFolder = ServerStorage:FindFirstChild("Weapons")
	local equipmentFolder = ServerStorage:FindFirstChild("Equipment")

	player.Backpack:ClearAllChildren()
	player.StarterGear:ClearAllChildren()

	local givenItems = {}

	local function giveItem(itemName)
		if itemName and not givenItems[itemName] then
			-- Weapons first, then equipment.
			local toolTemplate = nil
			if weaponsFolder then
				toolTemplate = weaponsFolder:FindFirstChild(itemName)
			end
			if not toolTemplate and equipmentFolder then
				toolTemplate = equipmentFolder:FindFirstChild(itemName)
			end

			if toolTemplate then
				toolTemplate:Clone().Parent = player.Backpack
				toolTemplate:Clone().Parent = player.StarterGear
				givenItems[itemName] = true
			end
		end
	end

	for _, itemData in ipairs(invData.Items or {}) do
		giveItem(itemData.Name)
	end

	for _, itemData in pairs(invData.Hotbar or {}) do
		if itemData and not itemData.IsSpell then
			giveItem(itemData.Name)
		end
	end

	for _, itemData in pairs(invData.Equipment or {}) do
		if itemData then
			giveItem(itemData.Name)
		end
	end
end

-- dataManager.HandlePlayerDeath() - drop part of a dead player's Liturgy
-- @player: the player who died
-- @position: where to drop it
--
-- Drops at most DEATH_DROP_AMOUNT.
--
-- Return: nothing.
function module.HandlePlayerDeath(player, position)
	local current = module.GetLiturgy(player)
	local dropAmount = math.min(current, DEATH_DROP_AMOUNT)

	if dropAmount > 0 then
		if module.RemoveLiturgy(player, dropAmount) then
			module.CreateDrop(position, dropAmount)
		end
	end
end

-- dataManager.CreateDrop() - create a Liturgy pickup in the world
-- @position: where to create it
-- @amount: the Liturgy in the pickup
--
-- The pickup disappears after DROP_LIFETIME seconds.
--
-- Return: nothing.
function module.CreateDrop(position, amount)
	if amount <= 0 then
		return
	end
	if typeof(position) ~= "Vector3" then
		position = Vector3.new(0, 10, 0)
	end

	local dropPart = liturgyTemplate:Clone()
	dropPart.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
	dropPart:SetAttribute("Amount", amount)
	dropPart.Parent = workspace

	local promptParent = dropPart
	if dropPart:IsA("Model") then
		promptParent = dropPart.PrimaryPart or dropPart:FindFirstChildWhichIsA("BasePart", true)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = ""
	prompt.ActionText = "Collect"
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent = promptParent or dropPart

	prompt.Triggered:Connect(function(picker)
		if picker.Character and picker.Character.Humanoid.Health > 0 then
			local storedAmount = dropPart:GetAttribute("Amount") or 0
			module.AddLiturgy(picker, storedAmount)
			dropPart:Destroy()
		end
	end)

	Debris:AddItem(dropPart, DROP_LIFETIME)
end

-- dataManager.GetWeaponLevel() - get a player's mastery level in a weapon family
-- @player: the player
-- @family: the weapon family
--
-- Return: the level, or 0 when the family does not exist.
function module.GetWeaponLevel(player, family)
	local profile = Profiles[player]
	if not profile then
		return 0
	end
	local weaponData = profile.Data.WeaponProgression[family]
	return weaponData and weaponData.Level or 0
end

-- Gives XP to one family and returns its new level. It does not touch quests: the
-- caller reconciles once, after every family has its XP.
local function grantFamilyXP(player, family, amount)
	local profile = Profiles[player]
	if not profile then
		return nil
	end

	local weaponData = profile.Data.WeaponProgression[family]
	if not weaponData then
		warn(`[dataManager] No WeaponProgression entry for family {family}.`)
		return nil
	end

	weaponData.XP += (amount * 10)

	while weaponData.Level < MAX_LEVEL do
		local xpNeeded = GetXPThreshold(weaponData.Level + 1)
		if weaponData.XP >= xpNeeded then
			weaponData.XP -= xpNeeded
			weaponData.Level += 1
		else
			break
		end
	end

	-- At the max level, keep XP at 0 so the bar does not fill past 25.
	if weaponData.Level >= MAX_LEVEL then
		weaponData.XP = 0
	end

	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local wFolder = stats:FindFirstChild("WeaponData")
			and stats.WeaponData:FindFirstChild(family)
		if wFolder then
			wFolder.CurrentXP.Value = weaponData.XP
			wFolder.Level.Value = weaponData.Level
			if weaponData.Level < MAX_LEVEL then
				wFolder.MaxXP.Value = GetXPThreshold(weaponData.Level + 1)
			else
				wFolder.MaxXP.Value = 0
			end
		end
	end

	return weaponData.Level
end

-- dataManager.AddWeaponXP() - give weapon XP to a player
-- @player: the player
-- @weaponName: a family ("Fists"), a branch weapon ("Caestus"), or a hybrid ("Guandao")
-- @amount: the XP
--
-- A branch weapon gives XP to its family. A hybrid gives half the XP to each parent
-- family. Quests are then reconciled from the profile, not from the level-up, so a
-- player who passes several milestones at once still gets the right checkpoint.
--
-- Return: nothing.
function module.AddWeaponXP(player, weaponName, amount)
	local profile = Profiles[player]
	if not profile then
		return
	end
	if not weaponName then
		return
	end

	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)

	local touched = {}

	if SkillConfig.IsHybrid(weaponName) then
		local parents = SkillConfig.HybridParents[weaponName]
		local split = amount / 2
		for _, parentFamily in ipairs(parents) do
			if grantFamilyXP(player, parentFamily, split) then
				table.insert(touched, parentFamily)
			end
		end
	else
		local family = SkillConfig.GetXPFamily(weaponName)
		if not family then
			warn(`[dataManager] Unknown weapon {weaponName} for XP.`)
			return
		end
		if grantFamilyXP(player, family, amount) then
			table.insert(touched, family)
		end
	end

	if #touched == 0 then
		return
	end

	task.spawn(function()
		local QuestManager = _G.QuestManager
		local TitleManager = _G.TitleManager

		for _, family in ipairs(touched) do
			if QuestManager then
				QuestManager.ReconcileClassQuests(player, family)
			end
			if module.GetWeaponLevel(player, family) >= MAX_LEVEL and TitleManager then
				TitleManager.CheckWeaponMastery(player, family)
			end
		end

		-- A parent family level-up can unlock a hybrid skill.
		if QuestManager then
			QuestManager.ReconcileHybrids(player)
		end
	end)
end

-- dataManager.SetCurrentWeapon() - save the weapon a player holds
-- @player: the player
-- @weaponName: the weapon name, or "" for none
--
-- Return: nothing.
function module.SetCurrentWeapon(player, weaponName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentWeapon = weaponName
	end
end

-- dataManager.GetCurrentWeapon() - get the saved weapon of a player
-- @player: the player
--
-- Return: the weapon name, DEFAULT_WEAPON when there is no profile.
function module.GetCurrentWeapon(player)
	local profile = Profiles[player]
	return profile and profile.Data.CurrentWeapon or DEFAULT_WEAPON
end

-- dataManager.GetSpellbookSnapshot() - get the spellbook view of a player
-- @player: the player
--
-- Finds the family of the player's weapon, then lists the owned and equipped skill of
-- each slot (Z, X, C). The client only draws this.
--
-- Return: { ok, family, slots }, where slots[slotKey] = { owned, equipped }. On failure,
-- { ok = false, reason = "NoProfile" }.
function module.GetSpellbookSnapshot(player)
	local profile = Profiles[player]
	if not profile then
		return { ok = false, reason = "NoProfile" }
	end

	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)

	-- Find the weapon from what the player has, not from the saved field: the held Tool
	-- first, then a weapon Tool in the Backpack. A Tool is a weapon if its name is a key
	-- in WeaponFamily, which skips spells and consumables.
	local function resolveWeaponName()
		local char = player.Character
		if char then
			local held = char:FindFirstChildOfClass("Tool")
			if held and SkillConfig.WeaponFamily[held.Name] then
				return held.Name
			end
		end
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, c in ipairs(backpack:GetChildren()) do
				if c:IsA("Tool") and SkillConfig.WeaponFamily[c.Name] then
					return c.Name
				end
			end
		end
		-- Last, the saved field, if it is a real weapon.
		local stored = profile.Data.CurrentWeapon
		if stored and SkillConfig.WeaponFamily[stored] then
			return stored
		end
		return nil
	end

	local weaponName = resolveWeaponName()
	if not weaponName then
		return { ok = true, family = nil, slots = {} }
	end
	local family = SkillConfig.WeaponFamily[weaponName]
	if not family then
		return { ok = true, family = nil, slots = {} }
	end

	local unlocked = profile.Data.UnlockedSpells or {}
	local ownedSet = {}
	for _, name in ipairs(unlocked) do
		ownedSet[name] = true
	end

	local equippedFam = (profile.Data.EquippedSkills or {})[family] or {}

	local slots = {}
	for slotIdx = 1, 3 do
		local slotKey = SkillConfig.SlotKeys[slotIdx]
		local owned, seen = {}, {}
		for wName, fam in pairs(SkillConfig.WeaponFamily) do
			if fam == family then
				local list = SkillConfig.WeaponSkills[wName]
				local skillName = list and list[slotIdx]
				if skillName and not seen[skillName] and ownedSet[skillName] then
					seen[skillName] = true
					table.insert(owned, skillName)
				end
			end
		end
		table.sort(owned)
		local eq = equippedFam[slotKey]
		if eq == "" then
			eq = nil
		end
		slots[slotKey] = { owned = owned, equipped = eq }
	end

	return { ok = true, family = family, slots = slots }
end

-- dataManager.GetInventoryData() - get a player's saved inventory
-- @player: the player
--
-- Return: the InventoryData table, or nil.
function module.GetInventoryData(player)
	local profile = Profiles[player]
	return profile and profile.Data.InventoryData or nil
end

-- dataManager.SaveInventoryData() - replace a player's saved inventory
-- @player: the player
-- @newInventoryData: the new { Items, Hotbar, Equipment } table
--
-- Return: nothing.
function module.SaveInventoryData(player, newInventoryData)
	local profile = Profiles[player]
	if profile then
		profile.Data.InventoryData = newInventoryData
	end
end

-- dataManager.HasItem() - check whether a player owns an item
-- @player: the player
-- @itemName: the item name
--
-- Return: true if the item is in the grid, hotbar, or equipment.
function module.HasItem(player, itemName)
	local profile = Profiles[player]
	if not profile then
		return false
	end

	local invData = profile.Data.InventoryData
	if not invData then
		return false
	end

	for _, item in ipairs(invData.Items or {}) do
		if item.Name == itemName then
			return true
		end
	end

	for _, item in pairs(invData.Hotbar or {}) do
		if item and item.Name == itemName then
			return true
		end
	end

	for _, item in pairs(invData.Equipment or {}) do
		if item and item.Name == itemName then
			return true
		end
	end

	return false
end

-- dataManager.UnlockSpell() - give a player a skill
-- @player: the player
-- @spellName: the skill name
--
-- Also equips the skill into its family slot. Does nothing if the player has it.
--
-- Return: nothing.
function module.UnlockSpell(player, spellName)
	local profile = Profiles[player]
	if profile then
		if not profile.Data.UnlockedSpells then
			profile.Data.UnlockedSpells = {}
		end

		local spells = profile.Data.UnlockedSpells
		if not table.find(spells, spellName) then
			table.insert(spells, spellName)

			local stats = player:FindFirstChild("PlayerStats")
			if stats then
				local skillsFolder = stats:FindFirstChild("UnlockedSkills")
				if skillsFolder and not skillsFolder:FindFirstChild(spellName) then
					local val = Instance.new("StringValue")
					val.Name = spellName
					val.Parent = skillsFolder
				end
			end
			-- Equip the new skill into its family slot. The other two slots do not change.
			local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
			local fam, slotIdx = SkillConfig.FindSkillSlot(spellName)
			if fam and slotIdx then
				local slotKey = SkillConfig.SlotKeys[slotIdx]
				if not profile.Data.EquippedSkills then
					profile.Data.EquippedSkills = {}
				end
				profile.Data.EquippedSkills[fam] = profile.Data.EquippedSkills[fam] or {}
				profile.Data.EquippedSkills[fam][slotKey] = spellName

				-- Copy it to the replicated folder so the client updates at once.
				if stats then
					local equippedFolder = stats:FindFirstChild("EquippedSkills")
					if equippedFolder then
						local famFolder = equippedFolder:FindFirstChild(fam)
						if not famFolder then
							famFolder = Instance.new("Folder")
							famFolder.Name = fam
							famFolder.Parent = equippedFolder
							for _, sk in pairs(SkillConfig.SlotKeys) do
								local sv = Instance.new("StringValue")
								sv.Name = sk
								sv.Parent = famFolder
							end
						end
						local slotVal = famFolder:FindFirstChild(slotKey)
						if slotVal then
							slotVal.Value = spellName
						end
					end
				end
			end

			local tm = _G.TitleManager
			if tm then
				tm.CheckSkillUnlock(player, spellName)
			end
		end
	end
end

-- dataManager.HasSpell() - check whether a player has a skill
-- @player: the player
-- @spellName: the skill name
--
-- Return: true if the player has it.
function module.HasSpell(player, spellName)
	local profile = Profiles[player]
	if not profile then
		return false
	end
	if not profile.Data.UnlockedSpells then
		return false
	end
	return table.find(profile.Data.UnlockedSpells, spellName) ~= nil
end

-- dataManager.EquipSkill() - equip an owned skill into a slot of its family
-- @player: the player
-- @family: the weapon family
-- @slotKey: "Z", "X", or "C"
-- @skillName: the skill name
--
-- The spire spellbook UI calls this. The skill must belong to the family and slot.
--
-- Return: true on success, false otherwise.
function module.EquipSkill(player, family, slotKey, skillName)
	local profile = Profiles[player]
	if not profile then
		return false
	end

	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)

	local fam, slotIdx = SkillConfig.FindSkillSlot(skillName)
	if fam ~= family then
		return false
	end
	if SkillConfig.SlotKeys[slotIdx] ~= slotKey then
		return false
	end

	if not module.HasSpell(player, skillName) then
		return false
	end

	profile.Data.EquippedSkills = profile.Data.EquippedSkills or {}
	profile.Data.EquippedSkills[family] = profile.Data.EquippedSkills[family] or {}
	profile.Data.EquippedSkills[family][slotKey] = skillName

	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local equippedFolder = stats:FindFirstChild("EquippedSkills")
		if equippedFolder then
			local famFolder = equippedFolder:FindFirstChild(family)
			if not famFolder then
				famFolder = Instance.new("Folder")
				famFolder.Name = family
				famFolder.Parent = equippedFolder
				for _, sk in pairs(SkillConfig.SlotKeys) do
					local sv = Instance.new("StringValue")
					sv.Name = sk
					sv.Parent = famFolder
				end
			end
			local slotVal = famFolder:FindFirstChild(slotKey)
			if slotVal then
				slotVal.Value = skillName
			end
		end
	end
	return true
end

-- dataManager.GetEquippedSkill() - get the equipped skill of a slot
-- @player: the player
-- @family: the weapon family
-- @slotKey: "Z", "X", or "C"
--
-- Return: the skill name, or nil.
function module.GetEquippedSkill(player, family, slotKey)
	local profile = Profiles[player]
	if not profile or not profile.Data.EquippedSkills then
		return nil
	end
	local famTbl = profile.Data.EquippedSkills[family]
	if not famTbl then
		return nil
	end
	local v = famTbl[slotKey]
	if v == "" then
		return nil
	end
	return v
end

-- dataManager.SetTutorialComplete() - set whether a player finished the tutorial
-- @player: the player
-- @status: true by default
--
-- Return: nothing.
function module.SetTutorialComplete(player, status)
	local profile = Profiles[player]
	if profile then
		if status == nil then
			status = true
		end
		profile.Data.TutorialComplete = status
	end
end

-- dataManager.GetTutorialComplete() - check whether a player finished the tutorial
-- @player: the player
--
-- Return: true if the tutorial is complete.
function module.GetTutorialComplete(player)
	local profile = Profiles[player]
	return profile and profile.Data.TutorialComplete or false
end

-- dataManager.ConsumeMana() - spend a player's mana
-- @player: the player
-- @amount: the mana to spend
--
-- Return: true if the player had enough, false otherwise.
function module.ConsumeMana(player, amount)
	local stats = player:FindFirstChild("PlayerStats")
	if not stats then
		return false
	end
	local mana = stats:FindFirstChild("Mana")
	if mana and mana.Value >= amount then
		mana.Value -= amount
		return true
	end
	return false
end

-- dataManager.ClearInventory() - empty a player's saved inventory
-- @player: the player
--
-- Return: nothing.
function module.ClearInventory(player)
	local profile = Profiles[player]
	if profile then
		profile.Data.InventoryData = { Items = {}, Hotbar = {}, Equipment = {} }
	end
end

-- dataManager.GetQuestData() - get a player's quest data
-- @player: the player
--
-- Return: the Quest table, or nil when there is no profile.
function module.GetQuestData(player)
	local p = Profiles[player]
	if not p then
		return nil
	end
	if not p.Data.Quest then
		p.Data.Quest = { Active = {}, Tracked = nil, Completed = {}, Cooldowns = {} }
	end
	if not p.Data.Quest.Active then
		p.Data.Quest.Active = {}
	end
	return p.Data.Quest
end

-- dataManager.GetActiveQuestEntry() - get the entry of an active quest
-- @player: the player
-- @questId: the quest ID
--
-- Return: { Id, Progress }, or nil.
function module.GetActiveQuestEntry(player, questId)
	local questData = module.GetQuestData(player)
	if not questData then
		return nil
	end
	for _, entry in ipairs(questData.Active) do
		if entry.Id == questId then
			return entry
		end
	end
	return nil
end

-- dataManager.IsQuestActive() - check whether a quest is active
-- @player: the player
-- @questId: the quest ID
--
-- Return: true if it is active.
function module.IsQuestActive(player, questId)
	return module.GetActiveQuestEntry(player, questId) ~= nil
end

-- dataManager.SetActiveQuest() - add a quest to the active list
-- @player: the player
-- @questId: the quest ID
--
-- Return: nothing.
function module.SetActiveQuest(player, questId)
	local questData = module.GetQuestData(player)
	if not questData then
		return
	end
	if module.IsQuestActive(player, questId) then
		return
	end
	table.insert(questData.Active, { Id = questId, Progress = 0 })
	-- Track it only if Tracked was never set (nil). false means the player untracked on
	-- purpose.
	if questData.Tracked == nil then
		questData.Tracked = questId
	end
end

-- dataManager.UpdateQuestProgress() - add progress to an active quest
-- @player: the player
-- @questId: the quest ID
-- @amount: the progress to add
--
-- Return: the new progress, or 0 when the quest is not active.
function module.UpdateQuestProgress(player, questId, amount)
	local entry = module.GetActiveQuestEntry(player, questId)
	if not entry then
		return 0
	end
	entry.Progress = entry.Progress + amount
	return entry.Progress
end

-- dataManager.SetTrackedQuest() - set the tracked quest
-- @player: the player
-- @questId: the quest ID, or nil to untrack
--
-- Tracked has three states: a quest ID, false (the player untracked on purpose, so
-- auto-tracking must not pick one), and nil (never set, so auto-tracking may pick one).
-- Untracking stores false, so a later grant or rejoin does not track a quest again.
--
-- Return: nothing.
function module.SetTrackedQuest(player, questId)
	local questData = module.GetQuestData(player)
	if not questData then
		return
	end
	if questId == nil then
		questData.Tracked = false
	else
		questData.Tracked = questId
	end
end

-- dataManager.GetTrackedQuest() - get the tracked quest
-- @player: the player
--
-- Return: the quest ID, or nil for both untracked (false) and never set (nil).
function module.GetTrackedQuest(player)
	local questData = module.GetQuestData(player)
	if not questData then
		return nil
	end
	local tracked = questData.Tracked
	if not tracked then
		return nil
	end
	return tracked
end

-- dataManager.ClearActiveQuest() - remove a quest from the active list
-- @player: the player
-- @questId: the quest ID
-- @markComplete: true to add the quest to the completed list
--
-- If the quest was tracked, the next active quest is tracked.
--
-- Return: nothing.
function module.ClearActiveQuest(player, questId, markComplete)
	local questData = module.GetQuestData(player)
	if not questData then
		return
	end
	for i, entry in ipairs(questData.Active) do
		if entry.Id == questId then
			table.remove(questData.Active, i)
			break
		end
	end
	if markComplete then
		if not table.find(questData.Completed, questId) then
			table.insert(questData.Completed, questId)
		end
	end
	if questData.Tracked == questId then
		if #questData.Active > 0 then
			questData.Tracked = questData.Active[1].Id
		else
			questData.Tracked = nil
		end
	end
end

-- dataManager.ClearQuest() - remove all trace of a quest
-- @player: the player
-- @questId: the quest ID
--
-- Removes the quest from the active and completed lists and untracks it.
--
-- Return: nothing.
function module.ClearQuest(player, questId)
	local p = Profiles[player]
	if not p then
		warn(`[dataManager] ClearQuest: no profile for {player}.`)
		return
	end

	local quest = p.Data.Quest
	if not quest then
		return
	end

	for i, entry in ipairs(quest.Active or {}) do
		if entry.Id == questId then
			table.remove(quest.Active, i)
			break
		end
	end

	for i, id in ipairs(quest.Completed or {}) do
		if id == questId then
			table.remove(quest.Completed, i)
			break
		end
	end

	if quest.Tracked == questId then
		quest.Tracked = nil
	end
end

-- dataManager.GetAllActiveQuests() - get every active quest entry
-- @player: the player
--
-- Return: an array of { Id, Progress }.
function module.GetAllActiveQuests(player)
	local questData = module.GetQuestData(player)
	if not questData then
		return {}
	end
	return questData.Active
end

-- dataManager.GetAttuned() - get the spires a player is attuned to
-- @player: the player
--
-- Return: an array of spire IDs.
function module.GetAttuned(player)
	local p = Profiles[player]
	if not p then
		return {}
	end
	if not p.Data.Attuned then
		p.Data.Attuned = {}
	end
	return p.Data.Attuned
end

-- dataManager.IsAttuned() - check whether a player is attuned to a spire
-- @player: the player
-- @spireId: the spire ID
--
-- Return: true if attuned.
function module.IsAttuned(player, spireId)
	local attuned = module.GetAttuned(player)
	return table.find(attuned, spireId) ~= nil
end

-- dataManager.AddAttuned() - attune a player to a spire
-- @player: the player
-- @spireId: the spire ID
--
-- Return: true if the spire is new, false otherwise.
function module.AddAttuned(player, spireId)
	local p = Profiles[player]
	if not p then
		return false
	end
	if not p.Data.Attuned then
		p.Data.Attuned = {}
	end
	if table.find(p.Data.Attuned, spireId) then
		return false
	end
	table.insert(p.Data.Attuned, spireId)
	return true
end

-- dataManager.UnlockTitle() - give a player a title
-- @player: the player
-- @title: the title
--
-- Return: true if the title is new, false otherwise.
function module.UnlockTitle(player, title)
	local p = Profiles[player]
	if not p then
		return false
	end
	if not p.Data.UnlockedTitles then
		p.Data.UnlockedTitles = {}
	end
	if table.find(p.Data.UnlockedTitles, title) then
		return false
	end
	table.insert(p.Data.UnlockedTitles, title)
	return true
end

-- dataManager.HasTitle() - check whether a player has a title
-- @player: the player
-- @title: the title
--
-- Return: true if the player has it.
function module.HasTitle(player, title)
	local p = Profiles[player]
	if not p then
		return false
	end
	if not p.Data.UnlockedTitles then
		return false
	end
	return table.find(p.Data.UnlockedTitles, title) ~= nil
end

-- dataManager.SetCurrentTitle() - equip a title
-- @player: the player
-- @title: an unlocked title, or "" for none
--
-- Also sets the Title attribute on the player.
--
-- Return: true on success, false if the title is locked.
function module.SetCurrentTitle(player, title)
	local p = Profiles[player]
	if not p then
		return false
	end
	if title ~= "" and not table.find(p.Data.UnlockedTitles or {}, title) then
		return false
	end
	p.Data.CurrentTitle = title
	player:SetAttribute("Title", title)
	return true
end

-- dataManager.GetCurrentTitle() - get the equipped title
-- @player: the player
--
-- Return: the title, or "".
function module.GetCurrentTitle(player)
	local p = Profiles[player]
	return p and p.Data.CurrentTitle or ""
end

-- dataManager.GetUnlockedTitles() - get a player's titles
-- @player: the player
--
-- Return: an array of titles.
function module.GetUnlockedTitles(player)
	local p = Profiles[player]
	return p and p.Data.UnlockedTitles or {}
end

-- dataManager.AddKill() - count a player kill
-- @player: the killer
--
-- Return: the new kill count.
function module.AddKill(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	p.Data.PlayerKills = (p.Data.PlayerKills or 0) + 1
	return p.Data.PlayerKills
end

-- dataManager.AddDeath() - count a death
-- @player: the player who died
--
-- Return: the new death count.
function module.AddDeath(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	p.Data.PlayerDeaths = (p.Data.PlayerDeaths or 0) + 1
	return p.Data.PlayerDeaths
end

-- dataManager.GetKills() - get a player's kill count
-- @player: the player
--
-- Return: the count.
function module.GetKills(player)
	local p = Profiles[player]
	return p and (p.Data.PlayerKills or 0) or 0
end

-- dataManager.GetDeaths() - get a player's death count
-- @player: the player
--
-- Return: the count.
function module.GetDeaths(player)
	local p = Profiles[player]
	return p and (p.Data.PlayerDeaths or 0) or 0
end

-- dataManager.SaveLastPosition() - save where a player is
-- @player: the player
-- @position: the Vector3 position
--
-- Return: nothing.
function module.SaveLastPosition(player, position)
	local p = Profiles[player]
	if not p then
		return
	end
	p.Data.LastPosition = { X = position.X, Y = position.Y, Z = position.Z }
end

-- dataManager.GetLastPosition() - get a player's saved position
-- @player: the player
--
-- Return: the Vector3, or nil.
function module.GetLastPosition(player)
	local p = Profiles[player]
	if not p or not p.Data.LastPosition then
		return nil
	end
	local pos = p.Data.LastPosition
	return Vector3.new(pos.X, pos.Y, pos.Z)
end

-- dataManager.ClearLastPosition() - forget a player's saved position
-- @player: the player
--
-- Return: nothing.
function module.ClearLastPosition(player)
	local p = Profiles[player]
	if not p then
		return
	end
	p.Data.LastPosition = nil
end

_G.DataManager = module

return module
