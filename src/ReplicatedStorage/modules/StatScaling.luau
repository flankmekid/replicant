--[[
	StatScaling
	Shared module: single source of truth for the Souls-like stat spread curves.
	Required by both the server damageCalculator (str/dex/magic damage) and
	dataManager (vitality HP, magic mana/regen, stamina movement).

	All stats are invested as integer points 0-50.

	Design targets (value at level 50, soft-capped at level 40):
	  Vitality  -> +100 max HP (additive, back-heavy lookup curve)
	  Strength  -> +35% weapon damage (M1/E/M2)     => multiplier 1.35
	  Dexterity -> +50% skill damage                 => multiplier 1.50
	  Magic     -> +50% racial-move damage (1.50),
	               +100 max mana,
	               5x passive mana regen, 2x in-combat regen
	  Stamina   -> movement: wall-run @10, 2nd dash @30, velocity soft-cap @20,
	               +1 walkspeed per 10 levels (continuous)

	Damage bonuses are returned as ADDITIVE fractions (e.g. 0.35), so callers
	sum them into one pool with armor/race and apply once. They are NOT
	multiplied together.
]]

local StatScaling = {}

StatScaling.MAX_STAT = 50
StatScaling.SOFT_CAP = 40 -- knee: full per-point value up to here, reduced after
local POST_CAP_RATIO = 0.30 -- points past the knee give 30% of normal value

-- ── Soft-cap helper ────────────────────────────────────────────────
-- Returns a 0..1 progress value for `points`, where progress reaches the
-- knee proportionally, then continues at POST_CAP_RATIO up to MAX_STAT,
-- normalized so that points == MAX_STAT returns exactly 1.0.
local function softCapProgress(points)
	points = math.clamp(points, 0, StatScaling.MAX_STAT)
	local knee = StatScaling.SOFT_CAP
	local maxStat = StatScaling.MAX_STAT
	-- raw "value units" accrued: 1 per point pre-knee, POST_CAP_RATIO per point after
	local function rawUnits(p)
		if p <= knee then
			return p
		end
		return knee + (p - knee) * POST_CAP_RATIO
	end
	local maxUnits = rawUnits(maxStat)
	if maxUnits <= 0 then return 0 end
	return rawUnits(points) / maxUnits
end
StatScaling.SoftCapProgress = softCapProgress

-- Generic: scale an additive bonus by soft-capped progress toward maxBonus.
-- e.g. scaledBonus(strPoints, 0.35) -> 0..0.35
local function scaledBonus(points, maxBonus)
	return softCapProgress(points) * maxBonus
end

-- ── VITALITY: max HP (additive) ────────────────────────────────────
-- Baked back-heavy cumulative lookup. Index = stat level (1-50).
-- Level 0 = +0. Lands exactly +100 at level 50. Hand-tunable.
local VITALITY_HP = {
	[0]=0,
	[1]=0,[2]=1,[3]=1,[4]=2,[5]=2,[6]=3,[7]=4,[8]=5,[9]=6,[10]=7,
	[11]=8,[12]=9,[13]=11,[14]=12,[15]=13,[16]=15,[17]=16,[18]=18,[19]=20,[20]=22,
	[21]=23,[22]=25,[23]=27,[24]=29,[25]=31,[26]=33,[27]=36,[28]=38,[29]=40,[30]=42,
	[31]=45,[32]=47,[33]=50,[34]=52,[35]=55,[36]=58,[37]=60,[38]=63,[39]=66,[40]=69,
	[41]=72,[42]=75,[43]=78,[44]=81,[45]=84,[46]=87,[47]=90,[48]=93,[49]=97,[50]=100,
}
StatScaling.VITALITY_HP = VITALITY_HP

function StatScaling.GetHPBonus(vitPoints)
	vitPoints = math.clamp(math.floor(vitPoints or 0), 0, StatScaling.MAX_STAT)
	return VITALITY_HP[vitPoints] or 0
end

-- ── STRENGTH: weapon damage additive bonus (max +0.35) ─────────────
function StatScaling.GetStrengthBonus(strPoints)
	return scaledBonus(strPoints or 0, 0.35)
end

-- ── DEXTERITY: skill damage additive bonus (max +0.50) ─────────────
function StatScaling.GetDexterityBonus(dexPoints)
	return scaledBonus(dexPoints or 0, 0.50)
end

-- ── MAGIC ──────────────────────────────────────────────────────────
-- Racial-move damage additive bonus (max +0.50)
function StatScaling.GetMagicDamageBonus(magicPoints)
	return scaledBonus(magicPoints or 0, 0.50)
end

-- Max mana flat bonus (max +100, additive). Linear (no soft cap) so each
-- point of magic gives a steady, legible +2 mana.
function StatScaling.GetManaBonus(magicPoints)
	magicPoints = math.clamp(math.floor(magicPoints or 0), 0, StatScaling.MAX_STAT)
	return math.floor((magicPoints / StatScaling.MAX_STAT) * 100 + 0.5)
end

-- Passive regen multiplier: 1x at 0 -> 5x at 50 (linear).
function StatScaling.GetPassiveRegenMult(magicPoints)
	magicPoints = math.clamp(magicPoints or 0, 0, StatScaling.MAX_STAT)
	return 1 + (magicPoints / StatScaling.MAX_STAT) * 4 -- 1..5
end

-- In-combat regen multiplier: 1x at 0 -> 2x at 50 (linear).
function StatScaling.GetCombatRegenMult(magicPoints)
	magicPoints = math.clamp(magicPoints or 0, 0, StatScaling.MAX_STAT)
	return 1 + (magicPoints / StatScaling.MAX_STAT) * 1 -- 1..2
end

-- ── STAMINA ────────────────────────────────────────────────────────
-- Discrete unlock thresholds
StatScaling.STAMINA_WALLRUN_UNLOCK = 10 -- 3rd wall run at >=10
StatScaling.STAMINA_DASH_UNLOCK    = 30 -- 2nd dash at >=30
StatScaling.STAMINA_VELOCITY_KNEE  = 20 -- velocity-time soft-caps here

function StatScaling.GetWallRunCount(stamPoints)
	return ((stamPoints or 0) >= StatScaling.STAMINA_WALLRUN_UNLOCK) and 3 or 2
end

function StatScaling.HasSecondDash(stamPoints)
	return (stamPoints or 0) >= StatScaling.STAMINA_DASH_UNLOCK
end

-- +1 walkspeed per 10 levels (continuous), max +5 at 50.
function StatScaling.GetWalkspeedBonus(stamPoints)
	stamPoints = math.clamp(stamPoints or 0, 0, StatScaling.MAX_STAT)
	return math.floor(stamPoints / 10)
end

-- Canonical base walkspeed for a character, including the Stamina bonus but BEFORE
-- race SpeedBoost. The single source of truth that every "reset to default speed"
-- site should use instead of the literal 16. Reads stamina live from PlayerStats.
StatScaling.BASE_WALKSPEED = 16
function StatScaling.GetBaseWalkSpeed(character)
	local stam = 0
	local Players = game:GetService("Players")
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		local stats = player:FindFirstChild("PlayerStats")
		local sf = stats and stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then stam = sf.Stamina.Value end
	end
	return StatScaling.BASE_WALKSPEED + StatScaling.GetWalkspeedBonus(stam)
end

-- Velocity (momentum) build-up time multiplier: faster (lower) with investment,
-- soft-capping its returns at level 20 but still improving slightly to 50.
-- Returns a 0..1 progress; callers map it onto their own time range.
function StatScaling.GetVelocityProgress(stamPoints)
	stamPoints = math.clamp(stamPoints or 0, 0, StatScaling.MAX_STAT)
	local knee = StatScaling.STAMINA_VELOCITY_KNEE
	local function rawUnits(p)
		if p <= knee then return p end
		return knee + (p - knee) * POST_CAP_RATIO
	end
	local maxUnits = rawUnits(StatScaling.MAX_STAT)
	return rawUnits(stamPoints) / maxUnits
end

-- ── SKILL POINT BUDGET (Model A) ───────────────────────────────────
-- Liturgy buys SKILL POINTS (capped at MAX_SKILL_POINTS). Assigning a skill
-- point to a stat is free (1:1). Buying the n-th skill point follows a gentle
-- rising curve tuned so all 150 cost ~200k Liturgy total.
StatScaling.MAX_SKILL_POINTS = 150
StatScaling.COST_BASE = 9
StatScaling.COST_EXPONENT = 1.15

-- Cost to buy the NEXT skill point given how many you already OWN.
function StatScaling.GetNextSkillPointCost(owned)
	owned = math.max(0, math.floor(owned or 0))
	return math.floor(StatScaling.COST_BASE * ((owned + 1) ^ StatScaling.COST_EXPONENT))
end

-- Backwards-compat alias (older callers referenced GetNextPointCost).
StatScaling.GetNextPointCost = StatScaling.GetNextSkillPointCost

return StatScaling
