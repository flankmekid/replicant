local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local MobConfig     = require(script.Parent.MobConfig)
local stateManager  = require(ReplicatedStorage.modules.stateHandler)
local HitbloxClass  = require(ReplicatedStorage.modules.hitboxClass)
local dmgModule     = require(ServerScriptService.modules.damageCalculator)
local DownedManager = require(ServerScriptService.modules.DownedManager)
local ParryService  = require(ServerScriptService.modules.parryService)

local BossAI = {}

local UPDATE_RATE      = 0.1
local MOVE_UPDATE_RATE = 0.3
local AGGRO_LEASH_TIME = 10
local AOE_WINDUP       = 1.5

local BossAtks = ReplicatedStorage.assets.BossAtks

local function getAliveFolder()
	local pm = workspace:FindFirstChild("plrManager")
	return pm and pm:FindFirstChild("alive") or workspace
end


local function isAlive(model)
	return model
		and model.PrimaryPart
		and model:FindFirstChild("Humanoid")
		and model.Humanoid.Health > 0
end

local function isPlayerTargetable(char)
	local af = getAliveFolder()
	return isAlive(char) and af and char:IsDescendantOf(af)
end

local function faceTarget(boss, targetPos)
	local root = boss.Model.PrimaryPart
	if not root then return end
	local gyro = root:FindFirstChild("MobGyro")
	if not gyro then return end
	local dir = (targetPos - root.Position) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.1 then return end
	gyro.CFrame = CFrame.new(root.Position, root.Position + dir)
end

local function playSound(boss, soundName)
	local arm = boss.Model:FindFirstChild("Right Arm")
	if not arm then return end
	local sound = arm:FindFirstChild(soundName)
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = arm
	clone:Play()
	game.Debris:AddItem(clone, clone.TimeLength + 0.5)
end

local function playBlast(boss)
	local arm = boss.Model:FindFirstChild("Right Arm")
	if not arm then return end
	local blastName = math.random() < 0.5 and "Blast" or "Blast2"
	local sound = arm:FindFirstChild(blastName)
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = arm
	clone:Play()
	game.Debris:AddItem(clone, clone.TimeLength + 0.5)
end

local function loadAnimations(animator, animData)
	local result = {}
	for key, value in pairs(animData) do
		if type(value) == "table" then
			result[key] = {}
			for subKey, id in pairs(value) do
				local anim = Instance.new("Animation")
				anim.AnimationId = id
				result[key][subKey] = animator:LoadAnimation(anim)
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


local function recordThreat(boss, player, amount)
	if not boss.ThreatTable then boss.ThreatTable = {} end
	local name = player.Name
	if not boss.ThreatTable[name] then
		boss.ThreatTable[name] = { Threat = 0, Player = player }
	end
	boss.ThreatTable[name].Threat += amount
end

local function rollAggro(boss, cfg)
	if not boss.ThreatTable then return nil end
	local candidates = {}
	for _, data in pairs(boss.ThreatTable) do
		local player = data.Player
		if player and player.Character and isPlayerTargetable(player.Character) then
			local dist = (player.Character.PrimaryPart.Position - boss.Model.PrimaryPart.Position).Magnitude
			if dist <= cfg.SeekRange then
				table.insert(candidates, { player = player, threat = data.Threat })
			end
		end
	end
	if #candidates == 0 then return nil end

	local totalWeight = 0
	for _, c in ipairs(candidates) do
		c.weight = c.threat + 100
		totalWeight += c.weight
	end

	local roll = math.random() * totalWeight
	local accumulated = 0
	for _, c in ipairs(candidates) do
		accumulated += c.weight
		if roll <= accumulated then return c.player.Character end
	end
	return candidates[1].player.Character
end

local function getClosestPlayer(position, seekRange)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and isPlayerTargetable(char) then
			local dist = (char.PrimaryPart.Position - position).Magnitude
			if dist <= seekRange and dist < bestDist then
				best     = char
				bestDist = dist
			end
		end
	end
	return best
end


local function pulseIndicator(indicator, windupTime)
	local elapsed = 0
	while elapsed < windupTime do
		local dt = task.wait(0.1)
		elapsed += dt
		if not indicator.Parent then return end
		local progress = elapsed / windupTime
		indicator.Transparency = 0.3 + 0.5 * math.abs(math.sin(progress * math.pi * (2 + progress * 6)))
	end
end

local function getFloorY(root)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { root.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), params)
	if result then
		return result.Position.Y
	end
	return root.Position.Y - root.Size.Y / 2
end

local function flatCFrame(position, forward)
	local f = Vector3.new(forward.X, 0, forward.Z).Unit
	if f.Magnitude < 0.01 then f = Vector3.new(0, 0, 1) end
	local r = Vector3.new(f.Z, 0, -f.X)
	return CFrame.fromMatrix(position, r, Vector3.new(0, 1, 0), -f)
end

local function xzDist(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end


local function aoeCircle(boss, aoeDef, cfg)
	if boss.Animations.AOE and boss.Animations.AOE.Circle then
		boss.Animations.AOE.Circle:Play()
	end
	playSound(boss, "Charge")

	local root   = boss.Model.PrimaryPart
	local radius = aoeDef.Radius or 20
	local floorY = getFloorY(root)

	local indicator = BossAtks.CircleAttack:Clone()
	indicator.Anchored   = true
	indicator.CanCollide = false
	indicator.CanTouch   = false
	local src = BossAtks.CircleAttack
	local rot = CFrame.fromMatrix(Vector3.zero, src.CFrame.XVector, src.CFrame.YVector, src.CFrame.ZVector)
	indicator.CFrame = CFrame.new(root.Position.X, floorY + 0.1, root.Position.Z) * rot
	indicator.Parent     = workspace

	pulseIndicator(indicator, AOE_WINDUP)
	if indicator.Parent then indicator:Destroy() end
	if not isAlive(boss.Model) then return end
	playBlast(boss)

	local bossPos = root.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then continue end
		if stateManager.GetState(char, "Dodging") then continue end
		-- XZ only: jumping doesn't help
		if xzDist(char.PrimaryPart.Position, bossPos) <= radius then
			dmgModule.CalculateDamage(boss.Model, char, aoeDef.Damage or cfg.Damage, 0)
		end
	end
end

local function aoeLine(boss, aoeDef, target, cfg)
	if boss.Animations.AOE and boss.Animations.AOE.Line then
		boss.Animations.AOE.Line:Play()
	end
	playSound(boss, "Charge")

	local root      = boss.Model.PrimaryPart
	local targetPos = target.PrimaryPart.Position
	local dir       = (targetPos - root.Position) * Vector3.new(1, 0, 1)
	local forward   = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector

	local length = aoeDef.Length or 20
	local width  = aoeDef.Width  or 6
	local floorY = getFloorY(root)

	local midPoint = Vector3.new(
		root.Position.X + forward.X * (length / 2),
		floorY + 0.1,
		root.Position.Z + forward.Z * (length / 2)
	)

	local indicator = BossAtks.LineAttack:Clone()
	indicator.Anchored   = true
	indicator.CanCollide = false
	indicator.CanTouch   = false
	indicator.CFrame = flatCFrame(midPoint, forward) * CFrame.Angles(0, math.rad(90), 0)
	indicator.Parent     = workspace

	pulseIndicator(indicator, AOE_WINDUP)
	if indicator.Parent then indicator:Destroy() end
	if not isAlive(boss.Model) then return end
	playBlast(boss)

	local bossPos  = root.Position
	local fwd      = Vector3.new(forward.X, 0, forward.Z)
	local right    = Vector3.new(forward.Z, 0, -forward.X)

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then continue end
		if stateManager.GetState(char, "Dodging") then continue end
		-- Project onto XZ plane only — jumping doesn't help
		local toPlayer = char.PrimaryPart.Position - bossPos
		local toPlayerXZ = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		local along = fwd:Dot(toPlayerXZ)
		local side  = math.abs(right:Dot(toPlayerXZ))
		if along >= 0 and along <= length and side <= width / 2 then
			dmgModule.CalculateDamage(boss.Model, char, aoeDef.Damage or cfg.Damage, 0)
		end
	end
end

local function aoeDonut(boss, aoeDef, cfg)
	if boss.Animations.AOE and boss.Animations.AOE.Donut then
		boss.Animations.AOE.Donut:Play()
	end
	playSound(boss, "Charge")

	local root   = boss.Model.PrimaryPart
	local outerR = 50
	local innerR = 25
	local floorY = getFloorY(root)

	local src = BossAtks.DonutAttack
	local rot = CFrame.fromMatrix(Vector3.zero, src.CFrame.XVector, src.CFrame.YVector, src.CFrame.ZVector)

	local indicator = src:Clone()
	indicator.Anchored   = true
	indicator.CanCollide = false
	indicator.CanTouch   = false
	indicator.CFrame     = CFrame.new(root.Position.X, floorY + 0.1, root.Position.Z) * rot
	indicator.Parent     = workspace

	pulseIndicator(indicator, AOE_WINDUP)
	if indicator.Parent then indicator:Destroy() end
	if not isAlive(boss.Model) then return end
	playBlast(boss)

	local bossPos = root.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then continue end
		if stateManager.GetState(char, "Dodging") then continue end
		local dist = xzDist(char.PrimaryPart.Position, bossPos)
		if dist > innerR and dist <= outerR then
			dmgModule.CalculateDamage(boss.Model, char, aoeDef.Damage or cfg.Damage, 0)
		end
	end
end

local function aoeCone(boss, aoeDef, target, cfg)
	if boss.Animations.AOE and boss.Animations.AOE.Cone then
		boss.Animations.AOE.Cone:Play()
	end
	playSound(boss, "Charge")

	local root      = boss.Model.PrimaryPart
	local targetPos = target.PrimaryPart.Position
	local dir       = (targetPos - root.Position) * Vector3.new(1, 0, 1)
	local forward   = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector

	local length    = aoeDef.Length    or 22
	local halfAngle = aoeDef.HalfAngle or 45
	local floorY    = getFloorY(root)
	local coneWidth = math.tan(math.rad(halfAngle)) * length * 2
	local midPoint  = Vector3.new(
		root.Position.X + forward.X * (length / 2),
		floorY,
		root.Position.Z + forward.Z * (length / 2)
	)

	local indicator = Instance.new("Part")
	indicator.Anchored     = true
	indicator.CanCollide   = false
	indicator.CanTouch     = false
	indicator.Material     = Enum.Material.Neon
	indicator.Color        = aoeDef.IndicatorColor or Color3.fromRGB(255, 165, 0)
	indicator.Transparency = 0.4
	indicator.CastShadow   = false
	indicator.Shape        = Enum.PartType.Block
	indicator.Size         = Vector3.new(coneWidth, 0.5, length)
	indicator.CFrame       = flatCFrame(midPoint, forward)
	indicator.Parent       = workspace

	pulseIndicator(indicator, AOE_WINDUP)
	if indicator.Parent then indicator:Destroy() end
	if not isAlive(boss.Model) then return end
	playBlast(boss)

	local bossPos = root.Position
	local fwd     = Vector3.new(forward.X, 0, forward.Z)

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not isPlayerTargetable(char) then continue end
		if stateManager.GetState(char, "Dodging") then continue end
		local toPlayer   = char.PrimaryPart.Position - bossPos
		local toPlayerXZ = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		local dist       = toPlayerXZ.Magnitude
		if dist > length then continue end
		if dist < 0.01 then continue end
		local dot = fwd:Dot(toPlayerXZ.Unit)
		if dot >= math.cos(math.rad(halfAngle)) then
			dmgModule.CalculateDamage(boss.Model, char, aoeDef.Damage or cfg.Damage, 0)
		end
	end
end


local AOE_TYPES = { "Circle", "Line", "Donut" }

local function fireAOE(boss, target, cfg)
	boss.AOEIndex = ((boss.AOEIndex or 0) % #AOE_TYPES) + 1
	local aoeType = AOE_TYPES[boss.AOEIndex]

	local aoeDef = {}
	if cfg.AOEAttacks then
		for _, def in ipairs(cfg.AOEAttacks) do
			if def.Type == aoeType then aoeDef = def break end
		end
	end
	aoeDef.Type = aoeType

	local ok, err = pcall(function()
		if aoeType == "Circle" then
			aoeCircle(boss, aoeDef, cfg)
		elseif aoeType == "Line" then
			aoeLine(boss, aoeDef, target, cfg)
		elseif aoeType == "Donut" then
			aoeDonut(boss, aoeDef, cfg)
		elseif aoeType == "Cone" then
			aoeCone(boss, aoeDef, target, cfg)
		end
	end)
	if not ok then
		warn("[BossAI] AOE error (" .. aoeType .. "):", err)
	end
end


local function playerIsAttacking(targetChar)
	return stateManager.GetState(targetChar, "M1")
		or stateManager.GetState(targetChar, "M2")
end

local function playerIsBlocking(targetChar)
	return stateManager.GetState(targetChar, "Blocking") == true
end


local function playerCommittedSwing(targetChar)
	return stateManager.GetState(targetChar, "CantAnything")
		and not stateManager.GetState(targetChar, "Stunned")
		and not stateManager.GetState(targetChar, "Dodging")
end

local function bossLocked(boss)
	return stateManager.GetState(boss.Model, "Stunned")
		or stateManager.GetState(boss.Model, "Parried")
end

local function lungeForward(boss, speed, life)
	local root = boss.Model.PrimaryPart
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = root.CFrame.LookVector * speed
	bv.Parent = root
	game.Debris:AddItem(bv, life or 0.3)
end

local function resolveHit(boss, targetChar, damage, knockback, breaksGuard)
	if not isAlive(targetChar) then return end
	local targetHRP   = targetChar:FindFirstChild("HumanoidRootPart")
	local attackerHRP = boss.Model:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not attackerHRP then return end

	local player = Players:GetPlayerFromCharacter(targetChar)

	if stateManager.GetState(targetChar, "Dodging") then
		local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
		sound.Parent = targetHRP
		sound:Play()
		game.Debris:AddItem(sound, 2)
		return
	end

	if stateManager.GetState(targetChar, "Parrying") then
		stateManager.SetStun(boss.Model, true, 2, 2)
		stateManager.SetState(boss.Model, "Parried", true, 2)
		boss.Model.Humanoid.WalkSpeed = 0
		do
			local stunAnimId = boss.Model.Humanoid.RigType == Enum.HumanoidRigType.R6
				and "rbxassetid://10700696839" or "rbxassetid://71380271624004"
			local a = Instance.new("Animation")
			a.AnimationId = stunAnimId
			local t = boss.Model.Humanoid:LoadAnimation(a)
			a:Destroy()
			t.Priority = Enum.AnimationPriority.Action4
			t:Play()
		end
		pcall(function() boss.Model["Right Arm"].parry:Play() end)
		local fxFolder = ReplicatedStorage.assets.FX["parry/blocked"]
		local parryFX  = fxFolder.parry:Clone()
		local clashFX  = fxFolder.Clash:Clone()
		parryFX.Parent = boss.Model:WaitForChild("Torso")
		clashFX.Parent = boss.Model:WaitForChild("Right Arm")
		parryFX.Enabled = true
		clashFX:Emit(30)
		game.Debris:AddItem(parryFX, 0.7)
		game.Debris:AddItem(clashFX, 0.7)
		if player then
			ParryService.ResetParry(player)
			require(ServerScriptService.modules.BlockResolver).OnParrySuccess(targetChar)
			ReplicatedStorage.remotes.replicate:FireClient(player, {
				Type = "Combat", Action = "M1", Func = "Parry",
				FolderName = (targetChar:FindFirstChildOfClass("Tool") and targetChar:FindFirstChildOfClass("Tool").Name) or "Katana"
			}, boss.Model, targetChar)
		end
		return "parried"
	end

	if stateManager.GetState(targetChar, "Blocking") then
		local BlockResolver = require(ServerScriptService.modules.BlockResolver)
		local verdict = BlockResolver.Resolve({
			attacker = boss.Model,
			target = targetChar,
			attackerHRP = attackerHRP,
			targetHRP = targetHRP,
			guardbreak = breaksGuard,
			attackClass = "M1",
			dmg = damage,
		})

		if verdict.outcome == "GuardBreak" then
			if verdict.broke then
				dmgModule.CalculateDamage(boss.Model, targetChar, verdict.chipDamage, 0)
			else
				dmgModule.CalculateDamage(boss.Model, targetChar, damage, 0)
			end
			boss.BlockPressure = 0
			if player then recordThreat(boss, player, damage) end
			local h1 = ReplicatedStorage.assets.FX.h1:Clone()
			h1.Parent = targetChar
			game.Debris:AddItem(h1, 0.1)
			return "guardbroken"
		elseif verdict.outcome == "Bypass" then
			dmgModule.CalculateDamage(boss.Model, targetChar, damage, 0)
			boss.BlockPressure = 0
			return "guardbroken"
		else
			-- Successful front block: chip damage, count block pressure.
			dmgModule.CalculateDamage(boss.Model, targetChar, verdict.chipDamage, 0)
			boss.BlockPressure = (boss.BlockPressure or 0) + 1
			local parryE = boss.Model.ToolFolder.Effects.parry:Clone()
			parryE.Parent = targetChar:WaitForChild("Torso")
			parryE.Enabled = true
			game.Debris:AddItem(parryE, 0.7)
			pcall(function() boss.Model["Right Arm"].ParryDraw:Play() end)
			return "blocked"
		end
	end

	local direction = (targetHRP.Position - attackerHRP.Position).Unit
	local Helper = nil
	pcall(function() Helper = require(ServerScriptService.modules.helperModule) end)
	if Helper and Helper.ApplyKnockback then
		Helper.ApplyKnockback(targetChar, direction, knockback or 5, 0.2)
	end
	stateManager.SetStun(targetChar, true, 0.5, 2)
	dmgModule.CalculateDamage(boss.Model, targetChar, damage, 0)
	boss.LastSuccessfulHitTime = os.clock()
	local killTag = boss.Model.Humanoid:FindFirstChild("KillTag")
	if killTag and player then killTag.Value = player.Name end
	if player then recordThreat(boss, player, damage) end
	
	local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
	highlight.Parent = targetChar
	game.Debris:AddItem(highlight, 0.1)
	
	local s = ReplicatedStorage.assets.sounds.katana.katanaHit:Clone()
	s.Parent = targetChar.Torso
	s:Play()
	
	local hitFX = ReplicatedStorage.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = targetChar:FindFirstChild("Torso")
	game.Debris:AddItem(hitFX, .5)

	local hitEff = ReplicatedStorage.assets.FX.BloodHitEff.Attachment:Clone()
	hitEff.Parent = targetChar:FindFirstChild("Torso")
	game.Debris:AddItem(hitEff, 1)
	return "hit"
end

local function meleeWindow(boss, damage, knockback, breaksGuard, weldOffset)
	local result = nil
	local hitbox, success = HitbloxClass.new({
		SizeOrPart   = 8,
		Debug        = false,
		DebounceTime = 0.5,
		Blacklist    = { boss.Model },
	})
	if not success or not hitbox then return nil end
	hitbox:WeldTo(boss.Model.PrimaryPart, weldOffset or CFrame.new(0, -1, -3))

	local alreadyHit = {}
	hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			if not isAlive(boss.Model) then break end
			if not hit or not isAlive(hit) then continue end
			if hit.Humanoid == boss.Model.Humanoid then continue end
			if alreadyHit[hit] then continue end
			if not Players:GetPlayerFromCharacter(hit) then continue end
			alreadyHit[hit] = true
			local r = resolveHit(boss, hit, damage, knockback, breaksGuard)
			result = result or r
		end
	end)

	hitbox:Start()
	task.wait(0.15)
	hitbox:Destroy()
	return result
end

local function bossM1Chain(boss, target, cfg)
	local hits = math.random(cfg.M1ChainMin or 2, cfg.M1ChainMax or 4)
	local m1Anims = boss.Animations.M1Chain

	for i = 1, hits do
		if not isAlive(boss.Model) or bossLocked(boss) then return false end
		if not isAlive(target) then return false end

		faceTarget(boss, target.PrimaryPart.Position)
		stateManager.SetState(boss.Model, "CantAnything", true, (cfg.M1Windup or 0.41) + 0.1)

		if m1Anims and #m1Anims > 0 then
			local idx = ((i - 1) % #m1Anims) + 1
			if m1Anims[idx] then m1Anims[idx]:Play(0.1) end
		end
		local sw = boss.Model["Right Arm"]:FindFirstChild("SwordLunge")
		if sw then sw:Play() end

		task.wait(cfg.M1Windup or 0.41)
		if not isAlive(boss.Model) or bossLocked(boss) then return false end

		-- Last hit of a max chain launches, like player combo 5.
		local isLast = (i == hits)
		local knock  = isLast and 12 or 5
		local res = meleeWindow(boss, cfg.M1Damage or 7, knock, false)

		if res == "parried" then return false end  -- exposed, drop the chain

		task.wait(cfg.M1HitGap or 0.45)
	end
	return true
end

local function bossCrit(boss, target, cfg)
	if not isAlive(boss.Model) or bossLocked(boss) then return end
	boss.CritCooldown = os.clock() + (cfg.CritCooldownTime or 6)

	faceTarget(boss, target.PrimaryPart.Position)
	stateManager.SetState(boss.Model, "CantAnything", true, (cfg.CritWindup or 1.0) + 0.4)

	if boss.Animations.Crit then boss.Animations.Crit:Play(0.1) end

	-- Danger telegraph (red shield), identical FX to the existing heavy attack.
	local dangerFX = ReplicatedStorage.assets.FX.danger:Clone()
	local weld     = Instance.new("WeldConstraint", dangerFX)
	dangerFX.Parent = boss.Model
	dangerFX.CFrame = boss.Model.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	weld.Part0 = boss.Model.HumanoidRootPart
	weld.Part1 = dangerFX
	TweenService:Create(dangerFX,
		TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
		{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }):Play()
	game.Debris:AddItem(dangerFX, 1)
	local dangerSound = ReplicatedStorage.assets.sounds:FindFirstChild("DANGER")
	if dangerSound then
		local s = dangerSound:Clone()
		s.Parent = boss.Model.PrimaryPart
		s:Play()
		game.Debris:AddItem(s, 2)
	end

	-- Small forward lunge on startup, like the player M2 (35 studs).
	task.delay(0.3, function()
		if isAlive(boss.Model) and not bossLocked(boss) then
			lungeForward(boss, cfg.CritLungeSpeed or 35, 0.3)
		end
	end)

	task.wait(cfg.CritWindup or 1.0)
	if not isAlive(boss.Model) or bossLocked(boss) then return end

	-- breaksGuard = true → always punches through block.
	meleeWindow(boss, cfg.CritDamage or 16, 8, true)
end

local function bossEStrike(boss, target, cfg)
	if not isAlive(boss.Model) or bossLocked(boss) then return end
	boss.ECooldown = os.clock() + (cfg.ECooldownTime or 5)

	faceTarget(boss, target.PrimaryPart.Position)
	stateManager.SetState(boss.Model, "CantAnything", true, (cfg.EWindup or 0.4) + 0.5)

	if boss.Animations.EStrike then boss.Animations.EStrike:Play(0.1) end
	local sw = boss.Model["Right Arm"]:FindFirstChild("SwordLunge")
	if sw then sw:Play() end

	task.wait(cfg.EWindup or 0.4)
	if not isAlive(boss.Model) or bossLocked(boss) then return end

	lungeForward(boss, cfg.ELungeSpeed or 50, 0.3)
	task.wait(0.1)
	meleeWindow(boss, cfg.EDamage or 9, 8, false)
end

local function bossDash(boss, target, cfg)
	if not isAlive(boss.Model) or bossLocked(boss) then return false end
	if os.clock() < (boss.DashCooldown or 0) then return false end

	boss.DashCooldown = os.clock() + (cfg.DashCooldownTime or 3)
	boss.IsDashing = true

	stateManager.SetState(boss.Model, "Dodging", true, cfg.DashIframeTime or 0.35)

	if boss.Animations.Dash then boss.Animations.Dash:Play(0.1) end

	local root = boss.Model.PrimaryPart
	local toPlayer = (target.PrimaryPart.Position - root.Position) * Vector3.new(1, 0, 1)
	local side = (math.random() < 0.5) and 1 or -1
	local dashDir = Vector3.new(-toPlayer.Z * side, 0, toPlayer.X * side)
	if dashDir.Magnitude < 0.1 then dashDir = -root.CFrame.LookVector end
	dashDir = dashDir.Unit

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = dashDir * (cfg.DashSpeed or 55)
	bv.Parent = root
	game.Debris:AddItem(bv, cfg.DashIframeTime or 0.35)

	task.delay(cfg.DashIframeTime or 0.35, function()
		boss.IsDashing = false
	end)
	return true
end

local function bossBlock(boss, cfg)
	if not isAlive(boss.Model) or bossLocked(boss) then return end
	stateManager.SetState(boss.Model, "Blocking", true, 0.6)
	-- Block stance anim: reuse the player block id already used elsewhere.
	do
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://96311777205911"
		local t = boss.Model.Humanoid:LoadAnimation(a)
		a:Destroy()
		t.Priority = Enum.AnimationPriority.Action3
		t:Play(0.05)
	end
	task.wait(0.6)
	stateManager.RemoveStates(boss.Model, "Blocking")
end

local function bossParry(boss, target, cfg)
	if not isAlive(boss.Model) or bossLocked(boss) then return false end
	if os.clock() < (boss.ParryCooldown or 0) then return false end
	boss.ParryCooldown = os.clock() + (cfg.ParryCooldownTime or 4.5)

	stateManager.SetState(boss.Model, "Parrying", true, cfg.ParryWindow or 0.4)
	pcall(function() boss.Model["Right Arm"].ParryDraw:Play() end)
	task.wait(cfg.ParryWindow or 0.4)
	stateManager.RemoveStates(boss.Model, "Parrying")
	return true
end

local function handlePlayerLikeAttack(boss, target, cfg)
	boss.IsAttacking = true
	boss.AttackCycle = (boss.AttackCycle or 0) + 1

	local root = boss.Model.PrimaryPart
	local dist = (target.PrimaryPart.Position - root.Position).Magnitude

	if playerIsAttacking(target) and dist <= (cfg.AttackRange + 4) then
		local playerM2 = stateManager.GetState(target, "M2")
		if playerM2 then
			if math.random() < (cfg.DashChance or 0.45) and bossDash(boss, target, cfg) then
				boss.IsAttacking = false
				return
			end
		else
			-- vs player M1: roll parry first, then dash.
			if math.random() < (cfg.ParryChance or 0.30) and bossParry(boss, target, cfg) then
				boss.IsAttacking = false
				return
			end
			if math.random() < (cfg.DashChance or 0.45) and bossDash(boss, target, cfg) then
				boss.IsAttacking = false
				return
			end
			-- Caught with defenses down mid-combo → maybe block the chip.
			if math.random() < (cfg.BlockChance or 0.40) then
				bossBlock(boss, cfg)
				boss.IsAttacking = false
				return
			end
		end
	end

	if (boss.BlockPressure or 0) >= (cfg.BlockPressureMax or 3)
		and os.clock() >= (boss.CritCooldown or 0)
		and dist <= (cfg.AttackRange + 4) then
		bossCrit(boss, target, cfg)
		boss.IsAttacking = false
		return
	end

	if dist > cfg.AttackRange + 2 then
		if dist <= (cfg.ERange or 28) and os.clock() >= (boss.ECooldown or 0) then
			bossEStrike(boss, target, cfg)
		end
		-- else: just let Update's movement walk us in this tick.
		boss.IsAttacking = false
		return
	end

	if cfg.AOEAttacks and os.clock() >= (boss.NextAOETime or 0) and math.random() < 0.5 then
		boss.NextAOETime = os.clock() + 8
		fireAOE(boss, target, cfg)
		task.wait(0.3)
		boss.IsAttacking = false
		return
	end

	local completed = bossM1Chain(boss, target, cfg)
	if completed and isAlive(boss.Model) and not bossLocked(boss) then
		local d2 = (target.PrimaryPart.Position - root.Position).Magnitude
		if d2 <= cfg.AttackRange + 3 then
			local roll = math.random()
			if roll < 0.35 and os.clock() >= (boss.CritCooldown or 0) then
				bossCrit(boss, target, cfg)
			elseif roll < 0.6 and os.clock() >= (boss.ECooldown or 0) then
				bossEStrike(boss, target, cfg)
			end
		end
	end

	local threshold = math.random(cfg.AggroRotationMin or 2, cfg.AggroRotationMax or 3)
	if boss.AttackCycle >= threshold then
		boss.AttackCycle = 0
		local newTarget = rollAggro(boss, cfg)
		if newTarget then boss.CurrentTarget = newTarget end
	end

	boss.IsAttacking = false
end


local function fireHitbox(boss, damage, isHeavy)
	local cfg       = MobConfig.Mobs[boss.Name]
	local dmgAmount = isHeavy and (cfg.HeavyDamage or damage * 2) or damage

	local hitbox, success = HitbloxClass.new({
		SizeOrPart   = 8,
		Debug        = false,
		DebounceTime = 0.5,
		Blacklist    = { boss.Model },
	})

	hitbox:WeldTo(boss.Model.PrimaryPart, CFrame.new(0, -1, -3))

	if not success or not hitbox then return end

	hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			if not isAlive(boss.Model) then break end

			local hyperarmor = boss.Model:FindFirstChild("Values")
				and boss.Model.Values:FindFirstChild("Hyperarmor")
				and boss.Model.Values.Hyperarmor.Value

			if stateManager.GetState(boss.Model, "Stunned") and not isHeavy and not hyperarmor then
				hitbox:Destroy()
				return
			end

			if not hit or not isAlive(hit) then continue end
			if hit.Humanoid == boss.Model.Humanoid then continue end

			local isParrying = stateManager.GetState(hit, "Parrying")
			local isBlocking = stateManager.GetState(hit, "Blocking")
			local isDodging  = stateManager.GetState(hit, "Dodging")
			local player     = Players:GetPlayerFromCharacter(hit)

			if isParrying then
				stateManager.SetStun(boss.Model, true, 2, 2)
				stateManager.SetState(boss.Model, "Parried", true, 2)

				local stunAnimId = boss.Model.Humanoid.RigType == Enum.HumanoidRigType.R6
					and "rbxassetid://10700696839"
					or  "rbxassetid://71380271624004"
				local stunAnim = Instance.new("Animation")
				stunAnim.AnimationId = stunAnimId
				local track = boss.Model.Humanoid:LoadAnimation(stunAnim)
				track.Priority = Enum.AnimationPriority.Action4
				track:Play()

				boss.Model["Right Arm"].parry:Play()

				local fxFolder = ReplicatedStorage.assets.FX["parry/blocked"]
				local parryFX  = fxFolder.parry:Clone()
				local clashFX  = fxFolder.Clash:Clone()
				parryFX.Parent = boss.Model:WaitForChild("Torso")
				clashFX.Parent = boss.Model:WaitForChild("Right Arm")
				parryFX.Enabled = true
				clashFX:Emit(30)
				game.Debris:AddItem(parryFX, 0.7)
				game.Debris:AddItem(clashFX, 0.7)

				boss.Model.Humanoid.WalkSpeed = 0
				if player then
					ParryService.ResetParry(player)
					ReplicatedStorage.remotes.replicate:FireClient(player, {Type = "Combat", Action = "M1", Func = "Parry", FolderName = (hit:FindFirstChildOfClass("Tool") and hit:FindFirstChildOfClass("Tool").Name) or "Katana"}, boss.Model, hit)
				end
				hitbox:Destroy()
				return

			elseif isBlocking then
				if isHeavy then
					boss.LastSuccessfulHitTime = os.clock()
					if player then recordThreat(boss, player, dmgAmount) end
					dmgModule.CalculateDamage(boss.Model, hit, dmgAmount, 0)
				else
					dmgModule.CalculateDamage(boss.Model, hit, dmgAmount / 2, 0)
				end
				local parryE = boss.Model.ToolFolder.Effects.parry:Clone()
				parryE.Parent = hit:WaitForChild("Torso")
				parryE.Enabled = true
				game.Debris:AddItem(parryE, 0.7)
				boss.Model["Right Arm"].ParryDraw:Play()

			elseif isDodging then
				local sound = boss.Model.ToolFolder.Dodged:Clone()
				sound.Parent = hit.HumanoidRootPart
				sound:Play()
				game.Debris:AddItem(sound, 1)

			else
				boss.LastSuccessfulHitTime = os.clock()
				local killTag = boss.Model.Humanoid:FindFirstChild("KillTag")
				if killTag and player then killTag.Value = player.Name end
				if player then recordThreat(boss, player, dmgAmount) end
				dmgModule.CalculateDamage(boss.Model, hit, dmgAmount, 0)
				stateManager.SetStun(hit, true, 0.5, 2)
				local hitAnimId = "rbxassetid://96311777205911"
				local reactionAnim = Instance.new("Animation")
				reactionAnim.AnimationId = hitAnimId
				local track = hit.Humanoid:LoadAnimation(reactionAnim)
				track.Priority = Enum.AnimationPriority.Action4
				track:Play()
				task.delay(0.4, function() track:Stop(0.1) end)
			end
		end
	end)

	hitbox:Start()
	task.wait(0.15)
	hitbox:Destroy()
end


local function handleBossAttack(boss, target, cfg)
	boss.IsAttacking = true
	boss.AttackCycle = (boss.AttackCycle or 0) + 1

	faceTarget(boss, target.PrimaryPart.Position)

	local useAOE = cfg.AOEAttacks ~= nil and boss.AttackCycle % 3 == 0

	if useAOE then
		fireAOE(boss, target, cfg)
		task.wait(0.3)
	else
		local attackAnims = boss.Animations.Attack
		local idx
		if cfg.AttackSequence == "LIST" then
			boss.AttackIndex = (boss.AttackIndex or 0) % #attackAnims + 1
			idx = boss.AttackIndex
		else
			idx = math.random(1, #attackAnims)
		end

		local attackAnim = attackAnims[idx]
		if attackAnim then attackAnim:Play() end

		local attackSound = boss.Model["Right Arm"]:FindFirstChild("SwordLunge")
		if attackSound then attackSound:Play() end

		task.wait(cfg.WindupTime)
		if not isAlive(boss.Model) then boss.IsAttacking = false return end

		local isHeavy = math.random() < (cfg.HeavyAttackChance or 0)

		if isHeavy then
			local dangerFX = ReplicatedStorage.assets.FX.danger:Clone()
			local weld     = Instance.new("WeldConstraint", dangerFX)
			dangerFX.Parent = boss.Model
			dangerFX.CFrame = boss.Model.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
			weld.Part0 = boss.Model.HumanoidRootPart
			weld.Part1 = dangerFX
			TweenService:Create(dangerFX,
				TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
				{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
			):Play()
			game.Debris:AddItem(dangerFX, 1)

			local dangerSound = ReplicatedStorage.assets.sounds:FindFirstChild("DANGER")
			if dangerSound then
				local s = dangerSound:Clone()
				s.Parent = boss.Model.PrimaryPart
				s:Play()
				game.Debris:AddItem(s, 2)
			end

			task.wait(cfg.HeavyWindupTime)
			if not isAlive(boss.Model) then boss.IsAttacking = false return end
			fireHitbox(boss, cfg.Damage, true)
		else
			fireHitbox(boss, cfg.Damage, false)
		end
	end

	local threshold = math.random(cfg.AggroRotationMin or 2, cfg.AggroRotationMax or 3)
	if boss.AttackCycle >= threshold then
		boss.AttackCycle = 0
		local newTarget = rollAggro(boss, cfg)
		if newTarget then boss.CurrentTarget = newTarget end
	end

	boss.IsAttacking = false
end

local function dispatchAttack(boss, target, cfg)
	if cfg.PlayerLike then
		handlePlayerLikeAttack(boss, target, cfg)
	else
		handleBossAttack(boss, target, cfg)
	end
end


local function onBossDeath(boss, cfg)
	for _, track in ipairs(boss.Model.Humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	local bv = Instance.new("BodyVelocity", boss.Model.PrimaryPart)
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = boss.Model.PrimaryPart.CFrame.LookVector * -15
	game.Debris:AddItem(bv, 0.1)

	local ragdollManager = require(ServerScriptService.modules.ragdollManager)
	ragdollManager.Ragdoll(boss.Model, 15)

	local topName, topDmg = nil, 0
	if boss.ThreatTable then
		for name, data in pairs(boss.ThreatTable) do
			if data.Threat > topDmg then
				topName = name
				topDmg  = data.Threat
			end
		end
	end

	if topName and boss.ThreatTable[topName] then
		local topPlayer = boss.ThreatTable[topName].Player
		if topPlayer and topPlayer.Character then
			local hum = topPlayer.Character:FindFirstChild("Humanoid")
			if hum then
				hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.3)
			end
			local dm = _G.DataManager
			if dm and cfg.XPWeapon and cfg.XPAmount then
				dm.AddWeaponXP(topPlayer, cfg.XPWeapon, cfg.XPAmount)
			end
			local qm = _G.QuestManager
			if qm and cfg.QuestId then
				qm.IncrementProgress(topPlayer, cfg.QuestId, 1)
			end
			if cfg.ItemDrop and math.random() <= (cfg.ItemDropChance or 0) then
				local irm = _G.ItemRewardManager
				if irm then irm.GiveReward(topPlayer, cfg.ItemDrop) end
			end
		end
	end

	boss.Dead = true

	task.wait(8)
	if boss.Model and boss.Model.Parent then boss.Model:Destroy() end

	task.wait(math.max(0, cfg.RespawnTime - 8))
	if boss.Respawn then boss:Respawn() end
end


function BossAI.Update(boss)
	if not isAlive(boss.Model) then return end
	if boss.Dead then return end
	if os.clock() - (boss.LastUpdate or 0) < UPDATE_RATE then return end
	boss.LastUpdate = os.clock()

	local cfg  = MobConfig.Mobs[boss.Name]
	local root = boss.Model.PrimaryPart

	if stateManager.GetState(boss.Model, "Stunned") then
		boss.Model.Humanoid:MoveTo(root.Position)
		if boss.Animations.Walk.IsPlaying then boss.Animations.Walk:Stop() end
		return
	end

	if boss.IsDashing then return end
	if boss.IsAttacking then return end
	if boss.State == "EXECUTING" then return end

	if not boss.CurrentTarget then
		local closest = getClosestPlayer(root.Position, cfg.SeekRange)
		if closest then
			boss.CurrentTarget = closest
			local player = Players:GetPlayerFromCharacter(closest)
			if player then recordThreat(boss, player, 1) end
		end
		return
	end

	local target = boss.CurrentTarget
	
	if not isAlive(target) then
		boss.CurrentTarget = nil
		return
	end

	local dist = (target.PrimaryPart.Position - root.Position).Magnitude

	if dist > cfg.SeekRange or not isPlayerTargetable(target) then
		if not boss.AggroLostTime then
			boss.AggroLostTime = os.clock()
		elseif os.clock() - boss.AggroLostTime > AGGRO_LEASH_TIME then
			boss.CurrentTarget = nil
			boss.AggroLostTime = nil
			boss.ThreatTable   = {}
		end
		return
	end

	boss.AggroLostTime = nil
	faceTarget(boss, target.PrimaryPart.Position)

	if cfg.PlayerLike
		and not boss.IsAttacking
		and not boss.IsDashing
		and not bossLocked(boss)
		and dist <= (cfg.AttackRange + 5)
		and playerCommittedSwing(target) then

		-- one reaction per distinct player commit
		local commitId = math.floor((os.clock()) * 1000)
		if not boss.LastReactCommit or (os.clock() - boss.LastReactCommit) > 0.5 then
			boss.LastReactCommit = os.clock()

			-- vs a guard-break (player M2) the boss only dashes, never parries,
			-- so the player's GB answer always connects.
			local playerM2 = stateManager.GetState(target, "M2")
			if playerM2 then
				if math.random() < (cfg.DashChance or 0.45) then
					boss.IsAttacking = true
					task.spawn(function()
						bossDash(boss, target, cfg)
						boss.IsAttacking = false
					end)
					return
				end
			else
				-- vs a normal swing: roll parry, then dash, then block.
				if math.random() < (cfg.ParryChance or 0.30) then
					boss.IsAttacking = true
					task.spawn(function()
						bossParry(boss, target, cfg)
						boss.IsAttacking = false
					end)
					return
				elseif math.random() < (cfg.DashChance or 0.45) then
					boss.IsAttacking = true
					task.spawn(function()
						bossDash(boss, target, cfg)
						boss.IsAttacking = false
					end)
					return
				elseif math.random() < (cfg.BlockChance or 0.40) then
					boss.IsAttacking = true
					task.spawn(function()
						bossBlock(boss, cfg)
						boss.IsAttacking = false
					end)
					return
				end
			end
		end
	end

	local isDowned  = target:GetAttribute("Downed") == true
	local isCarried = target:GetAttribute("Carried") == true

	if isDowned and not isCarried then
		if dist <= cfg.AttackRange then
			if boss.State ~= "EXECUTING" then
				boss.State = "EXECUTING"
				boss.Model.Humanoid:MoveTo(root.Position)
				DownedManager.NPCExecute(boss.Model, target)
				task.delay(3, function()
					if boss.State == "EXECUTING" then
						boss.State = "CHASE"
						boss.Model.Humanoid.WalkSpeed = cfg.WalkSpeed
					end
				end)
			end
		else
			if os.clock() - (boss.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
				boss.LastMoveUpdate = os.clock()
				boss.Model.Humanoid:MoveTo(target.PrimaryPart.Position)
			end
			if not boss.Animations.Walk.IsPlaying then
				boss.Animations.Idle:Stop()
				boss.Animations.Walk:Play()
			end
		end
		return
	end

	local engageRange = cfg.PlayerLike and (cfg.ERange or 28) or cfg.AttackRange

	if dist <= cfg.AttackRange then
		boss.Model.Humanoid:MoveTo(root.Position)
		if boss.Animations.Walk.IsPlaying then boss.Animations.Walk:Stop() end
		if not boss.Animations.Idle.IsPlaying then boss.Animations.Idle:Play() end
		if not boss.IsAttacking then
			boss.IsAttacking = true
			task.spawn(dispatchAttack, boss, target, cfg)
		end
	elseif cfg.PlayerLike and dist <= engageRange and os.clock() >= (boss.ECooldown or 0) and not boss.IsAttacking then
		boss.IsAttacking = true
		task.spawn(dispatchAttack, boss, target, cfg)
	else
		if os.clock() - (boss.LastMoveUpdate or 0) >= MOVE_UPDATE_RATE then
			boss.LastMoveUpdate = os.clock()
			boss.Model.Humanoid:MoveTo(target.PrimaryPart.Position)
		end
		if not boss.Animations.Walk.IsPlaying then
			boss.Animations.Idle:Stop()
			boss.Animations.Walk:Play()
		end
	end
end


function BossAI.Spawn(bossName, spawnCFrame)
	local cfg = MobConfig.Mobs[bossName]
	if not cfg then warn("[BossAI] No config for: " .. bossName) return end

	local storage  = game:GetService("ServerStorage")
	local template = storage:FindFirstChild("Mobs") and storage.Mobs:FindFirstChild(bossName)
	if not template then
		warn("[BossAI] No model in ServerStorage.Mobs for: " .. bossName)
		return
	end

	local model = template:Clone()
	model:SetPrimaryPartCFrame(spawnCFrame)
	model.Parent = getAliveFolder()

	local hum = model:FindFirstChild("Humanoid")
	if not hum then warn("[BossAI] No Humanoid in: " .. bossName) model:Destroy() return end

	hum.MaxHealth = cfg.Health
	hum.Health    = cfg.Health
	hum.WalkSpeed = cfg.WalkSpeed
	hum.JumpPower = cfg.JumpPower

	local gyro = Instance.new("BodyGyro")
	gyro.Name      = "MobGyro"
	gyro.MaxTorque = Vector3.new(0, 4e5, 0)
	gyro.D         = 200
	gyro.P         = 3000
	gyro.CFrame    = spawnCFrame
	gyro.Parent    = model.PrimaryPart

	model:SetAttribute("LiturgyWorth", cfg.LiturgyWorth or 0)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then part.CastShadow = cfg.CastShadow end
	end

	if not model:FindFirstChild("Values") then
		local v = Instance.new("Folder", model)
		v.Name = "Values"
		local h = Instance.new("BoolValue", v)
		h.Name  = "Hyperarmor"
		h.Value = false
	end

	local animator = hum:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anims = loadAnimations(animator, cfg.Animations)
	if anims.Idle then anims.Idle:Play() end

	local killTag = Instance.new("StringValue")
	killTag.Name   = "KillTag"
	killTag.Parent = hum

	local boss = {
		Name                  = bossName,
		Model                 = model,
		Animations            = anims,
		SpawnCFrame           = spawnCFrame,
		State                 = "CHASE",
		LastUpdate            = 0,
		LastMoveUpdate        = 0,
		AttackIndex           = 0,
		AttackCycle           = 0,
		AOEIndex              = 0,
		IsAttacking           = false,
		Dead                  = false,
		CurrentTarget         = nil,
		ThreatTable           = {},
		AggroLostTime         = nil,
		LastSuccessfulHitTime = 0,

		DashCooldown          = 0,
		CritCooldown          = 0,
		ECooldown             = 0,
		ParryCooldown         = 0,
		BlockPressure         = 0,
		IsDashing             = false,
		NextAOETime           = 0,
	}

	hum.HealthChanged:Connect(function(newHealth)
		local delta = hum.MaxHealth - newHealth
		if delta <= 0 then return end
		local killer = Players:FindFirstChild(killTag.Value)
		if killer then recordThreat(boss, killer, delta) end
	end)

	local deathConn
	deathConn = hum.Died:Connect(function()
		deathConn:Disconnect()
		task.spawn(onBossDeath, boss, cfg)
	end)

	return boss
end

return BossAI