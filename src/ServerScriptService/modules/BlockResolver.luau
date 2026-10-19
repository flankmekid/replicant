-- SPDX-License-Identifier: MIT
--
-- The only place that decides what happens when a hit lands on a blocking target:
-- the facing check, the guard bar, chip damage, and frame advantage. The rules are in
-- docs/combat-design.md.

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local StateHandler = require(RP.modules.stateHandler)
local GuardBarService = require(SSS.modules.GuardBarService)

local BlockResolver = {}

-- A dot product of forward and toAttacker above this counts as facing.
local blockAngleThreshold = 0.5

-- Chip fractions of the attack's damage that leak through a successful block.
local chipFraction = {
	M1 = 0.10,
	E = 0.10,
	M2 = 0, -- Guard breaks deal full damage instead.
	Skill = 0.15,
	Default = 0.10,
}

-- The attacker's recovery stun on a normal block, in seconds. A blocked E leaves the
-- defender plus. A blocked M1 is neutral.
local attackerRecovery = {
	E = 0.45,
	M1 = 0,
	Skill = 0,
	Default = 0,
}
local attackerRecoveryStunspeed = 6

-- A small shove on a normal blocked hit.
local blockKnockback = 5
-- The attackerPos argument is a projectile or skill origin, or the attacker's HRP position.
local function isFacing(attackerPos, targetHRP)
	if not attackerPos or not targetHRP then
		return false
	end
	local toAttacker = (attackerPos - targetHRP.Position).Unit
	local forward = targetHRP.CFrame.LookVector
	return forward:Dot(toAttacker) > blockAngleThreshold
end

-- BlockResolver.Resolve() - resolve a hit on a blocking target
-- @params: attacker, target, targetHRP, attackerHRP or attackerPos (a Vector3, for the
--          facing check), guardbreak, attackClass ("M1", "M2", "E", or "Skill"), dmg
--
-- Applies the guard bar and state effects. The caller applies damage, knockback, and FX,
-- because those vary per weapon and skill.
--
-- Return: a verdict { outcome, broke, chipDamage, knockback }. outcome is "Blocked",
-- "GuardBreak", or "Bypass". broke is true if this hit broke the block. chipDamage is
-- the damage the caller deals, and knockback is the knockback it applies.
function BlockResolver.Resolve(params)
	local target = params.target
	local attacker = params.attacker
	local class = params.attackClass or "Default"
	local dmg = params.dmg or 0
	local attackerPos = params.attackerPos or (params.attackerHRP and params.attackerHRP.Position)

	-- A hit from the side or back skips the block. The caller deals full damage.
	if not isFacing(attackerPos, params.targetHRP) then
		StateHandler.RemoveStates(target, "Blocking")
		return {
			outcome = "Bypass",
			broke = false,
			chipDamage = dmg,
			knockback = blockKnockback,
		}
	end

	-- A guard-break attack skips the bar and breaks the guard for full damage. It uses
	-- the same Break as a full bar, so the results are the same.
	if params.guardbreak then
		GuardBarService.Break(target)
		return {
			outcome = "GuardBreak",
			broke = true,
			chipDamage = dmg,
			knockback = blockKnockback,
		}
	end

	-- A real block fills the bar, which can break the block.
	local broke = GuardBarService.AddOnBlock(target, class)
	if broke then
		-- Break already applied the stun and the animation and emptied the bar.
		return {
			outcome = "GuardBreak",
			broke = true,
			chipDamage = (chipFraction[class] or chipFraction.Default) * dmg,
			knockback = blockKnockback,
		}
	end

	-- A normal block. Stun the attacker on moves where the defender comes out plus.
	local atkRecovery = attackerRecovery[class] or attackerRecovery.Default
	if atkRecovery > 0 and attacker then
		StateHandler.SetStun(attacker, true, atkRecovery, attackerRecoveryStunspeed)
	end

	return {
		outcome = "Blocked",
		broke = false,
		chipDamage = (chipFraction[class] or chipFraction.Default) * dmg,
		knockback = blockKnockback,
	}
end

-- BlockResolver.OnParrySuccess() - drain the guard bar of a player who parried
-- @target: the character that parried
--
-- The drain rules are here, next to the fill rules.
--
-- Return: nothing.
function BlockResolver.OnParrySuccess(target)
	GuardBarService.DrainOnParry(target)
end

-- BlockResolver.OnAttackerLandedHit() - drain the guard bar of an attacker who landed a hit
-- @attacker: the attacking character
--
-- Return: nothing.
function BlockResolver.OnAttackerLandedHit(attacker)
	GuardBarService.DrainOnHit(attacker)
end

return BlockResolver
