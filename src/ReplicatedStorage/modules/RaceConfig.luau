local RaceConfig = {}

-- Rarity Weights (Higher number = More common)
RaceConfig.Rarities = {
	{ Name = "Common", Weight = 40, Color = Color3.fromRGB(203, 203, 203) }, -- 50
	{ Name = "Uncommon", Weight = 30, Color = Color3.fromRGB(125, 205, 165) }, -- 30
	{ Name = "Rare", Weight = 15, Color = Color3.fromRGB(96, 146, 255) }, -- 15
	{ Name = "Epic", Weight = 10, Color = Color3.fromRGB(162, 96, 255) },
	{ Name = "Legendary", Weight = 5, Color = Color3.fromRGB(255, 53, 53) },
}

RaceConfig.Races = {
	-- [[ COMMON ]] --
	["Human"] = {
		Rarity = "Common",
		Stats = { HPBoost = 10 },
		Visuals = {
			SkinColor = Color3.fromRGB(255, 204, 153),
			HairColor = Color3.fromRGB(100, 50, 16),
		},
		Description = "Resilient and adaptable, they have withstood countless battles throughout history.",
	},

	["Elezen"] = {
		Rarity = "Common",
		Stats = { HPBoost = 5, ManaBoost = 1.3 },
		Visuals = {
			SkinColor = Color3.fromRGB(226, 220, 188),
			HairColor = Color3.fromRGB(255, 255, 255),
			Accessory = "ElfEars",
		},
		Description = "Avid scholars, enjoyers of nature.",
	},

	["Grob"] = {
		Rarity = "Common",
		Stats = { LiturgyMultiplier = 1.25, ManaBoost = 1.2 },
		Visuals = {
			SkinColor = Color3.fromRGB(138, 171, 133),
			HairColor = Color3.fromRGB(50, 100, 50),
			Accessory = "GoblinEars",
		},
		Description = "Greedy scavengers, creatures spat out of the Void.",
	},

	-- [[ UNCOMMON ]] --

	["Verdis"] = {
		Rarity = "Uncommon",
		Stats = { RegenMultiplier = 2.0, HPBoost = 15 },
		Visuals = {
			SkinColor = Color3.fromRGB(141, 200, 123),
			HairColor = Color3.fromRGB(43, 74, 38),
		},
		Description = "Experiments of the Elezen attempting to recreate nature.",
	},

	["Arach"] = {
		Rarity = "Uncommon",
		Stats = { HPBoost = 10, DefenseBoost = 1.2, JumpBoost = 1.5 },
		Visuals = {
			SkinColor = Color3.fromRGB(40, 40, 40),
			HairColor = Color3.fromRGB(45, 0, 0),
			Accessories = { "SpiderFangs", "SpiderEyes" },
		},
		Description = "'Go out there and show them what we can truly do as a group.' -Spider Queen Quelana.",
	},

	-- [[ RARE ]] --

	["Cruor"] = {
		Rarity = "Rare",
		Stats = { HPBoost = 20 },
		Visuals = {
			InvisibleRArm = true,
			SkinColor = Color3.fromRGB(150, 85, 85),
			HairColor = Color3.fromRGB(98, 51, 51),
			RightArm = "RightArmSpike",
		},
		Description = "An abomination made of flesh.",
	},

	["Karu"] = {
		Rarity = "Rare",
		Stats = { HPBoost = 30, DefenseBoost = 1.15 },
		Visuals = {
			SkinColor = Color3.fromRGB(108, 88, 75),
			HairColor = Color3.fromRGB(191, 181, 176),
			Accessories = { "RamHorns", "GoatTail" },
		},
		Description = "Sturdy mountain dwellers.",
	},

	["Meskar"] = {
		Rarity = "Rare",
		Stats = { DashDuration = 0.4, SlideDuration = 5.0, HPBoost = -5, ManaBoost = 1.75 },
		Visuals = {
			SkinColor = Color3.fromRGB(160, 160, 160),
			HairColor = Color3.fromRGB(255, 255, 255),
			Accessory = "SkullFace",
		},
		Description = "Nimble, but very fragile.",
	},

	-- [[ EPIC ]] --

	["Marasi"] = {
		Rarity = "Epic",
		Stats = { HPBoost = 25, DefenseBoost = 1.3 },
		Visuals = {
			SkinColor = Color3.fromRGB(110, 153, 202),
			HairColor = Color3.fromRGB(56, 73, 140),
			Accessory = "SharkFins",
		},
		Description = "Akin to sharks, their determination stood the test of time.",
	},

	["Seer"] = {
		Rarity = "Epic",
		Stats = { ESP = true, HPBoost = 10, DefenseBoost = 1.2, ManaBoost = 2 },
		Visuals = {
			InvisibleHead = true,
			SkinColor = Color3.fromRGB(100, 100, 100),
			HairColor = Color3.fromRGB(0, 0, 0),
			Accessory = "seerParticle",
		},
		Description = "The eye sees all who dare cross its path...",
	},

	-- [[ LEGENDARY ]] --

	["Maw"] = {
		Rarity = "Legendary",
		Stats = { HPBoost = 35, ManaBoost = 1.75, RegenMultiplier = 1.75, DefenseBoost = 1.1 },
		Visuals = {
			InvisibleHead = true,
			InvisibleHair = true,
			SkinColor = Color3.fromRGB(84, 73, 128),
			HairColor = Color3.fromRGB(57, 57, 99),
			Accessories = { "mawHead2", "mawHeadTop" },
		},
		Description = "Creatures of the void, masters of wyrmholes.",
	},

	["Ancestor"] = {
		Rarity = "Legendary",
		Stats = { HPBoost = 25, RegenMultiplier = 1.5, Lifesteal = true, ManaBoost = 1.5 },
		Visuals = {
			SkinColor = Color3.fromRGB(255, 236, 205),
			HairColor = Color3.fromRGB(254, 244, 221),
			Accessory = "RedHalo",
		},
		Description = "...?",
	},

	["Aegir"] = {
		Rarity = "Legendary",
		Stats = { ManaWhenHit = true, HPBoost = 40, ManaBoost = 2, RegenMultiplier = 1.75 },
		Visuals = {
			SkinColor = Color3.fromRGB(205, 205, 205),
			HairColor = Color3.fromRGB(248, 248, 248),
			Accessory = "dragonHorns",
		},
		Description = "An ancient race of the skies, left to remnants of their former glory.",
	},
}

return RaceConfig
