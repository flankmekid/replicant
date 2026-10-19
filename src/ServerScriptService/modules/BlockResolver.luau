-- BlockResolver — the single chokepoint for "a hit landed on a blocking target".
--
-- Every combat site that used to inline the block branch (CombatCore's resolveHit,
-- the per-weapon M2/E overrides, SkillFunctions, RacialSkills) calls Resolve() here
-- instead. This guarantees ONE consistent set of rules for: facing check, guard-bar
-- fill/drain/break, chip vs full damage, and frame advantage. It also means the
-- guard bar reacts identically to every attack type in the game.
--
-- Design (locked with author):
--   * Blocked E  -> DEFENDER is plus: the attacker eats a short recovery stun.
--   * Blocked M1 -> roughly NEUTRAL: small chip, nobody gains meaningful advantage.
--   * Guardbreak attacks (cfg.guardbreak; in current data that is every M2) BYPASS
--     the bar and break the guard outright (full damage). They never fill the bar.
--   * A hit from the side/back (outside the block cone) bypasses the block entirely.
--   * Non-guardbreak blocked hits FILL the blocker's guard bar. If the bar was
--     already full, this hit triggers a block-break (one hit of grace at full).
--
-- Resolve() performs the guard-bar + state side effects itself and returns a verdict
-- telling the CALLER how to apply its own damage/knockback/FX (which vary per weapon
-- and per skill, so they stay at the call site).
--
--   verdict = {
--     outcome    = "Blocked" | "GuardBreak" | "Bypass",
--     broke      = boolean,  -- this hit caused a block-break
--     chipDamage = number,   -- damage the caller should deal (0 for none)
--     knockback  = number,   -- knockback the caller should apply
--   }

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local StateHandler = require(RP.modules.stateHandler)
local GuardBarService = require(SSS.modules.GuardBarService)

local BlockResolver = {}

-- ------------------------------------------------------------------ tuning ----
local BLOCK_ANGLE_THRESHOLD = 0.5   -- dot(forward, toAttacker) above this = facing

-- Chip fractions of the attack's damage that leak through a successful block.
local CHIP_FRACTION = {
	M1 = 0.10,
	E = 0.10,
	M2 = 0,      -- guardbreaks; never chips (handled as full damage)
	Skill = 0.15,
	Default = 0.10,
}

-- Frame advantage. Blocked E punishes the attacker (defender plus); blocked M1 is
-- neutral (no stun on either). Values are the attacker's recovery-stun duration.
local ATTACKER_RECOVERY = {
	E = 0.45,    -- defender comes out plus
	M1 = 0,      -- neutral
	Skill = 0,   -- neutral by default
	Default = 0,
}
local ATTACKER_RECOVERY_STUNSPEED = 6

local BLOCK_KNOCKBACK = 5   -- small shove on a normal blocked hit

-- ------------------------------------------------------------------ helpers ---
-- attackerPos may be a Vector3 (projectile / skill origin) OR derived from an HRP.
local function isFacing(attackerPos, targetHRP)
	if not attackerPos or not targetHRP then return false end
	local toAttacker = (attackerPos - targetHRP.Position).Unit
	local forward = targetHRP.CFrame.LookVector
	return forward:Dot(toAttacker) > BLOCK_ANGLE_THRESHOLD
end

-- ------------------------------------------------------------------ api -------
-- params = {
--   attacker, target, targetHRP,
--   attackerHRP OR attackerPos (Vector3),   -- one of these for the facing check
--   guardbreak, attackClass, dmg
-- }
function BlockResolver.Resolve(params)
	local target = params.target
	local attacker = params.attacker
	local class = params.attackClass or "Default"
	local dmg = params.dmg or 0
	local attackerPos = params.attackerPos or (params.attackerHRP and params.attackerHRP.Position)

	-- Hit from side/back: block does not apply. Caller deals full damage.
	if not isFacing(attackerPos, params.targetHRP) then
		StateHandler.RemoveStates(target, "Blocking")
		return {
			outcome = "Bypass",
			broke = false,
			chipDamage = dmg,
			knockback = BLOCK_KNOCKBACK,
		}
	end

	-- Facing, and the attack guardbreaks: bypass the bar, break the guard, full dmg.
	-- Routes through the SAME unified Break as a bar-fill break, so the stun,
	-- CantAnything lockout, anim and 5s no-block recovery are identical either way.
	if params.guardbreak then
		GuardBarService.Break(target)
		return {
			outcome = "GuardBreak",
			broke = true,
			chipDamage = dmg,
			knockback = BLOCK_KNOCKBACK,
		}
	end

	-- Facing, non-guardbreak: a genuine block. Fill the bar; this may block-break.
	local broke = GuardBarService.AddOnBlock(target, class)
	if broke then
		-- GuardBarService.Break already applied the stun + anim + zeroed the bar.
		return {
			outcome = "GuardBreak",
			broke = true,
			chipDamage = (CHIP_FRACTION[class] or CHIP_FRACTION.Default) * dmg,
			knockback = BLOCK_KNOCKBACK,
		}
	end

	-- Normal successful block. Apply frame advantage by stunning the ATTACKER on
	-- moves where the defender should come out plus (E). M1 stays neutral (0).
	local atkRecovery = ATTACKER_RECOVERY[class] or ATTACKER_RECOVERY.Default
	if atkRecovery > 0 and attacker then
		StateHandler.SetStun(attacker, true, atkRecovery, ATTACKER_RECOVERY_STUNSPEED)
	end

	return {
		outcome = "Blocked",
		broke = false,
		chipDamage = (CHIP_FRACTION[class] or CHIP_FRACTION.Default) * dmg,
		knockback = BLOCK_KNOCKBACK,
	}
end

-- Called by any site when the TARGET successfully PARRIES (drains their bar) or when
-- the attacker LANDS a hit (drains the attacker's own bar pressure). Kept here so the
-- drain rules live next to the fill rules.
function BlockResolver.OnParrySuccess(target)
	GuardBarService.DrainOnParry(target)
end

function BlockResolver.OnAttackerLandedHit(attacker)
	GuardBarService.DrainOnHit(attacker)
end

return BlockResolver
