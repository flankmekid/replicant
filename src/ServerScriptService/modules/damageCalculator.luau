-- SPDX-License-Identifier: MIT
--
-- Applies damage from every source: combat tags, stat scaling, the downed check, hit
-- FX, damage numbers, the hit animation, and the default hitstun. The damage formula is
-- in docs/combat-design.md.

local module = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local CombatManager = require(ServerScriptService.modules.combatTagManager)
local AnimationHandler = require(game.ReplicatedStorage.modules.animationHandler)
local StateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local StatScaling = require(game.ReplicatedStorage.modules.StatScaling)
local DownedManager = require(ServerScriptService.modules.DownedManager)

local DamageNumberRemote = game.ReplicatedStorage.remotes:WaitForChild("DamageNumber")
local CameraShakeRemote = game.ReplicatedStorage.remotes:WaitForChild("CameraShake")

-- Damage above which a hit shakes the camera, the same as the red damage indicator.
local SHAKE_DAMAGE_THRESHOLD = 20

-- Reads a stat from a character attribute, then from PlayerStats, for players and NPCs.
local function getStatValue(character, statName, defaultValue)
	local attrValue = character:GetAttribute(statName)
	if attrValue ~= nil then
		return attrValue
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local stats = player:FindFirstChild("PlayerStats")
		if stats then
			local statObj = stats:FindFirstChild(statName)
			if statObj then
				return statObj.Value
			end
		end
	end
	return defaultValue
end

-- Reads invested stat points from PlayerStats.Stats. NPCs and bosses get 0, so stat
-- scaling does nothing against them.
local function getStatPoints(character, statName)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return 0
	end
	local stats = player:FindFirstChild("PlayerStats")
	if not stats then
		return 0
	end
	local folder = stats:FindFirstChild("Stats")
	if not folder then
		return 0
	end
	local obj = folder:FindFirstChild(statName)
	return obj and obj.Value or 0
end

-- damageCalculator.CalculateDamage() - deal damage from one character to another
-- @attackerChar: the attacking character
-- @targetChar: the character that takes the damage
-- @baseDmg: the base damage
-- @extraDmg: damage added to the base
-- @isInstantKill: true to down or kill the target at once
-- @dmgType: "Weapon" (scales with Strength), "Skill" (Dexterity), "Racial" (Dexterity
--           and Magic), or nil for true damage with no stat scaling
-- @stunOverride: the hitstun in seconds, 0.85 by default. Not used for "Weapon".
-- @stunSpeedOverride: the WalkSpeed during the hitstun, 2 by default
--
-- Weapon hits get no hitstun here, because the CombatCore knockback closures set the
-- per-move hitstun just before this call.
--
-- Return: the final damage, or nil when the target is missing or dead.
function module.CalculateDamage(
	attackerChar,
	targetChar,
	baseDmg,
	extraDmg,
	isInstantKill,
	dmgType,
	stunOverride,
	stunSpeedOverride
)
	if not targetChar then
		return
	end

	local targetHum = targetChar:FindFirstChild("Humanoid")
	if not targetHum or targetHum.Health <= 0 then
		return
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
	local attackerPlayer = Players:GetPlayerFromCharacter(attackerChar)

	if targetPlayer and attackerPlayer then
		CombatManager.TagPlayer(targetPlayer, attackerPlayer)
		CombatManager.TagPlayer(attackerPlayer, targetPlayer)

		local oldTag = targetHum:FindFirstChild("KillTag")
		if oldTag then
			oldTag:Destroy()
		end

		local tag = Instance.new("StringValue")
		tag.Name = "KillTag"
		tag.Value = attackerPlayer.Name
		tag.Parent = targetHum
		Debris:AddItem(tag, 30)
	end

	if not targetPlayer and attackerPlayer then
		local oldTag = targetHum:FindFirstChild("KillTag")
		if oldTag then
			oldTag:Destroy()
		end

		local tag = Instance.new("StringValue")
		tag.Name = "KillTag"
		tag.Value = attackerPlayer.Name
		tag.Parent = targetHum
		Debris:AddItem(tag, 15)
	end

	local armorBuffs
	if attackerPlayer then
		armorBuffs = attackerPlayer:FindFirstChild("PlayerStats"):FindFirstChild("ArmorBuffs")
	end

	baseDmg = baseDmg or 0
	extraDmg = extraDmg or 0

	local dmgBoost = getStatValue(attackerChar, "DamageBoost", 1)
	local armorDmgBoost = armorBuffs and armorBuffs:FindFirstChild("DamageBuff").Value or 1
	local defBoost = getStatValue(targetChar, "DefenseBoost", 1)

	-- Race, armor, and stat bonuses add into one pool that is applied once, so stacking
	-- is linear, not exponential.
	local statBonus = 0
	if dmgType == "Weapon" then
		statBonus = StatScaling.GetStrengthBonus(getStatPoints(attackerChar, "Strength"))
	elseif dmgType == "Skill" then
		statBonus = StatScaling.GetDexterityBonus(getStatPoints(attackerChar, "Dexterity"))
	elseif dmgType == "Racial" then
		statBonus = StatScaling.GetDexterityBonus(getStatPoints(attackerChar, "Dexterity"))
			+ StatScaling.GetMagicDamageBonus(getStatPoints(attackerChar, "Magic"))
	end

	local totalBonus = statBonus + (dmgBoost - 1) + (armorDmgBoost - 1)
	local finalMult = math.max(0, 1 + totalBonus)
	local rawDamage = (baseDmg + extraDmg) * finalMult
	if defBoost == 0 then
		defBoost = 1
	end
	local finalDamage = rawDamage / defBoost

	local wasDowned = DownedManager.CheckDownedCondition(targetChar, finalDamage, isInstantKill)

	if wasDowned then
		return finalDamage
	end

	-- An already downed target takes no damage, hit animation, or stun, because the
	-- ragdoll owns them. The hit restarts their bleed-out timer instead.
	if StateHandler.GetState(targetChar, "Downed") then
		DownedManager.ResetReviveTimer(targetChar)
		return finalDamage
	end

	if StateHandler.GetState(attackerChar, "Executing") then
		DownedManager.StopExecution(attackerChar)
	end

	if StateHandler.GetState(targetChar, "DefenseBuff") then
		finalDamage = finalDamage * 0.6
	end

	if StateHandler.GetState(attackerChar, "AttackBuff") then
		finalDamage = finalDamage * 1.3
	end

	targetHum:TakeDamage(finalDamage)

	if targetChar:FindFirstChild("Torso") then
		local r = math.random(-180, 180)

		local slashClone = game:GetService("ReplicatedStorage").assets.FX.SlashFX.A_Slice:Clone()
		slashClone.Parent = targetChar:FindFirstChild("Torso")

		slashClone.Orientation = Vector3.new(0, 180, r)

		task.delay(0.5, function()
			for _, v in pairs(slashClone:GetChildren()) do
				if v:IsA("ParticleEmitter") then
					v.Enabled = false
				end
			end
		end)
		game.Debris:AddItem(slashClone, 2)
	end

	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if hrp then
		local rounded = math.floor(finalDamage + 0.5)
		local victimPlayer = Players:GetPlayerFromCharacter(targetChar)
		for _, plr in Players:GetPlayers() do
			if plr ~= victimPlayer then
				DamageNumberRemote:FireClient(plr, hrp, rounded)
			end
		end
	end

	-- Taking a big hit shakes the camera harder than landing one.
	if finalDamage > SHAKE_DAMAGE_THRESHOLD then
		if targetPlayer then
			CameraShakeRemote:FireClient(targetPlayer, { kind = "Damage", taken = true })
		end
		if attackerPlayer and attackerPlayer ~= targetPlayer then
			CameraShakeRemote:FireClient(attackerPlayer, { kind = "Damage", taken = false })
		end
	end

	-- An armored target does not flinch, so the hit animation does not cancel their
	-- swing or cast. They still take the damage.
	if not targetChar:GetAttribute("HyperArmor") then
		local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
			or "rbxassetid://111089735892609"
		local anim = Instance.new("Animation")
		anim.AnimationId = animID
		local track = targetChar.Humanoid:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action4
		track:Play()
		task.delay(0.7, function()
			track:Stop()
		end)
		game.Debris:AddItem(anim, 2)
	end

	-- Weapon hits already have their per-move hitstun from CombatCore.
	if dmgType ~= "Weapon" then
		StateHandler.SetStun(targetChar, true, stunOverride or 0.85, stunSpeedOverride or 2)
	end

	DownedManager.DropIfCarrying(targetChar)

	if targetHum.Health <= 0 then
		if attackerPlayer then
			CombatManager.SetTagDuration(attackerPlayer, 5)
		end
	end

	if attackerChar:GetAttribute("Lifesteal") then
		attackerChar.Humanoid.Health += 2
	end

	-- Aegir racial passive: taking damage restores mana.
	if targetPlayer then
		local stats = targetPlayer:FindFirstChild("PlayerStats")
		if stats and stats.Race.Value == "Aegir" then
			local manaObj = stats:FindFirstChild("Mana")
			local maxManaObj = stats:FindFirstChild("MaxMana")

			if manaObj and maxManaObj then
				local manaRestore = finalDamage * 0.35
				manaObj.Value = math.min(manaObj.Value + manaRestore, maxManaObj.Value)

				local scaleFX = game.ReplicatedStorage.assets.FX.aegir.dragonEmit:Clone()
				scaleFX.Parent = targetChar.HumanoidRootPart
				scaleFX:Emit(5)
				game.Debris:AddItem(scaleFX, 1)
			end
		end
	end

	return finalDamage
end

return module
