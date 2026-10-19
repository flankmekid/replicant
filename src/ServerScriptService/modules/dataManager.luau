-- [[ DATA MANAGER (ProfileStore Implementation) ]] --
-- Location: ServerScriptService.modules.dataManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

-- Require the ProfileStore module
local ProfileStore = require(game.ServerScriptService.modules:WaitForChild("ProfileStore"))
local StatScaling = require(game.ReplicatedStorage.modules:WaitForChild("StatScaling"))

local module = {}

-- [[ CONFIGURATION ]] --
local DATA_STORE_NAME = "Apocrypha_Data_v6_TESTING" -- OLD :: "Apocrypha_Data_v3" "Apocrypha_Data_v5_TESTING"
local CURRENCY_NAME = "Liturgy"
local MAX_LEVEL = 25
local WEAPON_TYPES = { "Fists", "Katana", "Sword", "Dagger", "Greatsword" }
local DROP_LIFETIME = 180
local DEATH_DROP_AMOUNT = 200
local DEFAULT_WEAPON = "Fists"

-- [[ ASSETS ]] --
local assets = ReplicatedStorage:WaitForChild("assets")
local fxFolder = assets:WaitForChild("FX")
local liturgyTemplate = fxFolder:WaitForChild("Liturgy")
local facesFolder = ReplicatedStorage:WaitForChild("faces")

-- [[ EYE COLOR CONFIG ]] --
local REALISTIC_EYE_COLORS = {
	{ R = 89, G = 59, B = 32 }, -- Dark Brown
	{ R = 139, G = 69, B = 19 }, -- Brown
	{ R = 99, G = 78, B = 52 }, -- Hazel
	{ R = 45, G = 87, B = 139 }, -- Deep Blue
	{ R = 95, G = 140, B = 178 }, -- Light Blue
	{ R = 62, G = 107, B = 64 }, -- Green
	{ R = 128, G = 128, B = 128 }, -- Grey
	{ R = 48, G = 48, B = 48 }, -- Black/Very Dark
	{ R = 138, G = 119, B = 78 }, -- Amber
}

-- [[ PROFILE TEMPLATE ]] --
local ProfileTemplate = {
	Liturgy = 0,
	Spins = 100,
	Pity = 0,
	Race = "Human",
	TutorialComplete = false,
	WeaponProgression = {},

	UnlockedSpells = {},
	EquippedSkills = {}, -- [family] = {Z=, X=, C=}; per-family skill loadout for the spellbook

	Inventory = {},

	-- [[ NEW INVENTORY DATA STRUCTURE ]] --
	InventoryData = {
		Items = {}, -- Stores tables: {Id = "uuid", Name = "ItemName", Amount = 1}
		Hotbar = {}, -- Dictionary mapping slot index (1-9) to an Item Id
		Equipment = {
			Head = nil,
			Torso = nil,
			Legs = nil,
			Back = nil,
		},
	},

	-- [[ APPEARANCE ]] --
	EyeColor = nil,
	Face = nil,
	Hair = { 0, 0, 0 },
	Gender = "Male",
	ArmorColor = nil,

	-- [[ STATS ]] --
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

	-- [[ STAT SPREAD (Souls-like invested points, 0-50 each) ]] --
	Stats = {
		Vitality = 0,
		Stamina = 0,
		Strength = 0,
		Dexterity = 0,
		Magic = 0,
	},
	-- [[ SKILL POINT BUDGET (Model A) ]]
	-- SkillPointsOwned: total skill points bought with Liturgy (0..150, only rises).
	-- Stats are assigned from these for free (1 skill point = 1 stat point).
	-- Available to assign = SkillPointsOwned - (sum of all stat values).
	SkillPointsOwned = 0,

	-- [[ ARMOR ]]
	CurrentArmor = "Rags",
	OwnedArmors = { "Rags" },
	-- Transmog override. nil = vanity follows CurrentArmor; a string = an
	-- explicit vanity differing from the stats-armor. Stats always come from CurrentArmor.
	CurrentVanity = nil,

	-- [[ QUEST DATA ]] --
	Quest = {
		Active = {}, -- array of { Id = string, Progress = number }
		Tracked = nil, -- quest ID currently shown in the HUD tracker
		Completed = {},
		Cooldowns = {},
	},

	-- SPIRES
	Attuned = {},

	-- TITLES
	UnlockedTitles = {},
	CurrentTitle = "",
	PlayerKills = 0,
	PlayerDeaths = 0,

	-- LAST SAVED POS
	LastPosition = nil, -- stored as {X, Y, Z}
}

-- Initialize Weapon Progression
for _, weapon in ipairs(WEAPON_TYPES) do
	ProfileTemplate.WeaponProgression[weapon] = { XP = 0, Level = 1 }
end

local GameProfileStore = ProfileStore.New(DATA_STORE_NAME, ProfileTemplate)
local Profiles = {}

-- [[ HELPER: RANDOM FACE ]] --
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

-- [[ XP FORMULAS ]] --
local function GetXPThreshold(targetLevel)
	if targetLevel <= 1 then
		return 0
	end
	local xpNeeded = math.floor((50 * (targetLevel ^ 1.2)) + (targetLevel * 25))
	return math.ceil(xpNeeded / 25) * 25
end

-- [[ STATS VISUALIZATION ]] --
function module.CreateSessionStats(player, profile)
	local data = profile.Data

	local playerStats = Instance.new("Folder")
	playerStats.Name = "PlayerStats"

	-- Liturgy (Currency)
	local liturgyVal = Instance.new("IntValue")
	liturgyVal.Name = CURRENCY_NAME
	liturgyVal.Value = data.Liturgy
	liturgyVal.Parent = playerStats
	liturgyVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Liturgy = val
		end
	end)

	-- Spins
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

	-- Race Name
	local raceVal = Instance.new("StringValue")
	raceVal.Name = "Race"
	raceVal.Value = data.Race
	raceVal.Parent = playerStats
	raceVal.Changed:Connect(function(val)
		if Profiles[player] then
			Profiles[player].Data.Race = val
		end
	end)

	-- [[ ARMOR BUFFS ]] --
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

	-- [[ STATS VALUES ]] --
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

	-- [[ STAT SPREAD: invested point counts (read by damageCalculator & client UI) ]] --
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

	-- Skill-point budget mirrors (display-only; server is authoritative).
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

	-- Mana Setup (MaxMana now includes the Magic stat's flat +mana bonus)
	local magicManaBonus = StatScaling.GetManaBonus(data.Stats.Magic or 0)
	local calculatedMaxMana = (data.MaxMana * data.ManaBoost) + magicManaBonus
	local manaVal = Instance.new("NumberValue", playerStats)
	manaVal.Name = "Mana"
	manaVal.Value = calculatedMaxMana

	local maxManaVal = Instance.new("NumberValue", playerStats)
	maxManaVal.Name = "MaxMana"
	maxManaVal.Value = calculatedMaxMana

	-- Folders
	local weaponDataFolder = Instance.new("Folder")
	weaponDataFolder.Name = "WeaponData"
	weaponDataFolder.Parent = playerStats

	local skillsFolder = Instance.new("Folder")
	skillsFolder.Name = "UnlockedSkills"
	skillsFolder.Parent = playerStats

	-- [[ FIXED: Load Spells separately from tools ]] --
	if data.UnlockedSpells then
		for _, spellName in ipairs(data.UnlockedSpells) do
			local val = Instance.new("StringValue")
			val.Name = spellName
			val.Parent = skillsFolder
		end
	end

	-- [[ EQUIPPED SKILLS (Spellbook loadout) ]] --
	-- Build a replicated folder the client reads to resolve Z/X/C per family.
	-- Structure: PlayerStats.EquippedSkills.<Family> with StringValues named Z/X/C.
	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
	if not data.EquippedSkills then
		data.EquippedSkills = {}
	end

	-- Migration: if a player has unlocked spells but no saved loadout, rebuild it
	-- by placing each unlocked spell into its family slot (last-write-wins per slot).
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

	-- Weapon Progression
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

-- [[ MANA REGENERATION ]] --
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

-- [[ DATA LOADING ]] --
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

		-- Migrate old quest structure to new array-based structure
		local q = profile.Data.Quest
		if q then
			-- Old structure had Active as a string or nil, Progress as a number
			if type(q.Active) ~= "table" then
				local oldId = type(q.Active) == "string" and q.Active or nil
				local oldProgress = type(q.Progress) == "number" and q.Progress or 0
				q.Active = {}
				if oldId then
					table.insert(q.Active, { Id = oldId, Progress = oldProgress })
				end
				q.Progress = nil
			end
			-- Only seed a default track when Tracked was never set (nil). `false`
			-- means the player deliberately untracked in a prior session; preserve it
			-- so rejoining does not silently re-track the first active quest.
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

		-- 1. Initialize InventoryData if it doesn't exist
		if not profile.Data.InventoryData then
			profile.Data.InventoryData = { Items = {}, Hotbar = {}, Equipment = {} }
		end

		-- 2. DATA MIGRATION: Old Inventory to New InventoryData
		if profile.Data.Inventory and #profile.Data.Inventory > 0 then
			if #profile.Data.InventoryData.Items == 0 then
				for _, toolName in ipairs(profile.Data.Inventory) do
					table.insert(profile.Data.InventoryData.Items, {
						Id = game:GetService("HttpService"):GenerateGUID(false),
						Name = toolName,
						Amount = 1,
					})
				end
				print("[DATA] Migrated old inventory format for " .. player.Name)
			end
			profile.Data.Inventory = nil
		end

		-- 3. [[ NEW PLAYER LOGIC: GIVE DEFAULT WEAPON TO HOTBAR ]] --
		local invData = profile.Data.InventoryData
		local isInventoryEmpty = #invData.Items == 0
		local isHotbarEmpty = true

		-- Check if any slot in hotbar is filled
		for i = 1, 9 do
			if invData.Hotbar[tostring(i)] or invData.Hotbar[i] then
				isHotbarEmpty = false
				break
			end
		end

		if isInventoryEmpty and isHotbarEmpty then
			print(
				"[DATA] New Player detected. Assigning " .. DEFAULT_WEAPON .. " to Hotbar Slot 1."
			)
			local defaultItem = {
				Id = game:GetService("HttpService"):GenerateGUID(false),
				Name = DEFAULT_WEAPON,
				Amount = 1,
			}
			-- Assign to Slot 1 in Data
			invData.Hotbar["1"] = defaultItem
		end

		-- Ensure CurrentWeapon matches the default if empty
		if profile.Data.CurrentWeapon == nil or profile.Data.CurrentWeapon == "" then
			profile.Data.CurrentWeapon = DEFAULT_WEAPON
		end

		-- [[ 4. APPEARANCE INITIALIZATION ]] --
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
			print(string.format("[DATA] Profile loaded for %s", player.Name))
		else
			profile:EndSession()
		end
	else
		player:Kick("Data could not be loaded. Please rejoin.")
	end
end

local LOG_PENALTY_AMOUNT = 500

function module.PlayerRemoving(player)
	local combatExpiry = player:GetAttribute("CombatLogExpiry")

	if combatExpiry and os.clock() < combatExpiry then
		print(player.Name .. " combat logged! Applying penalty inside DataManager.")

		local success = module.RemoveLiturgy(player, LOG_PENALTY_AMOUNT)

		if success then
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				module.CreateDrop(char.HumanoidRootPart.Position, LOG_PENALTY_AMOUNT)
			end
		end
	end

	-- Remove this leaver as an attacker from everyone they had tagged, and drop
	-- their own tag. Without this, a victim stays in combat after their attacker
	-- leaves (combat tag persists). Done here (PlayerRemoving) to avoid the
	-- ordering race the manager comment warns about.
	local okTag, TagManager =
		pcall(require, game:GetService("ServerScriptService").modules.combatTagManager)
	if okTag and TagManager then
		TagManager.HandlePlayerLeft(player)
	end

	local profile = Profiles[player]
	if profile then
		profile:EndSession()
		print(string.format("[DATA] Saved %s", player.Name))
	end
end

-- [[ API METHODS ]] --
function module.GetProfile(player)
	return Profiles[player]
end

-- [[ STAT SPREAD API (Model A: skill-point budget) ]] --
local VALID_STATS =
	{ Vitality = true, Stamina = true, Strength = true, Dexterity = true, Magic = true }

function module.GetStat(player, statName)
	local p = Profiles[player]
	if not p or not p.Data.Stats then
		return 0
	end
	return p.Data.Stats[statName] or 0
end

-- Sum of all assigned stat points (= skill points currently spent).
local function sumStats(p)
	local total = 0
	if p.Data.Stats then
		for stat in pairs(VALID_STATS) do
			total = total + (p.Data.Stats[stat] or 0)
		end
	end
	return total
end

function module.GetSkillPointsOwned(player)
	local p = Profiles[player]
	return p and (p.Data.SkillPointsOwned or 0) or 0
end

function module.GetAvailableSkillPoints(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	return (p.Data.SkillPointsOwned or 0) - sumStats(p)
end

-- Mirror stat values + skill-point counters into the live PlayerStats.Stats folder.
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

-- Buy one SKILL POINT with Liturgy (rising curve, capped at MAX_SKILL_POINTS).
-- Returns true, cost on success; false, reason on failure.
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

-- Assign one available skill point to a stat (free, 1:1). Capped at MAX_STAT.
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

-- Respec: free ALL assigned skill points (zero every stat). Keeps owned points.
-- No Liturgy involved (you keep the points you bought; this just frees them to
-- reassign). Refuses if nothing is assigned.
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

function module.GetNextSkillPointCost(player)
	return StatScaling.GetNextSkillPointCost(module.GetSkillPointsOwned(player))
end

-- APPEARANCE API
function module.GetEyeColor(player)
	local p = Profiles[player]
	if p and p.Data.EyeColor then
		local c = p.Data.EyeColor
		return Color3.fromRGB(c.R, c.G, c.B)
	end
	return Color3.new(0, 0, 0)
end

function module.GetFace(player)
	local p = Profiles[player]
	return p and p.Data.Face or "rbxassetid://0"
end

function module.SetFace(player, textureId)
	local p = Profiles[player]
	if p then
		p.Data.Face = textureId
	end
end

-- [[ BARBER API ]] --
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

function module.SetHair(player, slot, id)
	local p = Profiles[player]
	if p then
		if not p.Data.Hair then
			p.Data.Hair = { 0, 0, 0 }
		end
		p.Data.Hair[slot] = id
	end
end

function module.ResetHair(player)
	local p = Profiles[player]
	if p then
		p.Data.Hair = { 0, 0, 0 }
	end
end

function module.SetGender(player, gender)
	local p = Profiles[player]
	if p then
		p.Data.Gender = gender
	end
end

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

-- Liturgy Logic
function module.GetLiturgy(player)
	local p = Profiles[player]
	return p and p.Data.Liturgy or 0
end

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

function module.GetCurrentArmor(player)
	local profile = Profiles[player]
	return profile and profile.Data.CurrentArmor or "Rags"
end

function module.SetCurrentArmor(player, armorName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentArmor = armorName
	end
end

function module.OwnsArmor(player, armorName)
	local profile = Profiles[player]
	if not profile then
		return false
	end
	return table.find(profile.Data.OwnedArmors, armorName) ~= nil
end

function module.AddArmor(player, armorName)
	local profile = Profiles[player]
	if profile then
		if not table.find(profile.Data.OwnedArmors, armorName) then
			table.insert(profile.Data.OwnedArmors, armorName)
		end
	end
end

-- Vanity (transmog) accessors. CurrentVanity is nil when vanity follows the
-- stats-armor; GetCurrentVanity resolves that fallback for callers.
function module.GetCurrentVanity(player)
	local profile = Profiles[player]
	if not profile then
		return "Rags"
	end
	return profile.Data.CurrentVanity or profile.Data.CurrentArmor or "Rags"
end

function module.SetCurrentVanity(player, armorName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentVanity = armorName
	end
end

function module.GetPity(player)
	local p = Profiles[player]
	return p and p.Data.Pity or 0
end

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

function module.GetSpins(player)
	local p = Profiles[player]
	return p and p.Data.Spins or 0
end

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

function module.YieldUntilLoaded(player)
	if Profiles[player] then
		return
	end
	local t = tick()
	repeat
		task.wait(0.1)
	until Profiles[player] or tick() - t > 15
end

-- [[ FIXED HYBRID LOGIC: EquipLoadout ]] --
function module.EquipLoadout(player, character)
	local profile = Profiles[player]
	if not profile then
		return
	end

	local data = profile.Data
	local invData = data.InventoryData or { Items = {}, Hotbar = {}, Equipment = {} }
	local currentWeapon = data.CurrentWeapon

	-- [[ REFERENCE BOTH FOLDERS ]] --
	local weaponsFolder = ServerStorage:FindFirstChild("Weapons")
	local equipmentFolder = ServerStorage:FindFirstChild("Equipment")

	player.Backpack:ClearAllChildren()
	player.StarterGear:ClearAllChildren()

	local givenItems = {}

	-- Helper function to clone tool if not already given
	local function giveItem(itemName)
		--task.wait()
		if itemName and not givenItems[itemName] then
			-- [[ DUAL FOLDER CHECK ]] --
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

	-- 1. Read all tools from general items array
	for _, itemData in ipairs(invData.Items or {}) do
		print(itemData.Name)
		giveItem(itemData.Name)
	end

	-- 2. Read all tools from the hotbar dictionary
	for _, itemData in pairs(invData.Hotbar or {}) do
		if itemData and not itemData.IsSpell then
			print(itemData.Name)
			giveItem(itemData.Name)
		end
	end

	-- 3. Read all tools from equipment dictionary (if you treat equipment as tools)
	for _, itemData in pairs(invData.Equipment or {}) do
		if itemData then
			print(itemData.Name)
			giveItem(itemData.Name)
		end
	end

	-- Equip the last known equipped weapon automatically
	--local toolToEquip = player.Backpack:FindFirstChild(currentWeapon)
	--local humanoid = character:FindFirstChild("Humanoid")

	--if toolToEquip and humanoid then
	--	humanoid:EquipTool(toolToEquip)
	--end
end

-- Drops
function module.HandlePlayerDeath(player, position)
	local current = module.GetLiturgy(player)
	local dropAmount = math.min(current, DEATH_DROP_AMOUNT)

	if dropAmount > 0 then
		if module.RemoveLiturgy(player, dropAmount) then
			module.CreateDrop(position, dropAmount)
		end
	end
end

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

-- Reads a family's current mastery level straight off the profile. Returns 0 when
-- the family does not exist, so callers can compare against thresholds safely.
function module.GetWeaponLevel(player, family)
	local profile = Profiles[player]
	if not profile then
		return 0
	end
	local weaponData = profile.Data.WeaponProgression[family]
	return weaponData and weaponData.Level or 0
end

-- Awards XP to a SINGLE family and returns the level it ended on. Does not touch
-- quests; the caller reconciles once, after all families have been credited.
local function grantFamilyXP(player, family, amount)
	local profile = Profiles[player]
	if not profile then
		return nil
	end

	local weaponData = profile.Data.WeaponProgression[family]
	if not weaponData then
		warn("[DataManager] No WeaponProgression entry for family: " .. tostring(family))
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

	-- Cap XP at the max-level threshold so the bar does not keep filling past 25.
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

-- Awards weapon XP. `weaponName` may be a family ("Fists"), a branch weapon
-- ("Caestus", "Shackles"), or a hybrid ("Guandao").
--
--   branch weapon -> resolved to its family via SkillConfig.WeaponFamily
--   hybrid        -> HALVED XP to each of its two parent families
--
-- Quest state is NEVER driven off the level-up event. We credit the XP, then ask
-- the reconciler to evaluate the resulting profile state. A player who blows past
-- several milestones in one hit, or who is already mid-quest, still lands on the
-- correct next checkpoint, because the reconciler reads the profile rather than
-- trusting a one-shot signal it might miss.
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
			warn("[DataManager] Unrecognised weapon for XP: " .. tostring(weaponName))
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

		-- A parent family levelling may have crossed a hybrid threshold, so
		-- re-evaluate every hybrid whose parents we just touched.
		if QuestManager then
			QuestManager.ReconcileHybrids(player)
		end
	end)
end

-- Inventory & Selection
function module.SetCurrentWeapon(player, weaponName)
	local profile = Profiles[player]
	if profile then
		profile.Data.CurrentWeapon = weaponName
	end
end

function module.GetCurrentWeapon(player)
	local profile = Profiles[player]
	return profile and profile.Data.CurrentWeapon or DEFAULT_WEAPON
end

-- [[ SPELLBOOK SNAPSHOT ]] --
-- Resolves the player's CurrentWeapon -> family, then for each slot (Z/X/C)
-- returns the skills they own and which one is equipped. All server-authoritative;
-- the client just renders this. Returns { ok, family, slots = { Z = {owned={}, equipped=}, ... } }.
function module.GetSpellbookSnapshot(player)
	local profile = Profiles[player]
	if not profile then
		return { ok = false, reason = "NoProfile" }
	end

	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)

	-- Resolve the player's weapon from what they actually have, not the stored field.
	-- Priority: the held Tool (one weapon on the avatar at a time), then any weapon
	-- Tool in the Backpack (covers a sheathed weapon while resting). A Tool is a
	-- weapon iff its name is a key in WeaponFamily, which skips spells/consumables.
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
		-- Last resort: the stored field, if it happens to be a real weapon.
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

function module.GetInventoryData(player)
	local profile = Profiles[player]
	return profile and profile.Data.InventoryData or nil
end

function module.SaveInventoryData(player, newInventoryData)
	local profile = Profiles[player]
	if profile then
		profile.Data.InventoryData = newInventoryData
	end
end

function module.HasItem(player, itemName)
	local profile = Profiles[player]
	if not profile then
		return false
	end

	local invData = profile.Data.InventoryData
	if not invData then
		return false
	end

	-- 1. Check general inventory
	for _, item in ipairs(invData.Items or {}) do
		if item.Name == itemName then
			return true
		end
	end

	-- 2. Check hotbar
	for _, item in pairs(invData.Hotbar or {}) do
		if item and item.Name == itemName then
			return true
		end
	end

	-- 3. Check equipped gear
	for _, item in pairs(invData.Equipment or {}) do
		if item and item.Name == itemName then
			return true
		end
	end

	return false
end

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
			-- [[ AUTO-EQUIP INTO SPELLBOOK ]] --
			-- Place the newly learned skill into its own family slot, overwriting
			-- whatever sat there. Other two slots are left untouched.
			local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
			local fam, slotIdx = SkillConfig.FindSkillSlot(spellName)
			if fam and slotIdx then
				local slotKey = SkillConfig.SlotKeys[slotIdx]
				if not profile.Data.EquippedSkills then
					profile.Data.EquippedSkills = {}
				end
				profile.Data.EquippedSkills[fam] = profile.Data.EquippedSkills[fam] or {}
				profile.Data.EquippedSkills[fam][slotKey] = spellName

				-- Mirror to the replicated folder so the client updates immediately.
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

			print(string.format("[DATA] %s unlocked spell: %s", player.Name, spellName))
			local tm = _G.TitleManager
			if tm then
				tm.CheckSkillUnlock(player, spellName)
			end
		end
	end
end

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

-- [[ SPELLBOOK: equip an owned skill into a slot of its family ]] --
-- Validates ownership and that the skill actually belongs to (family, slot).
-- Returns true on success. Used by the spire spellbook UI.
function module.EquipSkill(player, family, slotKey, skillName)
	local profile = Profiles[player]
	if not profile then
		return false
	end

	local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)

	-- Verify the skill belongs to this family + slot.
	local fam, slotIdx = SkillConfig.FindSkillSlot(skillName)
	if fam ~= family then
		return false
	end
	if SkillConfig.SlotKeys[slotIdx] ~= slotKey then
		return false
	end

	-- Verify ownership.
	if not module.HasSpell(player, skillName) then
		return false
	end

	profile.Data.EquippedSkills = profile.Data.EquippedSkills or {}
	profile.Data.EquippedSkills[family] = profile.Data.EquippedSkills[family] or {}
	profile.Data.EquippedSkills[family][slotKey] = skillName

	-- Mirror to replicated folder.
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

-- Returns the equipped skill name for a family + slot, or nil.
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

-- Tutorial
function module.SetTutorialComplete(player, status)
	local profile = Profiles[player]
	if profile then
		if status == nil then
			status = true
		end
		profile.Data.TutorialComplete = status
	end
end

function module.GetTutorialComplete(player)
	local profile = Profiles[player]
	return profile and profile.Data.TutorialComplete or false
end

-- Mana
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

-- [[ FIXED: Clear the new OOP Inventory Data structure ]]
function module.ClearInventory(player)
	local profile = Profiles[player]
	if profile then
		profile.Data.InventoryData = { Items = {}, Hotbar = {}, Equipment = {} }
		print(string.format("[DATA] Cleared saved inventory for %s", player.Name))
	end
end

-- [[ GET QUEST DATA ]]
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

-- [[ GET SINGLE ACTIVE QUEST ENTRY BY ID ]]
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

-- [[ CHECK IF QUEST IS ACTIVE ]]
function module.IsQuestActive(player, questId)
	return module.GetActiveQuestEntry(player, questId) ~= nil
end

-- [[ ADD QUEST TO ACTIVE ARRAY ]]
function module.SetActiveQuest(player, questId)
	local questData = module.GetQuestData(player)
	if not questData then
		return
	end
	if module.IsQuestActive(player, questId) then
		return
	end
	table.insert(questData.Active, { Id = questId, Progress = 0 })
	-- Auto-track ONLY if Tracked was never set (nil). A `false` here means the
	-- player deliberately untracked, so leave it alone instead of re-picking.
	if questData.Tracked == nil then
		questData.Tracked = questId
	end
end

-- [[ UPDATE PROGRESS FOR A SPECIFIC QUEST ]]
function module.UpdateQuestProgress(player, questId, amount)
	local entry = module.GetActiveQuestEntry(player, questId)
	if not entry then
		return 0
	end
	entry.Progress = entry.Progress + amount
	return entry.Progress
end

-- [[ SET TRACKED QUEST ]]
-- Tracked has THREE states, do not collapse them:
--   a quest id  -> that quest is tracked
--   false       -> player deliberately untracked; auto-track must NOT re-pick
--   nil         -> never set; auto-track is free to pick a default on grant/load
-- Untracking passes questId == nil, which we store as `false` (the sentinel) so
-- a later grant/completion/reconcile does not silently re-track on rejoin.
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

-- [[ GET TRACKED QUEST ID ]]
-- Returns a quest id, or nil for both "untracked" (false) and "never set" (nil).
-- Callers that only care about the id keep working; the false/nil distinction is
-- only consulted by the auto-track guards below.
function module.GetTrackedQuest(player)
	local questData = module.GetQuestData(player)
	if not questData then
		return nil
	end
	local tracked = questData.Tracked
	if not tracked then
		return nil
	end -- covers both false and nil
	return tracked
end

-- [[ REMOVE QUEST FROM ACTIVE ARRAY AND OPTIONALLY MARK COMPLETE ]]
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
	-- If the completed quest was tracked, auto-track the next available one
	if questData.Tracked == questId then
		if #questData.Active > 0 then
			questData.Tracked = questData.Active[1].Id
		else
			questData.Tracked = nil
		end
	end
end

function module.ClearQuest(player, questId)
	local p = Profiles[player]
	if not p then
		warn("[DataManager] Profile not found for " .. tostring(player))
		return
	end

	local quest = p.Data.Quest
	if not quest then
		return
	end

	-- Remove from Active
	for i, entry in ipairs(quest.Active or {}) do
		if entry.Id == questId then
			table.remove(quest.Active, i)
			print("[DataManager] Removed " .. questId .. " from Active.")
			break
		end
	end

	-- Remove from Completed
	for i, id in ipairs(quest.Completed or {}) do
		if id == questId then
			table.remove(quest.Completed, i)
			print("[DataManager] Removed " .. questId .. " from Completed.")
			break
		end
	end

	-- Clear tracked if it was this quest
	if quest.Tracked == questId then
		quest.Tracked = nil
	end

	print("[DataManager] ClearQuest done for: " .. questId)
end

-- [[ GET ALL ACTIVE QUEST ENTRIES ]]
function module.GetAllActiveQuests(player)
	local questData = module.GetQuestData(player)
	if not questData then
		return {}
	end
	return questData.Active
end

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

function module.IsAttuned(player, spireId)
	local attuned = module.GetAttuned(player)
	return table.find(attuned, spireId) ~= nil
end

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
	print(string.format("[DATA] %s unlocked title: %s", player.Name, title))
	return true
end

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

function module.GetCurrentTitle(player)
	local p = Profiles[player]
	return p and p.Data.CurrentTitle or ""
end

function module.GetUnlockedTitles(player)
	local p = Profiles[player]
	return p and p.Data.UnlockedTitles or {}
end

function module.AddKill(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	p.Data.PlayerKills = (p.Data.PlayerKills or 0) + 1
	return p.Data.PlayerKills
end

function module.AddDeath(player)
	local p = Profiles[player]
	if not p then
		return 0
	end
	p.Data.PlayerDeaths = (p.Data.PlayerDeaths or 0) + 1
	return p.Data.PlayerDeaths
end

function module.GetKills(player)
	local p = Profiles[player]
	return p and (p.Data.PlayerKills or 0) or 0
end

function module.GetDeaths(player)
	local p = Profiles[player]
	return p and (p.Data.PlayerDeaths or 0) or 0
end

function module.SaveLastPosition(player, position)
	local p = Profiles[player]
	if not p then
		return
	end
	p.Data.LastPosition = { X = position.X, Y = position.Y, Z = position.Z }
	--print(p.Data.LastPosition)
end

function module.GetLastPosition(player)
	local p = Profiles[player]
	if not p or not p.Data.LastPosition then
		return nil
	end
	local pos = p.Data.LastPosition
	--print(pos)
	return Vector3.new(pos.X, pos.Y, pos.Z)
end

function module.ClearLastPosition(player)
	local p = Profiles[player]
	if not p then
		return
	end
	p.Data.LastPosition = nil
end

_G.DataManager = module

return module
