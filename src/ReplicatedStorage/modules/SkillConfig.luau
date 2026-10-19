-- SPDX-License-Identifier: MIT
--
-- Every skill: which weapon or race has it, its mana cost, cooldown, and type, the
-- weapon families, and the hybrid weapon rules. The family and hybrid design is in
-- docs/systems-design.md.

local SkillConfig = {}

-- The Z, X, and C skills of each weapon.
SkillConfig.WeaponSkills = {
	["Greatsword"] = { "Whirlwind", "Abyssal Scream", "Berserker Armor" },
	["Dragon Slayer"] = { "Whirlwind", "Abyssal Scream", "Berserker Armor" },
	["Deathbringer"] = { "Whirlwind", "Abyssal Scream", "Berserker Armor" },

	["Sword"] = { "Elfin Dance", "Air Wave", "Morgan" },
	["Excalibur"] = { "Elfin Dance", "Air Wave", "Morgan" },

	["Fists"] = {},
	["Caestus"] = { "Mantra Palm", "Monastic Stance", "Rising Dragon" },
	["Shackles"] = { "Gohadoken", "Asura Glide", "Messatsu" },

	["Katana"] = { "Zanshin", "Kurai", "Kirikizu" },
	["Vermillion"] = { "Zanshin", "Kurai", "Kirikizu" },

	["Dagger"] = { "Hidden Daggers", "Ying Yang Spiral", "Mystic Eyes" },
	["Tanto"] = { "Hidden Daggers", "Ying Yang Spiral", "Mystic Eyes" },

	["Guandao"] = { "Downward Cleave", "Tianshi", "Dao" },

	["Scythe"] = {},
}

-- The racial skill of each race, keyed by the Race value in PlayerStats.
SkillConfig.RaceSkills = {
	["Human"] = "Adrenaline Surge",
	["Elezen"] = "Arcane Siphon",
	["Seer"] = "Null Gaze",
	["Meskar"] = "Spectre Round",
	["Karu"] = "Headbutt",
	["Verdis"] = "Root Prison",
	["Marasi"] = "Tidal Slug",
	["Cruor"] = "Parasitic Impale",
	["Arach"] = "Silk Grasp",
	["Maw"] = "Void Crunch",
	["Ancestor"] = "Vampire Drain",
	["Grob"] = "Jury-Rigged Bomb",
	["Aegir"] = "Draco Kick",
}

-- The cost, cooldown, and type of every skill.
SkillConfig.Skills = {
	-- Dragon Slayer.
	["Whirlwind"] = { Mana = 25, Cooldown = 6 },
	["Abyssal Scream"] = { Mana = 35, Cooldown = 25 },
	["Berserker Armor"] = { Mana = 50, Cooldown = 60, Type = "Buff" },

	-- Excalibur.
	["Elfin Dance"] = { Mana = 20, Cooldown = 4 },
	["Air Wave"] = { Mana = 30, Cooldown = 6 },
	["Morgan"] = { Mana = 60, Cooldown = 15 },

	-- Caestus.
	["Mantra Palm"] = { Mana = 15, Cooldown = 4 },
	["Monastic Stance"] = { Mana = 30, Cooldown = 25, Type = "Buff" },
	["Rising Dragon"] = { Mana = 35, Cooldown = 8 },

	-- Shackles.
	["Gohadoken"] = { Mana = 20, Cooldown = 5 },
	["Asura Glide"] = { Mana = 10, Cooldown = 0.4 },
	["Messatsu"] = { Mana = 40, Cooldown = 25 },

	-- Vermillion.
	["Zanshin"] = { Mana = 15, Cooldown = 6, HPCost = 5 },
	["Kurai"] = { Mana = 15, Cooldown = 5 },
	["Kirikizu"] = { Mana = 25, Cooldown = 10, HPCost = 10 },

	-- Tanto.
	["Hidden Daggers"] = { Mana = 15, Cooldown = 8 },
	["Ying Yang Spiral"] = { Mana = 20, Cooldown = 10 },
	["Mystic Eyes"] = { Mana = 50, Cooldown = 60, Type = "Buff" },

	-- Guandao.
	["Downward Cleave"] = { Mana = 20, Cooldown = 10 },
	["Tianshi"] = { Mana = 25, Cooldown = 14 },
	["Dao"] = { Mana = 30, Cooldown = 15 },

	-- Racial skills. The comment names the race in the lore.
	["Adrenaline Surge"] = { Mana = 0, Cooldown = 60, Type = "Buff" }, -- Vermeer.
	["Arcane Siphon"] = { Mana = 0, Cooldown = 60 }, -- Albin.
	["Null Gaze"] = { Mana = 60, Cooldown = 30 }, -- Aphanis.
	["Spectre Round"] = { Mana = 20, Cooldown = 7 }, -- Ossuar.
	["Headbutt"] = { Mana = 20, Cooldown = 20 }, -- Karu.
	["Root Prison"] = { Mana = 35, Cooldown = 35 }, -- Chloris.
	["Tidal Slug"] = { Mana = 30, Cooldown = 10 }, -- Glaucus.
	["Parasitic Impale"] = { Mana = 30, Cooldown = 25 }, -- Cruor.
	["Silk Grasp"] = { Mana = 20, Cooldown = 10 }, -- Skotos.
	["Void Crunch"] = { Mana = 30, Cooldown = 15 }, -- Porphyr.
	["Vampire Drain"] = { Mana = 15, Cooldown = 20 }, -- Caelum.
	["Jury-Rigged Bomb"] = { Mana = 5, Cooldown = 30 }, -- Virdis.
	["Draco Kick"] = { Mana = 25, Cooldown = 10 }, -- Aegir.
}

-- The family of each weapon. Branch weapons share the family of their seed weapon, so
-- skills from both branches (for example Monk Z and Akuma X) fit in one loadout.
-- Hybrids are their own family, because they have their own skill lists.
SkillConfig.WeaponFamily = {
	["Fists"] = "Fists",
	["Caestus"] = "Fists",
	["Shackles"] = "Fists",

	["Sword"] = "Sword",
	["Excalibur"] = "Sword",

	["Katana"] = "Katana",
	["Vermillion"] = "Katana",

	["Dagger"] = "Dagger",
	["Tanto"] = "Dagger",

	["Greatsword"] = "Greatsword",
	["Dragon Slayer"] = "Greatsword",
	["Deathbringer"] = "Greatsword",

	["Guandao"] = "Guandao",
	["Scythe"] = "Scythe",
}

-- The two parent families of each hybrid weapon. A hybrid has no XP bar or class quests
-- of its own: swinging it gives half the XP to each parent, and its skills unlock when
-- both parents reach a level.
SkillConfig.HybridParents = {
	["Guandao"] = { "Sword", "Dagger" },
	["Scythe"] = { "Greatsword", "Dagger" },
}

-- The level that both parents need for each hybrid skill, by slot (1 = Z, 2 = X,
-- 3 = C), and for the hybrid weapon itself.
SkillConfig.HybridSkillThresholds = { [1] = 15, [2] = 20, [3] = 25 }
SkillConfig.HybridUnlockLevel = 10

-- SkillConfig.IsHybrid() - check whether a weapon is a hybrid
-- @weaponName: the weapon name
--
-- Return: true for a hybrid, which feeds two parent families.
function SkillConfig.IsHybrid(weaponName)
	return SkillConfig.HybridParents[weaponName] ~= nil
end

-- SkillConfig.GetXPFamily() - get the family whose XP bar a weapon feeds
-- @weaponName: the weapon name
--
-- Return: the family, or nil for a hybrid (use HybridParents) or an unknown weapon.
function SkillConfig.GetXPFamily(weaponName)
	if SkillConfig.HybridParents[weaponName] then
		return nil
	end
	return SkillConfig.WeaponFamily[weaponName]
end

-- The slot keys by slot index, as used in EquippedSkills.
SkillConfig.SlotKeys = { [1] = "Z", [2] = "X", [3] = "C" }

-- SkillConfig.GetSlotIndex() - find the slot of a skill in a family
-- @family: the weapon family
-- @skillName: the skill name
--
-- Searches every weapon of the family.
--
-- Return: the slot index (1 = Z, 2 = X, 3 = C), or nil.
function SkillConfig.GetSlotIndex(family, skillName)
	for weaponName, fam in pairs(SkillConfig.WeaponFamily) do
		if fam == family then
			local list = SkillConfig.WeaponSkills[weaponName]
			if list then
				for i, name in ipairs(list) do
					if name == skillName then
						return i
					end
				end
			end
		end
	end
	return nil
end

-- SkillConfig.FindSkillSlot() - find the family and slot of a skill
-- @skillName: the skill name
--
-- Return: the family and slot index, or nil, nil for a skill that is not a weapon
-- skill, such as a racial skill.
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
