-- DashConfig: the single tuning table for weapon-attack dashes.
--
-- A "dash" here means exactly one thing: the forward BodyVelocity a weapon swing
-- applies to the ATTACKER. Q dashes, sprint, skill dashes (SkillFunctions), racial
-- dashes (RacialSkills) and mob/boss dashes (MobAI, BossAI) are NOT in this table and
-- nothing here touches them.
--
-- Distance closed is speed * life. A 26-speed dash at 0.3s life covers about 7.8
-- studs. Tune `speed` to change how far a move carries. Tune `life` only to change
-- how the burst reads, because a short life feels like a snap and a long one like a
-- glide.
--
-- Call sites (every one of them reads this table, nothing hardcodes a dash anymore):
--   M1Finisher     ReplicatedStorage.localHandler.Combat._Shared.M1
--   M1Air          ReplicatedStorage.localHandler.Combat._Shared.M1
--   M1Lunge        ServerScriptService.modules.LungeService, started by CombatCore
--   M2             ServerScriptService.root.serverFramework.Combat._Shared.CombatCore
--   E              ReplicatedStorage.localHandler.Combat._Shared.E
--   TantoE1/E2     ServerScriptService.root.serverFramework.Combat.Tanto.E
--   ShacklesM2     ServerScriptService.root.serverFramework.Combat.Shackles.M2
--   ShacklesM2Air  ReplicatedStorage.localHandler.Combat.Shackles.M2

local DashConfig = {}

-- [[ GUARD RAILS ]] --
-- Every value that leaves Get() passes through these unless the entry is exempt.
-- They exist so a later edit cannot quietly reintroduce a 75-speed gap-closer
-- without raising the ceiling here, deliberately, in one visible place.
DashConfig.MAX_SPEED = 50
DashConfig.MIN_LIFE = 0.2

-- [[ MOVE DEFAULTS ]] --
-- speed = 0 disables the dash. Get() returns nil and the call site skips the
-- BodyVelocity entirely. Nothing else about the move changes: animation, FX,
-- hitbox and timing all stay exactly where they were.
--
-- exempt = true skips both guard rails. Reserved for bespoke multi-part moves whose
-- numbers are the move design, not a balance dial.
local DEFAULTS = {
	-- Last hit of the M1 string. The dash is off: the finisher no longer travels.
	-- Put a speed here to bring it back. Watch for whiffs if you do not, because M1
	-- knockback drifts the target backward over the string and this dash used to pay
	-- for that drift.
	M1Finisher = { speed = 0, life = 0.3 },

	-- M1 in freefall. Deliberately unchanged. Its call site also pins Y velocity at
	-- zero (MaxForce.Y = 9999) and that is what produces the air hang. The hang is
	-- intended, and it lives at the call site, not here.
	M1Air = { speed = 45, life = 0.3 },

	-- The running attack step-in. LungeService uses this as the raw boost velocity
	-- and as its chase speed cap. It is no longer multiplied by anything: the old
	-- BURST_MULT of 1.35 is gone and these are the final numbers.
	M1Lunge = { speed = 35, life = 0.3 },

	M2 = { speed = 26, life = 0.3 },

	-- E is uniform. The fist family used to run 75 here and no longer does.
	E = { speed = 50, life = 0.3 },

	-- [[ BESPOKE MOVES ]] --
	-- Tanto E is a short step followed by a longer one, because the move is multihit.
	-- Both halves are the move design. Unchanged, and exempt from the rails.
	TantoE1 = { speed = 35, life = 0.3 },
	TantoE2 = { speed = 60, life = 0.1, exempt = true },

	-- Shackles M2 does not route through CombatCore, so it never read the shared M2
	-- value and still does not. Unchanged.
	ShacklesM2 = { speed = 35, life = 0.3 },
	ShacklesM2Air = { speed = 45, life = 0.4 },
}

-- [[ PER-WEAPON OVERRIDES ]] --
-- Only what actually differs from the defaults above. Anything absent falls through.
local OVERRIDES = {
	-- The fist family keeps its gap-closing identity on M2, at a smaller edge than
	-- before: 40 against 26 instead of 60 against 35.
	Caestus = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },
	Fists = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },
	Shackles = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },

	-- Longer reach weapons step in further on the running attack.
	Excalibur = { M1Lunge = { speed = 50 } },
	Guandao = { M1Lunge = { speed = 50 } },
	Katana = { M1Lunge = { speed = 50 } },
	Scythe = { M1Lunge = { speed = 50 } },
	Sword = { M1Lunge = { speed = 50 } },
	Vermillion = { M1Lunge = { speed = 50 } },

	-- Greatsword, Dragon Slayer, Deathbringer, Dagger and Tanto sit at the 35 lunge
	-- default and need no entry.
}

-- Returns speed, life for a move, or nil when the dash is disabled.
--
--   local speed, life = DashConfig.Get("M2", "Katana")
--   if speed then ... end
--
-- `weapon` is optional. Omit it for moves that only one weapon owns.
function DashConfig.Get(move, weapon)
	local base = DEFAULTS[move]
	if not base then
		warn("[DashConfig] unknown move key: " .. tostring(move))
		return nil
	end

	local speed = base.speed
	local life = base.life

	local weaponEntry = weapon and OVERRIDES[weapon]
	local override = weaponEntry and weaponEntry[move]
	if override then
		if override.speed then
			speed = override.speed
		end
		if override.life then
			life = override.life
		end
	end

	if speed <= 0 then
		return nil
	end

	if not base.exempt then
		if speed > DashConfig.MAX_SPEED then
			speed = DashConfig.MAX_SPEED
		end
		if life < DashConfig.MIN_LIFE then
			life = DashConfig.MIN_LIFE
		end
	end

	return speed, life
end

return DashConfig
