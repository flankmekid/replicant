--!strict
-- SPDX-License-Identifier: MIT
--
-- The values of every weapon, for the client and the server: animations, sounds,
-- cooldowns, damage, hitboxes, and timing. Dash speeds are in DashConfig. The timing
-- design (for example server.e.eRecovery) is in docs/combat-design.md.

local C = {}

-- The uppercut juggle. The client M1 (the attacker's rise) and CombatCore (the
-- victim's launch) both read it, so they always agree on the apex.
C.Uppercut = {
	RiseHeight = 14, -- Studs that both rise from their own footing.
	Offset = 4, -- Studs that the victim is placed ahead of the attacker.
	HangWindow = 1.2, -- Seconds at the apex.
	Responsiveness = 30, -- AlignPosition ease: higher snaps up faster.
}

-- The family field groups weapons that share a moveset, so shared code can ask whether
-- a weapon is a greatsword. Do not use xpName for that: xpName only redirects XP (nil
-- means the weapon's own track). A weapon built from a family base gets its family.

-- Deep-merges override onto a copy of base. A list replaces the whole base list, so it
-- never keeps the tail of a longer base list. Everything is copied, so two weapons
-- built from one base cannot change each other.
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

local function merge(base: any, override: any): any
	local out = deepCopy(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(out[k]) == "table" and v[1] == nil then
			out[k] = merge(out[k], v)
		else
			out[k] = deepCopy(v)
		end
	end
	return out
end

-- Sets the cooldown keys "<weapon>_M2" and "<weapon>_E".
local function withCooldownKeys(name: string, cfg: any): any
	cfg.client.m2.cdKey = name .. "_M2"
	cfg.client.e.cdKey = name .. "_E"
	return cfg
end

-- The greatsword base. Greatsword, Dragon Slayer, and Deathbringer differ only in
-- damage, the M2 shape, and the trail model.
local GreatswordBase = {
	family = "Greatsword",
	client = {
		m1 = {
			cooldown = 0.8,
			comboAnims = {
				"rbxassetid://75252982138756",
				"rbxassetid://83321379404970",
				"rbxassetid://75252982138756",
				"rbxassetid://83321379404970",
				"rbxassetid://12074819641",
			},
			lungeAnim = "rbxassetid://12074847009",
			airAnim = "rbxassetid://120024992814931",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.3,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 6,
			animID = "rbxassetid://140565464786135",
			cdTag = "Critical",
			cdTime = 6,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://89138660171326",
			cdTag = "E",
			cdTime = 3.6,
			eWindupWait = 0.6,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://75746825553579",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 10,
			windup = 0.6,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.3,
			swingSoundFunc = "Swing",
			-- The xpName field is absent: nil means the weapon's own XP track. A merge
			-- cannot set a value back to nil, so the variants that use the Greatsword track
			-- set it below.
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(11, 7, 11),
			hitboxOffset = CFrame.new(0, 0, -5),
			comboMap = { "R", "L", "R", "L", "R", "-", "-", "U" },
			swingFX = { folder = "GSSlashes", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 13,
			windup = 0.6,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 11, 9),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 2, 16 },
			swingFX = { folder = "GSSlashes", slash = "SlashFXUp", part = "HumanoidRootPart" },
			hitboxOffset = CFrame.new(0, 0, -5),
		},
		e = {
			dmg = 11,
			windup = 0.7,
			guardbreak = false,
			eRecovery = 0.3,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(14, 7, 12),
			swingFX = { folder = "GSSlashes", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
		},
	},
	tool = { weldPart = "Greatsword", idleAnim = "rbxassetid://12074709199" },
}

C["Caestus"] = {
	client = {
		m1 = {
			cooldown = 0.5,
			comboAnims = {
				"rbxassetid://120522365139110",
				"rbxassetid://118388583927592",
				"rbxassetid://134477588734123",
				"rbxassetid://83421056516300",
				"rbxassetid://127652739314319",
			},
			lungeAnim = "rbxassetid://131646776816840",
			airAnim = "rbxassetid://89409612525164",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://89428867846129",
			cdKey = "Caestus_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 2,
			animID = "rbxassetid://129341879780968",
			cdKey = "Caestus_E",
			cdTag = "E",
			cdTime = 2.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://78626426378686",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "PunchSound",
			m2Swing = "PunchSound",
			eSwing = "PunchSound",
			hit = "PunchHit",
			gb = "PunchHit",
		},
	},
	server = {
		m1 = {
			dmg = 7,
			windup = 0.333,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 14, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "PunchSound",
			xpName = "Fists",
			trailBlade = nil,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 6, 8),
			hitboxOffset = CFrame.new(1, -1, -4),
			comboMap = { "R", "L", "R", "L", "R", "U", "RLU", "U" },
			swingFX = {
				folder = "FistSlashWhite",
				rightPart = "Torso",
				upPart = "HumanoidRootPart",
			},
		},
		m2 = {
			dmg = 6,
			windup = 0.66,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 7, 6),
			hitboxDuration = 0.2,
			postCooldown = 4,
			setSpeed = { 14, 16 },
			swingFX = { folder = "FistSlashWhite", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -3),
			xpName = "Fists",
		},
		e = {
			dmg = 7,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 6, 8),
			swingFX = { folder = "FistSlashWhite", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 14, 16 },
			xpName = "Fists",
			trailBlade = nil,
		},
	},
	tool = { weldPart = nil, idleAnim = "rbxassetid://102436755105644" },
}

C["Dagger"] = {
	client = {
		m1 = {
			cooldown = 0.4,
			comboAnims = {
				"rbxassetid://113064652209163",
				"rbxassetid://139414553077908",
				"rbxassetid://129665787591050",
				"rbxassetid://132164060511681",
				"rbxassetid://135589429108202",
			},
			lungeAnim = "rbxassetid://116928872151839",
			airAnim = "rbxassetid://131630220640395",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = nil,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = { cooldown = 4, animID = "rbxassetid://105653775477364" },
		e = { custom = true }, -- A custom throw E in its own module.
		block = {
			blockAnim = "rbxassetid://88771475533388",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "dagger.daggerSwing",
			m2Swing = "dagger.daggerLunge",
			eSwing = "dagger.daggerSwing",
			hit = "dagger.daggerHit",
			gb = "dagger.daggerHit",
		},
	},
	server = {
		m1 = {
			dmg = 5,
			windup = 0.3,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = nil,
			trailBlade = { model = "Dagger", part = "Blade" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(5, 4, 5),
			hitboxOffset = CFrame.new(1, -1, -4),
			comboMap = { "L", "R", "L", "R", "L", "U", "RLU", "U" },
			swingFX = { folder = "slashFX", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 7,
			windup = 0.6,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 7, 6),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -3),
			xpName = nil,
		},
		e = {
			dmg = 6,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(5, 4, 5),
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = "Blade", idleAnim = "rbxassetid://124925225124105" },
}

-- Deathbringer and Dragon Slayer are the greatsword base with more damage. Their XP
-- goes to the Greatsword track.
C["Deathbringer"] = withCooldownKeys(
	"Deathbringer",
	merge(GreatswordBase, {
		server = {
			m1 = {
				xpName = "Greatsword",
				trailBlade = { model = "Deathbringer", part = "Greatsword" },
			},
			m2 = { xpName = "Greatsword" },
			e = {
				xpName = "Greatsword",
				trailBlade = { model = "Deathbringer", part = "Greatsword" },
			},
		},
	})
)

C["Dragon Slayer"] = withCooldownKeys(
	"Dragon Slayer",
	merge(GreatswordBase, {
		server = {
			m1 = {
				xpName = "Greatsword",
				trailBlade = { model = "Dragon Slayer", part = "Greatsword" },
			},
			m2 = { xpName = "Greatsword" },
			e = {
				xpName = "Greatsword",
				trailBlade = { model = "Dragon Slayer", part = "Greatsword" },
			},
		},
	})
)

C["Excalibur"] = {
	client = {
		m1 = {
			cooldown = 0.6,
			comboAnims = {
				"rbxassetid://114445073328189",
				"rbxassetid://133004135285326",
				"rbxassetid://80789854734263",
				"rbxassetid://104365254449720",
			},
			lungeAnim = "rbxassetid://127322241276345",
			airAnim = "rbxassetid://133184595696252",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 0.5,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://133000376160967",
			cdKey = "Excalibur_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://106055406798496",
			cdKey = "Excalibur_E",
			cdTag = "E",
			cdTime = 3.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://108301561470863",
			parryAnim = "rbxassetid://85755994980927",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 7,
			windup = 0.41,
			guardbreak = false,
			maxCombo = 4,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = "Sword",
			trailBlade = { model = "Excalibur", part = "Sword" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			hitboxOffset = CFrame.new(0, -1, -3),
			comboMap = { "R", "L", "R", "L", "U", "RLU", "U", "-" },
			swingFX = { folder = "slashFXPurple", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 10,
			windup = 1,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFXPurple", slash = "SlashFXDown", part = "HumanoidRootPart" },
			hitboxOffset = CFrame.new(0, -1, -3),
			xpName = "Sword",
		},
		e = {
			dmg = 8,
			windup = 0.8,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			swingFX = { folder = "slashFXPurple", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = "Sword",
			trailBlade = nil,
		},
	},
	tool = { weldPart = "Uchigatana", idleAnim = "rbxassetid://128438569605036" },
}

C["Fists"] = {
	client = {
		m1 = {
			cooldown = 0.5,
			comboAnims = {
				"rbxassetid://91594781717410",
				"rbxassetid://85174374982448",
				"rbxassetid://126029733860542",
				"rbxassetid://83421056516300",
				"rbxassetid://127652739314319",
			},
			lungeAnim = "rbxassetid://131646776816840",
			airAnim = "rbxassetid://131630220640395",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://120719298691152",
			cdKey = "Fists_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 2,
			animID = "rbxassetid://129341879780968",
			cdKey = "Fists_E",
			cdTag = "E",
			cdTime = 2.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://90274625983274",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "PunchSound",
			m2Swing = "PunchSound",
			eSwing = "PunchSound",
			hit = "PunchHit",
			gb = "PunchHit",
		},
	},
	server = {
		m1 = {
			dmg = 4,
			windup = 0.333,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "PunchSound",
			xpName = nil,
			trailBlade = nil,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 6, 6),
			hitboxOffset = CFrame.new(1, -1, -4),
			comboMap = { "L", "R", "L", "L", "R", "U", "RLU", "U" },
			swingFX = {
				folder = "FistSlashWhite",
				rightPart = "Torso",
				upPart = "HumanoidRootPart",
			},
		},
		m2 = {
			dmg = 6,
			windup = 0.5,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 7, 6),
			hitboxDuration = 0.2,
			postCooldown = 4,
			setSpeed = { 4, 16 },
			swingFX = { folder = "FistSlashWhite", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -3),
			xpName = nil,
		},
		e = {
			dmg = 6,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 6, 8),
			swingFX = { folder = "FistSlashWhite", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = nil, idleAnim = "rbxassetid://96039324012000" },
}

-- The base greatsword: a slower, weaker M2 (a wide 1.2-second sweep instead of the
-- quick 0.2-second stab of the variants), and its own XP track.
C["Greatsword"] = withCooldownKeys(
	"Greatsword",
	merge(GreatswordBase, {
		client = {
			m2 = { cooldown = 7, animID = "rbxassetid://140565464786135", cdTime = 7 },
		},
		server = {
			m1 = { dmg = 8, trailBlade = { model = "Greatsword", part = "Greatsword" } },
			m2 = {
				dmg = 5,
				windup = 0.6,
				hitboxSize = Vector3.new(11, 7, 11),
				hitboxDuration = 0.2,
				swingFX = { slash = "SlashFXDown" },
			},
			e = {
				dmg = 9,
				hitboxSize = Vector3.new(12, 7, 11),
				trailBlade = { model = "Greatsword", part = "Greatsword" },
			},
		},
	})
)

C["Guandao"] = {
	client = {
		m1 = {
			cooldown = 0.6,
			comboAnims = {
				"rbxassetid://82285313584065",
				"rbxassetid://82661079692126",
				"rbxassetid://82285313584065",
				"rbxassetid://82661079692126",
			},
			lungeAnim = "rbxassetid://104237193184444",
			airAnim = "rbxassetid://125596523289062",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://104185970724824",
			cdKey = "Guandao_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://83720949515827",
			cdKey = "Guandao_E",
			cdTag = "E",
			cdTime = 3,
			eWindupWait = 0.6,
			eAnimSpeed = 1,
		},
		block = {
			blockAnim = "rbxassetid://108301561470863",
			parryAnim = "rbxassetid://85755994980927",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 8,
			windup = 0.5,
			guardbreak = false,
			maxCombo = 4,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = nil,
			trailBlade = { model = "Guandao", part = "guandaoBlade" },
			hitboxShape = "InRadius",
			hitboxSize = 7,
			hitboxOffset = CFrame.new(0, -1, -5),
			comboMap = { "L", "R", "L", "R", "U", "RLU", "U" },
			swingFX = {
				folder = "guandao.FireSlashes",
				rightPart = "HumanoidRootPart",
				upPart = "HumanoidRootPart",
			},
		},
		m2 = {
			dmg = 12,
			windup = 0.6,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "guandao.FireSlashes", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(0, -1, -3),
			xpName = nil,
		},
		e = {
			dmg = 9,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			swingFX = { folder = "guandao.FireSlashes", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = "mainPart", idleAnim = "rbxassetid://74843814604044" },
}

C["Katana"] = {
	client = {
		m1 = {
			cooldown = 0.6,
			comboAnims = {
				"rbxassetid://114445073328189",
				"rbxassetid://133004135285326",
				"rbxassetid://80789854734263",
				"rbxassetid://104365254449720",
				"rbxassetid://133831562453891",
			},
			lungeAnim = "rbxassetid://106820530333875",
			airAnim = "rbxassetid://133184595696252",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://99454982620637",
			cdKey = "Katana_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://105034588643859",
			cdKey = "Katana_E",
			cdTag = "E",
			cdTime = 3.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://108301561470863",
			parryAnim = "rbxassetid://85755994980927",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 7,
			windup = 0.41,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = nil,
			trailBlade = { model = "Katana", part = "Uchigatana" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 8),
			hitboxOffset = CFrame.new(0, 0, -2),
			comboMap = { "R", "L", "R", "L", "R", "U", "RLU", "U" },
			swingFX = { folder = "slashFX", rightPart = "Torso", upPart = "HumanoidRootPart" },
			trail = { model = "Katana", blade = "Uchigatana" },
		},
		m2 = {
			dmg = 10,
			windup = 1,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFX", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(0, 0, -3),
			xpName = nil,
		},
		e = {
			dmg = 8,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(11, 7, 9),
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(0, 0, -3),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = "Uchigatana", idleAnim = "rbxassetid://119845449014322" },
}

C["Scythe"] = {
	client = {
		m1 = {
			cooldown = 0.7,
			comboAnims = {
				"rbxassetid://126088969753717",
				"rbxassetid://96445225762196",
				"rbxassetid://91896980557009",
				"rbxassetid://124620041655915",
			},
			lungeAnim = "rbxassetid://104237193184444",
			airAnim = "rbxassetid://125596523289062",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://104185970724824",
			cdKey = "Scythe_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://83720949515827",
			cdKey = "Scythe_E",
			cdTag = "E",
			cdTime = 3.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1,
		},
		block = {
			blockAnim = "rbxassetid://108301561470863",
			parryAnim = "rbxassetid://85755994980927",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 8,
			windup = 0.6,
			guardbreak = false,
			maxCombo = 4,
			setSpeed = { 8, 16 },
			lungeWait = 0.7,
			swingSoundFunc = "Swing",
			xpName = nil,
			trailBlade = { model = "Scythe", part = "mainPart" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			hitboxOffset = CFrame.new(0, 0, -2),
			comboMap = { "L", "R", "L", "R", "L", "U", "RLU", "U" },
			swingFX = { folder = "GSSlashes", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 10,
			windup = 0.6,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFX", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(0, -1, -3),
			xpName = nil,
		},
		e = {
			dmg = 9,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = "mainPart", idleAnim = "rbxassetid://74843814604044" },
}

C["Shackles"] = {
	client = {
		m1 = {
			cooldown = 0.5,
			comboAnims = {
				"rbxassetid://91594781717410",
				"rbxassetid://85174374982448",
				"rbxassetid://126029733860542",
				"rbxassetid://83421056516300",
				"rbxassetid://127652739314319",
			},
			lungeAnim = "rbxassetid://12084988940",
			airAnim = "rbxassetid://131630220640395",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://112488887193091",
			cdKey = "Shackles_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 2,
			animID = "rbxassetid://129341879780968",
			cdKey = "Shackles_E",
			cdTag = "E",
			cdTime = 2.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://90274625983274",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "PunchSound",
			m2Swing = "PunchSound",
			eSwing = "PunchSound",
			hit = "PunchHit",
			gb = "PunchHit",
		},
	},
	server = {
		m1 = {
			dmg = 7,
			windup = 0.333,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 14, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "PunchSound",
			xpName = "Fists",
			trailBlade = nil,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 6, 8),
			hitboxOffset = CFrame.new(1, -1, -3),
			comboMap = { "L", "R", "L", "L", "R", "U", "RLU", "U" },
			swingFX = { folder = "FistSlash", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 12,
			windup = 0.9,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 7, 6),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 14, 16 },
			swingFX = { folder = "FistSlash", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -3),
			xpName = "Fists",
		},
		e = {
			dmg = 7,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 6, 8),
			swingFX = { folder = "FistSlash", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 14, 16 },
			xpName = "Fists",
			trailBlade = nil,
		},
	},
	tool = { weldPart = nil, idleAnim = "rbxassetid://76184287408728" },
}

C["Sword"] = {
	client = {
		m1 = {
			cooldown = 0.6,
			comboAnims = {
				"rbxassetid://95741265754072",
				"rbxassetid://137684081723536",
				"rbxassetid://95741265754072",
				"rbxassetid://137684081723536",
			},
			lungeAnim = "rbxassetid://109278941983106",
			airAnim = "rbxassetid://85616104803022",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 0.5,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://137977683268052",
			cdKey = "Sword_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://137684081723536",
			cdKey = "Sword_E",
			cdTag = "E",
			cdTime = 3.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://98445666179570",
			parryAnim = "rbxassetid://128724578433172",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 7,
			windup = 0.41,
			guardbreak = false,
			maxCombo = 4,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = nil,
			trailBlade = { model = "Sword", part = "ExHandle" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 8),
			hitboxOffset = CFrame.new(0, -1, -3),
			comboMap = { "R", "L", "R", "L", "U", "RLU", "U", "-" },
			swingFX = { folder = "slashFX", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 10,
			windup = 1,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFX", slash = "SlashFXUp", part = "HumanoidRootPart" },
			hitboxOffset = CFrame.new(0, -1, -3),
			xpName = nil,
		},
		e = {
			dmg = 7,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = nil,
			trailBlade = nil,
		},
	},
	tool = { weldPart = nil, idleAnim = "rbxassetid://128953311847203" },
}

C["Tanto"] = {
	client = {
		m1 = {
			cooldown = 0.5,
			comboAnims = {
				"rbxassetid://113064652209163",
				"rbxassetid://139414553077908",
				"rbxassetid://129665787591050",
				"rbxassetid://132164060511681",
				"rbxassetid://135589429108202",
			},
			lungeAnim = "rbxassetid://116928872151839",
			airAnim = "rbxassetid://131630220640395",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = nil,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = { cooldown = 4, animID = "rbxassetid://105653775477364" },
		e = { custom = true }, -- A custom throw E in its own module.
		block = {
			blockAnim = "rbxassetid://88771475533388",
			parryAnim = "rbxassetid://12075933616",
		},
		sounds = {
			m1Swing = "dagger.daggerSwing",
			m2Swing = "dagger.daggerLunge",
			eSwing = "dagger.daggerSwing",
			hit = "dagger.daggerHit",
			gb = "dagger.daggerHit",
		},
	},
	server = {
		m1 = {
			dmg = 5,
			windup = 0.3,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = "Dagger",
			trailBlade = { model = "Tanto", part = "Blade" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(5, 4, 5),
			hitboxOffset = CFrame.new(1, -1, -4),
			comboMap = { "L", "R", "L", "R", "L", "U", "RLU", "U" },
			swingFX = { folder = "slashFX", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 6,
			windup = 0.6,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(6, 7, 6),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFX", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -3),
			xpName = "Dagger",
		},
		e = {
			dmg = 5,
			windup = nil,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(5, 4, 5),
			swingFX = { folder = "slashFX", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 2, 16 },
			xpName = "Dagger",
			trailBlade = nil,
		},
	},
	tool = { weldPart = "Blade", idleAnim = "rbxassetid://124925225124105" },
}

C["Vermillion"] = {
	client = {
		m1 = {
			cooldown = 0.6,
			comboAnims = {
				"rbxassetid://114445073328189",
				"rbxassetid://133004135285326",
				"rbxassetid://80789854734263",
				"rbxassetid://104365254449720",
				"rbxassetid://133831562453891",
			},
			lungeAnim = "rbxassetid://106820530333875",
			airAnim = "rbxassetid://133184595696252",
			uppercutAnim = "rbxassetid://113982059903937",
			animSpeed = 1.2,
			finisherExtraWait = 1,
			uppercutWait = 0.35,
			lungeWait = 0.5,
			airWait = 0.35,
		},
		m2 = {
			cooldown = 4,
			animID = "rbxassetid://121694381561946",
			cdKey = "Vermillion_M2",
			cdTag = "Critical",
			cdTime = 4,
		},
		e = {
			cooldown = 3,
			animID = "rbxassetid://105034588643859",
			cdKey = "Vermillion_E",
			cdTag = "E",
			cdTime = 3.4,
			eWindupWait = 0.4,
			eAnimSpeed = 1.2,
		},
		block = {
			blockAnim = "rbxassetid://108301561470863",
			parryAnim = "rbxassetid://85755994980927",
		},
		sounds = {
			m1Swing = "katana.katanaSwing",
			m2Swing = "katana.katanaLunge",
			eSwing = "katana.katanaSwing",
			hit = "katana.katanaHit",
			gb = "katana.katanaHit",
		},
	},
	server = {
		m1 = {
			dmg = 8,
			windup = 0.41,
			guardbreak = false,
			maxCombo = 5,
			setSpeed = { 8, 16 },
			lungeWait = 0.5,
			swingSoundFunc = "Swing",
			xpName = "Katana",
			trailBlade = { model = "Vermillion", part = "Uchigatana" },
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			hitboxOffset = CFrame.new(0, -1, -3),
			comboMap = { "R", "L", "R", "L", "R", "U", "RLU", "U" },
			swingFX = { folder = "slashFXRed", rightPart = "Torso", upPart = "HumanoidRootPart" },
		},
		m2 = {
			dmg = 12,
			windup = 1,
			guardbreak = true,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(7, 7, 8),
			hitboxDuration = 0.2,
			postCooldown = 3,
			setSpeed = { 4, 16 },
			swingFX = { folder = "slashFXRed", slash = "SlashFXRight", part = "Torso" },
			hitboxOffset = CFrame.new(0, -1, -3),
			xpName = "Katana",
		},
		e = {
			dmg = 9,
			windup = 0.6,
			guardbreak = false,
			hitboxShape = "InBox",
			hitboxSize = Vector3.new(9, 7, 9),
			swingFX = { folder = "slashFXRed", slash = "SlashFXLeft", part = "Torso" },
			hitboxOffset = CFrame.new(1, -1, -4),
			setSpeed = { 4, 16 },
			xpName = "Katana",
			trailBlade = nil,
		},
	},
	tool = { weldPart = "Uchigatana", idleAnim = "rbxassetid://119845449014322" },
}

return C
