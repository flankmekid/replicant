local SkillConfig = {}

-- [[ 1. WEAPON MAPPING ]] --
SkillConfig.WeaponSkills = {
	["Greatsword"] = {"Whirlwind", "Abyssal Scream", "Berserker Armor"},
	["Dragon Slayer"] = {"Whirlwind", "Abyssal Scream", "Berserker Armor"},
	["Deathbringer"] = {"Whirlwind", "Abyssal Scream", "Berserker Armor"},
	
	["Sword"] 		  = {"Elfin Dance", "Air Wave", "Morgan"},
	["Excalibur"]     = {"Elfin Dance", "Air Wave", "Morgan"},
	
	["Fists"] = {}, 
	["Caestus"]       = {"Mantra Palm", "Monastic Stance", "Rising Dragon"},
	["Shackles"]      = {"Gohadoken", "Asura Glide", "Messatsu"},
	
	["Katana"]        = {"Zanshin", "Kurai", "Kirikizu"},
	["Vermillion"]    = {"Zanshin", "Kurai", "Kirikizu"},
	
	["Dagger"]        = {"Hidden Daggers", "Ying Yang Spiral", "Mystic Eyes"},
	["Tanto"]         = {"Hidden Daggers", "Ying Yang Spiral", "Mystic Eyes"},
	
	["Guandao"]       = {"Downward Cleave", "Tianshi", "Dao"},
	
	["Scythe"] = {},
}

-- [[ 2. RACE MAPPING (NEW) ]] --
-- Maps the "Race" string in PlayerStats to the Skill Name
SkillConfig.RaceSkills = {
	["Human"] = "Adrenaline Surge",
	["Elezen"]   = "Arcane Siphon",
	["Seer"] = "Null Gaze",
	["Meskar"]  = "Spectre Round",
	["Karu"]    = "Headbutt",
	["Verdis"] = "Root Prison",
	["Marasi"] = "Tidal Slug",
	["Cruor"]   = "Parasitic Impale",
	["Arach"]  = "Silk Grasp",
	["Maw"] = "Void Crunch",
	["Ancestor"]  = "Vampire Drain",
	["Grob"]  = "Jury-Rigged Bomb",
	["Aegir"] = "Draco Kick",
}

-- [[ 3. SKILL STATS ]] --
SkillConfig.Skills = {
	-- [[ DRAGON SLAYER ]] --
	["Whirlwind"] = { Mana = 25, Cooldown = 6 },
	["Abyssal Scream"] = { Mana = 35, Cooldown = 25 },
	["Berserker Armor"] = { Mana = 50, Cooldown = 60, Type = "Buff" },

	-- [[ EXCALIBUR ]] --
	["Elfin Dance"] = { Mana = 20, Cooldown = 4 },
	["Air Wave"] = { Mana = 30, Cooldown = 6 },
	["Morgan"] = { Mana = 60, Cooldown = 15 },

	-- [[ CAESTUS ]] --
	["Mantra Palm"] = { Mana = 15, Cooldown = 4 },
	["Monastic Stance"] = { Mana = 30, Cooldown = 25, Type = "Buff" },
	["Rising Dragon"] = { Mana = 35, Cooldown = 8 },

	-- [[ SHACKLES ]] --
	["Gohadoken"] = { Mana = 20, Cooldown = 5 },
	["Asura Glide"] = { Mana = 10, Cooldown = 0.4 },
	["Messatsu"] = { Mana = 40, Cooldown = 25 },

	-- [[ VERMILLION ]] --
	["Zanshin"] = { Mana = 15, Cooldown = 6, HPCost = 5 },
	["Kurai"] = { Mana = 15, Cooldown = 5, },
	["Kirikizu"] = { Mana = 25, Cooldown = 10, HPCost = 10 },

	-- [[ TANTO ]] --
	["Hidden Daggers"] = { Mana = 15, Cooldown = 8 },
	["Ying Yang Spiral"] = { Mana = 20, Cooldown = 10 },
	["Mystic Eyes"] = { Mana = 50, Cooldown = 60, Type = "Buff" },
	
	-- [[ GUANDAO ]] --
	["Downward Cleave"] = { Mana = 20, Cooldown = 10 },
	["Tianshi"] = { Mana = 25, Cooldown = 14 },
	["Dao"] = {Mana = 30, Cooldown = 15},

	-- [[ RACIAL SKILLS (NEW) ]] --
	["Adrenaline Surge"] = { Mana = 0, Cooldown = 60, Type = "Buff" }, -- Vermeer (HPCost handled in logic)
	["Arcane Siphon"] = { Mana = 0, Cooldown = 60 }, -- Albin
	["Null Gaze"] = { Mana = 60, Cooldown = 30 }, -- Aphanis
	["Spectre Round"] = { Mana = 20, Cooldown = 7 }, -- Ossuar
	["Headbutt"] = { Mana = 20, Cooldown = 20 }, -- Karu
	["Root Prison"] = { Mana = 35, Cooldown = 35 }, -- Chloris
	["Tidal Slug"] = { Mana = 30, Cooldown = 10 }, -- Glaucus
	["Parasitic Impale"] = { Mana = 30, Cooldown = 25 }, -- Cruor
	["Silk Grasp"] = { Mana = 20, Cooldown = 10 }, -- Skotos
	["Void Crunch"] = { Mana = 30, Cooldown = 15 },  -- Porphyr
	["Vampire Drain"] = { Mana = 15, Cooldown = 20 }, -- Caelum
	["Jury-Rigged Bomb"] = { Mana = 5, Cooldown = 30 },  -- Virdis
	["Draco Kick"] = {Mana = 25, Cooldown = 10}, -- Aegir
}

-- [[ 4. WEAPON -> SEED FAMILY MAPPING ]] --
-- Every weapon resolves to a seed family. Branches share their seed's family
-- so cross-branch skill mixing (e.g. Monk Z + Akuma X) lives in one loadout.
-- Hybrids (Guandao, Scythe) are their own families since they have their own skill lists.
SkillConfig.WeaponFamily = {
	["Fists"]        = "Fists",
	["Caestus"]      = "Fists",
	["Shackles"]     = "Fists",

	["Sword"]        = "Sword",
	["Excalibur"]    = "Sword",

	["Katana"]       = "Katana",
	["Vermillion"]   = "Katana",

	["Dagger"]       = "Dagger",
	["Tanto"]        = "Dagger",

	["Greatsword"]   = "Greatsword",
	["Dragon Slayer"]= "Greatsword",
	["Deathbringer"] = "Greatsword",

	["Guandao"]      = "Guandao",
	["Scythe"]       = "Scythe",
}

-- [[ 4b. HYBRID WEAPONS ]] --
-- Hybrids are NOT their own XP family. They are terminal weapons unlocked by
-- reaching thresholds in two parent families, and swinging one awards HALVED XP
-- to BOTH parents. They keep a WeaponFamily entry above purely so their skill
-- loadout has somewhere to live; XP and class quests route through here instead.
--
-- Weapon unlock:  both parents at 10
-- Skill Z unlock: both parents at 15
-- Skill X unlock: both parents at 20
-- Skill C unlock: both parents at 25
--
-- Hybrids get NO class quests. The trainer is world-discovered; the skills are
-- granted by the reconciler when both parents cross a threshold.
SkillConfig.HybridParents = {
	["Guandao"] = { "Sword", "Dagger" },
	["Scythe"]  = { "Greatsword", "Dagger" },
}

-- Thresholds a hybrid's parents must BOTH reach. Index = skill slot (1=Z,2=X,3=C).
SkillConfig.HybridSkillThresholds = { [1] = 15, [2] = 20, [3] = 25 }
SkillConfig.HybridUnlockLevel = 10

-- True if the weapon is a hybrid (feeds two parent families instead of one).
function SkillConfig.IsHybrid(weaponName)
	return SkillConfig.HybridParents[weaponName] ~= nil
end

-- Resolves any weapon name to the family whose XP bar it feeds.
-- Returns nil for hybrids (they feed two; use HybridParents), and nil for
-- anything unrecognised, so callers can bail rather than silently no-op.
function SkillConfig.GetXPFamily(weaponName)
	if SkillConfig.HybridParents[weaponName] then return nil end
	return SkillConfig.WeaponFamily[weaponName]
end

-- Slot index <-> key used in the EquippedSkills folder / table.
SkillConfig.SlotKeys = { [1] = "Z", [2] = "X", [3] = "C" }

-- [[ 5. HELPERS ]] --
-- Returns the slot index (1=Z, 2=X, 3=C) a skill occupies within its family,
-- searching every weapon that maps to the given family. Returns nil if not found.
function SkillConfig.GetSlotIndex(family, skillName)
	for weaponName, fam in pairs(SkillConfig.WeaponFamily) do
		if fam == family then
			local list = SkillConfig.WeaponSkills[weaponName]
			if list then
				for i, name in ipairs(list) do
					if name == skillName then return i end
				end
			end
		end
	end
	return nil
end

-- Given a raw skill name, find which family + slot it belongs to.
-- Returns family, slotIndex. Returns nil, nil if it isn't a weapon skill (e.g. racial).
function SkillConfig.FindSkillSlot(skillName)
	for weaponName, list in pairs(SkillConfig.WeaponSkills) do
		for i, name in ipairs(list) do
			if name == skillName then
				return SkillConfig.WeaponFamily[weaponName], i
			end
		end
	end
	return nil, nil
end

return SkillConfig