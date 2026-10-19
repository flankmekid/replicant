-- SPDX-License-Identifier: MIT
--
-- The stat spread curves (Vitality, Strength, Dexterity, Magic, Stamina; 0 to 50
-- points each) and the skill point price. The server and the client both use them.
-- Damage bonuses are additive fractions (0.35 means +35%), so callers add them into one
-- pool. The design targets are in docs/systems-design.md.

local StatScaling = {}

StatScaling.MAX_STAT = 50
-- Full value per point up to SOFT_CAP. After it, a point gives postCapRatio of that.
StatScaling.SOFT_CAP = 40
local postCapRatio = 0.30

-- Returns the progress (0 to 1) of points on the soft-capped curve. MAX_STAT returns
-- exactly 1.
local function softCapProgress(points)
	points = math.clamp(points, 0, StatScaling.MAX_STAT)
	local knee = StatScaling.SOFT_CAP
	local maxStat = StatScaling.MAX_STAT
	-- One unit per point before the soft cap, postCapRatio per point after.
	local function rawUnits(p)
		if p <= knee then
			return p
		end
		return knee + (p - knee) * postCapRatio
	end
	local maxUnits = rawUnits(maxStat)
	if maxUnits <= 0 then
		return 0
	end
	return rawUnits(points) / maxUnits
end
StatScaling.SoftCapProgress = softCapProgress

-- Scales maxBonus by the soft-capped progress of points.
local function scaledBonus(points, maxBonus)
	return softCapProgress(points) * maxBonus
end

-- Vitality: flat max HP by level, back-heavy, +100 at level 50. Tuned by hand.
local vitalityHp = {
	[0] = 0,
	[1] = 0,
	[2] = 1,
	[3] = 1,
	[4] = 2,
	[5] = 2,
	[6] = 3,
	[7] = 4,
	[8] = 5,
	[9] = 6,
	[10] = 7,
	[11] = 8,
	[12] = 9,
	[13] = 11,
	[14] = 12,
	[15] = 13,
	[16] = 15,
	[17] = 16,
	[18] = 18,
	[19] = 20,
	[20] = 22,
	[21] = 23,
	[22] = 25,
	[23] = 27,
	[24] = 29,
	[25] = 31,
	[26] = 33,
	[27] = 36,
	[28] = 38,
	[29] = 40,
	[30] = 42,
	[31] = 45,
	[32] = 47,
	[33] = 50,
	[34] = 52,
	[35] = 55,
	[36] = 58,
	[37] = 60,
	[38] = 63,
	[39] = 66,
	[40] = 69,
	[41] = 72,
	[42] = 75,
	[43] = 78,
	[44] = 81,
	[45] = 84,
	[46] = 87,
	[47] = 90,
	[48] = 93,
	[49] = 97,
	[50] = 100,
}
StatScaling.VITALITY_HP = vitalityHp

-- StatScaling.GetHPBonus() - get the max HP bonus of Vitality
-- @vitPoints: the Vitality points
--
-- Return: the flat HP bonus.
function StatScaling.GetHPBonus(vitPoints)
	vitPoints = math.clamp(math.floor(vitPoints or 0), 0, StatScaling.MAX_STAT)
	return vitalityHp[vitPoints] or 0
end

-- StatScaling.GetStrengthBonus() - get the weapon damage bonus of Strength
-- @strPoints: the Strength points
--
-- Return: an additive fraction, up to 0.35.
function StatScaling.GetStrengthBonus(strPoints)
	return scaledBonus(strPoints or 0, 0.35)
end

-- StatScaling.GetDexterityBonus() - get the skill damage bonus of Dexterity
-- @dexPoints: the Dexterity points
--
-- Return: an additive fraction, up to 0.50.
function StatScaling.GetDexterityBonus(dexPoints)
	return scaledBonus(dexPoints or 0, 0.50)
end

-- StatScaling.GetMagicDamageBonus() - get the racial skill damage bonus of Magic
-- @magicPoints: the Magic points
--
-- Return: an additive fraction, up to 0.50.
function StatScaling.GetMagicDamageBonus(magicPoints)
	return scaledBonus(magicPoints or 0, 0.50)
end

-- StatScaling.GetManaBonus() - get the max mana bonus of Magic
-- @magicPoints: the Magic points
--
-- Linear, with no soft cap, so each point gives a steady +2 mana.
--
-- Return: the flat mana bonus, up to 100.
function StatScaling.GetManaBonus(magicPoints)
	magicPoints = math.clamp(math.floor(magicPoints or 0), 0, StatScaling.MAX_STAT)
	return math.floor((magicPoints / StatScaling.MAX_STAT) * 100 + 0.5)
end

-- StatScaling.GetPassiveRegenMult() - get the passive mana regen multiplier of Magic
-- @magicPoints: the Magic points
--
-- Return: 1 at 0 points to 5 at 50, linear.
function StatScaling.GetPassiveRegenMult(magicPoints)
	magicPoints = math.clamp(magicPoints or 0, 0, StatScaling.MAX_STAT)
	return 1 + (magicPoints / StatScaling.MAX_STAT) * 4
end

-- StatScaling.GetCombatRegenMult() - get the in-combat mana regen multiplier of Magic
-- @magicPoints: the Magic points
--
-- Return: 1 at 0 points to 2 at 50, linear.
function StatScaling.GetCombatRegenMult(magicPoints)
	magicPoints = math.clamp(magicPoints or 0, 0, StatScaling.MAX_STAT)
	return 1 + (magicPoints / StatScaling.MAX_STAT) * 1
end

-- Stamina unlocks: the third wall run, the second dash, and the level where the
-- momentum build-up soft-caps.
StatScaling.STAMINA_WALLRUN_UNLOCK = 10
StatScaling.STAMINA_DASH_UNLOCK = 30
StatScaling.STAMINA_VELOCITY_KNEE = 20

-- StatScaling.GetWallRunCount() - get the number of wall runs
-- @stamPoints: the Stamina points
--
-- Return: 3 from STAMINA_WALLRUN_UNLOCK, otherwise 2.
function StatScaling.GetWallRunCount(stamPoints)
	return ((stamPoints or 0) >= StatScaling.STAMINA_WALLRUN_UNLOCK) and 3 or 2
end

-- StatScaling.HasSecondDash() - check whether Stamina unlocks the second dash
-- @stamPoints: the Stamina points
--
-- Return: true from STAMINA_DASH_UNLOCK.
function StatScaling.HasSecondDash(stamPoints)
	return (stamPoints or 0) >= StatScaling.STAMINA_DASH_UNLOCK
end

-- StatScaling.GetWalkspeedBonus() - get the WalkSpeed bonus of Stamina
-- @stamPoints: the Stamina points
--
-- Return: +1 per 10 points, up to +5.
function StatScaling.GetWalkspeedBonus(stamPoints)
	stamPoints = math.clamp(stamPoints or 0, 0, StatScaling.MAX_STAT)
	return math.floor(stamPoints / 10)
end

-- StatScaling.GetBaseWalkSpeed() - get the base WalkSpeed of a character
-- @character: the character
--
-- Includes the Stamina bonus, read live from PlayerStats, but not the race SpeedBoost.
-- Use this instead of the literal 16.
--
-- Return: the WalkSpeed.
StatScaling.BASE_WALKSPEED = 16
function StatScaling.GetBaseWalkSpeed(character)
	local stam = 0
	local Players = game:GetService("Players")
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		local stats = player:FindFirstChild("PlayerStats")
		local sf = stats and stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			stam = sf.Stamina.Value
		end
	end
	return StatScaling.BASE_WALKSPEED + StatScaling.GetWalkspeedBonus(stam)
end

-- StatScaling.GetVelocityProgress() - get the momentum build-up progress of Stamina
-- @stamPoints: the Stamina points
--
-- More Stamina builds momentum faster. The returns soft-cap at level 20 and still
-- improve a little up to 50. Callers map the progress onto their own time range.
--
-- Return: progress from 0 to 1.
function StatScaling.GetVelocityProgress(stamPoints)
	stamPoints = math.clamp(stamPoints or 0, 0, StatScaling.MAX_STAT)
	local knee = StatScaling.STAMINA_VELOCITY_KNEE
	local function rawUnits(p)
		if p <= knee then
			return p
		end
		return knee + (p - knee) * postCapRatio
	end
	local maxUnits = rawUnits(StatScaling.MAX_STAT)
	return rawUnits(stamPoints) / maxUnits
end

-- Skill points are bought with Liturgy, up to MAX_SKILL_POINTS, on a gentle rising
-- curve: all 150 cost about 200k Liturgy.
StatScaling.MAX_SKILL_POINTS = 150
StatScaling.COST_BASE = 9
StatScaling.COST_EXPONENT = 1.15

-- StatScaling.GetNextSkillPointCost() - get the price of the next skill point
-- @owned: the skill points the player already owns
--
-- Return: the Liturgy cost.
function StatScaling.GetNextSkillPointCost(owned)
	owned = math.max(0, math.floor(owned or 0))
	return math.floor(StatScaling.COST_BASE * ((owned + 1) ^ StatScaling.COST_EXPONENT))
end

-- The old name of GetNextSkillPointCost.
StatScaling.GetNextPointCost = StatScaling.GetNextSkillPointCost

return StatScaling
