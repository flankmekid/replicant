local module = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

-- Modules
local CombatManager = require(ServerScriptService.modules.combatTagManager)
local AnimationHandler = require(game.ReplicatedStorage.modules.animationHandler)
local StateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local StatScaling = require(game.ReplicatedStorage.modules.StatScaling)
-- [[ NEW REQUIRE ]] --
local DownedManager = require(ServerScriptService.modules.DownedManager)

local DamageNumberRemote = game.ReplicatedStorage.remotes:WaitForChild("DamageNumber")
local CameraShakeRemote = game.ReplicatedStorage.remotes:WaitForChild("CameraShake")

-- Damage above which we add a camera shake (mirrors the red damage-indicator threshold).
local SHAKE_DAMAGE_THRESHOLD = 20

-- Helper to find a stat value inside a model (Player or NPC)
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

-- Reads an invested stat-point value (Vitality/Stamina/Strength/Dexterity/Magic)
-- from PlayerStats.Stats. Returns 0 for non-players (NPCs/bosses), so stat
-- scaling is a no-op against them and nothing nil-indexes.
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

-- [[ ADDED isInstantKill PARAMETER ]] --
-- stunOverride / stunSpeedOverride: optional per-move hitstun. Callers that pass
-- nothing keep the historical 0.85s duration. stunSpeedOverride defaults to 2 so
-- a hit victim is pinned near-immobile (they cannot walk out of an attack); pass a
-- higher value for stuns that should still allow repositioning.
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

	-- [[ 1. APPLY INITIAL COMBAT TAGS (PvP) ]] --
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

	-- [[ 2. APPLY NPC KILL TAG (PvE) ]] --
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

	-- Sanitize inputs
	baseDmg = baseDmg or 0
	extraDmg = extraDmg or 0

	local dmgBoost = getStatValue(attackerChar, "DamageBoost", 1)
	local armorDmgBoost = armorBuffs and armorBuffs:FindFirstChild("DamageBuff").Value or 1
	local defBoost = getStatValue(targetChar, "DefenseBoost", 1)

	-- [[ ADDITIVE DAMAGE COMBINATION + STAT SPREAD SCALING ]] --
	-- All damage sources contribute their bonus to ONE pool, applied once.
	-- race DamageBoost, armor DamageBuff, and the relevant stat are summed
	-- (never multiplied together), so stacking scales linearly, not exponentially.
	--   dmgType "Weapon" -> Strength (M1/E/M2)
	--   dmgType "Skill"  -> Dexterity
	--   dmgType "Racial" -> Dexterity + Magic add-on (dual-scaled)
	--   dmgType nil/other -> no stat scaling (back-compat / true damage)
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

	-- [[ DOWNED SYSTEM INTEGRATION START ]] --
	-- Check if this damage should knock the player down instead of applying damage
	local wasDowned = DownedManager.CheckDownedCondition(targetChar, finalDamage, isInstantKill)

	if wasDowned then
		-- Player was JUST knocked down.
		return finalDamage
	end

	-- [[ THE FIX: Abort the rest of the script if they are ALREADY downed ]] --
	-- This prevents standing hit animations and overlapping stuns from breaking the ragdoll
	if StateHandler.GetState(targetChar, "Downed") then
		-- Hitting a body that is already down refreshes their bleed-out. They do
		-- not take damage (they cannot: the ragdoll owns them), but the clock
		-- restarts, so beating on someone keeps them there.
		DownedManager.ResetReviveTimer(targetChar)
		return finalDamage
	end
	-- [[ DOWNED SYSTEM INTEGRATION END ]] --

	if StateHandler.GetState(attackerChar, "Executing") then
		DownedManager.StopExecution(attackerChar)
	end

	if StateHandler.GetState(targetChar, "DefenseBuff") then
		finalDamage = finalDamage * 0.6
	end

	if StateHandler.GetState(attackerChar, "AttackBuff") then
		finalDamage = finalDamage * 1.3
	end

	-- [[ DEAL DAMAGE ]] --
	targetHum:TakeDamage(finalDamage)

	-- slash fx
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

	-- [[ CAMERA SHAKE on big hits ]] --
	-- Same threshold as the red damage indicator. Taking a hit shakes harder than landing one.
	if finalDamage > SHAKE_DAMAGE_THRESHOLD then
		if targetPlayer then
			CameraShakeRemote:FireClient(targetPlayer, { kind = "Damage", taken = true })
		end
		if attackerPlayer and attackerPlayer ~= targetPlayer then
			CameraShakeRemote:FireClient(attackerPlayer, { kind = "Damage", taken = false })
		end
	end

	-- [[ HIT ANIM ]] --
	-- HYPERARMOR: skip the flinch/hit-react animation on an armored target so it does
	-- not stomp their in-progress swing/cast animation. They still took the damage
	-- above; they just do not visibly flinch out of their move.
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

	-- Hitstun. Weapon hits (M1/M2/E) set their own per-move hitstun in CombatCore's
	-- knockback closures, which run just before this damage call; applying a stun
	-- here too would clobber that per-move value with a flat one. So for dmgType
	-- "Weapon" we skip it and let CombatCore own it. Everything else (skills, racials,
	-- mobs/bosses with dmgType nil) has no such closure, so this is their hitstun:
	-- default 0.85s, walkspeed pinned to 2 (can't walk out), unless the caller passed
	-- explicit overrides.
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

	-- [[ AEGIR RACIAL PASSIVE ]] --
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
