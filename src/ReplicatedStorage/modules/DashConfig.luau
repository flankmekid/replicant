-- SPDX-License-Identifier: MIT
--
-- The one tuning table for weapon-attack dashes: the forward velocity that a weapon
-- swing gives the attacker. Other dashes are not here. The distance is speed times
-- life. The design and the list of call sites are in docs/combat-design.md.

local DashConfig = {}

-- Get clamps every value to these, unless the entry is exempt.
DashConfig.MAX_SPEED = 50
DashConfig.MIN_LIFE = 0.2

-- A speed of 0 turns the dash off: Get returns nil and the call site skips the mover.
-- exempt = true skips the guard rails, for multi-part moves whose numbers are the
-- move design.
local DEFAULTS = {
	-- The last hit of the M1 string. The dash is off.
	M1Finisher = { speed = 0, life = 0.3 },

	-- M1 in freefall. The air hang comes from its call site, not from this table.
	M1Air = { speed = 45, life = 0.3 },

	-- The running attack. LungeService uses this as the boost velocity and the chase
	-- speed cap.
	M1Lunge = { speed = 35, life = 0.3 },

	M2 = { speed = 26, life = 0.3 },

	E = { speed = 50, life = 0.3 },

	-- Tanto E is a short step and then a longer one, because the move is multihit.
	TantoE1 = { speed = 35, life = 0.3 },
	TantoE2 = { speed = 60, life = 0.1, exempt = true },

	-- Shackles M2 does not use CombatCore, so it has its own entries.
	ShacklesM2 = { speed = 35, life = 0.3 },
	ShacklesM2Air = { speed = 45, life = 0.4 },
}

-- Per-weapon values that differ from the defaults.
local OVERRIDES = {
	-- The fist family keeps a gap-closing M2.
	Caestus = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },
	Fists = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },
	Shackles = { M1Lunge = { speed = 50 }, M2 = { speed = 40 } },

	-- Longer weapons step in further on the running attack.
	Excalibur = { M1Lunge = { speed = 50 } },
	Guandao = { M1Lunge = { speed = 50 } },
	Katana = { M1Lunge = { speed = 50 } },
	Scythe = { M1Lunge = { speed = 50 } },
	Sword = { M1Lunge = { speed = 50 } },
	Vermillion = { M1Lunge = { speed = 50 } },
}

-- DashConfig.Get() - get the dash of a move
-- @move: the move key, such as "M2"
-- @weapon: the weapon name, or nil for a move that only one weapon has
--
-- Example: local speed, life = DashConfig.Get("M2", "Katana")
--
-- Return: the speed and life, or nil when the dash is off or the key is unknown.
function DashConfig.Get(move, weapon)
	local base = DEFAULTS[move]
	if not base then
		warn(`[DashConfig] Unknown move key {move}.`)
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
