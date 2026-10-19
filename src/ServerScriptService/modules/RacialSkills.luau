-- SPDX-License-Identifier: MIT
--
-- The racial skill of each race. Every skill is a function named after the race, and
-- processHit resolves the hits of most of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local modules = ReplicatedStorage:WaitForChild("modules")
local SSSmodules = ServerScriptService:WaitForChild("modules")
local HitboxClass = require(modules:WaitForChild("hitboxClass"))
local StateHandler = require(modules:WaitForChild("stateHandler"))
local AnimationHandler = require(modules:WaitForChild("animationHandler"))
local RagdollManager = require(SSSmodules:WaitForChild("ragdollManager"))
local VFX = require(game.ServerScriptService.modules.VFXModule)
local dmgCalculator = require(game.ServerScriptService.modules.damageCalculator)
local FallTracker = require(game.ServerScriptService.modules.FallTracker)
local SpeedService = require(SSSmodules:WaitForChild("SpeedService"))

local RacialSkills = {}

local Assets = ReplicatedStorage:WaitForChild("assets")
local SoundFolder = Assets:WaitForChild("sounds"):WaitForChild("skills")
local FXFolder = Assets:WaitForChild("FX")

local function playSound(char: Instance, soundTemplate: Sound?)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		warn(`[RacialSkills] {char.Name} has no HumanoidRootPart for a sound.`)
		return
	end

	local s
	if typeof(soundTemplate) == "string" then
		s = Instance.new("Sound")
		s.SoundId = soundTemplate
	elseif typeof(soundTemplate) == "Instance" and soundTemplate:IsA("Sound") then
		s = soundTemplate:Clone()
	else
		return
	end

	s.Parent = root
	if s.RollOffMaxDistance > 150 then
		s.RollOffMaxDistance = 150
	else
		s.RollOffMaxDistance = s.RollOffMaxDistance
	end
	s:Play()
	Debris:AddItem(s, s.TimeLength + 1)
end

local function applyKnockback(
	targetChar: Model,
	direction: Vector3,
	force: number,
	duration: number
)
	local hrp = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then
		return
	end

	hrp.AssemblyLinearVelocity = Vector3.zero

	local att = Instance.new("Attachment")
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.MaxForce = 999999
	lv.VectorVelocity = (direction * force) + Vector3.new(0, 5, 0)
	lv.Attachment0 = att
	lv.Parent = hrp

	Debris:AddItem(att, duration)
	Debris:AddItem(lv, duration)
end

-- Resolves a skill hit on each target: dodge, then parry, block, or a clean hit.
-- weaponType picks special VFX, and specialProperties carries effects such as
-- GuardBreak, Silence, Root, and Slow.
local function processHit(
	attackerPlayer: Player,
	attackerChar: Model,
	hitCharsTable: { Model },
	alreadyHit: { [Model]: boolean },
	damage: number,
	weaponType: string?,
	knockbackDist: number?,
	stunTime: number?,
	ragdollTime: number?,
	originPart: BasePart?,
	specialProperties: { [string]: any }?
)
	local attackerHRP = attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart
	-- A projectile passes originPart, which replaces the attacker HRP for direction and
	-- facing.
	local originPosition = (originPart and originPart.Position)
		or (attackerHRP and attackerHRP.Position)

	if not attackerHRP or not originPosition then
		return
	end

	-- An attacker stunned during the swing deals no damage.
	if StateHandler.IsInterrupted(attackerChar) then
		return
	end

	for _, targetChar in pairs(hitCharsTable) do
		local humanoid = targetChar:FindFirstChild("Humanoid") :: Humanoid
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local isPlayer = game.Players:GetPlayerFromCharacter(targetChar)
		if (isPlayer and isPlayer == attackerPlayer) or alreadyHit[targetChar] then
			continue
		end

		local targetHRP = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
		if not targetHRP then
			continue
		end

		if StateHandler.GetState(targetChar, "Dodging") then
			playSound(targetHRP, ReplicatedStorage.assets.sounds:FindFirstChild("Dodged"))

			for _, part in pairs(targetChar:GetChildren()) do
				if
					part:IsA("BasePart")
					and part.Name ~= "HumanoidRootPart"
					and part.Name ~= "Head"
					and part.Name ~= "Left Arm"
				then
					local oldTansparency = part.Transparency
					part.Transparency = 0.7
					task.delay(0.5, function()
						part.Transparency = oldTansparency
					end)
				end
			end
			continue
		end

		local function applyFinalDamage(modDamage: number, modKnockback: number)
			local direction = (targetHRP.Position - originPosition).Unit

			local animID = (math.random() > 0.5) and "rbxassetid://96311777205911"
				or "rbxassetid://111089735892609"
			AnimationHandler.LoadAnim(targetChar, "Hit", animID, nil, false)

			applyKnockback(targetChar, direction, modKnockback or 0, 0.2)
			if stunTime and stunTime > 0 then
				StateHandler.SetStun(targetChar, true, stunTime, 2)
			end
			if ragdollTime and ragdollTime > 0 then
				RagdollManager.Ragdoll(targetChar, ragdollTime)
			end

			dmgCalculator.CalculateDamage(attackerChar, targetChar, modDamage, 0, false, "Racial")

			local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
			h1.Parent = attackerChar
			game.Debris:AddItem(h1, 0.1)

			local s = ReplicatedStorage.assets.sounds.PunchHit:Clone()
			s.Parent = targetHRP
			s:Play()
			game.Debris:AddItem(s, s.TimeLength + 1)

			local blood = Assets.FX:FindFirstChild("BloodHitEff").Attachment
			if blood then
				local clone = blood:Clone()
				clone.Parent = targetHRP
				clone.BloodHit:Emit(10)
				Debris:AddItem(clone, 1)
			end

			if specialProperties then
				if specialProperties.Silence then
					StateHandler.SetState(
						targetChar,
						"Silenced",
						true,
						specialProperties.SilenceDuration or 2
					)
				end
				if specialProperties.Root then
					targetHRP.Anchored = true

					playSound(targetChar, SoundFolder:FindFirstChild("Crackling"))

					AnimationHandler.LoadAnim(
						targetChar,
						"Rooted",
						"rbxassetid://84818556494893",
						nil,
						false
					)

					local rootEffectTop =
						ReplicatedStorage.assets.FX.skills:FindFirstChild("RootedPart").Top:Clone()
					local rootEffectBottom = ReplicatedStorage.assets.FX.skills
						:FindFirstChild("RootedPart").Bottom
						:Clone()
					rootEffectTop.Parent = targetHRP
					rootEffectBottom.Parent = targetHRP

					game.Debris:AddItem(rootEffectTop, specialProperties.RootDuration or 2)
					game.Debris:AddItem(rootEffectBottom, specialProperties.RootDuration or 2)

					task.delay(specialProperties.RootDuration or 2, function()
						targetHRP.Anchored = false
					end)
				end
				if specialProperties.Slow then
					-- A real slow: the target can still move. Each beam tick refreshes it
					-- instead of stacking.
					local targetHum = targetChar:FindFirstChild("Humanoid")
					if targetHum then
						local slowSpeed = specialProperties.SlowSpeed or 6
						local slowDuration = specialProperties.SlowDuration or 1
						-- Pushing the same source again refreshes the slow. A stun still wins,
						-- and the slow overrides base and block speed.
						SpeedService.Push(
							targetChar,
							"NullGaze",
							slowSpeed,
							SpeedService.Priority.DEBUFF
						)
						-- Also lock dashes. A dash uses a LinearVelocity that ignores WalkSpeed,
						-- so a slowed target could dash out. The Dash LocalScript reads DashLocked.
						targetChar:SetAttribute("DashLocked", true)
						local token = (targetChar:GetAttribute("NullGazeSlowToken") or 0) + 1
						targetChar:SetAttribute("NullGazeSlowToken", token)
						task.delay(slowDuration, function()
							-- Only the timer of the latest tick releases the slow and dash lock.
							if not targetChar or not targetChar.Parent then
								return
							end
							if targetChar:GetAttribute("NullGazeSlowToken") ~= token then
								return
							end
							SpeedService.Pop(targetChar, "NullGaze")
							targetChar:SetAttribute("NullGazeSlowToken", nil)
							targetChar:SetAttribute("DashLocked", nil)
						end)
					end
				end
			end

			if weaponType == "Water" then
				local ballClone = game:GetService("ReplicatedStorage").Magic.Ball:Clone()
				local swirlClone = game:GetService("ReplicatedStorage").Magic.SwirlShockwaveFire
					:Clone()
				local groundClone = game:GetService("ReplicatedStorage").Magic.DestroyedGround
					:Clone()

				groundClone.Parent = game.Workspace
				ballClone.Parent = game.Workspace
				swirlClone.Parent = game.Workspace
				ballClone.Position = humanoid.Parent.Torso.Position
				swirlClone.Position = humanoid.Parent.Torso.Position
				groundClone.Position = Vector3.new(
					humanoid.Parent.Torso.Position.X,
					humanoid.Parent.Torso.Position.Y - 5.5,
					humanoid.Parent.Torso.Position.Z
				)

				local destination1 = Vector3.new(
					humanoid.Parent.Torso.Position.X,
					humanoid.Parent.Torso.Position.Y - 3.5,
					humanoid.Parent.Torso.Position.Z
				)
				local destination2 = Vector3.new(
					humanoid.Parent.Torso.Position.X,
					humanoid.Parent.Torso.Position.Y - 6.5,
					humanoid.Parent.Torso.Position.Z
				)

				local TweenService = game:GetService("TweenService")
				local tweenInfo1 = TweenInfo.new(
					0.5,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.InOut,
					0,
					false,
					0
				)
				local tweenInfo2 =
					TweenInfo.new(2, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, 0, false, 0)

				local Settings1 = { Position = destination1 }
				local Tween1 = TweenService:Create(groundClone, tweenInfo1, Settings1)

				local Settings2 = { Position = destination2 }
				local Tween2 = TweenService:Create(groundClone, tweenInfo2, Settings2)

				Tween1:Play()
				wait(5)
				Tween2:Play()
			end

			alreadyHit[targetChar] = true
		end

		local isBlocking = StateHandler.GetState(targetChar, "Blocking")
		local isParrying = StateHandler.GetState(targetChar, "Parrying")

		local toAttacker = (originPosition - targetHRP.Position).Unit
		local forward = targetHRP.CFrame.LookVector
		local dot = forward:Dot(toAttacker)
		-- Within 60 degrees of the target's facing.
		local isFacing = dot > 0.5

		if isParrying then
			local parryE = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
				:Clone()
			local effect2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit
				:Clone()
			local clash = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
				:Clone()
			local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
			h1.Parent = attackerChar
			game.Debris:AddItem(h1, 0.1)
			parryE.Parent = attackerChar:WaitForChild("Torso")
			effect2.Parent = attackerChar:WaitForChild("Torso")
			clash.Parent = attackerChar:WaitForChild("Right Arm")

			local clash2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
				:Clone()
			clash2.Parent = targetChar:WaitForChild("Right Arm")
			clash2:Emit(30)
			game.Debris:AddItem(clash2, 0.7)

			local s = game:GetService("ReplicatedStorage").assets.sounds.ParrySound:Clone()
			s.Parent = targetHRP
			s:Play()
			game.Debris:AddItem(s, s.TimeLength + 1)

			parryE.Enabled = true
			effect2.Enabled = true
			clash:Emit(30)
			game.Debris:AddItem(clash, 0.7)
			game.Debris:AddItem(parryE, 0.7)
			game.Debris:AddItem(effect2, 0.7)

			-- A parry beats hyper armor: clear it so the punish stun lands.
			attackerChar:SetAttribute("HyperArmor", nil)
			StateHandler.SetStun(attackerChar, true, 0.5, 2)
			StateHandler.SetState(attackerChar, "CantAnything", true, 0.5)

			AnimationHandler.StopAnim(attackerChar, "ALL")
			AnimationHandler.LoadAnim(
				attackerChar,
				"Parried",
				"rbxassetid://116383775729821",
				nil,
				false
			)
			return
		elseif isBlocking then
			-- BlockResolver decides the block. A racial skill can guard-break through
			-- specialProperties.GuardBreak.
			local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
			local verdict = BlockResolver.Resolve({
				attacker = attackerChar,
				target = targetChar,
				attackerPos = originPosition,
				targetHRP = targetHRP,
				guardbreak = specialProperties and specialProperties.GuardBreak or false,
				attackClass = "Skill",
				dmg = damage,
			})

			if verdict.outcome == "GuardBreak" then
				playSound(targetHRP, Assets.sounds:FindFirstChild("GuardBreak"))
				AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
				if verdict.broke then
					applyFinalDamage(verdict.chipDamage, verdict.knockback)
				else
					applyFinalDamage(damage, knockbackDist)
				end
			elseif verdict.outcome == "Bypass" then
				applyFinalDamage(damage, knockbackDist)
			else
				BlockResolver.OnAttackerLandedHit(attackerChar)
				playSound(targetHRP, Assets.sounds:FindFirstChild("Block"))
				local spark = Assets.FX["parry/blocked"].parry:Clone()
				spark.Parent = targetHRP
				Debris:AddItem(spark, 0.5)
				applyFinalDamage(verdict.chipDamage, verdict.knockback)
			end
		else
			applyFinalDamage(damage, knockbackDist)
		end
	end
end

-- RacialSkills.Human() - Adrenaline Surge: trade 15 HP for 1.3x damage for 20 seconds
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Human(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChild("Humanoid") :: Humanoid
	if not hrp or not hum then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)

	AnimationHandler.LoadAnim(character, "Skill", "rbxassetid://126568014162974", nil, false)

	task.wait(0.5)

	playSound(character, SoundFolder:FindFirstChild("PunchHit"))

	local aura = ReplicatedStorage.assets.FX.adrenalineSurgePart

	local function applyAura(targetPart, duration)
		if not targetPart then
			return
		end

		for _, item in pairs(aura:GetChildren()) do
			if item:IsA("ParticleEmitter") then
				local clone = item:Clone()
				clone.Parent = targetPart
				game.Debris:AddItem(clone, duration)
			end
		end
	end

	for _, v in pairs(character:GetChildren()) do
		if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
			applyAura(v, 20)
		end
	end

	if hum.Health > hum.MaxHealth / 7 then
		hum:TakeDamage(15)
	end

	character:SetAttribute("AttackBuff", (character:GetAttribute("AttackBuff") or 1) * 1.3)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 50, 50)
	highlight.OutlineColor = Color3.fromRGB(150, 0, 0)
	highlight.FillTransparency = 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	Debris:AddItem(highlight, 20)

	task.delay(20, function()
		if character then
			character:SetAttribute("AttackBuff", (character:GetAttribute("AttackBuff") or 1) / 1.3)
		end
	end)
end

-- RacialSkills.Elezen() - Arcane Siphon: refill the caster's mana
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Elezen(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 2)

	AnimationHandler.LoadAnim(character, "Skill", "rbxassetid://117886434655481", nil, false)

	hrp.Anchored = true

	task.wait(2)

	hrp.Anchored = false

	if not character or not character.Parent or StateHandler.GetState(character, "Stunned") then
		return
	end

	local sparks = ReplicatedStorage.assets.FX.skills.manaSparks.Main:Clone()
	sparks.Parent = hrp
	for _, eff in pairs(sparks:GetChildren()) do
		if eff:IsA("ParticleEmitter") and eff:GetAttribute("EmitCount") then
			eff:Emit(eff:GetAttribute("EmitCount"))
		end
	end

	playSound(character, SoundFolder:FindFirstChild("ManaCharge"))

	-- TODO: Add the counter: while ManaCounter is set, a hit deals no damage and gives
	-- mana. The skill only refills mana now.
	player:FindFirstChild("PlayerStats"):FindFirstChild("Mana").Value =
		player:FindFirstChild("PlayerStats"):FindFirstChild("MaxMana").Value
end

-- RacialSkills.Seer() - Null Gaze: a beam that damages and slows for about 5 seconds
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Seer(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 6)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.75)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://129404885767130"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	hrp.Anchored = true

	task.wait(0.75)

	playSound(character, SoundFolder:FindFirstChild("Fire"))

	hrp.Anchored = false

	SpeedService.Push(character, "RacialSkill", 3, SpeedService.Priority.SKILL)

	local fire = ReplicatedStorage.assets.FireForwad.Attachment:Clone()
	fire.Parent = character.Head
	game.Debris:AddItem(fire, 5)

	local params = {
		SizeOrPart = Vector3.new(4, 6, 12),
		LookingFor = "Humanoid",
		Debug = false,
		Blacklist = { character },
	}

	local hitbox = HitboxClass.new(params)
	local hitList = {}
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -6))

	hitbox.HitSomeone:Connect(function(hitChars)
		-- Ten ticks at 5 damage keep the total near 50. stunTime is 0, so the slow
		-- controls movement instead of a freeze.
		processHit(player, character, hitChars, hitList, 5, "Magic", 10, 0, 0, nil, {
			Slow = true,
			-- A hard crawl, so the target cannot walk out of an M1.
			SlowSpeed = 4,
			-- Longer than the tick spacing, so the slow holds for the whole beam.
			SlowDuration = 1.0,
		})
	end)

	task.spawn(function()
		-- 10 ticks of 0.4 seconds active and a 0.1-second gap, about 5 seconds in total.
		for i = 1, 10 do
			if not hitbox or not character or character.Humanoid.Health <= 0 then
				break
			end
			hitbox:Start()
			task.wait(0.4)

			hitbox:Stop()
			hitbox:ClearTaggedChars()
			table.clear(hitList)
			task.wait(0.1)
		end
	end)

	task.delay(5, function()
		if hitbox then
			hitbox:Destroy()
		end
		if character and character:FindFirstChild("Humanoid") then
			SpeedService.Pop(character, "RacialSkill")
		end
	end)
end

-- RacialSkills.Meskar() - Spectre Round: fire a beam projectile from a gun
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Meskar(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local gunTemplate = ReplicatedStorage.assets:FindFirstChild("gunHandle")
	local gun = gunTemplate:Clone()
	gun.Name = "MeskariGun"

	local arm = character:FindFirstChild("Left Arm")

	gun.Parent = character

	local motor = gun.gunHandle
	motor.Parent = character
	motor.Part0 = arm
	motor.Part1 = gun

	Debris:AddItem(gun, 1)
	Debris:AddItem(motor, 2)

	StateHandler.SetState(character, "CantAnything", true, 1)
	AnimationHandler.LoadAnim(character, "Shoot", "rbxassetid://130627090034596", nil, false)

	playSound(character, SoundFolder:FindFirstChild("GunLunge"))

	local laser = gun.Laser2

	local info = TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0)

	local laser2tweenON = game.TweenService:Create(laser, info, { Transparency = 0.3 })
	local laser2tweenOFF = game.TweenService:Create(laser, info, { Transparency = 1 })

	task.wait(0.5)

	for i, v in pairs(gun.MuzzleFlash:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(3)
		end
	end

	laser2tweenON:Play()
	task.delay(0.2, function()
		laser2tweenOFF:Play()
	end)

	playSound(character, SoundFolder:FindFirstChild("Gunshot"))

	local duration = 0.2

	local params = {
		SizeOrPart = Vector3.new(3, 14, 3),
		LookingFor = "Humanoid",
		Blacklist = { character },
		Debug = false,
	}

	local hitbox = HitboxClass.new(params)

	hitbox:WeldTo(character["Left Arm"], CFrame.new(0, -9, 0))

	local alreadyHit = {}

	hitbox.HitSomeone:Connect(function(hitChars)
		processHit(player, character, hitChars, alreadyHit, 10, "Ranged", 30, 1, 1, hrp)
		hitbox:Destroy()
	end)

	hitbox:Start()
	task.delay(duration, function()
		if hitbox then
			hitbox:Destroy()
		end
	end)
end

-- RacialSkills.Karu() - Headbutt: lunge forward and knock the target up and back
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Karu(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://85417894607734"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	playSound(character, SoundFolder:FindFirstChild("Step"))

	task.wait(0.1)

	SpeedService.Push(character, "RacialSkill", 0, SpeedService.Priority.SKILL)

	task.wait(0.5)

	playSound(character, SoundFolder:FindFirstChild("woosh"))
	playSound(character, SoundFolder:FindFirstChild("Dash"))

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = hrp.CFrame.LookVector * 60
	bv.Parent = hrp
	Debris:AddItem(bv, 0.2)

	local params = {
		SizeOrPart = Vector3.new(4, 6, 4),
		LookingFor = "Humanoid",
		Debug = false,
		Blacklist = { character },
		WeldTo = hrp,
	}

	local hitbox = HitboxClass.new(params)
	local hitList = {}
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -4))

	hitbox.HitSomeone:Connect(function(hitChars)
		processHit(player, character, hitChars, hitList, 15, "Physical", 50, 1, 2)
	end)

	hitbox:Start()

	task.delay(0.4, function()
		hitbox:Destroy()
		SpeedService.Pop(character, "RacialSkill")
	end)
end

-- RacialSkills.Verdis() - Root Prison: root every target around the caster
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Verdis(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	hrp.Anchored = true

	StateHandler.SetState(character, "CantAnything", true, 1.2)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://128593873114650"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	task.wait(1)

	playSound(character, SoundFolder:FindFirstChild("GroundSlam"))

	local params = {
		SizeOrPart = 10,
		SpatialOption = "InRadius",
		LookingFor = "Humanoid",
		Blacklist = { character },
		Debug = false,
	}

	local hitbox = HitboxClass.new(params)
	hitbox:WeldTo(hrp)
	local hitList = {}

	hitbox.HitSomeone:Connect(function(hitChars)
		-- Root without a ragdoll.
		processHit(
			player,
			character,
			hitChars,
			hitList,
			5,
			"Nature",
			0,
			0,
			0,
			nil,
			{ Root = true, RootDuration = 2 }
		)
	end)

	hitbox:Start()

	local vfx = Assets.FX.skills:FindFirstChild("VerdisSkillPart").Attachment:Clone()
	vfx.Parent = hrp
	Debris:AddItem(vfx, 1.5)

	task.delay(0.2, function()
		hitbox:Destroy()
		hrp.Anchored = false
	end)
end

-- RacialSkills.Marasi() - Tidal Slug: throw a water projectile
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Marasi(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)
	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://131815122798568"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	playSound(player.Character, game:GetService("ReplicatedStorage").assets.sounds.magic.Fire)

	local Glow1 = game.ReplicatedStorage.Magic.BlueGlow.Glow:Clone()
	local Glow2 = game.ReplicatedStorage.Magic.BlueGlow.Glow:Clone()

	Glow1.Parent = player.Character["Right Arm"]
	Glow1.Position = player.Character["Right Arm"].RightGripAttachment.Position

	Glow2.Parent = player.Character["Left Arm"]
	Glow2.Position = player.Character["Left Arm"].LeftGripAttachment.Position

	task.wait(0.2)

	SpeedService.Push(character, "RacialSkill", 2, SpeedService.Priority.SKILL)

	task.wait(0.8)

	Glow1:Destroy()
	Glow2:Destroy()

	SpeedService.Pop(character, "RacialSkill")

	playSound(character, SoundFolder:FindFirstChild("Explosion"))

	local params = {
		SizeOrPart = 3,
		LookingFor = "Humanoid",
		Blacklist = { character },
		Debug = false,
	}

	local hitbox = HitboxClass.new(params)

	local projectile = ReplicatedStorage.assets.waterBomb:Clone()
	projectile.Parent = workspace.plrManager.projectiles
	projectile.CFrame = character.PrimaryPart.CFrame * CFrame.new(0, -0.5, -3)
	hitbox:WeldTo(projectile)

	local bv = Instance.new("BodyVelocity")
	bv.Velocity = hrp.CFrame.LookVector * 70
	bv.MaxForce = Vector3.new(1, 1, 1) * 1000000
	bv.Parent = projectile

	local alreadyHit = {}

	hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			local humanoid = hit:FindFirstChild("Humanoid")
			local targetChar = humanoid and humanoid.Parent
			if
				not targetChar
				or targetChar:IsA("Model") and not targetChar:FindFirstChild("Humanoid")
			then
				continue
			end

			local isPlayer = game.Players:GetPlayerFromCharacter(targetChar)

			if humanoid and (not isPlayer or isPlayer ~= player) and not alreadyHit[targetChar] then
				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = player.Character:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then
					return
				end

				if StateHandler.GetState(player.Character, "Stunned") then
					return
				end

				if StateHandler.GetState(targetChar, "Dodging") then
					local targetPlrData =
						game.Players:GetPlayerFromCharacter(targetChar).PlayerStats
					if targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
						targetPlrData.Mana.Value += 8
					end

					local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
					sound.Parent = targetHRP
					sound:Play()
					local effect = ReplicatedStorage.assets.FX.Dodged:Clone()
					effect.Parent = targetHRP
					effect.Enabled = true
					game.Debris:AddItem(sound, 3)
					game.Debris:AddItem(effect, 0.3)

					if targetChar.Torso then
						for _, part in pairs(targetChar:GetChildren()) do
							if
								part:IsA("BasePart")
								and part ~= targetHRP
								and part.Name ~= "Head"
								and part.Name ~= "Left Arm"
							then
								local oldTrans = part.Transparency
								part.Transparency = 0.7
								task.delay(0.3, function()
									part.Transparency = oldTrans
								end)
							end
						end
					end

					return
				end

				local function doAttack(extraDmg, knockbackDistance)
					local direction = (targetHRP.Position - attackerHRP.Position).Unit

					local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
						or "rbxassetid://111089735892609"
					AnimationHandler.LoadAnim(targetChar, "Hit", animID, nil, false)
					require(game.ServerScriptService.modules.helperModule).ApplyKnockback(
						targetChar,
						direction,
						knockbackDistance * 5,
						0.2
					)
					StateHandler.SetStun(targetChar, true, 1, 2)
					require(game.ServerScriptService.modules.ragdollManager).Ragdoll(targetChar, 1)

					dmgCalculator.CalculateDamage(
						attackerHRP.Parent,
						targetChar,
						25,
						extraDmg,
						false,
						"Racial"
					)

					playSound(targetChar, game.ReplicatedStorage.assets.sounds.magic.Explosion)

					if targetChar.Humanoid.Health > 0 then
						require(game.ServerScriptService.modules.dataManager).AddWeaponXP(
							game.Players:GetPlayerFromCharacter(player.Character),
							"Fists",
							25 + extraDmg
						)
					end

					local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
					highlight.Parent = humanoid.Parent
					game.Debris:AddItem(highlight, 0.1)

					local hitEff =
						game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
							:Clone()
					hitEff.Parent = targetChar:FindFirstChild("Torso")
					game:GetService("Debris"):AddItem(hitEff, 1)
					task.delay(0.5, function()
						for _, v in pairs(hitEff:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								v.Enabled = false
							end
						end
					end)

					local ballClone = game:GetService("ReplicatedStorage").Magic.Ball:Clone()
					local swirlClone = game:GetService("ReplicatedStorage").Magic.SwirlShockwaveFire
						:Clone()
					local groundClone = game:GetService("ReplicatedStorage").Magic.DestroyedGround
						:Clone()

					groundClone.Parent = game.Workspace
					ballClone.Parent = game.Workspace
					swirlClone.Parent = game.Workspace
					ballClone.Position = humanoid.Parent.Torso.Position
					swirlClone.Position = humanoid.Parent.Torso.Position
					groundClone.Position = Vector3.new(
						humanoid.Parent.Torso.Position.X,
						humanoid.Parent.Torso.Position.Y - 5.5,
						humanoid.Parent.Torso.Position.Z
					)

					local destination1 = Vector3.new(
						humanoid.Parent.Torso.Position.X,
						humanoid.Parent.Torso.Position.Y - 3.5,
						humanoid.Parent.Torso.Position.Z
					)
					local destination2 = Vector3.new(
						humanoid.Parent.Torso.Position.X,
						humanoid.Parent.Torso.Position.Y - 6.5,
						humanoid.Parent.Torso.Position.Z
					)

					local TweenService = game:GetService("TweenService")
					local tweenInfo1 = TweenInfo.new(
						0.5,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.InOut,
						0,
						false,
						0
					)
					local tweenInfo2 = TweenInfo.new(
						2,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.InOut,
						0,
						false,
						0
					)

					local Settings1 = { Position = destination1 }
					local Tween1 = TweenService:Create(groundClone, tweenInfo1, Settings1)

					local Settings2 = { Position = destination2 }
					local Tween2 = TweenService:Create(groundClone, tweenInfo2, Settings2)

					Tween1:Play()
					wait(5)
					Tween2:Play()

					alreadyHit[targetChar] = true
				end

				if StateHandler.GetState(targetChar, "Parrying") then
					local parryE =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
							:Clone()
					local effect2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
					local clash =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
							:Clone()
					local clash2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
							:Clone()
					clash2.Parent = targetChar:WaitForChild("Right Arm")
					clash2:Emit(30)
					game.Debris:AddItem(clash2, 0.7)
					local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
					h1.Parent = player.Character
					game.Debris:AddItem(h1, 0.1)
					parryE.Parent = player.Character:WaitForChild("Torso")
					effect2.Parent = player.Character:WaitForChild("Torso")
					clash.Parent = player.Character:WaitForChild("Right Arm")
					parryE.Enabled = true
					effect2.Enabled = true
					clash:Emit(30)
					game.Debris:AddItem(clash, 0.7)
					game.Debris:AddItem(parryE, 0.7)
					game.Debris:AddItem(effect2, 0.7)

					playSound(player.Character, ReplicatedStorage.assets.sounds.ParrySound)

					-- A parry beats hyper armor: clear it so the punish stun lands.
					player.Character:SetAttribute("HyperArmor", nil)
					StateHandler.SetStun(player.Character, true, 0.5, 2)
					StateHandler.SetState(player.Character, "CantAnything", true, 0.5)

					AnimationHandler.StopAnim(player.Character, "ALL")
					AnimationHandler.LoadAnim(
						player.Character,
						"Parried",
						"rbxassetid://74891530644094",
						nil,
						false
					)

					hitbox:Destroy()
					game.Debris:AddItem(projectile, 0.2)
				elseif
					StateHandler.GetState(targetChar, "M1")
					or StateHandler.GetState(targetChar, "M2")
				then
					hitbox:Destroy()
					return
				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- BlockResolver checks facing and fills the guard bar. This skill keeps its own
					-- fixed chip damage.
					local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
					local verdict = BlockResolver.Resolve({
						attacker = character,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = false,
						attackClass = "Skill",
						dmg = 0,
					})

					if verdict.outcome == "Bypass" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(0, 5)
					elseif verdict.outcome == "GuardBreak" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(-4, 5)
					else
						BlockResolver.OnAttackerLandedHit(character)
						doAttack(-4, 5)
						playSound(targetChar, ReplicatedStorage.assets.sounds.BlockingHit2)
						local parryE =
							game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
								:Clone()
						local effect2 =
							game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit
								:Clone()
						local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
						h1.Parent = targetChar
						game.Debris:AddItem(h1, 0.1)
						parryE.Parent = targetChar:WaitForChild("Torso")
						effect2.Parent = targetChar:WaitForChild("Torso")
						parryE.Enabled = true
						effect2.Enabled = true
						game.Debris:AddItem(parryE, 0.7)
						game.Debris:AddItem(effect2, 0.7)
					end
				else
					doAttack(0, 5)
				end
			end
		end
	end)

	hitbox:Start()
	Debris:AddItem(projectile, 3)
	task.delay(3, function()
		if hitbox then
			hitbox:Destroy()
		end
	end)
end

-- RacialSkills.Cruor() - Parasitic Impale: grab a target and deal damage over time
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Cruor(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 2)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2

	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
	game.TweenService
		:Create(NewShield2, tweenInfo, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://139662498198370"
	local animator = character:FindFirstChild("Humanoid")
		and character.Humanoid:FindFirstChild("Animator")
	if animator then
		local skillAnim = animator:LoadAnimation(anim)
		skillAnim:Play()

		task.delay(1, function()
			if skillAnim.IsPlaying then
				skillAnim:Stop()
			end
		end)
	end

	SpeedService.Push(character, "RacialSkill", 0, SpeedService.Priority.SKILL)

	task.wait(0.75)

	if not character or not character.Parent or not hrp or not hrp.Parent then
		return
	end

	local params = {
		SizeOrPart = Vector3.new(4, 4, 5),
		LookingFor = "Humanoid",
		Debug = false,
		Blacklist = { character },
		InitialPosition = hrp.CFrame,
	}

	local hitbox = HitboxClass.new(params)
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -3))

	local grabbed = false

	hitbox.HitSomeone:Connect(function(hitChars)
		if grabbed then
			return
		end

		for _, target in pairs(hitChars) do
			if
				target == character
				or not target:FindFirstChild("Humanoid")
				or target.Humanoid.Health <= 0
			then
				continue
			end
			SpeedService.Pop(character, "RacialSkill")

			if StateHandler.GetState(target, "Dodging") then
				playSound(target.HumanoidRootPart, SoundFolder:FindFirstChild("Dodged"))
				for _, part in pairs(target:GetChildren()) do
					if
						part:IsA("BasePart")
						and part.Name ~= "HumanoidRootPart"
						and part.Name ~= "Head"
						and part.Name ~= "Left Arm"
					then
						local oldTrans = part.Transparency
						part.Transparency = 0.7
						task.delay(0.3, function()
							part.Transparency = oldTrans
						end)
					end
				end
				continue
			end

			local tHRP = target:FindFirstChild("HumanoidRootPart")
			local tHum = target:FindFirstChild("Humanoid")

			if tHRP and tHum then
				grabbed = true
				hitbox:Destroy()

				StateHandler.SetState(target, "CantAnything", true, 1)
				StateHandler.SetStun(target, true, 1, 0)

				if animator then
					local anim2 = Instance.new("Animation")
					anim2.AnimationId = "rbxassetid://99307393579631"
					local grabAnim = animator:LoadAnimation(anim2)
					grabAnim:Play()
				end

				FallTracker.Reset(tHRP.Parent)
				tHRP.CFrame = hrp.CFrame * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.pi, 0)

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = tHRP
				weld.Parent = hrp

				tHRP.Anchored = false
				StateHandler.SetStun(target, true, 3, 0)

				task.spawn(function()
					for i = 1, 2 do
						if not target.Parent or tHum.Health <= 0 or not character.Parent then
							break
						end
						task.wait(0.5)

						dmgCalculator.CalculateDamage(character, target, 10, 0, false, "Racial")

						local bloodFX = Assets.FX:FindFirstChild("BloodHitEff")
						if bloodFX then
							local blood = bloodFX.Attachment:Clone()
							blood.Parent = tHRP
							blood.ParticleEmitter:Emit(5)
							Debris:AddItem(blood, 1)
						end

						playSound(tHRP, ReplicatedStorage.assets.sounds:FindFirstChild("PunchHit"))
					end

					if weld then
						weld:Destroy()
					end
					RagdollManager.Ragdoll(target, 1)
				end)

				-- Grab only one target.
				break
			end
		end
	end)

	hitbox:Start()

	-- Remove the hitbox after 0.2 seconds if nobody was hit.
	task.delay(0.2, function()
		if hitbox then
			hitbox:Destroy()
		end
		SpeedService.Pop(character, "RacialSkill")
	end)
end

-- RacialSkills.Arach() - Silk Grasp: grapple to a wall or pull into an enemy
-- @player: the casting player
-- @character: the player's character
-- @mouseHit: where the player aimed
--
-- Return: nothing. Yields for the grapple travel and the impact.
function RacialSkills.Arach(player: Player, character: Model, mouseHit: CFrame?)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChild("Humanoid")
	if not hrp or not hum or not mouseHit then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 2)

	local maxDist = 77.5
	local grappleSpeed = 0.2

	local AssetFolder = ReplicatedStorage.assets:FindFirstChild("grapple")
	local cordTemplate = AssetFolder:FindFirstChild("Cord")
	local grapplePartTemplate = AssetFolder:FindFirstChild("GrapplePart")

	if not cordTemplate or not grapplePartTemplate then
		warn("[RacialSkills] Grapple assets are missing in ReplicatedStorage.assets.grapple.")
		return
	end

	-- The server checks the grapple target with its own raycast.
	local startPos = hrp.Position
	local direction = (mouseHit.Position - startPos).Unit * maxDist

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances =
		{ character, workspace:FindFirstChild("ProjectileFolder") }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(startPos, direction, rayParams)
	local targetPos = rayResult and rayResult.Position or (startPos + direction)
	local hitInstance = rayResult and rayResult.Instance

	local dist = (targetPos - startPos).Magnitude
	if dist > maxDist then
		return
	end

	-- Without a hit, the point must be at least 4 studs above the caster.
	if not hitInstance and (targetPos.Y - hrp.Position.Y) < 4 then
		return
	end

	-- An invisible part is not a grapple target, unless it belongs to a character.
	if
		hitInstance
		and hitInstance.Transparency == 1
		and not hitInstance.Parent:FindFirstChild("Humanoid")
	then
		return
	end

	local enemyChar = nil
	if hitInstance then
		if hitInstance.Parent:FindFirstChild("Humanoid") then
			enemyChar = hitInstance.Parent
		elseif hitInstance.Parent.Parent:FindFirstChild("Humanoid") then
			enemyChar = hitInstance.Parent.Parent
		end
	end

	-- Only a character in plrManager.alive can be pulled in.
	if
		enemyChar
		and not enemyChar:IsDescendantOf(
			workspace:FindFirstChild("plrManager") and workspace.plrManager.alive or workspace
		)
	then
		return
	end

	AnimationHandler.LoadAnim(character, "Skill", "rbxassetid://70984351311195", nil, false)

	local attach = Instance.new("Attachment")
	attach.Parent = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")
	Debris:AddItem(attach, 0.7)

	local grapplePart = grapplePartTemplate:Clone()
	grapplePart.CFrame = CFrame.new(hrp.Position, targetPos)
	grapplePart.Parent = workspace
	Debris:AddItem(grapplePart, 4)

	local cord = cordTemplate:Clone()
	cord.Attachment0 = attach
	cord.Attachment1 = grapplePart:FindFirstChild("Attachment2")
		or Instance.new("Attachment", grapplePart)
	cord.Parent = attach.Parent
	Debris:AddItem(cord, 0.7)

	-- Attach the grapple part to a hit enemy.
	if enemyChar then
		local enemyTorso = enemyChar:FindFirstChild("Torso")
			or enemyChar:FindFirstChild("UpperTorso")
		if enemyTorso then
			local weld = Instance.new("Weld")
			weld.Part0 = enemyTorso
			weld.Part1 = grapplePart
			grapplePart.Anchored = false
			weld.Parent = grapplePart
		end
	else
		grapplePart.Anchored = true
	end

	local tween =
		game:GetService("TweenService")
			:Create(grapplePart, TweenInfo.new(grappleSpeed), { CFrame = CFrame.new(targetPos) })
	tween:Play()

	task.wait(grappleSpeed)

	if not character:IsDescendantOf(workspace) then
		return
	end

	playSound(character, SoundFolder:FindFirstChild("GrappleSound"))

	for _, obj in pairs(hrp:GetChildren()) do
		if obj:IsA("BodyVelocity") then
			obj:Destroy()
		end
	end

	local bv = Instance.new("BodyVelocity")
	bv.Name = "GrappleVelocity"
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.P = 1250

	local between = targetPos - hrp.Position

	if not enemyChar then
		-- Pull to the wall.
		bv.Velocity = Vector3.new(0, 60, 0) + between * 1.4
		bv.Parent = hrp
		Debris:AddItem(bv, 0.5)
	else
		-- Pull to the enemy.
		local daf = (enemyChar:FindFirstChild("HumanoidRootPart").Position - hrp.Position)

		bv.Velocity = Vector3.new(daf.X * 1.8, daf.Y + 50, daf.Z * 1.8)

		task.spawn(function()
			for i = 1, 8 do
				if not bv.Parent then
					break
				end
				bv.Velocity = Vector3.new(
					daf.X * (math.abs(i - 10) / 10 + 1),
					daf.Y + 50,
					daf.Z * (math.abs(i - 10) / 10 + 1)
				)
				task.wait(0.1)
			end
		end)

		bv.Parent = hrp
		Debris:AddItem(bv, 0.45)

		-- Wait for the impact.
		task.wait(0.6)

		if not enemyChar or not enemyChar:FindFirstChild("Humanoid") then
			return
		end

		local enemyState = {
			Blocking = StateHandler.GetState(enemyChar, "Blocking"),
			Parrying = StateHandler.GetState(enemyChar, "Parrying"),
			Dodging = StateHandler.GetState(enemyChar, "Dodging"),
		}

		if not enemyState.Blocking and not enemyState.Parrying and not enemyState.Dodging then
			local eHum = enemyChar.Humanoid
			if eHum.Health > 0 then
				dmgCalculator.CalculateDamage(character, enemyChar, 15, 0, false, "Racial")

				local h1 = ReplicatedStorage.assets.FX:FindFirstChild("h1"):Clone()
				h1.Parent = enemyChar:FindFirstChild("HumanoidRootPart")
				Debris:AddItem(h1, 0.1)

				AnimationHandler.LoadAnim(
					enemyChar,
					"Hit",
					"rbxassetid://96311777205911",
					nil,
					false
				)
				RagdollManager.Ragdoll(enemyChar, 1)

				playSound(enemyChar.HumanoidRootPart, SoundFolder:FindFirstChild("OwlSlash"))
				playSound(enemyChar.HumanoidRootPart, SoundFolder:FindFirstChild("PunchHit"))
			end
		elseif enemyState.Parrying then
			RagdollManager.Ragdoll(character, 2)
			playSound(character, ReplicatedStorage.assets.FX["parry/blocked"].parry)
		elseif enemyState.Blocking then
			-- This skill keeps its own block result (the attacker bounces off and ragdolls),
			-- but blocking it still fills the guard bar.
			local GuardBarService = require(game.ServerScriptService.modules.GuardBarService)
			if GuardBarService.AddOnBlock(enemyChar, "Skill") == false then
				RagdollManager.Ragdoll(character, 2)
				playSound(
					enemyChar.HumanoidRootPart,
					ReplicatedStorage.assets.sounds:FindFirstChild("Block")
				)
			end
		elseif enemyState.Dodging then
			playSound(enemyChar.HumanoidRootPart, SoundFolder:FindFirstChild("Dodged"))

			for _, part in pairs(enemyChar:GetChildren()) do
				if
					part:IsA("BasePart")
					and part.Name ~= "HumanoidRootPart"
					and part.Name ~= "Head"
				then
					local oldTrans = part.Transparency
					part.Transparency = 0.7
					task.delay(0.3, function()
						part.Transparency = oldTrans
					end)
				end
			end

			RagdollManager.Ragdoll(character, 2)
		end
	end
end

-- RacialSkills.Maw() - Void Crunch: a bite that breaks the target's guard
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Maw(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://110763167362898"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	task.wait(0.1)

	SpeedService.Push(character, "RacialSkill", 3, SpeedService.Priority.SKILL)

	task.wait(0.5)

	local skillVFX = ReplicatedStorage.assets.FX.skills.MawSkill.MIDDLE:Clone()
	skillVFX.Parent = hrp
	game.Debris:AddItem(skillVFX, 0.5)

	playSound(character, SoundFolder:FindFirstChild("Bite"))

	local params = {
		SizeOrPart = 6,
		LookingFor = "Humanoid",
		Blacklist = { character },
	}

	local hitbox = HitboxClass.new(params)
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -3))
	local hitList = {}

	hitbox.HitSomeone:Connect(function(hitChars)
		processHit(
			player,
			character,
			hitChars,
			hitList,
			30,
			"Void",
			20,
			1,
			0,
			nil,
			{ GuardBreak = true }
		)
	end)

	hitbox:Start()

	task.delay(0.3, function()
		hitbox:Destroy()
		SpeedService.Pop(character, "RacialSkill")
	end)
end

-- RacialSkills.Ancestor() - Vampire Drain: grab a target and drain HP to heal
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Ancestor(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChild("Humanoid")
	if not hrp or not hum then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)

	hrp.Anchored = true

	playSound(character, SoundFolder:FindFirstChild("Drain"))

	local params = {
		SizeOrPart = Vector3.new(6, 5, 6),
		LookingFor = "Humanoid",
		Blacklist = { character },
	}

	local hitbox = HitboxClass.new(params)
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -3))
	local grabbed = false

	AnimationHandler.LoadAnim(character, "VampireBite", "rbxassetid://84861768973112", nil, false)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	task.wait(0.5)

	hitbox.HitSomeone:Connect(function(hitChars)
		if grabbed then
			return
		end
		for _, target in pairs(hitChars) do
			local tHRP = target:FindFirstChild("HumanoidRootPart")
			local tHum = target:FindFirstChild("Humanoid")

			if StateHandler.GetState(target, "Dodging") then
				local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
				sound.Parent = tHRP
				sound:Play()
				local effect = ReplicatedStorage.assets.FX.Dodged:Clone()
				effect.Parent = tHRP
				effect.Enabled = true
				game.Debris:AddItem(sound, 3)
				game.Debris:AddItem(effect, 0.3)

				if target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso") then
					for _, part in pairs(target:GetChildren()) do
						if part:IsA("BasePart") and part ~= tHRP and part.Name ~= "Head" then
							local oldTrans = part.Transparency
							part.Transparency = 0.7
							task.delay(0.3, function()
								part.Transparency = oldTrans
							end)
						end
					end
				end
				continue
			end

			if tHRP and tHum then
				AnimationHandler.StopAnim(character, "VampireBite", "rbxassetid://84861768973112")

				AnimationHandler.LoadAnim(
					character,
					"VampGrabAnim",
					"rbxassetid://108023368315027",
					nil,
					false
				)

				StateHandler.SetState(character, "CantAnything", true, 1)
				StateHandler.SetState(target, "CantAnything", true, 1.5)
				StateHandler.SetStun(target, true, 1.5, 0)

				grabbed = true

				FallTracker.Reset(tHRP.Parent)
				tHRP.CFrame = hrp.CFrame * CFrame.new(0, 0, -2) * CFrame.Angles(0, math.pi, 0)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = tHRP
				weld.Parent = hrp

				tHRP.Anchored = false

				task.wait(0.5)

				local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
					or "rbxassetid://111089735892609"
				AnimationHandler.LoadAnim(target, "Hit", animID, nil, false)

				RagdollManager.Ragdoll(target, 1)

				dmgCalculator.CalculateDamage(character, target, 15, 0, false, "Racial")

				playSound(target, ReplicatedStorage.assets.sounds.PunchHit)

				local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
				highlight.Parent = target
				game.Debris:AddItem(highlight, 0.1)

				local hitEff = game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
					:Clone()
				local torso = target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso")
				if torso then
					hitEff.Parent = torso
					game:GetService("Debris"):AddItem(hitEff, 1)
					task.delay(0.5, function()
						for _, v in pairs(hitEff:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								v.Enabled = false
							end
						end
					end)
				end

				hum.Health = math.min(hum.Health + 15, hum.MaxHealth)

				-- If the target died, remove the weld at once, so the body does not drag the
				-- attacker down.
				if tHum.Health <= 0 then
					if weld then
						weld:Destroy()
					end
					if hrp then
						hrp.Anchored = false
					end
				else
					task.delay(0.5, function()
						if weld then
							weld:Destroy()
						end
						if hrp then
							hrp.Anchored = false
						end
					end)
				end

				break
			end
		end
	end)

	hitbox:Start()

	task.delay(0.2, function()
		hitbox:Destroy()
		if not grabbed then
			hrp.Anchored = false
		end
	end)
end

-- RacialSkills.Grob() - Jury-Rigged Bomb: throw a bomb that explodes, smokes, or fails
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing.
function RacialSkills.Grob(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	AnimationHandler.LoadAnim(character, "ThrowBomb", "rbxassetid://98864333664089", nil, false)

	hrp.Anchored = true

	task.wait(0.6)

	hrp.Anchored = false

	playSound(character, SoundFolder:FindFirstChild("woosh"))

	local bombModel = ReplicatedStorage.assets:FindFirstChild("bomb"):Clone()
	local bombPart = bombModel:WaitForChild("rootBomb")
	bombModel.PrimaryPart = bombPart
	bombModel:PivotTo(hrp.CFrame * CFrame.new(0, 2, -1))

	bombModel.Parent = workspace.plrManager.projectiles

	-- The bomb parts are welded, so a velocity on the root part moves the whole model.
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = (hrp.CFrame.LookVector + Vector3.new(0, 0.5, 0)) * 50
	bv.MaxForce = Vector3.new(1, 1, 1) * 10000
	bv.Parent = bombPart

	game.Debris:AddItem(bv, 0.3)

	task.delay(1.5, function()
		if not bombModel.Parent then
			return
		end

		local rng = math.random(1, 100)
		local explosionType = "Normal"

		if rng <= 10 then
			explosionType = "Dud"
		elseif rng <= 40 then
			explosionType = "Smoke"
		end

		if explosionType == "Dud" then
			-- A dud hurts the caster a little.
			if character:FindFirstChild("Humanoid").Health > 20 then
				character:FindFirstChild("Humanoid"):TakeDamage(5)
			end
			playSound(bombPart, SoundFolder:FindFirstChild("Dud"))

			-- Keep the dud visible for a moment.
			task.delay(2, function()
				if bombModel then
					bombModel:Destroy()
				end
			end)
		elseif explosionType == "Smoke" then
			playSound(bombPart, SoundFolder:FindFirstChild("Explosion"))
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.new(0.2, 0.2, 0.2)
			smoke.Size = 20
			smoke.Parent = bombPart

			-- Remove the bomb after the smoke clears.
			task.delay(5, function()
				if bombModel then
					bombModel:Destroy()
				end
			end)
		else
			playSound(bombPart, SoundFolder:FindFirstChild("Explosion"))
			local params = {
				SizeOrPart = 15,
				InitialPosition = bombPart.CFrame,
				SpatialOption = "InRadius",
				LookingFor = "Humanoid",
				Blacklist = { character },
			}
			local hitbox = HitboxClass.new(params)
			local hitList = {}
			hitbox.HitSomeone:Connect(function(hitChars)
				processHit(player, character, hitChars, hitList, 20, "Explosion", 40, 1, 2)
			end)
			hitbox:Start()

			task.delay(0.2, function()
				hitbox:Destroy()
			end)

			local exp = Instance.new("Explosion")
			exp.Position = bombPart.Position
			exp.DestroyJointRadiusPercent = 0
			exp.Parent = workspace

			bombModel:Destroy()
		end
	end)
end

-- RacialSkills.Aegir() - lunge with dragon wings and slam the ground
-- @player: the casting player
-- @character: the player's character
--
-- Return: nothing. Yields during the lunge.
function RacialSkills.Aegir(player: Player, character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	StateHandler.SetState(character, "CantAnything", true, 1)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.TweenService
		:Create(
			NewShield2,
			TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
			{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
		)
		:Play()
	game.Debris:AddItem(NewShield2, 0.5)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://125846023799817"
	local animator = character.Humanoid.Animator
	local skillAnim = animator:LoadAnimation(anim)
	skillAnim:Play()

	playSound(character, SoundFolder:FindFirstChild("Step"))

	task.wait(0.4)

	local eff = ReplicatedStorage.assets.FX.fists.partic:Clone()
	eff.Parent = character:FindFirstChild("Right Leg")
	eff.Enabled = true
	Debris:AddItem(eff, 0.7)

	SpeedService.Push(character, "RacialSkill", 4, SpeedService.Priority.SKILL)

	playSound(character, SoundFolder:FindFirstChild("woosh"))
	playSound(character, SoundFolder:FindFirstChild("Dash"))

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(25000, 0, 25000)
	bv.Velocity = hrp.CFrame.LookVector * 50
	bv.Parent = hrp
	Debris:AddItem(bv, 0.3)

	task.wait(0.5)

	VFX.Wings(character:FindFirstChild("Torso"))

	playSound(character, SoundFolder:WaitForChild("GroundImpact"))

	local params = {
		SizeOrPart = Vector3.new(7, 6, 8),
		LookingFor = "Humanoid",
		Debug = false,
		Blacklist = { character },
		WeldTo = hrp,
	}

	local hitbox = HitboxClass.new(params)
	local hitList = {}
	hitbox:WeldTo(hrp, CFrame.new(0, 0, -4))

	local startPos = hrp.Position + (hrp.CFrame.LookVector * 5)
	local direction = Vector3.new(0, -15, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(startPos, direction, params)

	if result then
		local slamEff = ReplicatedStorage.assets.FX.aegir.groundSlam:Clone()
		slamEff.Parent = workspace
		slamEff.Position = result.Position + Vector3.new(0, 0.25, 0)
		for _, v in pairs(slamEff.floor:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				v:Emit(5)
			end
		end
		Debris:AddItem(slamEff, 3)
	end

	hitbox.HitSomeone:Connect(function(hitChars)
		processHit(player, character, hitChars, hitList, 30, "Physical", 25, 1, 2)
	end)

	hitbox:Start()

	task.delay(0.3, function()
		hitbox:Destroy()
		SpeedService.Pop(character, "RacialSkill")
	end)
end

return RacialSkills
