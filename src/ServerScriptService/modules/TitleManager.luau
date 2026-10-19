-- [[ TITLE MANAGER ]]
-- Location: ServerScriptService.modules (ModuleScript)
-- Handles all title unlock checks and client notifications.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)

local AurasFolder = ReplicatedStorage:WaitForChild("assets"):WaitForChild("auras"):WaitForChild("title")

local TitleManager = {}

-- ── TITLE DEFINITIONS ─────────────────────────────────────────────────────────
-- Each entry: Title string, Liturgy reward, unlock condition description

TitleManager.Titles = {

	-- Kill titles
	["the Bully"] = { Liturgy = 300,  Description = "Kill 10 players."  },
	["the Butcher"] = { Liturgy = 300,  Description = "Kill 50 players."  },
	["the Ghost"]   = { Liturgy = 1000, Description = "Kill 100 players." },
	["Hollow One"]  = { Liturgy = 1500, Description = "Kill 500 players." },

	-- Death titles
	["the Victim"]   = { Liturgy = 50,   Description = "Die once."         },
	["the Hunted"]   = { Liturgy = 150,  Description = "Die 10 times."     },
	["the Prey"]     = { Liturgy = 500,  Description = "Die 50 times."     },
	["the Befallen"] = { Liturgy = 2000, Description = "Die 200 times."    },
	["the Vengeful"] = { Liturgy = 1000, Description = "Die 500 times."    },

	-- Weapon mastery titles
	["the Hero"]     = { Liturgy = 0, Description = "Reach level 25 with the Sword."      },
	["the Berserker"]= { Liturgy = 0, Description = "Reach level 25 with the Greatsword." },
	["the Shade"]    = { Liturgy = 0, Description = "Reach level 25 with the Dagger."     },
	["the Ronin"]    = { Liturgy = 0, Description = "Reach level 25 with the Katana."     },
	["the Iron Fist"]= { Liturgy = 0, Description = "Reach level 25 with the Fists."      },
	["the Oni"]      = { Liturgy = 0, Description = "Obtain the skill Messatsu."           },

	-- Progression titles
	["the Unfound"]   = { Liturgy = 0, Description = "Reach level 25 with any weapon."    },
	["the Replicant"] = { Liturgy = 0, Description = "Reach level 25 with all weapons."   },
	
	-- Dev specs
	["Angel's Thanatos"] = { Liturgy = 6700, Description = "???", UserId = 107650965},
	["the Primal Maw"] = { Liturgy = 6700, Description = "???", UserId = 1526974131},
	["the Unforgiven"] = { Liturgy = 6700, Description = "???", UserId = 1718017878},
	["the Dragon Knight"] = { Liturgy = 6700, Description = "???", UserId = 1718017878},
}

-- ── KILL THRESHOLDS ───────────────────────────────────────────────────────────

local KILL_TITLES = {
	{ Threshold = 10,  Title = "the Butcher" },
	{ Threshold = 100, Title = "the Ghost"   },
	{ Threshold = 250, Title = "the Wraith"   },
	{ Threshold = 500, Title = "the Phantom"  },
}

-- ── DEATH THRESHOLDS ──────────────────────────────────────────────────────────

local DEATH_TITLES = {
	{ Threshold = 1,   Title = "the Victim"   },
	{ Threshold = 10,  Title = "the Hunted"   },
	{ Threshold = 50,  Title = "the Prey"     },
	{ Threshold = 200, Title = "the Befallen" },
	{ Threshold = 500, Title = "the Vengeful" },
}

-- ── WEAPON MASTERY MAP ────────────────────────────────────────────────────────

local WEAPON_TITLES = {
	Sword      = "the Hero",
	Greatsword = "the Berserker",
	Dagger     = "the Shade",
	Katana     = "the Ronin",
	Fists      = "the Iron Fist",
}

local ALL_WEAPONS = { "Sword", "Greatsword", "Dagger", "Katana", "Fists" }

-- ── NOTIFICATION REMOTE ───────────────────────────────────────────────────────

local remotes = ReplicatedStorage:WaitForChild("remotes")

local TitleEarnedRemote = remotes:FindFirstChild("TitleEarned")
if not TitleEarnedRemote then
	TitleEarnedRemote = Instance.new("RemoteEvent")
	TitleEarnedRemote.Name   = "TitleEarned"
	TitleEarnedRemote.Parent = remotes
end

local TitleUnlockedRemote = remotes:FindFirstChild("TitleUnlocked")
if not TitleUnlockedRemote then
	TitleUnlockedRemote = Instance.new("RemoteEvent")
	TitleUnlockedRemote.Name   = "TitleUnlocked"
	TitleUnlockedRemote.Parent = remotes
end

-- ── GRANT HELPER ─────────────────────────────────────────────────────────────

local function grantTitle(player, titleName)
	local def = TitleManager.Titles[titleName]
	if not def then return end

	local isNew = DataManager.UnlockTitle(player, titleName)
	if not isNew then return end

	-- Give Liturgy reward
	if def.Liturgy and def.Liturgy > 0 then
		DataManager.AddLiturgy(player, def.Liturgy)
	end

	-- Notify client — repurposes quest complete UI
	TitleEarnedRemote:FireClient(player, titleName, def.Liturgy or 0)

	-- Refresh title selector if open
	TitleUnlockedRemote:FireClient(player, titleName)

	print(string.format("[TitleManager] %s earned title: %s (+%d L)",
		player.Name, titleName, def.Liturgy or 0))
end

-- ── PUBLIC CHECKS ─────────────────────────────────────────────────────────────

function TitleManager.CheckKills(player)
	local kills = DataManager.GetKills(player)
	for _, entry in ipairs(KILL_TITLES) do
		if kills >= entry.Threshold then
			grantTitle(player, entry.Title)
		end
	end
end

function TitleManager.CheckDeaths(player)
	local deaths = DataManager.GetDeaths(player)
	for _, entry in ipairs(DEATH_TITLES) do
		if deaths >= entry.Threshold then
			grantTitle(player, entry.Title)
		end
	end
end

function TitleManager.CheckWeaponMastery(player, weaponName)
	local weaponTitle = WEAPON_TITLES[weaponName]
	if weaponTitle then
		grantTitle(player, weaponTitle)
	end

	-- Unfound — any weapon at 25
	grantTitle(player, "the Unfound")

	-- Replicant — check all weapons
	local profile = DataManager.GetProfile(player)
	if not profile then return end

	local allMax = true
	for _, wName in ipairs(ALL_WEAPONS) do
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

-- Add this new public function at the bottom with your other public checks
function TitleManager.UpdateAura(player, equippedTitleName)
	local character = player.Character
	if not character then return end

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
		warn(string.format("[TitleManager] Missing Aura folder in ReplicatedStorage for: %s", equippedTitleName))
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
			-- Optional warning if you misspell a folder or the player is missing a limb
			warn(string.format("[TitleManager] Character %s is missing part: %s", player.Name, partFolder.Name))
		end
	end
end

function TitleManager.CheckSpecUnlock(player)
	for titleName, def in pairs(TitleManager.Titles) do
		if def.UserId and def.UserId == player.UserId then
			grantTitle(player, titleName)
		end
	end
end

function TitleManager.CheckSkillUnlock(player, spellName)
	if spellName == "Messatsu" then
		grantTitle(player, "the Oni")
	end
end

_G.TitleManager = TitleManager
return TitleManager