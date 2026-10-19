-- BuffService: centralized, weapon-independent combat buffs.
--
-- Buffs used to live as per-weapon local tables (monasticStance/buffState) inside
-- individual M1 modules (Caestus, Tanto, Dragon Slayer...), so a transposed skill
-- on a sibling weapon (Dagger, Fists, Shackles, Greatsword) set state on the wrong
-- module and never affected that weapon's hits. This moves buff state onto the
-- PLAYER, keyed by skill name, so every weapon in a class benefits automatically.
--
-- A buff carries:
--   damage : how the buffed hit's damage is computed from (dmg, extraDmg)
--   heal   : flat HP restored per buffed hit
--   mana   : flat mana restored per buffed hit (capped so it never overfills)
--   fx     : which visual routine to run on activate (aura / eyes / none)
-- Numbers preserve the original per-weapon behavior. `perWeapon` lets you override
-- any field for a specific equipped weapon later without touching this logic.

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local damageCalculator = require(SSS.modules.damageCalculator)

local module = {}

-- active[plr] = { [buffName] = { def = <def>, expireToken = <token> } }
local active = setmetatable({}, { __mode = "k" })

-- ── damage modes ────────────────────────────────────────────────────────────
-- each returns (baseArg, extraArg) to hand to CalculateDamage.
local DamageModes = {
	-- base + half-of-base as extra (Monastic Stance / Berserker Armor)
	additiveHalf = function(dmg, extra)
		return dmg, dmg / 2
	end,
	-- double the base, keep original extra (Mystic Eyes)
	doubleBase = function(dmg, extra)
		return dmg * 2, extra
	end,
}

-- ── buff definitions (tunable) ──────────────────────────────────────────────
-- keyed by the skill name exactly as it appears in SkillConfig.
module.Buffs = {
	["Monastic Stance"] = {
		duration = 10,
		damage = "additiveHalf",
		heal = 0,
		mana = 5,
		fx = "aura",
	},
	["Mystic Eyes"] = {
		duration = 30,
		damage = "doubleBase",
		heal = 0,
		mana = 5,
		fx = "eyes",
	},
	["Berserker Armor"] = {
		duration = 30,
		damage = "additiveHalf",
		heal = 10,
		mana = 5,
		fx = "none",
	},

	-- Optional per-equipped-weapon overrides. Any field set here wins for that
	-- weapon; unset fields fall back to the base def above. Empty for now (all
	-- siblings share the origin's numbers), but this is the tuning hook.
	-- e.g. ["Mystic Eyes"].perWeapon = { Dagger = { damage = "additiveHalf" } }
}

-- ── helpers ─────────────────────────────────────────────────────────────────
local function getEquippedWeapon(char)
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == char then return tool.Name end
	return nil
end

-- resolve the effective def for a player's currently-equipped weapon, applying
-- any per-weapon override on top of the base def.
local function resolveDef(def, weaponName)
	local perWeapon = def.perWeapon and weaponName and def.perWeapon[weaponName]
	if not perWeapon then return def end
	local merged = {}
	for k, v in pairs(def) do merged[k] = v end
	for k, v in pairs(perWeapon) do merged[k] = v end
	return merged
end

local function restoreMana(plr, amount)
	if not amount or amount <= 0 then return end
	local stats = plr:FindFirstChild("PlayerStats")
	local mana = stats and stats:FindFirstChild("Mana")
	local maxMana = stats and stats:FindFirstChild("MaxMana")
	if not mana then return end
	local cap = maxMana and maxMana.Value or math.huge
	mana.Value = math.min(mana.Value + amount, cap)
end

-- ── FX ──────────────────────────────────────────────────────────────────────
local FX = {}

function FX.aura(char)
	for _, part in pairs(char:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local eff = RP.assets.FX.MonasticStancePart.MonasticStance:Clone()
			eff.Parent = part
			eff.Name = "MonasticStance"
			eff.Enabled = true
		end
	end
end

function FX.auraOff(char)
	for _, part in pairs(char:GetChildren()) do
		if part:IsA("BasePart") then
			local eff = part:FindFirstChild("MonasticStance")
			if eff then
				eff.Enabled = false
				Debris:AddItem(eff, 1)
			end
		end
	end
end

function FX.eyes(char, duration)
	-- head eye visual (weapon-agnostic)
	local head = char:FindFirstChild("Head")
	if head then
		local eye = RP.assets.FX.skills.tanto.ResurrectionEYE:Clone()
		local weld = Instance.new("Weld")
		weld.Part0 = head
		weld.Part1 = eye
		eye.Parent = head
		weld.Parent = head
		Debris:AddItem(eye, duration)
		Debris:AddItem(weld, duration)
	end

	-- blade highlight on whatever bladed weapon is equipped (Tanto has a
	-- BladeHighlight child; parity copies exist on siblings like Dagger)
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		local highlight = tool:FindFirstChild("BladeHighlight", true)
		if highlight and highlight:IsA("Highlight") then
			highlight.Enabled = true
			task.delay(duration, function()
				if highlight.Parent then highlight.Enabled = false end
			end)
		end
	end
end

local function runActivateFX(def, char, duration)
	if def.fx == "aura" then
		FX.aura(char)
	elseif def.fx == "eyes" then
		FX.eyes(char, duration)
	end
	-- activation sound, matched to the old behavior
	local ok, s = pcall(function() return RP.assets.sounds.PunchHit:Clone() end)
	if ok and s and char:FindFirstChild("HumanoidRootPart") then
		s.Parent = char.HumanoidRootPart
		s:Play()
		Debris:AddItem(s, 2)
	end
end

local function runDeactivateFX(def, char)
	if def.fx == "aura" then
		FX.auraOff(char)
	end
	-- eyes clean themselves up via Debris timers
end

-- ── public API ──────────────────────────────────────────────────────────────

-- forward-declared; defined with Deactivate below (Activate refreshes need it).
local cancelExpiry


-- Activate a named buff on a player. Duration comes from the def (falls back to
-- the passed duration, then 10s). Re-activating refreshes the timer.
function module.Activate(plr, buffName, durationOverride)
	local def = module.Buffs[buffName]
	if not def then return end
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local weaponName = getEquippedWeapon(char)
	local eff = resolveDef(def, weaponName)
	local duration = durationOverride or eff.duration or 10

	active[plr] = active[plr] or {}

	-- cancel any prior timer for this buff (refresh). Re-casting a buff while its
	-- aura is up must also clear the OLD body's FX, or a refresh across a respawn
	-- leaves particles behind.
	local prior = active[plr][buffName]
	if prior then
		cancelExpiry(prior)
		if prior.char and prior.char ~= char then
			pcall(runDeactivateFX, prior.def, prior.char)
		end
	end

	-- Remember the body the buff was applied to. On death/respawn plr.Character is
	-- replaced, and the FX are welded to the OLD parts; sweeping the new body finds
	-- nothing and the particles stay on the corpse.
	local entry = { def = eff, char = char }
	active[plr][buffName] = entry

	runActivateFX(eff, char, duration)

	entry.expireToken = task.delay(duration, function()
		module.Deactivate(plr, buffName)
	end)
end

-- Cancels a scheduled expiry safely.
--
-- The expire thread's body IS module.Deactivate (see the task.delay above), so when
-- a buff runs its full duration, Deactivate executes INSIDE the very thread it is
-- about to cancel. task.cancel on the running coroutine throws "cannot cancel
-- thread". Pop the token first, then only cancel if it is not the thread we are
-- standing in.
function cancelExpiry(entry)
	local token = entry.expireToken
	if not token then return end
	entry.expireToken = nil
	if token == coroutine.running() then return end
	pcall(task.cancel, token)
end

-- Tears down one buff. `charOverride` lets callers (death, respawn, menu) pass the
-- body the buff was actually applied to, because plr.Character may already be a new
-- character, or nil, by the time we get here. Without it, auraOff would sweep the
-- wrong body and leave particles welded to the corpse forever.
function module.Deactivate(plr, buffName, charOverride)
	local bucket = active[plr]
	local entry = bucket and bucket[buffName]
	if not entry then return end

	cancelExpiry(entry)

	bucket[buffName] = nil
	if next(bucket) == nil then active[plr] = nil end

	local char = charOverride or entry.char or plr.Character
	if char then
		pcall(runDeactivateFX, entry.def, char)
	end
end

-- Tears down EVERY buff on a player. This is the lifecycle hook that was missing:
-- nothing but the expiry timer ever called Deactivate, so buff state (and its FX,
-- and its heal/damage modifiers) survived death, respawn, race reroll, and menu
-- return. A player who died with Monastic Stance up kept the aura on the corpse and
-- kept the buff in `active`, and a rerolled race inherited whatever was still there.
function module.ClearAll(plr, charOverride)
	local bucket = active[plr]
	if not bucket then return end
	for buffName in pairs(bucket) do
		module.Deactivate(plr, buffName, charOverride)
	end
	active[plr] = nil
end

-- Returns the first active buff def for a player, or nil. (Buffs here don't
-- stack with each other in practice; a class has one buff skill.)
local function getActiveDef(plr)
	local bucket = active[plr]
	if not bucket then return nil end
	local _, entry = next(bucket)
	return entry and entry.def or nil
end

-- The single damage entry point every weapon's onDamage should call. Applies
-- the buffed damage math + heal + mana if a buff is active, plain damage if not.
-- `dmgType` defaults to "Weapon" (matches the M1/M2/E path).
function module.ApplyDamage(plr, char, targetChar, dmg, extraDmg, dmgType)
	dmgType = dmgType or "Weapon"
	local def = plr and getActiveDef(plr)

	if not def then
		return damageCalculator.CalculateDamage(char, targetChar, dmg, extraDmg, false, dmgType)
	end

	local mode = DamageModes[def.damage] or DamageModes.additiveHalf
	local baseArg, extraArg = mode(dmg, extraDmg)
	local result = damageCalculator.CalculateDamage(char, targetChar, baseArg, extraArg, false, dmgType)

	if def.heal and def.heal > 0 and char:FindFirstChild("Humanoid") then
		char.Humanoid.Health = math.min(char.Humanoid.Health + def.heal, char.Humanoid.MaxHealth)
	end
	restoreMana(plr, def.mana)

	return result
end

function module.IsActive(plr, buffName)
	local bucket = active[plr]
	if not bucket then return false end
	if buffName then return bucket[buffName] ~= nil end
	return next(bucket) ~= nil
end

Players.PlayerRemoving:Connect(function(plr)
	local bucket = active[plr]
	if bucket then
		for name, entry in pairs(bucket) do
			if entry.expireToken then task.cancel(entry.expireToken) end
		end
		active[plr] = nil
	end
end)

return module
