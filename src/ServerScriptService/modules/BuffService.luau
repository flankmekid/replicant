-- SPDX-License-Identifier: MIT
--
-- Owns combat buffs such as Monastic Stance, Mystic Eyes, and Berserker Armor. A buff
-- belongs to the player and is keyed by skill name, so it works with every weapon of
-- the class, not only the weapon that has the skill.

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local damageCalculator = require(SSS.modules.damageCalculator)

local module = {}

-- Layout: active[plr][buffName] = { def, char, expireToken }.
local active = setmetatable({}, { __mode = "k" })

-- Each damage mode returns the base and extra damage to pass to CalculateDamage.
local DamageModes = {
	-- Base plus half of the base as extra (Monastic Stance, Berserker Armor).
	additiveHalf = function(dmg, extra)
		return dmg, dmg / 2
	end,
	-- Double base, the extra unchanged (Mystic Eyes).
	doubleBase = function(dmg, extra)
		return dmg * 2, extra
	end,
}

-- BuffService.Buffs holds the buff definitions, keyed by the skill name in SkillConfig.
--
-- Each buff has a duration, a damage mode, heal and mana restored per buffed hit (mana
-- never overfills), and an fx routine ("aura", "eyes", or "none"). A perWeapon table
-- can override any field for one equipped weapon, for example
-- ["Mystic Eyes"].perWeapon = { Dagger = { damage = "additiveHalf" } }.
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
}

local function getEquippedWeapon(char)
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == char then
		return tool.Name
	end
	return nil
end

-- Returns the def with the per-weapon override for the equipped weapon applied.
local function resolveDef(def, weaponName)
	local perWeapon = def.perWeapon and weaponName and def.perWeapon[weaponName]
	if not perWeapon then
		return def
	end
	local merged = {}
	for k, v in pairs(def) do
		merged[k] = v
	end
	for k, v in pairs(perWeapon) do
		merged[k] = v
	end
	return merged
end

local function restoreMana(plr, amount)
	if not amount or amount <= 0 then
		return
	end
	local stats = plr:FindFirstChild("PlayerStats")
	local mana = stats and stats:FindFirstChild("Mana")
	local maxMana = stats and stats:FindFirstChild("MaxMana")
	if not mana then
		return
	end
	local cap = maxMana and maxMana.Value or math.huge
	mana.Value = math.min(mana.Value + amount, cap)
end

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

	-- Light up the blade of any bladed weapon. Tanto has a BladeHighlight child, and
	-- siblings such as Dagger have copies.
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		local highlight = tool:FindFirstChild("BladeHighlight", true)
		if highlight and highlight:IsA("Highlight") then
			highlight.Enabled = true
			task.delay(duration, function()
				if highlight.Parent then
					highlight.Enabled = false
				end
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
	local ok, s = pcall(function()
		return RP.assets.sounds.PunchHit:Clone()
	end)
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
	-- The eyes FX removes itself through Debris.
end

-- Defined below with Deactivate. Activate needs it to refresh a buff.
local cancelExpiry

-- BuffService.Activate() - start a buff on a player
-- @plr: the player
-- @buffName: the skill name of the buff
-- @durationOverride: the duration in seconds, used when the def has none
--
-- Activating a buff that is already active restarts its timer.
--
-- Return: nothing.
function module.Activate(plr, buffName, durationOverride)
	local def = module.Buffs[buffName]
	if not def then
		return
	end
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	local weaponName = getEquippedWeapon(char)
	local eff = resolveDef(def, weaponName)
	local duration = durationOverride or eff.duration or 10

	active[plr] = active[plr] or {}

	-- A refresh cancels the old timer. If the player respawned, it also removes the FX
	-- from the old body.
	local prior = active[plr][buffName]
	if prior then
		cancelExpiry(prior)
		if prior.char and prior.char ~= char then
			pcall(runDeactivateFX, prior.def, prior.char)
		end
	end

	-- Remember the body that has the FX. After a respawn, plr.Character is the new body,
	-- and the FX would stay on the corpse.
	local entry = { def = eff, char = char }
	active[plr][buffName] = entry

	runActivateFX(eff, char, duration)

	entry.expireToken = task.delay(duration, function()
		module.Deactivate(plr, buffName)
	end)
end

-- When a buff runs out, Deactivate runs inside the expiry thread, and task.cancel on
-- the running thread throws. So clear the token first and skip the cancel in that case.
function cancelExpiry(entry)
	local token = entry.expireToken
	if not token then
		return
	end
	entry.expireToken = nil
	if token == coroutine.running() then
		return
	end
	pcall(task.cancel, token)
end

-- BuffService.Deactivate() - end one buff on a player
-- @plr: the player
-- @buffName: the skill name of the buff
-- @charOverride: the body that has the FX, for death, respawn, and menu return, when
--                plr.Character is already a new body or nil
--
-- Return: nothing.
function module.Deactivate(plr, buffName, charOverride)
	local bucket = active[plr]
	local entry = bucket and bucket[buffName]
	if not entry then
		return
	end

	cancelExpiry(entry)

	bucket[buffName] = nil
	if next(bucket) == nil then
		active[plr] = nil
	end

	local char = charOverride or entry.char or plr.Character
	if char then
		pcall(runDeactivateFX, entry.def, char)
	end
end

-- BuffService.ClearAll() - end every buff on a player
-- @plr: the player
-- @charOverride: the body that has the FX, as in Deactivate
--
-- Call this on death, respawn, race reroll, and menu return, so no buff, FX, or
-- modifier carries over.
--
-- Return: nothing.
function module.ClearAll(plr, charOverride)
	local bucket = active[plr]
	if not bucket then
		return
	end
	for buffName in pairs(bucket) do
		module.Deactivate(plr, buffName, charOverride)
	end
	active[plr] = nil
end

-- Returns the first active buff def, or nil. A class has one buff skill, so buffs do
-- not stack in practice.
local function getActiveDef(plr)
	local bucket = active[plr]
	if not bucket then
		return nil
	end
	local _, entry = next(bucket)
	return entry and entry.def or nil
end

-- BuffService.ApplyDamage() - deal weapon damage with the active buff applied
-- @plr: the attacking player
-- @char: the attacking character
-- @targetChar: the target
-- @dmg: the base damage
-- @extraDmg: the extra damage
-- @dmgType: the damage type, "Weapon" by default
--
-- Every weapon's onDamage calls this. Without an active buff it deals plain damage.
--
-- Return: the final damage from CalculateDamage.
function module.ApplyDamage(plr, char, targetChar, dmg, extraDmg, dmgType)
	dmgType = dmgType or "Weapon"
	local def = plr and getActiveDef(plr)

	if not def then
		return damageCalculator.CalculateDamage(char, targetChar, dmg, extraDmg, false, dmgType)
	end

	local mode = DamageModes[def.damage] or DamageModes.additiveHalf
	local baseArg, extraArg = mode(dmg, extraDmg)
	local result =
		damageCalculator.CalculateDamage(char, targetChar, baseArg, extraArg, false, dmgType)

	if def.heal and def.heal > 0 and char:FindFirstChild("Humanoid") then
		char.Humanoid.Health = math.min(char.Humanoid.Health + def.heal, char.Humanoid.MaxHealth)
	end
	restoreMana(plr, def.mana)

	return result
end

-- BuffService.IsActive() - check whether a player has a buff
-- @plr: the player
-- @buffName: the skill name of the buff, or nil for any buff
--
-- Return: true if the buff is active.
function module.IsActive(plr, buffName)
	local bucket = active[plr]
	if not bucket then
		return false
	end
	if buffName then
		return bucket[buffName] ~= nil
	end
	return next(bucket) ~= nil
end

Players.PlayerRemoving:Connect(function(plr)
	local bucket = active[plr]
	if bucket then
		for name, entry in pairs(bucket) do
			if entry.expireToken then
				task.cancel(entry.expireToken)
			end
		end
		active[plr] = nil
	end
end)

return module
