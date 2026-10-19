local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobConfig = require(script.Parent.MobConfig)
local stateManager = require(ReplicatedStorage.modules.stateHandler)
local HitbloxClass = require(ReplicatedStorage.modules.hitboxClass)
local dmgModule = require(ServerScriptService.modules.damageCalculator)
local DownedManager = require(ServerScriptService.modules.DownedManager)
local ParryService = require(ServerScriptService.modules.parryService)

local MobAI = {}

local AGGRO_LEASH_TIME = 8
local WANDER_WAIT_MIN = 3
local WANDER_WAIT_MAX = 6
local UPDATE_RATE = 0.1
local MOVE_UPDATE_RATE = 0.3
local LOS_UPDATE_RATE = 0.5
local SEARCH_DURATION = 10
local SEARCH_WALK_SPEED_MULT = 0.65
local DETECTION_FREEZE_TIME = 0.25

local ORBIT_SPEED_MULT = 0.75
local ORBIT_RANGE_MULT = 1.6
local FLANK_ANGLE_DEG = 120
local REPULSION_RADIUS = 5
local REPULSION_BLEND = 0.35

local MAX_ATTACK_TOKENS = 2
local TOKEN_OVERLAP_WINDOW = 0.05

MobAI.Registry = {}

MobAI.AttackTokens = {}

local aliveFolder = workspace:FindFirstChild("plrManager"):FindFirstChild("alive")

local DETECTION_FX_TEMPLATE = ReplicatedStorage.assets:FindFirstChild("MobDetection")
local DETECTION_SOUND_TEMPLATE = ReplicatedStorage.assets.sounds:FindFirstChild("MobDetectionSound")

local CombatCore = require(game.ServerScriptService.root.serverFramework.Combat._Shared.CombatCore)

local function isAlive(model)
	return model
		and model.PrimaryPart
		and model:FindFirstChild("Humanoid")
		and model.Humanoid.Health > 0
end

local function isPlayerTargetable(char)
	return isAlive(char) and aliveFolder and char:IsDescendantOf(aliveFolder)
end

local function getTokenPool(char)
	if not MobAI.AttackTokens[char] then
		MobAI.AttackTokens[char] = { count = 0, lastFireTime = 0 }
	end
	return MobAI.AttackTokens[char]
end

local function claimAttackToken(char)
	local pool = getTokenPool(char)
	if pool.count >= MAX_ATTACK_TOKENS then
		return false
	end
	if pool.count >= 1 and (os.clock() - pool.lastFireTime) < TOKEN_OVERLAP_WINDOW then
		return false
	end
	pool.count += 1
	return true
end

local function releaseAttackToken(char)
	local pool = getTokenPool(char)
	if pool.count > 0 then
		pool.count -= 1
	end
end

local function markAttackFired(char)
	local pool = getTokenPool(char)
	pool.lastFireTime = os.clock()
end

local function pruneTokenPools()
	for char in pairs(MobAI.AttackTokens) do
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or not char.Parent then
			MobAI.AttackTokens[char] = nil
		end
	end
end

local function playDetectionFX(mob)
	if mob.IsDetecting then
		return
	end
	mob.IsDetecting = true

	local root = mob.Model and mob.Model.PrimaryPart
	if not root then
		mob.IsDetecting = false
		return
	end

	local cfg = MobConfig.Mobs[mob.Name]

	if DETECTION_FX_TEMPLATE then
		local attachTemplate = DETECTION_FX_TEMPLATE:FindFirstChildOfClass("Attachment")
		if attachTemplate then
			local attachClone = attachTemplate:Clone()
			attachClone.Parent = root
			local emitter = attachClone:FindFirstChild("particle")
				or attachClone:FindFirstChildOfClass("ParticleEmitter")
			if emitter then
				emitter:Emit(1)
			end
			game.Debris:AddItem(attachClone, 3)
		end
	end

	if DETECTION_SOUND_TEMPLATE then
		local sound = DETECTION_SOUND_TEMPLATE:Clone()
		sound.Parent = root
		local senseRadius = (cfg and cfg.PackSenseRadius or 100)
		sound.RollOffMaxDistance = senseRadius + 50
		sound:Play()
		game.Debris:AddItem(sound, (sound.TimeLength > 0 and sound.TimeLength or 2) + 0.5)
	end

	mob.Model.Humanoid.WalkSpeed = 0
	mob.Model.Humanoid:MoveTo(root.Position)

	task.delay(DETECTION_FREEZE_TIME, function()
		mob.IsDetecting = false
		if isAlive(mob.Model) and not mob.Dead then
			local mobCfg = MobConfig.Mobs[mob.Name]
			if mobCfg then
				mob.Model.Humanoid.WalkSpeed = mobCfg.WalkSpeed
			end
		end
	end)
end

local function inCone(mobRoot, targetRoot, halfAngleDeg, length)
	local toTarget = targetRoot.Position - mobRoot.Position
	if toTarget.Magnitude > length then
		return false
	end
	local dot = mobRoot.CFrame.LookVector:Dot(toTarget.Unit)
	return dot >= math.cos(math.rad(halfAngleDeg))
end

local function getClosestPlayerInCone(mobRoot, cfg)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then
			continue
		end
		local dist = (char.PrimaryPart.Position - mobRoot.Position).Magnitude
		if dist < bestDist and inCone(mobRoot, char.PrimaryPart, cfg.ConeAngle, cfg.ConeLength) then
			best = char
			bestDist = dist
		end
	end
	return best, bestDist
end

local function getClosestPlayer(position, seekRange)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then
			continue
		end
		local dist = (char.PrimaryPart.Position - position).Magnitude
		if dist <= seekRange and dist < bestDist then
			best = char
			bestDist = dist
		end
	end
	return best, bestDist
end

local function playerInRange(point, range)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if isPlayerTargetable(char) then
			if (char.PrimaryPart.Position - point).Magnitude <= range then
				return true
			end
		end
	end
	return false
end

local function faceTarget(mob, targetPos)
	local root = mob.Model.PrimaryPart
	if not root then
		return
	end
	local gyro = root:FindFirstChild("MobGyro")
	if not gyro then
		return
	end
	local dir = (targetPos - root.Position) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.1 then
		return
	end
	gyro.CFrame = CFrame.new(root.Position, root.Position + dir)
end

local function loadAnimations(animator, animData)
	local result = {}
	for key, value in pairs(animData) do
		if type(value) == "table" then
			result[key] = {}
			for i, id in ipairs(value) do
				local anim = Instance.new("Animation")
				anim.AnimationId = id
				result[key][i] = animator:LoadAnimation(anim)
				anim:Destroy()
			end
		else
			local anim = Instance.new("Animation")
			anim.AnimationId = value
			result[key] = animator:LoadAnimation(anim)
			anim:Destroy()
		end
	end
	return result
end

local function angleFromPlayerFacing(playerRoot, mobRoot)
	local toMob = (mobRoot.Position - playerRoot.Position) * Vector3.new(1, 0, 1)
	if toMob.Magnitude < 0.1 then
		return 0
	end
	local dot = playerRoot.CFrame.LookVector:Dot(toMob.Unit)
	dot = math.clamp(dot, -1, 1)
	return math.deg(math.acos(dot))
end

local function computeOrbitTarget(playerRoot, mobRoot, orbitRadius, orbitDir)
	local toMob = (mobRoot.Position - playerRoot.Position) * Vector3.new(1, 0, 1)
	if toMob.Magnitude < 0.1 then
		toMob = Vector3.new(1, 0, 0)
	end
	local perp = Vector3.new(-toMob.Z * orbitDir, 0, toMob.X * orbitDir).Unit
	local orbitAnchor = playerRoot.Position + toMob.Unit * orbitRadius
	return orbitAnchor + perp * (orbitRadius * 0.5)
end

local function computeRepulsionVector(mob)
	local root = mob.Model.PrimaryPart
	if not root then
		return Vector3.zero
	end
	local repulsion = Vector3.zero
	local myPos = root.Position
	for _, other in pairs(MobAI.Registry) do
		if other == mob then
			continue
		end
		if other.Dead then
			continue
		end
		local otherRoot = other.Model and other.Model.PrimaryPart
		if not otherRoot then
			continue
		end
		local diff = myPos - otherRoot.Position
		local dist = diff.Magnitude
		if dist > 0 and dist < REPULSION_RADIUS then
			repulsion += diff.Unit * ((REPULSION_RADIUS - dist) / REPULSION_RADIUS)
		end
	end
	return repulsion
end

local function startLOSCache(mob)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	task.spawn(function()
		while isAlive(mob.Model) and not mob.Dead do
			task.wait(LOS_UPDATE_RATE)
			if not isAlive(mob.Model) or mob.Dead then
				break
			end

			local root = mob.Model.PrimaryPart
			local cfg = MobConfig.Mobs[mob.Name]
			local closestChar, _ = getClosestPlayer(root.Position, cfg and cfg.SeekRange or 60)

			if not closestChar then
				mob.CanSeePlayer = false
				continue
			end
			local targetRoot = closestChar.PrimaryPart
			if not targetRoot then
				mob.CanSeePlayer = false
				continue
			end

			rayParams.FilterDescendantsInstances = { mob.Model }
			local origin = root.Position + Vector3.new(0, 1.5, 0)
			local targetPos = targetRoot.Position + Vector3.new(0, 1.5, 0)
			local result = workspace:Raycast(origin, targetPos - origin, rayParams)

			if not result or result.Instance:IsDescendantOf(closestChar) then
				mob.CanSeePlayer = true
				mob.LastKnownPosition = targetRoot.Position
				mob.LOSTarget = closestChar
			else
				mob.CanSeePlayer = false
			end
		end
	end)
end

local function broadcastPackAlert(mob, lastKnownPos)
	local cfg = MobConfig.Mobs[mob.Name]
	if not cfg or not cfg.PackID then
		return
	end

	local alertRadius = cfg.PackAlertRadius or 50
	local myPos = mob.Model.PrimaryPart.Position

	for _, packMob in pairs(MobAI.Registry) do
		if packMob == mob then
			continue
		end
		if packMob.Dead then
			continue
		end
		if not isAlive(packMob.Model) then
			continue
		end
		local packCfg = MobConfig.Mobs[packMob.Name]
		if not packCfg or packCfg.PackID ~= cfg.PackID then
			continue
		end
		if (packMob.Model.PrimaryPart.Position - myPos).Magnitude > alertRadius then
			continue
		end
		if packMob.State == "IDLE" or packMob.State == "WANDER" then
			MobAI.ReceiveAlert(packMob, lastKnownPos)
		end
	end
end

local function broadcastPackClear(mob)
	local cfg = MobConfig.Mobs[mob.Name]
	if not cfg or not cfg.PackID then
		return
	end
	local myPos = mob.Model.PrimaryPart.Position
	for _, packMob in pairs(MobAI.Registry) do
		if packMob == mob then
			continue
		end
		if packMob.Dead then
			continue
		end
		if not isAlive(packMob.Model) then
			continue
		end
		local packCfg = MobConfig.Mobs[packMob.Name]
		if not packCfg or packCfg.PackID ~= cfg.PackID then
			continue
		end
		if (packMob.Model.PrimaryPart.Position - myPos).Magnitude > 30 then
			continue
		end
		if packMob.State == "SEARCH" then
			packMob.State = MobConfig.Mobs[packMob.Name].PatrolMode == "WANDER" and "WANDER"
				or "IDLE"
			packMob.SearchTimer = nil
			packMob.SearchTarget = nil
		end
	end
end

local function mergeCombatGroup(mob, targetChar)
	local cfg = MobConfig.Mobs[mob.Name]
	if not cfg or not cfg.PackID then
		return
	end

	local cwCount = 0 -- how many packmates are circling clockwise (OrbitDir = 1)
	local ccwCount = 0 -- counterclockwise (OrbitDir = -1)

	for _, packMob in pairs(MobAI.Registry) do
		if packMob == mob then
			continue
		end
		if packMob.Dead then
			continue
		end
		if packMob.State ~= "CHASE" then
			continue
		end
		if packMob.Target ~= targetChar then
			continue
		end
		local packCfg = MobConfig.Mobs[packMob.Name]
		if not packCfg or packCfg.PackID ~= cfg.PackID then
			continue
		end

		if packMob.OrbitDir == 1 then
			cwCount += 1
		else
			ccwCount += 1
		end
	end

	-- Assign the less-used direction so mobs spread to opposite sides
	if cwCount > ccwCount then
		mob.OrbitDir = -1
	elseif ccwCount > cwCount then
		mob.OrbitDir = 1
	end
	-- If equal (including both zero, meaning first aggro), keep whatever was
	-- randomly assigned when the mob originally spotted the player.
end

function MobAI.ReceiveAlert(mob, lastKnownPos)
	if mob.Dead then
		return
	end
	if mob.State == "CHASE" or mob.State == "SEARCH" then
		return
	end
	if mob.IsDetecting then
		return
	end

	task.spawn(function()
		playDetectionFX(mob)
		task.wait(DETECTION_FREEZE_TIME)
		if mob.Dead or mob.State == "CHASE" then
			return
		end
		mob.SearchTarget = lastKnownPos
		mob.SearchTimer = os.clock()
		mob.State = "SEARCH"
		mob.IsWandering = false
		local cfg = MobConfig.Mobs[mob.Name]
		if cfg then
			mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed * SEARCH_WALK_SPEED_MULT
		end
	end)
end

function MobAI.Register(mob)
	MobAI.Registry[mob.Model] = mob
end

function MobAI.Unregister(mob)
	MobAI.Registry[mob.Model] = nil
end

local function recordDamage(mob, player, amount)
	if not mob.DamageLog then
		mob.DamageLog = {}
	end
	local name = player.Name
	if not mob.DamageLog[name] then
		mob.DamageLog[name] = { Damage = 0, Player = player }
	end
	mob.DamageLog[name].Damage += amount
end

local function getTopDamageDealer(mob)
	if not mob.DamageLog then
		return nil
	end
	local topName, topDmg = nil, 0
	for name, data in pairs(mob.DamageLog) do
		if data.Damage > topDmg then
			topName = name
			topDmg = data.Damage
		end
	end
	if not topName then
		return nil
	end
	return mob.DamageLog[topName].Player
end

local function onDeath(mob)
	local cfg = MobConfig.Mobs[mob.Name]
	if not cfg then
		return
	end
	if not mob.Model or not mob.Model.Parent then
		return
	end
	if not mob.Model.PrimaryPart then
		return
	end

	MobAI.Unregister(mob)

	if mob.AttackTokenTarget and mob.AttackTokenTarget.Parent then
		releaseAttackToken(mob.AttackTokenTarget)
	end
	mob.AttackTokenTarget = nil

	for _, track in ipairs(mob.Model.Humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	local bv = Instance.new("BodyVelocity", mob.Model.PrimaryPart)
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = mob.Model.PrimaryPart.CFrame.LookVector * -20
	game.Debris:AddItem(bv, 0.1)

	local spawnFXTemplate =
		game.ReplicatedStorage.assets.FX:FindFirstChild("NPCSpawnParticle").Main.partic
	if spawnFXTemplate then
		local emitter = spawnFXTemplate:Clone()
		emitter.Parent = mob.Model.PrimaryPart
		emitter:Emit(20)
		game.Debris:AddItem(emitter, 4)
	end

	local ragdollManager = require(ServerScriptService.modules.ragdollManager)
	ragdollManager.Ragdoll(mob.Model, 10)

	local topDealer = getTopDamageDealer(mob)
	if topDealer and topDealer.Character then
		local char = topDealer.Character
		print("Top damage dealer: " .. char.Name)
		local hum = char:FindFirstChild("Humanoid")
		if hum then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.2)
		end
		local dm = _G.DataManager
		if dm and cfg.XPWeapon and cfg.XPAmount then
			dm.AddWeaponXP(topDealer, cfg.XPWeapon, cfg.XPAmount)
		end
		local qm = _G.QuestManager
		if qm and cfg.QuestId then
			qm.IncrementProgress(topDealer, cfg.QuestId, 1)
		end
		if cfg.ItemDrop and math.random() <= (cfg.ItemDropChance or 0) then
			local irm = _G.ItemRewardManager
			if irm then
				irm.GiveReward(topDealer, cfg.ItemDrop)
			end
		end
	end

	mob.Dead = true
	task.wait(4)

	if spawnFXTemplate then
		local emitter = spawnFXTemplate:Clone()
		emitter.Parent = mob.Model.PrimaryPart
		emitter:Emit(20)
		game.Debris:AddItem(emitter, 4)
	end

	task.wait(1)

	if mob.Model and mob.Model.Parent then
		mob.Model:Destroy()
	end
	task.wait(math.max(0, cfg.RespawnTime - 5))
	if mob.Respawn then
		mob:Respawn()
	end
end

local function fireHitbox(mob, damage, isHeavy, attackToken)
	local cfg = MobConfig.Mobs[mob.Name]
	local dmgAmount = isHeavy and (cfg.HeavyDamage or damage * 2) or damage

	local hitbox, success = HitbloxClass.new({
		SizeOrPart = 8,
		Debug = false,
		DebounceTime = 0.5,
		Blacklist = { mob.Model },
	})

	hitbox:WeldTo(mob.Model.PrimaryPart, CFrame.new(0, -1, -3))
	if not success or not hitbox then
		return
	end

	CombatCore.MarkHitbox(attackToken)

	hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			if not isAlive(mob.Model) then
				break
			end
			if hit.Name == mob.Model.Name then
				continue
			end

			local hyperarmor = mob.Model:FindFirstChild("Values")
				and mob.Model.Values:FindFirstChild("Hyperarmor")
				and mob.Model.Values.Hyperarmor.Value

			if stateManager.GetState(mob.Model, "Stunned") and not isHeavy and not hyperarmor then
				hitbox:Destroy()
				return
			end

			if not hit or not isAlive(hit) then
				continue
			end
			if hit.Humanoid == mob.Model.Humanoid then
				continue
			end

			-- clash with the target's attack (shared registry with players)
			local clashOutcome, clashTarget = CombatCore.ResolveClash(attackToken, hit)
			if clashOutcome == "lose" then
				if attackToken then
					attackToken.cancelled = true
				end
				hitbox:Destroy()
				return
			elseif clashOutcome == "win" then
				clashTarget.cancelled = true
			end
			local isParrying = stateManager.GetState(hit, "Parrying")
			local isBlocking = stateManager.GetState(hit, "Blocking")
			local isDodging = stateManager.GetState(hit, "Dodging")

			if isParrying then
				stateManager.SetStun(mob.Model, true, 2, 2)
				stateManager.SetState(mob.Model, "Parried", true, 2)
				local stunAnimId = mob.Model.Humanoid.RigType == Enum.HumanoidRigType.R6
						and "rbxassetid://10700696839"
					or "rbxassetid://71380271624004"
				local stunAnim = Instance.new("Animation")
				stunAnim.AnimationId = stunAnimId
				local track = mob.Model.Humanoid:LoadAnimation(stunAnim)
				track.Priority = Enum.AnimationPriority.Action4
				track:Play()
				mob.Model["Right Arm"].parry:Play()
				local fxFolder = ReplicatedStorage.assets.FX["parry/blocked"]
				local parryFX = fxFolder.parry:Clone()
				local clashFX = fxFolder.Clash:Clone()
				parryFX.Parent = mob.Model:WaitForChild("Torso")
				clashFX.Parent = mob.Model:WaitForChild("Right Arm")
				parryFX.Enabled = true
				clashFX:Emit(30)
				game.Debris:AddItem(parryFX, 0.7)
				game.Debris:AddItem(clashFX, 0.7)
				local targetPlrData = game.Players:GetPlayerFromCharacter(hit).PlayerStats
				if targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
					targetPlrData.Mana.Value += 8
				end
				ParryService.ResetParry(game.Players:GetPlayerFromCharacter(hit))
				require(game:GetService("ServerScriptService").modules.BlockResolver).OnParrySuccess(
					hit
				)
				ReplicatedStorage.remotes.replicate:FireClient(
					game.Players:GetPlayerFromCharacter(hit),
					{
						Type = "Combat",
						Action = "M1",
						Func = "Parry",
						FolderName = (
							hit:FindFirstChildOfClass("Tool")
							and hit:FindFirstChildOfClass("Tool").Name
						) or "Katana",
					},
					mob.Model,
					hit
				)
				hitbox:Destroy()
				return
			elseif isBlocking then
				-- Route through the shared BlockResolver so a mob hit feeds the
				-- player's guard bar (fill / block-break / facing). Heavy attacks
				-- guardbreak, matching the prior isHeavy = full-damage behavior.
				local BlockResolver =
					require(game:GetService("ServerScriptService").modules.BlockResolver)
				local mobHRP = mob.Model:FindFirstChild("HumanoidRootPart")
				local verdict = BlockResolver.Resolve({
					attacker = mob.Model,
					target = hit,
					attackerHRP = mobHRP,
					targetHRP = hit:FindFirstChild("HumanoidRootPart"),
					guardbreak = isHeavy,
					attackClass = isHeavy and "M2" or "M1",
					dmg = dmgAmount,
				})

				if verdict.outcome == "GuardBreak" then
					mob.LastSuccessfulHitTime = os.clock()
					if verdict.broke then
						dmgModule.CalculateDamage(mob.Model, hit, verdict.chipDamage, 0)
					else
						dmgModule.CalculateDamage(mob.Model, hit, dmgAmount, 0)
					end
				elseif verdict.outcome == "Bypass" then
					dmgModule.CalculateDamage(mob.Model, hit, dmgAmount, 0)
				else
					dmgModule.CalculateDamage(mob.Model, hit, verdict.chipDamage, 0)
				end
				local parryE = mob.Model.ToolFolder.Effects.parry:Clone()
				parryE.Parent = hit:WaitForChild("Torso")
				parryE.Enabled = true
				game.Debris:AddItem(parryE, 0.7)
				mob.Model["Right Arm"].ParryDraw:Play()
			elseif isDodging then
				local sound = mob.Model.ToolFolder.Dodged:Clone()
				sound.Parent = hit.HumanoidRootPart
				sound:Play()
				game.Debris:AddItem(sound, 1)
				local targetPlrData = game.Players:GetPlayerFromCharacter(hit).PlayerStats
				if targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
					targetPlrData.Mana.Value += 8
				end
				local effect = ReplicatedStorage.assets.FX.Dodged:Clone()
				effect.Parent = hit:FindFirstChild("HumanoidRootPart")
				effect.Enabled = true
				game.Debris:AddItem(sound, 3)
				game.Debris:AddItem(effect, 0.3)
			else
				mob.LastSuccessfulHitTime = os.clock()
				local killTag = mob.Model.Humanoid:FindFirstChild("KillTag")
				local player = Players:GetPlayerFromCharacter(hit)
				if killTag and player then
					killTag.Value = player.Name
				end
				dmgModule.CalculateDamage(mob.Model, hit, dmgAmount, 0)
				mob.Model["Right Arm"].Hit1:Play()
				local hitAnimId = "rbxassetid://96311777205911"
				local reactionAnim = Instance.new("Animation")
				reactionAnim.AnimationId = hitAnimId
				local track = hit.Humanoid:LoadAnimation(reactionAnim)
				track.Priority = Enum.AnimationPriority.Action4
				track:Play()
				task.delay(0.4, function()
					track:Stop(0.1)
				end)
			end
		end
	end)

	hitbox:Start()
	task.wait(0.15)
	hitbox:Destroy()
end

local function handleAttack(mob, target, cfg)
	local targetChar = target
	pruneTokenPools()
	if not claimAttackToken(targetChar) then
		return
	end
	mob.AttackTokenTarget = targetChar

	mob.IsAttacking = true
	mob.LastAttack = os.clock()

	local attackToken = CombatCore.BeginAttack(mob.Model)

	local attackSound = mob.Model["Right Arm"].SwordLunge
	attackSound:Play()

	local attackAnims = mob.Animations.Attack
	local idx
	if cfg.AttackSequence == "LIST" then
		mob.AttackIndex = (mob.AttackIndex or 0) % #attackAnims + 1
		idx = mob.AttackIndex
	else
		idx = math.random(1, #attackAnims)
	end

	faceTarget(mob, target.PrimaryPart.Position)
	local attackAnim = attackAnims[idx]
	if attackAnim then
		attackAnim:Play()
	end

	local windupTime = cfg.WindupTime + math.random() * (cfg.WindupVariance or 0)
	local elapsed = 0
	while elapsed < windupTime do
		if attackToken.cancelled or not isAlive(mob.Model) then
			break
		end
		task.wait(math.min(0.05, windupTime - elapsed))
		elapsed += 0.05
	end

	if attackToken.cancelled or not isAlive(mob.Model) then
		if attackAnim then
			attackAnim:Stop(0.1)
		end
		mob.IsAttacking = false
		releaseAttackToken(targetChar)
		mob.AttackTokenTarget = nil
		CombatCore.FinishAttack(mob.Model, attackToken)
		return
	end

	local isHeavy = math.random() < (cfg.HeavyAttackChance or 0)

	if isHeavy then
		local dangerFX = game.ReplicatedStorage.assets.FX.danger:Clone()
		local weld = Instance.new("WeldConstraint", dangerFX)
		dangerFX.Parent = mob.Model
		dangerFX.CFrame = mob.Model.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
		weld.Part0 = mob.Model.HumanoidRootPart
		weld.Part1 = dangerFX
		local tween = game.TweenService:Create(
			dangerFX,
			TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		tween:Play()
		game.Debris:AddItem(dangerFX, 1)
		local dangerSound = game.ReplicatedStorage.assets.sounds:FindFirstChild("DANGER")
		if dangerSound then
			local s = dangerSound:Clone()
			s.Parent = mob.Model.PrimaryPart
			s:Play()
			game.Debris:AddItem(s, 2)
		end
		fireHitbox(mob, cfg.Damage, true, attackToken)
	else
		fireHitbox(mob, cfg.Damage, false, attackToken)
	end

	markAttackFired(targetChar)
	releaseAttackToken(targetChar)
	mob.AttackTokenTarget = nil
	mob.IsAttacking = false
	CombatCore.FinishAttack(mob.Model, attackToken)
	mob.AttackCycle = (mob.AttackCycle or 0) + 1
	mob.State = "CHASE"
end

local function handleWander(mob, cfg)
	if mob.IsWandering then
		return
	end
	mob.IsWandering = true

	task.spawn(function()
		while mob.State == "WANDER" and isAlive(mob.Model) do
			local spawnPos = mob.SpawnCFrame.Position
			local angle = math.random() * math.pi * 2
			local radius = math.random() * (cfg.WanderRadius or 20)
			local dest = spawnPos
				+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed / 2
			faceTarget(mob, dest)
			mob.Model.Humanoid:MoveTo(dest)
			if mob.Animations.SlowWalk and not mob.Animations.SlowWalk.IsPlaying then
				mob.Animations.SlowWalk:Play()
			end
			local timeout = 6
			local elapsed = 0
			repeat
				elapsed += task.wait(0.25)
				if not isAlive(mob.Model) then
					break
				end
				if mob.State ~= "WANDER" then
					break
				end
			until (mob.Model.PrimaryPart.Position - dest).Magnitude < 3 or elapsed >= timeout
			if mob.State ~= "WANDER" then
				break
			end
			mob.Model.Humanoid:MoveTo(mob.Model.PrimaryPart.Position)
			if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
				mob.Animations.SlowWalk:Stop()
			end
			if not mob.Animations.Idle.IsPlaying then
				mob.Animations.Idle:Play()
			end
			task.wait(math.random(WANDER_WAIT_MIN, WANDER_WAIT_MAX))
		end
		mob.IsWandering = false
	end)
end

local function handleSearch(mob, cfg)
	if mob.IsSearching then
		return
	end
	mob.IsSearching = true

	task.spawn(function()
		local searchPos = mob.SearchTarget
		if not searchPos then
			mob.IsSearching = false
			mob.State = cfg.PatrolMode == "WANDER" and "WANDER" or "IDLE"
			return
		end

		mob.Model.Humanoid:MoveTo(searchPos)
		if not mob.Animations.Walk.IsPlaying then
			mob.Animations.Idle:Stop()
			if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
				mob.Animations.SlowWalk:Stop()
			end
			mob.Animations.Walk:Play()
		end

		local travelTimeout = 6
		local travelElapsed = 0
		repeat
			travelElapsed += task.wait(0.25)
			if not isAlive(mob.Model) or mob.Dead then
				break
			end
			if mob.State ~= "SEARCH" then
				mob.IsSearching = false
				return
			end
			if mob.CanSeePlayer and mob.LOSTarget and isPlayerTargetable(mob.LOSTarget) then
				mob.Target = mob.LOSTarget
				mob.Aggroed = true
				mob.AggroLostTime = nil
				mob.State = "CHASE"
				mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
				mergeCombatGroup(mob, mob.LOSTarget)
				mob.IsSearching = false
				return
			end
		until (mob.Model.PrimaryPart.Position - searchPos).Magnitude < 4
			or travelElapsed >= travelTimeout

		if mob.State ~= "SEARCH" then
			mob.IsSearching = false
			return
		end

		mob.Model.Humanoid:MoveTo(mob.Model.PrimaryPart.Position)
		if mob.Animations.Walk.IsPlaying then
			mob.Animations.Walk:Stop()
		end
		if not mob.Animations.Idle.IsPlaying then
			mob.Animations.Idle:Play()
		end

		local lookElapsed = 0
		local lookAccum = 0

		while mob.State == "SEARCH" and isAlive(mob.Model) and not mob.Dead do
			local dt = task.wait(0.1)
			lookElapsed += dt
			lookAccum += dt
			if mob.CanSeePlayer and mob.LOSTarget and isPlayerTargetable(mob.LOSTarget) then
				mob.Target = mob.LOSTarget
				mob.Aggroed = true
				mob.AggroLostTime = nil
				mob.State = "CHASE"
				mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
				mergeCombatGroup(mob, mob.LOSTarget)
				mob.IsSearching = false
				return
			end
			if lookAccum >= 1.5 then
				lookAccum = 0
				local root = mob.Model.PrimaryPart
				if root then
					local gyro = root:FindFirstChild("MobGyro")
					if gyro then
						gyro.CFrame = CFrame.fromEulerAnglesXYZ(0, math.random(0, 628) / 100, 0)
							+ root.Position
					end
				end
			end
			if lookElapsed >= SEARCH_DURATION then
				break
			end
		end

		if mob.State ~= "SEARCH" then
			mob.IsSearching = false
			return
		end

		broadcastPackClear(mob)
		mob.SearchTarget = nil
		mob.SearchTimer = nil
		mob.IsSearching = false
		mob.State = cfg.PatrolMode == "WANDER" and "WANDER" or "IDLE"
		mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
		mob.Model.Humanoid:MoveTo(mob.SpawnCFrame.Position)
	end)
end

local function handleObstacleJumping(mob, target)
	local root = mob.Model.PrimaryPart
	local targetRoot = target.PrimaryPart
	local hum = mob.Model:FindFirstChild("Humanoid")
	if not root or not targetRoot or not hum then
		return
	end

	local toTarget = targetRoot.Position - root.Position
	local flatDist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
	local yDiff = toTarget.Y
	if flatDist <= 4 then
		return
	end

	local shouldJump = false
	if yDiff > 3 then
		shouldJump = true
	else
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { mob.Model, target }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(root.Position, root.CFrame.LookVector * 3, rayParams)
		if result then
			shouldJump = true
		end
	end
	if shouldJump then
		hum.Jump = true
	end
end

function MobAI.Update(mob)
	if not isAlive(mob.Model) then
		return
	end
	if mob.Dead then
		return
	end
	if mob.IsDetecting then
		return
	end
	if os.clock() - (mob.LastUpdate or 0) < UPDATE_RATE then
		return
	end
	mob.LastUpdate = os.clock()

	local cfg = MobConfig.Mobs[mob.Name]
	local root = mob.Model.PrimaryPart

	-- Hide/show
	if not playerInRange(root.Position, cfg.NPCHideRange) then
		mob.Model.Parent = ReplicatedStorage
		return
	else
		if mob.Model.Parent ~= aliveFolder then
			mob.Model.Parent = aliveFolder
		end
	end

	-- Stun
	if stateManager.GetState(mob.Model, "Stunned") then
		if mob.AttackTokenTarget then
			releaseAttackToken(mob.AttackTokenTarget)
			mob.AttackTokenTarget = nil
		end
		mob.IsAttacking = false
		mob.Model.Humanoid:MoveTo(root.Position)
		if mob.Animations.Walk.IsPlaying then
			mob.Animations.Walk:Stop()
		end
		return
	end

	if mob.IsAttacking then
		return
	end

	if mob.State == "IDLE" or mob.State == "WANDER" then
		if mob.Model.Humanoid.Health == mob.Model.Humanoid.MaxHealth then
			local target = getClosestPlayerInCone(root, cfg)
			if target then
				mob.Target = target
				mob.Aggroed = true
				mob.AggroLostTime = nil
				mob.OrbitDir = (math.random() < 0.5) and 1 or -1
				task.spawn(function()
					playDetectionFX(mob)
					task.wait(DETECTION_FREEZE_TIME)
					if mob.Dead then
						return
					end
					mob.State = "CHASE"
					mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
					mergeCombatGroup(mob, target)
					broadcastPackAlert(mob, target.PrimaryPart.Position)
				end)
				if mob.Animations.Idle.IsPlaying then
					mob.Animations.Idle:Stop()
				end
				if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
					mob.Animations.SlowWalk:Stop()
				end
				return
			end
		else
			local target, _ = getClosestPlayer(root.Position, cfg.SeekRange)
			if target then
				mob.Target = target
				mob.Aggroed = true
				mob.AggroLostTime = nil
				mob.OrbitDir = (math.random() < 0.5) and 1 or -1
				task.spawn(function()
					playDetectionFX(mob)
					task.wait(DETECTION_FREEZE_TIME)
					if mob.Dead then
						return
					end
					mob.State = "CHASE"
					mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
					mergeCombatGroup(mob, target)
					broadcastPackAlert(mob, target.PrimaryPart.Position)
				end)
				if mob.Animations.Idle.IsPlaying then
					mob.Animations.Idle:Stop()
				end
				if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
					mob.Animations.SlowWalk:Stop()
				end
				return
			end
		end

		if mob.State == "IDLE" then
			if not mob.Animations.Idle.IsPlaying then
				mob.Animations.Idle:Play()
			end
			if mob.Animations.Walk.IsPlaying then
				mob.Animations.Walk:Stop()
			end
		else
			handleWander(mob, cfg)
		end
	elseif mob.State == "SEARCH" then
		if mob.CanSeePlayer and mob.LOSTarget and isPlayerTargetable(mob.LOSTarget) then
			mob.Target = mob.LOSTarget
			mob.Aggroed = true
			mob.AggroLostTime = nil
			mob.State = "CHASE"
			mob.IsSearching = false
			mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
			mergeCombatGroup(mob, mob.LOSTarget)
			broadcastPackAlert(mob, mob.LOSTarget.PrimaryPart.Position)
			return
		end
		handleSearch(mob, cfg)
	elseif mob.State == "CHASE" then
		local target, dist = getClosestPlayer(root.Position, cfg.SeekRange)

		if not target then
			if not mob.AggroLostTime then
				mob.AggroLostTime = os.clock()
			elseif os.clock() - mob.AggroLostTime > AGGRO_LEASH_TIME then
				mob.Target = nil
				mob.Aggroed = false
				mob.AggroLostTime = nil
				if mob.LastKnownPosition then
					mob.SearchTarget = mob.LastKnownPosition
					mob.SearchTimer = os.clock()
					mob.State = "SEARCH"
					mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed * SEARCH_WALK_SPEED_MULT
				else
					mob.State = cfg.PatrolMode == "WANDER" and "WANDER" or "IDLE"
					mob.Model.Humanoid:MoveTo(mob.SpawnCFrame.Position)
				end
			end
			return
		end

		mob.Target = target
		mob.AggroLostTime = nil

		local isDowned = target:GetAttribute("Downed") == true
		local isCarried = target:GetAttribute("Carried") == true

		if isDowned and not isCarried then
			faceTarget(mob, target.PrimaryPart.Position)
			if dist <= cfg.AttackRange then
				if mob.State ~= "EXECUTING" then
					mob.State = "EXECUTING"
					mob.Model.Humanoid:MoveTo(mob.Model.PrimaryPart.Position)
					faceTarget(mob, target.PrimaryPart.Position)
					DownedManager.NPCExecute(mob.Model, target)
					task.delay(3, function()
						if mob.State == "EXECUTING" then
							mob.State = "CHASE"
							mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
						end
					end)
				end
			else
				if os.clock() - (mob.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
					mob.LastMoveUpdate = os.clock()
					mob.Model.Humanoid:MoveTo(target.PrimaryPart.Position)
					handleObstacleJumping(mob, target)
				end
				if not mob.Animations.Walk.IsPlaying then
					mob.Animations.Idle:Stop()
					if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
						mob.Animations.SlowWalk:Stop()
					end
					mob.Animations.Walk:Play()
				end
			end
			return
		else
			if os.clock() - (mob.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
				mob.LastMoveUpdate = os.clock()
				mob.Model.Humanoid:MoveTo(target.PrimaryPart.Position)
				handleObstacleJumping(mob, target)
			end

			faceTarget(mob, target.PrimaryPart.Position)

			if not mob.Animations.Walk.IsPlaying then
				mob.Animations.Idle:Stop()
				if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
					mob.Animations.SlowWalk:Stop()
				end
				mob.Animations.Walk:Play()
			end
		end

		local targetRoot = target.PrimaryPart
		local orbitRadius = cfg.AttackRange * ORBIT_RANGE_MULT
		local attackCooldown = cfg.AttackSpeed + math.random() * (cfg.AttackSpeedVariance or 0)
		local cooldownReady = (os.clock() - (mob.LastAttack or 0)) >= attackCooldown

		local isFlanking = false
		if targetRoot then
			isFlanking = angleFromPlayerFacing(targetRoot, root) > FLANK_ANGLE_DEG
		end

		local repulsion = computeRepulsionVector(mob)

		if dist <= cfg.AttackRange and cooldownReady then
			mob.Model.Humanoid:MoveTo(root.Position + repulsion * REPULSION_BLEND)
			if mob.Animations.Walk.IsPlaying then
				mob.Animations.Walk:Stop()
			end
			if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
				mob.Animations.SlowWalk:Stop()
			end
			if not mob.Animations.Idle.IsPlaying then
				mob.Animations.Idle:Play()
			end
			faceTarget(mob, targetRoot.Position)
			if not mob.IsAttacking then
				task.spawn(handleAttack, mob, target, cfg)
			end
		elseif dist <= cfg.AttackRange and not cooldownReady then
			local holdPos = root.Position + repulsion * REPULSION_BLEND
			mob.Model.Humanoid:MoveTo(holdPos)
			faceTarget(mob, targetRoot.Position)
			if mob.Animations.Walk.IsPlaying then
				mob.Animations.Walk:Stop()
			end
			if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
				mob.Animations.SlowWalk:Stop()
			end
			if not mob.Animations.Idle.IsPlaying then
				mob.Animations.Idle:Play()
			end
		elseif isFlanking and dist <= orbitRadius * 1.2 and cooldownReady then
			mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
			if os.clock() - (mob.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
				mob.LastMoveUpdate = os.clock()
				mob.Model.Humanoid:MoveTo(targetRoot.Position)
				handleObstacleJumping(mob, target)
			end

			faceTarget(mob, targetRoot.Position)

			if not mob.Animations.Walk.IsPlaying then
				mob.Animations.Idle:Stop()
				if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
					mob.Animations.SlowWalk:Stop()
				end
				mob.Animations.Walk:Play()
			end
		else
			local pool = getTokenPool(target)
			local tokensFull = pool.count >= MAX_ATTACK_TOKENS

			if tokensFull then
				mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed * ORBIT_SPEED_MULT
				if os.clock() - (mob.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
					mob.LastMoveUpdate = os.clock()
					local orbitTarget =
						computeOrbitTarget(targetRoot, root, orbitRadius, mob.OrbitDir or 1)
					local finalTarget = orbitTarget + repulsion * REPULSION_BLEND
					mob.Model.Humanoid:MoveTo(finalTarget)
					faceTarget(mob, targetRoot.Position)
				end
				if mob.Animations.Walk.IsPlaying then
					mob.Animations.Walk:Stop()
				end
				if mob.Animations.SlowWalk and not mob.Animations.SlowWalk.IsPlaying then
					mob.Animations.Idle:Stop()
					mob.Animations.SlowWalk:Play()
				end
			else
				mob.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
				if os.clock() - (mob.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
					mob.LastMoveUpdate = os.clock()
					local advanceTarget = targetRoot.Position + repulsion * REPULSION_BLEND
					mob.Model.Humanoid:MoveTo(advanceTarget)
					handleObstacleJumping(mob, target)
				end

				faceTarget(mob, targetRoot.Position)

				if not mob.Animations.Walk.IsPlaying then
					mob.Animations.Idle:Stop()
					if mob.Animations.SlowWalk and mob.Animations.SlowWalk.IsPlaying then
						mob.Animations.SlowWalk:Stop()
					end
					mob.Animations.Walk:Play()
				end
			end
		end
	elseif mob.State == "HEAVY" or mob.State == "ATTACKING" or mob.State == "EXECUTING" then
		return
	end
end

function MobAI.Spawn(mobName, spawnCFrame)
	local cfg = MobConfig.Mobs[mobName]
	if not cfg then
		warn("[MobAI] No config for: " .. mobName)
		return
	end

	local storage = game:GetService("ServerStorage")
	local template = storage:FindFirstChild("Mobs") and storage.Mobs:FindFirstChild(mobName)
	if not template then
		warn("[MobAI] No model in ServerStorage.Mobs for: " .. mobName)
		return
	end

	local model = template:Clone()
	model:SetPrimaryPartCFrame(spawnCFrame)
	model.Parent = aliveFolder

	local hum = model:FindFirstChild("Humanoid")
	if not hum then
		warn("[MobAI] No Humanoid in: " .. mobName)
		model:Destroy()
		return
	end

	hum.MaxHealth = cfg.Health
	hum.Health = cfg.Health
	hum.WalkSpeed = cfg.WalkSpeed
	hum.JumpPower = cfg.JumpPower
	hum.BreakJointsOnDeath = false

	local spawnFXTemplate =
		game.ReplicatedStorage.assets.FX:FindFirstChild("NPCSpawnParticle").Main.partic
	if spawnFXTemplate then
		local emitter = spawnFXTemplate:Clone()
		emitter.Parent = model.PrimaryPart
		emitter:Emit(20)
		game.Debris:AddItem(emitter, 4)
	end

	local gyro = Instance.new("BodyGyro")
	gyro.Name = "MobGyro"
	gyro.MaxTorque = Vector3.new(0, 4e5, 0)
	gyro.D = 200
	gyro.P = 3000
	gyro.CFrame = spawnCFrame
	gyro.Parent = model.PrimaryPart

	model:SetAttribute("LiturgyWorth", cfg.LiturgyWorth or 0)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CastShadow = cfg.CastShadow
		end
	end

	if not model:FindFirstChild("Values") then
		local v = Instance.new("Folder", model)
		v.Name = "Values"
		local h = Instance.new("BoolValue", v)
		h.Name = "Hyperarmor"
		h.Value = false
	end

	local animator = hum:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anims = loadAnimations(animator, cfg.Animations)
	if anims.Idle then
		anims.Idle:Play()
	end

	local killTag = Instance.new("StringValue")
	killTag.Name = "KillTag"
	killTag.Parent = hum

	local mob = {
		Name = mobName,
		Model = model,
		Animations = anims,
		SpawnCFrame = spawnCFrame,
		State = cfg.PatrolMode == "WANDER" and "WANDER" or "IDLE",
		StateTimer = 0,
		LastUpdate = 0,
		LastAttack = 0,
		LastMoveUpdate = 0,
		AttackIndex = 0,
		AttackCycle = 0,
		IsAttacking = false,
		IsWandering = false,
		IsSearching = false,
		IsDetecting = false,
		Aggroed = false,
		Target = nil,
		AggroLostTime = nil,
		Dead = false,
		DamageLog = {},
		LastSuccessfulHitTime = 0,
		CanSeePlayer = false,
		LastKnownPosition = nil,
		LOSTarget = nil,
		SearchTarget = nil,
		SearchTimer = nil,
		OrbitDir = 1,
		AttackTokenTarget = nil,
	}

	MobAI.Register(mob)
	startLOSCache(mob)

	local deathConn
	deathConn = hum.Died:Connect(function()
		task.spawn(onDeath, mob)
		deathConn:Disconnect()
	end)

	hum.HealthChanged:Connect(function(newHealth)
		local delta = hum.MaxHealth - newHealth
		if delta <= 0 then
			return
		end
		local tag = hum:FindFirstChild("KillTag")
		if not tag then
			return
		end
		local killer = Players:FindFirstChild(tag.Value)
		if killer then
			recordDamage(mob, killer, delta)
		end
	end)

	return mob
end

return MobAI
