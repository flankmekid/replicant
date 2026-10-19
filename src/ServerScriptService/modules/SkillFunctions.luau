-- SPDX-License-Identifier: MIT
--
-- The server side of the weapon skills, keyed by skill name, and the universal Burst.
-- processHit resolves the hits of most skills.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local StateHandler = require(ReplicatedStorage.modules.stateHandler)
local animationHandler = require(ReplicatedStorage.modules.animationHandler)
local hitboxClass = require(ReplicatedStorage.modules.hitboxClass)
local hitboxTypes = require(ReplicatedStorage.modules.hitboxClass.Types)
local helperModule = require(ServerScriptService.modules.helperModule)
local ragdollManager = require(ServerScriptService.modules.ragdollManager)
local dataManager = require(ServerScriptService.modules.dataManager)
local dmgCalculator = require(ServerScriptService.modules.damageCalculator)
local ParryService = require(ServerScriptService.modules.parryService)
local SpeedService = require(ServerScriptService.modules.SpeedService)

local module = {}

local function playSound(char, soundIdOrObj)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		warn(`[SkillFunctions] {char.Name} has no HumanoidRootPart for a sound.`)
		return
	end

	local s
	if typeof(soundIdOrObj) == "string" then
		s = Instance.new("Sound")
		s.SoundId = soundIdOrObj
	elseif typeof(soundIdOrObj) == "Instance" and soundIdOrObj:IsA("Sound") then
		s = soundIdOrObj:Clone()
	else
		return
	end

	s.Parent = root
	s:Play()
	Debris:AddItem(s, s.TimeLength + 1)
end

local function applyDashEffect(char)
	for _, v in pairs(char:GetChildren()) do
		if v:IsA("BasePart") and v.Transparency ~= 1 then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Transparency = 0.1
			part.CanCollide = false
			part.Parent = workspace
			part.BrickColor = BrickColor.new("Really black")
			part.Material = Enum.Material.Neon
			part.Size = v.Size
			part.CFrame = v.CFrame
			if v:FindFirstChildOfClass("SpecialMesh") then
				v:FindFirstChildOfClass("SpecialMesh"):Clone().Parent = part
			end
			TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			Debris:AddItem(part, 0.5)
		end
	end
end

local function createAfterImage(character)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Transparency ~= 1 then
			local clone = Instance.new("Part")
			clone.Anchored = true
			clone.CanCollide = false
			clone.Transparency = 0.1
			clone.BrickColor = BrickColor.Black()
			clone.Material = Enum.Material.Neon
			clone.Size = part.Size
			clone.CFrame = part.CFrame
			clone.Parent = workspace
			clone.Name = "AfterImageFX"

			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh:Clone().Parent = clone
			end

			TweenService:Create(clone, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			Debris:AddItem(clone, 0.6)
		end
	end
end

-- Resolves a skill hit on each target: dodge, then block, parry, or a clean hit, with
-- damage, stun, and weapon XP.
local function processHit(
	player,
	attackerChar,
	hitCharsTable,
	alreadyHit,
	damage,
	weaponType,
	knockbackDist,
	stunTime,
	ragdollTime,
	originPart,
	extraVar
)
	local attackerHRP = attackerChar:FindFirstChild("HumanoidRootPart")
	-- A projectile passes originPart. Otherwise the attacker's HumanoidRootPart is the
	-- origin.
	local originPosition = originPart and originPart.Position
		or (attackerHRP and attackerHRP.Position)

	local var = nil
	if extraVar then
		var = tostring(extraVar)
	end

	if not attackerHRP or not originPosition then
		return
	end
	if StateHandler.IsInterrupted(attackerChar) then
		return
	end

	for _, hit in pairs(hitCharsTable) do
		local humanoid = hit:FindFirstChild("Humanoid")
		local targetChar = humanoid and humanoid.Parent
		if
			not targetChar
			or (targetChar:IsA("Model") and not targetChar:FindFirstChild("Humanoid"))
		then
			continue
		end

		local isPlayer = game.Players:GetPlayerFromCharacter(targetChar)

		if humanoid and (not isPlayer or isPlayer ~= player) and not alreadyHit[targetChar] then
			local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetHRP then
				return
			end

			if StateHandler.GetState(targetChar, "Dodging") then
				local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
				sound.Parent = targetHRP
				sound:Play()
				local effect = ReplicatedStorage.assets.FX.Dodged:Clone()
				effect.Parent = targetHRP
				effect.Enabled = true
				game.Debris:AddItem(sound, 3)
				game.Debris:AddItem(effect, 0.3)

				if
					targetChar:FindFirstChild("Torso") or targetChar:FindFirstChild("UpperTorso")
				then
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

			local function doAttack(extraDmg, finalKnockback)
				local direction = (targetHRP.Position - originPosition).Unit

				local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
					or "rbxassetid://111089735892609"
				animationHandler.LoadAnim(targetChar, "Hit", animID, nil, false)

				helperModule.ApplyKnockback(targetChar, direction, finalKnockback, 0.2)
				StateHandler.SetStun(targetChar, true, stunTime or 0.5, 2)
				if ragdollTime and ragdollTime > 0 then
					ragdollManager.Ragdoll(targetChar, ragdollTime)
				end

				dmgCalculator.CalculateDamage(
					attackerChar,
					targetChar,
					damage,
					extraDmg,
					false,
					"Skill"
				)

				if var and var == "LifeRegen" then
					attackerChar.Humanoid.Health += damage
				end

				if targetChar.Humanoid.Health > 0 then
					dataManager.AddWeaponXP(player, weaponType, damage + extraDmg)
				end

				local s = ReplicatedStorage.assets.sounds.PunchHit:Clone()
				s.Parent = targetHRP
				s:Play()
				game.Debris:AddItem(s, s.TimeLength + 1)

				local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
				highlight.Parent = targetChar
				highlight.Enabled = true
				game.Debris:AddItem(highlight, 0.2)

				local hitEff = game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
					:Clone()
				local torso = targetChar:FindFirstChild("Torso")
					or targetChar:FindFirstChild("UpperTorso")
				if torso then
					hitEff.Parent = torso
					for _, v in pairs(hitEff:GetChildren()) do
						if v:IsA("ParticleEmitter") then
							v.Enabled = true
						end
					end
					game:GetService("Debris"):AddItem(hitEff, 1)
					task.delay(0.5, function()
						for _, v in pairs(hitEff:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								v.Enabled = false
							end
						end
					end)
				end

				alreadyHit[targetChar] = true
			end

			if StateHandler.GetState(targetChar, "Blocking") then
				-- Skills do not guard-break by default. They fill the guard bar and can break the
				-- block.
				local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
				local verdict = BlockResolver.Resolve({
					attacker = attackerChar,
					target = targetChar,
					attackerPos = originPosition,
					targetHRP = targetHRP,
					guardbreak = false,
					attackClass = "Skill",
					dmg = damage,
				})
				local extra = verdict.chipDamage - damage

				if verdict.outcome == "Bypass" then
					animationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
					doAttack(extra, knockbackDist)
				elseif verdict.outcome == "GuardBreak" then
					-- The guard bar broke. GuardBarService already set the stun and the animation.
					animationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
					doAttack(extra, verdict.knockback)
				else
					BlockResolver.OnAttackerLandedHit(attackerChar)
					local parryE = ReplicatedStorage.assets.FX["parry/blocked"].parry:Clone()
					local torso = targetChar:FindFirstChild("Torso")
						or targetChar:FindFirstChild("UpperTorso")
					if torso then
						parryE.Parent = torso
						parryE.Enabled = true
						game.Debris:AddItem(parryE, 0.7)
					end
					doAttack(extra, verdict.knockback)
				end
			elseif StateHandler.GetState(targetChar, "Parrying") then
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
				ParryService.ResetParry(game.Players:GetPlayerFromCharacter(targetChar))
				require(game.ServerScriptService.modules.BlockResolver).OnParrySuccess(targetChar)
				if game.Players:GetPlayerFromCharacter(targetChar) then
					ReplicatedStorage.remotes.replicate:FireClient(
						game.Players:GetPlayerFromCharacter(targetChar),
						{
							Type = "Combat",
							Action = "M1",
							Func = "Parry",
							FolderName = (
								targetChar:FindFirstChildOfClass("Tool")
								and targetChar:FindFirstChildOfClass("Tool").Name
							) or "Katana",
						},
						attackerChar,
						targetChar
					)
				end

				animationHandler.StopAnim(attackerChar, "ALL")
				animationHandler.LoadAnim(
					attackerChar,
					"Parried",
					"rbxassetid://116383775729821",
					nil,
					false
				)
				return
			else
				doAttack(0, knockbackDist)
			end
		end
	end
end

-- SkillFunctions.AbyssalScream() - cast Abyssal Scream, a Dragon Slayer skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.AbyssalScream(player)
	local character = player.Character
	local hum = character.Humanoid
	local root = character.HumanoidRootPart

	StateHandler.SetState(character, "CantAnything", true, 1)

	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://81314710758281", nil, false)

	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	NewShield2.Parent = character
	NewShield2.CFrame = root.CFrame * CFrame.new(0, 5, 0)
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	WeldCon.Part0 = root
	WeldCon.Part1 = NewShield2
	WeldCon.Parent = NewShield2

	local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
	TweenService
		:Create(NewShield2, InfoTween, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()

	playSound(character, "rbxassetid://7100154577")
	Debris:AddItem(NewShield2, 2)

	task.wait(0.7)

	local gsAura = ReplicatedStorage.assets.FX.dragonSlayer.gsAuraPart

	local function applyAura(targetPart, duration)
		if not targetPart then
			return
		end

		for _, item in pairs(gsAura:GetChildren()) do
			if item:IsA("ParticleEmitter") then
				local clone = item:Clone()
				clone.Parent = targetPart
				game.Debris:AddItem(clone, duration)
			end
		end
	end

	local emitAttach = ReplicatedStorage.assets.FX.skills.AbyssalScreamEmits:Clone()
	emitAttach.Parent = root
	for _, eff in pairs(emitAttach:GetChildren()) do
		if eff:IsA("ParticleEmitter") and eff:GetAttribute("EmitCount") then
			eff:Emit(eff:GetAttribute("EmitCount"))
		end
	end

	applyAura(character:FindFirstChild("Left Leg"), 10)
	applyAura(character:FindFirstChild("Right Leg"), 10)

	playSound(character, ReplicatedStorage.assets.sounds.greatsword.Scream1)
	playSound(character, ReplicatedStorage.assets.sounds.greatsword.Scream2)

	local hitboxParams = { SizeOrPart = 7, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(root, CFrame.new(0, 2, 0))
	Hitbox:Start()

	StateHandler.SetState(character, "M1", true, 0.3)
	StateHandler.SetState(character, "MoveSpeedBuff", true, 10)
	StateHandler.SetState(character, "DefenseBuff", true, 10)

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(player, character, hitCharsTable, alreadyHit, 20, "Greatsword", 15, 0.5, 1, root)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
	end)
end

-- How long the burst gives i-frames and its hitbox is live.
local BURST_ACTIVE = 0.15
-- The CantAnything lock. It outlasts the i-frames, so a whiffed burst can be punished.
local BURST_WHIFF_RECOVERY = 1.0
-- How long the user is rooted after a burst that catches a target.
local BURST_ROOT_HIT = 0.5
-- How long the user is rooted after a whiff.
local BURST_ROOT_WHIFF = 1.0
-- The knockback radius around the user, in studs.
local BURST_RADIUS = 8
local BURST_KNOCKBACK = 30
-- How long enemies stay ragdolled, in seconds.
local BURST_RAGDOLL = 1.0

-- SkillFunctions.Burst() - break out of a combo with i-frames and knockback
-- @player: the player who pressed T
--
-- BurstHandler checks the mana and the cooldown. The design is in
-- docs/combat-design.md.
--
-- Return: nothing.
function module.Burst(player)
	local character = player.Character
	if not character then
		return
	end
	local hum = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return
	end

	-- Clear the stun first, so a player caught in a combo can burst out.
	StateHandler.SetStun(character, false)

	StateHandler.SetState(character, "Dodging", true, BURST_ACTIVE)
	StateHandler.SetState(character, "CantAnything", true, BURST_WHIFF_RECOVERY)

	-- Root the user. A whiff keeps the long root. The first target hit reschedules the
	-- release to the short root, and the token makes the old timer do nothing. The hitbox
	-- closes long before either release, so the result is known in time.
	helperModule.SetSpeed(character, 0)
	local rootToken = 0
	local function scheduleUnroot(after)
		rootToken += 1
		local myToken = rootToken
		task.delay(after, function()
			if myToken ~= rootToken then
				return
			end
			helperModule.ResetSpeed(character)
		end)
	end
	scheduleUnroot(BURST_ROOT_WHIFF)

	animationHandler.LoadAnim(character, "Burst", "rbxassetid://71570879146947", nil, false)

	-- TODO: Replace the reused Abyssal Scream telegraph with a Burst VFX.
	local shield = ReplicatedStorage.assets.FX.danger:Clone()
	shield.Parent = character
	shield.CFrame = root.CFrame * CFrame.new(0, 3, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = shield
	weld.Parent = shield
	TweenService:Create(shield, TweenInfo.new(0.15, Enum.EasingStyle.Cubic), { Transparency = 1 })
		:Play()
	Debris:AddItem(shield, 1)

	playSound(character, "rbxassetid://133937210261198")

	local emitAttach = ReplicatedStorage.assets.FX.skills.AbyssalScreamEmits:Clone()
	emitAttach.Parent = root
	for _, eff in pairs(emitAttach:GetChildren()) do
		if eff:IsA("ParticleEmitter") and eff:GetAttribute("EmitCount") then
			eff:Emit(eff:GetAttribute("EmitCount"))
		end
	end

	-- No damage: each enemy hit gets knockback and a short ragdoll.
	local Hitbox =
		hitboxClass.new({ SizeOrPart = BURST_RADIUS, SpatialOption = "InRadius", DebounceTime = 1 })
	Hitbox:WeldTo(root, CFrame.new(0, 0, 0))
	Hitbox:Start()

	local alreadyHit = {}
	local rootShortened = false
	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			local targetHum = hit:FindFirstChild("Humanoid")
			local targetChar = targetHum and targetHum.Parent
			if not targetChar then
				continue
			end
			local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetHRP or alreadyHit[targetChar] then
				continue
			end

			-- Never hit the caster.
			local hitPlr = game.Players:GetPlayerFromCharacter(targetChar)
			if targetChar == character or (hitPlr and hitPlr == player) then
				continue
			end

			alreadyHit[targetChar] = true

			-- The first target shortens the root. Later targets do not reschedule it.
			if not rootShortened then
				rootShortened = true
				scheduleUnroot(BURST_ROOT_HIT)
			end

			local direction = (targetHRP.Position - root.Position).Unit
			helperModule.ApplyKnockback(targetChar, direction, BURST_KNOCKBACK, 0.2)
			if BURST_RAGDOLL > 0 then
				ragdollManager.Ragdoll(targetChar, BURST_RAGDOLL)
			end
		end
	end)

	task.delay(BURST_ACTIVE, function()
		Hitbox:Destroy()
	end)
end

-- SkillFunctions.Whirlwind() - cast Whirlwind, a greatsword-family skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Whirlwind(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	StateHandler.SetState(character, "CantAnything", true, 2)
	StateHandler.SetState(character, "Sliding", true, 2)

	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://129202616365258", nil, false)
	playSound(character, ReplicatedStorage.assets.sounds.greatsword.woosh)

	task.delay(0.5, function()
		if not character or not root then
			return
		end
		local airborneVelocity = Instance.new("BodyVelocity")
		airborneVelocity.Parent = root
		airborneVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
		airborneVelocity.Velocity = (root.CFrame.LookVector * 60) + Vector3.new(0, 50, 0)
		Debris:AddItem(airborneVelocity, 0.4)

		applyDashEffect(character)
		task.delay(0.5, function()
			applyDashEffect(character)
		end)
	end)

	task.wait(1.6)
	playSound(character, ReplicatedStorage.assets.sounds.greatsword.GroundImpact)

	local function getEquippedTool()
		local currentCharacter = player.Character
		if not currentCharacter then
			return nil
		end
		local tool = currentCharacter:FindFirstChildOfClass("Tool")
		if tool and tool.Parent == currentCharacter then
			return tool.Name
		end
		return nil
	end

	if getEquippedTool() then
		local tool = character:FindFirstChild("Dragon Slayer")
			or character:FindFirstChild("Greatsword")
		local groundSlam = game.ReplicatedStorage.assets.FX.groundSlam.Attachment:Clone()
		groundSlam.Parent = tool.Greatsword
		groundSlam.Position = tool.Greatsword.Top.Position
		groundSlam.Orientation = Vector3.new(0, 0, 50)
		for _, eff in pairs(groundSlam:GetChildren()) do
			if eff:IsA("ParticleEmitter") then
				eff:Emit(eff:GetAttribute("EmitCount"))
			end
		end
	end

	local hitboxParams = { SizeOrPart = 8, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(root, CFrame.new(0, 0, -4))
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(player, character, hitCharsTable, alreadyHit, 15, "Greatsword", 15, 0.5, 0, root)
	end)

	task.delay(0.3, function()
		Hitbox:Destroy()
		helperModule.ResetSpeed(character)
	end)
end

-- SkillFunctions.BerserkerArmor() - cast Berserker Armor, a greatsword-family buff skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.BerserkerArmor(player)
	local char = player.Character
	local hum = char.Humanoid

	local RaceConfig = require(ReplicatedStorage.modules.RaceConfig)
	local raceValue = player:FindFirstChild("PlayerStats"):FindFirstChild("Race")

	local raceData = RaceConfig.Races[raceValue.Value]
	local visuals = raceData.Visuals

	local ArmorShirtTemplate = "http://www.roblox.com/asset/?id=1182924324"
	local ArmorPantsTemplate = "http://www.roblox.com/asset/?id=1182925117"

	animationHandler.LoadAnim(char, "Activate", "rbxassetid://81970199114583", nil, false)

	hum.Health += hum.MaxHealth / 4

	local oldShirtObj = char:FindFirstChildOfClass("Shirt")
	local oldPantsObj = char:FindFirstChildOfClass("Pants")

	local oldShirt = oldShirtObj and oldShirtObj.ShirtTemplate or ""
	local oldPants = oldPantsObj and oldPantsObj.PantsTemplate or ""

	char.HumanoidRootPart.Anchored = true

	task.wait(1)

	local gsAura = game.ReplicatedStorage.assets.FX.dragonSlayer.gsAuraPart

	local function applyAura(targetPart, duration)
		if not targetPart then
			return
		end

		for _, item in pairs(gsAura:GetChildren()) do
			if item:IsA("ParticleEmitter") then
				local clone = item:Clone()
				clone.Parent = targetPart
				game.Debris:AddItem(clone, duration)
			end
		end
	end

	applyAura(char:FindFirstChild("Torso"), 30)
	applyAura(char:FindFirstChild("Head"), 30)

	for i, v in pairs(char:GetChildren()) do
		if v:IsA("Accessory") then
			local handle = v:FindFirstChild("Handle")
			if handle then
				handle.Transparency = 1
			end
		end
	end

	local oldHeadColor = char.Head.Color
	char.Head.Color = Color3.fromRGB(0, 0, 0)

	char.HumanoidRootPart.Anchored = false

	playSound(char, ReplicatedStorage.assets.sounds.greatsword.Scream1)
	playSound(char, ReplicatedStorage.assets.sounds.greatsword.Scream2)

	local helmet = game.ReplicatedStorage.assets.FX.dragonSlayer.MainHelmet:Clone()
	helmet.Parent = char
	helmet.Head.Part0 = helmet
	helmet.Head.Part1 = char.Head

	local cape = game.ReplicatedStorage.assets.FX.dragonSlayer.Cape2:Clone()
	cape.Parent = char
	cape.Torso.Part0 = cape
	cape.Torso.Part1 = char.Torso

	local Shirt = char:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", char)
	local Pants = char:FindFirstChildOfClass("Pants") or Instance.new("Pants", char)

	Shirt.ShirtTemplate = ArmorShirtTemplate
	Pants.PantsTemplate = ArmorPantsTemplate

	task.spawn(function()
		for i = 1, 6 do
			if not char or hum.Health <= 10 then
				break
			end
			hum:TakeDamage(10)
			task.wait(5)
		end
		if char and char:FindFirstChild("Head") then
			char.Head.Color = oldHeadColor
		end

		if char then
			if visuals.InvisibleHair then
				for i, v in pairs(char:GetChildren()) do
					if v:IsA("Accessory") and v.AccessoryType ~= Enum.AccessoryType.Hair then
						local handle = v:FindFirstChild("Handle")
						if handle then
							handle.Transparency = 0
						end
					end
				end
			else
				for i, v in pairs(char:GetChildren()) do
					if v:IsA("Accessory") then
						local handle = v:FindFirstChild("Handle")
						if handle then
							handle.Transparency = 0
						end
					end
				end
			end
		end

		if helmet then
			helmet:Destroy()
		end
		if cape then
			cape:Destroy()
		end

		if Shirt and Shirt.Parent then
			if oldShirt ~= "" then
				Shirt.ShirtTemplate = oldShirt
			else
				Shirt:Destroy()
			end
		end
		if Pants and Pants.Parent then
			if oldPants ~= "" then
				Pants.PantsTemplate = oldPants
			else
				Pants:Destroy()
			end
		end
	end)
end

-- SkillFunctions.AirWave() - cast Air Wave, an Excalibur skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.AirWave(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	helperModule.SetSpeed(character, 0, 16)

	StateHandler.SetState(character, "CantAnything", true, 1.5)
	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://128012851889140", nil, false)
	playSound(character, ReplicatedStorage.assets.sounds.katana.katanaSheath)

	local position = root.CFrame * CFrame.new(0, -2, -8)

	local hover = ReplicatedStorage.assets.FX.skills.magicHover:Clone()
	hover.Parent = workspace.plrManager.projectiles
	hover.CFrame = position
	game.Debris:AddItem(hover, 1)

	task.wait(0.6)
	playSound(character, ReplicatedStorage.assets.sounds.magic.Fire)

	local explosion = ReplicatedStorage.assets.FX.skills.ExcSkill2:Clone()
	explosion.CFrame = position
	explosion.Parent = workspace
	for _, v in pairs(explosion.Explosion:GetChildren()) do
		v:Emit(v:GetAttribute("EmitCount"))
	end

	local hitboxParams = { SizeOrPart = 10, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(explosion)
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(player, character, hitCharsTable, alreadyHit, 12, "Sword", 15, 0.5, 1, explosion)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
		helperModule.ResetSpeed(character)
	end)
	Debris:AddItem(explosion, 1)
end

-- SkillFunctions.ElfinDance() - cast Elfin Dance, an Excalibur skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.ElfinDance(player)
	local character = player.Character

	StateHandler.SetState(character, "Dodging", true, 0.3)
	StateHandler.SetState(character, "CantAnything", true, 1.3)
	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://113290197729979", nil, false)

	applyDashEffect(character)

	local BV = Instance.new("BodyVelocity", character.HumanoidRootPart)
	BV.MaxForce = Vector3.new(25000, 0, 25000)
	BV.Velocity = character.HumanoidRootPart.CFrame.lookVector * -40
	Debris:AddItem(BV, 0.3)

	task.wait(0.5)

	applyDashEffect(character)
	local BV2 = Instance.new("BodyVelocity", character.HumanoidRootPart)
	BV2.MaxForce = Vector3.new(25000, 0, 25000)
	BV2.Velocity = character.HumanoidRootPart.CFrame.lookVector * 40
	Debris:AddItem(BV2, 0.5)

	playSound(character, ReplicatedStorage.assets.sounds.katana.katanaLunge)
	task.wait(0.5)

	local hitboxParams = { SizeOrPart = 5, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 0, -4))
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			10,
			"Sword",
			5,
			0.5,
			0,
			character.HumanoidRootPart
		)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
	end)
end

-- SkillFunctions.Morgan() - cast Morgan, the Excalibur ultimate
-- @player: the casting player
--
-- Return: nothing.
function module.Morgan(player)
	local character = player.Character
	local tool = character:FindFirstChild("Excalibur")
	StateHandler.SetState(character, "CantAnything", true, 5)

	local soundFolder = ReplicatedStorage.assets.sounds.magic.excUlt
	playSound(character, soundFolder.UltStart)

	local ExcaliburAnim =
		character.Humanoid.Animator:LoadAnimation(ReplicatedStorage.assets.animations.Ult)
	ExcaliburAnim:Play()

	local hitboxParams =
		{ SizeOrPart = Vector3.new(25, 10, 100), SpatialOption = "InBox", DebounceTime = 10 }
	local Hitbox = hitboxClass.new(hitboxParams)

	ExcaliburAnim.KeyframeReached:Connect(function(kf)
		if kf == "StartGlowing" then
			playSound(character, soundFolder.Swing)

			playSound(character, soundFolder.Rise)

			playSound(character, soundFolder.Shining)

			tool.Uchigatana.Bottom.Fire.Enabled = true
			tool.Uchigatana.Bottom.Flare.Enabled = true
			tool.Uchigatana.Bottom.Glow.Enabled = true
		elseif kf == "EnableUpDraftParticle" then
			helperModule.SetSpeed(character, 0, 16)

			local UpDraftEffect =
				game.ReplicatedStorage.assets.FX.skills.EffectsExc.UpDraftParticle:Clone()
			UpDraftEffect.Parent = workspace.plrManager.projectiles
			UpDraftEffect.CFrame = character.HumanoidRootPart.CFrame
			game.Debris:AddItem(UpDraftEffect, 9)

			local upBeam = tool.Uchigatana.Bottom.Beam55
			upBeam.Enabled = true

			game:GetService("TweenService")
				:Create(UpDraftEffect.PointLight, TweenInfo.new(1), { Brightness = 1 })
				:Play()

			for i, v in pairs(UpDraftEffect.Attachment:GetChildren()) do
				v.Enabled = true
				task.delay(4, function()
					v.Enabled = false
				end)
			end

			for i, v in pairs(UpDraftEffect.Attachment2:GetChildren()) do
				v.Enabled = true
				task.delay(4.5, function()
					v.Enabled = false
				end)
			end

			task.delay(4, function()
				upBeam.Enabled = false
				game:GetService("TweenService")
					:Create(UpDraftEffect.PointLight, TweenInfo.new(1), { Brightness = 0 })
					:Play()
				task.wait(1)
				UpDraftEffect.PointLight.Enabled = false
			end)
		elseif kf == "Hit" then
			tool.Uchigatana.Bottom.Fire.Enabled = false
			tool.Uchigatana.Bottom.Flare.Enabled = false
			tool.Uchigatana.Bottom.Glow.Enabled = false

			playSound(character, soundFolder.Explosion)

			local FloorSlash = game.ReplicatedStorage.assets.FX.skills.EffectsExc.FloorSlash:Clone()
			FloorSlash.Parent = workspace.plrManager.projectiles
			FloorSlash.CFrame = character.HumanoidRootPart.CFrame
			FloorSlash.Position = FloorSlash.Position + Vector3.new(0.5, -3, 0)
			task.delay(0.5, function()
				for _, v in pairs(FloorSlash:GetDescendants()) do
					if v:IsA("ParticleEmitter") then
						v:Emit(v:GetAttribute("EmitCount"))
					end
				end
			end)
			game.Debris:AddItem(FloorSlash, 5)

			game:GetService("TweenService")
				:Create(FloorSlash, TweenInfo.new(0.5), { Size = Vector3.new(38, 0.001, 100) })
				:Play()
			game:GetService("TweenService")
				:Create(
					FloorSlash,
					TweenInfo.new(0.5),
					{ CFrame = FloorSlash.CFrame * CFrame.new(0, 0, -50) }
				)
				:Play()
			task.delay(1, function()
				game:GetService("TweenService")
					:Create(FloorSlash.Decal, TweenInfo.new(1), { Transparency = 1 })
					:Play()
			end)

			local function createSliceVFX(positionOffset, EndPos)
				local sliceVFX = game.ReplicatedStorage.assets.FX.skills.EffectsExc.Slice:Clone()
				sliceVFX.Parent = workspace.plrManager.projectiles
				sliceVFX.CFrame = character.HumanoidRootPart.CFrame
				sliceVFX.Position = sliceVFX.Position - positionOffset
				game.Debris:AddItem(sliceVFX, 3)

				game:GetService("TweenService")
					:Create(sliceVFX, TweenInfo.new(0.5), { Size = Vector3.new(10, 15, 100) })
					:Play()
				game:GetService("TweenService")
					:Create(
						sliceVFX,
						TweenInfo.new(0.5),
						{ CFrame = character.HumanoidRootPart.CFrame * EndPos }
					)
					:Play()
				task.delay(2, function()
					game:GetService("TweenService")
						:Create(sliceVFX, TweenInfo.new(0.5), { Transparency = 1 })
						:Play()
				end)
			end

			createSliceVFX(Vector3.new(-10, 3, 0), CFrame.new(10, 5, -50))
			createSliceVFX(Vector3.new(10, 3, 0), CFrame.new(-10, 5, -50))
			Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 3, -50))
			Hitbox:Start()
			task.delay(0.3, function()
				Hitbox:Stop()
				helperModule.ResetSpeed(character)
			end)
		end
	end)

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			35,
			"Sword",
			0,
			0.5,
			2,
			character.HumanoidRootPart
		)
	end)

	task.delay(5.3, function()
		Hitbox:Destroy()
	end)
end

-- SkillFunctions.MantraPalm() - cast Mantra Palm, a Caestus skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.MantraPalm(player)
	StateHandler.SetState(player.Character, "CantAnything", true, 0.75)

	animationHandler.LoadAnim(player.Character, "Shoot", "rbxassetid://101837266978570", nil, false)

	local hitboxParams = {
		SizeOrPart = 3,
		SpatialOption = "InRadius",
		DebounceTime = 1,
		VelocityPrediction = false,
		Debug = false,
	} :: hitboxTypes.HitboxParams

	local Hitbox, connected = hitboxClass.new(hitboxParams)
	local HRP = player.Character.HumanoidRootPart
	local Glow1 = game.ReplicatedStorage.Magic.MonkGlow.Glow:Clone()

	Glow1.Parent = player.Character["Right Arm"]
	Glow1.Position = player.Character["Right Arm"].RightGripAttachment.Position

	HRP.Parent.Humanoid.JumpHeight = 0
	SpeedService.Push(HRP.Parent, "SkillSlow", 0, SpeedService.Priority.SKILL)

	animationHandler.LoadAnim(player.Character, "rbxassetid://101837266978570", nil, false)

	task.wait(0.75)

	local fireball = game:GetService("ReplicatedStorage").Magic.FireballMonk

	local fireballClone = fireball:Clone()
	fireballClone.Parent = game.Workspace
	fireballClone.Position = player.Character.HumanoidRootPart.Position
	fireballClone.Rotation = player.Character.HumanoidRootPart.Rotation
	Hitbox:WeldTo(fireballClone)
	Hitbox:Start()

	Glow1:Destroy()
	fireballClone.BodyVelocity.Velocity = (
		player.Character.HumanoidRootPart.CFrame.LookVector * 125
	)

	local hitsomeone = false

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			local humanoid = hit:WaitForChild("Humanoid")

			local isParrying = StateHandler:GetState(humanoid.Parent, "Parrying")
			local isDodging = StateHandler:GetState(humanoid.Parent, "Dodging")
			local isBlocking = StateHandler:GetState(humanoid.Parent, "Blocking")

			if humanoid then
				if StateHandler.GetState(player.Character, "Stunned") then
					return
				end

				if
					humanoid.Parent.Name ~= player.Name
					and isParrying
					and not isDodging
					and not isBlocking
				then
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
					clash2.Parent = humanoid.Parent:WaitForChild("Right Arm")
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

					-- A parry beats hyper armor: clear it so the punish stun lands.
					player.Character:SetAttribute("HyperArmor", nil)
					StateHandler.SetStun(player.Character, true, 0.5, 2)
					StateHandler.SetState(player.Character, "CantAnything", true, 0.5)
					ParryService.ResetParry(game.Players:GetPlayerFromCharacter(humanoid.Parent))
					require(game.ServerScriptService.modules.BlockResolver).OnParrySuccess(
						humanoid.Parent
					)
					if game.Players:GetPlayerFromCharacter(humanoid.Parent) then
						ReplicatedStorage.remotes.replicate:FireClient(
							game.Players:GetPlayerFromCharacter(humanoid.Parent),
							{
								Type = "Combat",
								Action = "M1",
								Func = "Parry",
								FolderName = (
									humanoid.Parent:FindFirstChildOfClass("Tool")
									and humanoid.Parent:FindFirstChildOfClass("Tool").Name
								) or "Katana",
							},
							player.Character,
							humanoid.Parent
						)
					end

					animationHandler.StopAnim(player.Character, "ALL")
					animationHandler.LoadAnim(
						player.Character,
						"Parried",
						"rbxassetid://74891530644094",
						nil,
						false
					)
				elseif
					humanoid.Parent.Name ~= player.Name
					and not isDodging
					and not isParrying
					and isBlocking
				then
					dmgCalculator.CalculateDamage(
						player.Character,
						humanoid.Parent,
						5,
						0,
						false,
						"Skill"
					)
					hitsomeone = true

					if humanoid.Parent.Humanoid.Health > 0 then
						require(game.ServerScriptService.modules.dataManager).AddWeaponXP(
							game.Players:GetPlayerFromCharacter(player.Character),
							"Fists",
							5
						)
					end

					local sound = ReplicatedStorage.assets.sounds.BlockingHit2:Clone()
					sound.Parent = humanoid.Parent
					sound:Play()
					game.Debris:AddItem(sound, 1)

					local parryE =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
							:Clone()
					local effect2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
					local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
					h1.Parent = humanoid.Parent
					game.Debris:AddItem(h1, 0.1)
					parryE.Parent = humanoid.Parent:WaitForChild("Torso")
					effect2.Parent = humanoid.Parent:WaitForChild("Torso")
					parryE.Enabled = true
					effect2.Enabled = true
					game.Debris:AddItem(parryE, 0.7)
					game.Debris:AddItem(effect2, 0.7)
				elseif
					humanoid.Parent.Name ~= player.Name
					and not isDodging
					and not isParrying
					and not isBlocking
				then
					playSound(humanoid.Parent, ReplicatedStorage.assets.sounds.magic.Explosion)
					dmgCalculator.CalculateDamage(
						player.Character,
						humanoid.Parent,
						10,
						0,
						false,
						"Skill"
					)
					hitsomeone = true

					if humanoid.Parent.Humanoid.Health > 0 then
						require(game.ServerScriptService.modules.dataManager).AddWeaponXP(
							game.Players:GetPlayerFromCharacter(player.Character),
							"Fists",
							10
						)
					end

					local kb = Instance.new("BodyVelocity")
					local ballClone = game:GetService("ReplicatedStorage").Magic.Ball:Clone()
					local swirlClone = game:GetService("ReplicatedStorage").Magic.SwirlShockwaveFire
						:Clone()
					local groundClone = game:GetService("ReplicatedStorage").Magic.DestroyedGround
						:Clone()

					kb.P = math.huge
					kb.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
					kb.Velocity = fireballClone.CFrame.LookVector * 25
					kb.Parent = humanoid.Parent.Torso

					groundClone.Parent = workspace
					ballClone.Parent = workspace
					swirlClone.Parent = workspace
					game.Debris:AddItem(ballClone, 5)
					game.Debris:AddItem(swirlClone, 5)
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

					local Settings1 = { Position = destination1 }

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

					local Tween1 = TweenService:Create(groundClone, tweenInfo1, Settings1)

					local Settings2 = { Position = destination2 }
					local Tween2 = TweenService:Create(groundClone, tweenInfo2, Settings2)

					game.Debris:AddItem(fireballClone)
					game.Debris:AddItem(kb, 0.5)
					game.Debris:AddItem(groundClone, 5)

					Tween1:Play()

					task.wait(5)

					Tween2:Play()
				elseif
					humanoid.Parent.Name ~= player.Name
					and isDodging
					and not isParrying
					and not isBlocking
				then
					local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
					sound.Parent = humanoid.Parent
					sound:Play()
					local effect = ReplicatedStorage.assets.FX.Dodged:Clone()
					effect.Parent = humanoid.Parent
					effect.Enabled = true
					game.Debris:AddItem(sound, 3)
					game.Debris:AddItem(effect, 0.3)

					if humanoid.Parent.Torso then
						for _, part in pairs(humanoid.Parent:GetChildren()) do
							if
								part:IsA("BasePart")
								and part ~= humanoid.Parent.HumanoidRootPart
							then
								local oldTrans = part.Transparency
								part.Transparency = 0.7
								task.delay(0.3, function()
									part.Transparency = oldTrans
								end)
							end
						end
					end
				end
			end
		end
	end)

	task.delay(2, function()
		game.Debris:AddItem(fireballClone)
		Hitbox:Destroy()
	end)

	HRP.Parent.Humanoid.JumpHeight = 7.2
	SpeedService.Pop(HRP.Parent, "SkillSlow")
end

-- SkillFunctions.MonasticStance() - cast Monastic Stance, the Caestus buff skill
-- @player: the casting player
--
-- Return: nothing.
function module.MonasticStance(player)
	local char = player.Character

	animationHandler.LoadAnim(char, "Activate", "rbxassetid://97964685841149", nil, false)
end

-- SkillFunctions.RisingDragon() - cast Rising Dragon, a Caestus skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.RisingDragon(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	helperModule.SetSpeed(character, 0, 16)
	StateHandler.SetState(character, "CantAnything", true, 2)

	animationHandler.LoadAnim(character, "M1", "rbxassetid://122781628053647", nil, false)

	local Glow1 = game.ReplicatedStorage.Magic.MonkGlow.Glow:Clone()
	local rLeg = character:FindFirstChild("Right Leg")

	if rLeg then
		Glow1.Parent = rLeg
		if rLeg:FindFirstChild("RightFootAttachment") then
			Glow1.Position = rLeg.RightFootAttachment.Position
		end
		Debris:AddItem(Glow1, 2)
	else
		Glow1:Destroy()
	end

	local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)

	local NewShield2 = game.ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	game.TweenService
		:Create(NewShield2, InfoTween, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()
	game.TweenService
		:Create(NewShield2, InfoTween, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()
	game.Debris:AddItem(NewShield2, 2)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)

	task.wait(0.85)

	local hitboxParams =
		{ SizeOrPart = 6, SpatialOption = "InRadius", Debug = false, DebounceTime = 0.4 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(root, CFrame.new(0, 0, -5))
	Hitbox:Start()

	local thirdhit = false

	StateHandler.SetState(character, "M1", true, 0.9)

	task.spawn(function()
		for i = 1, 3 do
			if not character or not root then
				break
			end
			local curVel = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(curVel.X, 60, curVel.Z)

			local s = ReplicatedStorage.assets.sounds.PunchSound:Clone()
			s.Parent = root
			s:Play()
			Debris:AddItem(s, 1)

			createAfterImage(character)

			if i == 3 then
				thirdhit = true
			end
			task.wait(0.4)
		end
	end)

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
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

			if humanoid and (not isPlayer or isPlayer ~= player) then
				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = character:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then
					return
				end

				local isDodging = StateHandler:GetState(targetChar, "Dodging")

				if StateHandler:GetState(character, "Stunned") then
					return
				end

				if isDodging then
					local sound = game.ReplicatedStorage.assets.sounds.Dodged:Clone()
					sound.Parent = targetChar.HumanoidRootPart
					sound:Play()
					local effect = game.ReplicatedStorage.assets.FX.Dodged:Clone()
					effect.Parent = targetChar.HumanoidRootPart
					effect.Enabled = true
					game.Debris:AddItem(sound, 3)
					game.Debris:AddItem(effect, 0.3)
					return
				end

				StateHandler.SetStun(targetChar, true, 1, 0)
				dmgCalculator.CalculateDamage(character, targetChar, 7, 0, false, "Skill")

				if targetChar.Humanoid.Health > 0 then
					require(game.ServerScriptService.modules.dataManager).AddWeaponXP(
						game.Players:GetPlayerFromCharacter(player.Character),
						"Fists",
						7
					)
				end

				local sound = game.ReplicatedStorage.assets.sounds.PunchHit:Clone()
				sound.Parent = targetHRP
				sound:Play()
				game.Debris:AddItem(sound, 2)

				local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
				highlight.Parent = humanoid.Parent
				game.Debris:AddItem(highlight, 0.1)

				local hitEff = game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
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

				task.spawn(function()
					local currentTargetVel = targetHRP.AssemblyLinearVelocity

					targetHRP.AssemblyLinearVelocity =
						Vector3.new(currentTargetVel.X, 60, currentTargetVel.Z)

					task.wait(0.4)
				end)

				if thirdhit then
					ragdollManager.Ragdoll(targetChar, 2)

					local BV = Instance.new("BodyVelocity", targetChar.HumanoidRootPart)
					BV.MaxForce = Vector3.new(25000, 0, 25000)
					BV.Velocity = targetChar.HumanoidRootPart.CFrame.lookVector * -60
					game.Debris:AddItem(BV, 0.3)
				end
			end
		end
	end)

	task.delay(1, function()
		helperModule.ResetSpeed(character)
		if Hitbox then
			Hitbox:Destroy()
		end
	end)
end

-- SkillFunctions.Gohadoken() - cast Gohadoken, a Shackles fireball
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Gohadoken(player)
	StateHandler.SetState(player.Character, "CantAnything", true, 0.75)

	local hitboxParams = {
		SizeOrPart = 8,
		SpatialOption = "InRadius",
		DebounceTime = 1,
		VelocityPrediction = false,
		Debug = false,
	} :: hitboxTypes.HitboxParams

	local Hitbox, connected = hitboxClass.new(hitboxParams)
	local HRP = player.Character.HumanoidRootPart
	local Glow1 = game.ReplicatedStorage.Magic.PurpleGlow.Glow:Clone()

	Glow1.Parent = player.Character["Right Arm"]
	Glow1.Position = player.Character["Right Arm"].RightGripAttachment.Position

	HRP.Parent.Humanoid.JumpHeight = 0
	SpeedService.Push(HRP.Parent, "SkillSlow", 0, SpeedService.Priority.SKILL)

	playSound(player.Character, game:GetService("ReplicatedStorage").assets.sounds.magic.Fire)

	animationHandler.LoadAnim(player.Character, "Shoot", "rbxassetid://97583385902594", nil, false)

	task.wait(0.75)

	local fireballClone = game:GetService("ReplicatedStorage").Magic.Fireball:Clone()
	fireballClone.Parent = game.Workspace
	fireballClone.CFrame = player.Character.HumanoidRootPart.CFrame
		* CFrame.Angles(0, math.rad(90), 0)
	Hitbox:WeldTo(fireballClone)
	Hitbox:Start()

	Glow1:Destroy()
	fireballClone.BodyVelocity.Velocity = (player.Character.HumanoidRootPart.CFrame.LookVector * 75)

	game.Debris:AddItem(fireballClone, 3)
	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
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

					Hitbox:Destroy()
					game.Debris:AddItem(fireballClone, 0.2)

					local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
						or "rbxassetid://111089735892609"
					animationHandler.LoadAnim(targetChar, "Hit", animID, nil, false)
					require(game.ServerScriptService.modules.helperModule).ApplyKnockback(
						targetChar,
						direction,
						knockbackDistance * 5,
						0.2
					)
					StateHandler.SetStun(targetChar, true, 1, 2)
					require(game.ServerScriptService.modules.ragdollManager).Ragdoll(targetChar, 1)

					dmgCalculator.CalculateDamage(
						player.Character,
						targetChar,
						12,
						extraDmg,
						false,
						"Skill"
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
					Debris:AddItem(groundClone, 7)
					Debris:AddItem(swirlClone, 7)
					Debris:AddItem(ballClone, 7)
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
					ParryService.ResetParry(game.Players:GetPlayerFromCharacter(targetChar))
					require(game.ServerScriptService.modules.BlockResolver).OnParrySuccess(
						targetChar
					)
					if game.Players:GetPlayerFromCharacter(targetChar) then
						ReplicatedStorage.remotes.replicate:FireClient(
							game.Players:GetPlayerFromCharacter(targetChar),
							{
								Type = "Combat",
								Action = "M1",
								Func = "Parry",
								FolderName = (
									targetChar:FindFirstChildOfClass("Tool")
									and targetChar:FindFirstChildOfClass("Tool").Name
								) or "Katana",
							},
							player.Character,
							targetChar
						)
					end

					animationHandler.StopAnim(player.Character, "ALL")
					animationHandler.LoadAnim(
						player.Character,
						"Parried",
						"rbxassetid://74891530644094",
						nil,
						false
					)

					Hitbox:Destroy()
					game.Debris:AddItem(fireballClone, 0.2)
				elseif
					StateHandler.GetState(targetChar, "M1")
					or StateHandler.GetState(targetChar, "M2")
				then
					Hitbox:Destroy()
					return
				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- BlockResolver checks facing and fills the guard bar. This skill keeps its own
					-- fixed chip damage on a normal block.
					local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
					local verdict = BlockResolver.Resolve({
						attacker = player.Character,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = false,
						attackClass = "Skill",
						dmg = 0,
					})

					if verdict.outcome == "Bypass" then
						animationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(0, 5)
					elseif verdict.outcome == "GuardBreak" then
						animationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(-4, 5)
					else
						BlockResolver.OnAttackerLandedHit(player.Character)
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

	task.delay(3, function()
		Hitbox:Destroy()
	end)

	HRP.Parent.Humanoid.JumpHeight = 7.2
	SpeedService.Pop(HRP.Parent, "SkillSlow")
end

-- SkillFunctions.AsuraGlide() - cast Asura Glide, a Shackles skill
-- @player: the casting player
--
-- Return: nothing.
function module.AsuraGlide(player)
	local char = player.Character
	local root = char.HumanoidRootPart

	StateHandler.SetState(char, "Dodging", true, 0.3)
	StateHandler.SetState(char, "CantAnything", true, 0.3)

	playSound(char, ReplicatedStorage.assets.sounds.OniDash)

	animationHandler.LoadAnim(char, "Glide", "rbxassetid://84494630442432", nil, false)

	task.delay(0.4, function()
		animationHandler.StopAnim(char, "Glide", "rbxassetid://84494630442432")
	end)

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(80000, 0, 80000)
	bv.Velocity = root.CFrame.lookVector * 35
	bv.Parent = root
	Debris:AddItem(bv, 0.415)

	applyDashEffect(char)
end

-- SkillFunctions.Messatsu() - cast Messatsu, the Shackles grab
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Messatsu(player)
	local character = player.Character
	local root = character.HumanoidRootPart
	local dmg = 20

	helperModule.SetSpeed(character, 0, 16)

	StateHandler.SetState(character, "CantAnything", true, 4)
	StateHandler.SetState(character, "Dodging", true, 1.8)

	animationHandler.LoadAnim(character, "Windup", "rbxassetid://108425878268854", nil, false)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)
	local NewShield2 = ReplicatedStorage.assets.FX.danger:Clone()
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = character
	NewShield2.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = character.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	TweenService:Create(
		NewShield2,
		TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
		{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
	):Play()
	TweenService:Create(
		NewShield2,
		TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
		{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
	):Play()
	game.Debris:AddItem(NewShield2, 1.5)

	task.wait(1.5)

	playSound(character, ReplicatedStorage.assets.sounds.OniDash)

	animationHandler.LoadAnim(character, "Dash", "rbxassetid://89337388294441", nil, false)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(80000, 0, 80000)
	bv.Velocity = root.CFrame.LookVector * 35
	bv.Parent = root
	Debris:AddItem(bv, 0.4)

	local hitboxParams =
		{ SizeOrPart = Vector3.new(6, 6, 6), SpatialOption = "InBox", DebounceTime = 0.5 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(root, CFrame.new(1, -1, -4))
	Hitbox:Start()

	local hitSomeone = false
	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
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
				local attackerHRP = character:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then
					return
				end

				if StateHandler.GetState(character, "Stunned") then
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

				hitSomeone = true

				Hitbox:Stop()

				animationHandler.StopAnim(character, "ALL")
				animationHandler.StopAnim(targetChar, "ALL")

				helperModule.SetSpeed(character, 0, 16)
				helperModule.SetSpeed(targetChar, 0, 16)

				local ff = Instance.new("ForceField")
				ff.Parent = character
				ff.Visible = false
				local ff2 = Instance.new("ForceField")
				ff2.Parent = targetChar
				ff2.Visible = false

				game.Debris:AddItem(ff, 2)
				game.Debris:AddItem(ff2, 1.8)

				humanoid.AutoRotate = false
				character.Humanoid.AutoRotate = false

				-- Remove velocity and rotation movers, so the grab holds the attacker still.
				for _, v in pairs(character.HumanoidRootPart:GetChildren()) do
					if
						v:IsA("BodyVelocity")
						or v:IsA("BodyGyro")
						or v:IsA("AlignOrientation")
						or v:IsA("BodyAngularVelocity")
					then
						v:Destroy()
					end
				end

				for i, v in pairs(character:GetChildren()) do
					if v:IsA("BasePart") then
						v.CanCollide = false
					end
				end
				for i, v in pairs(targetChar:GetChildren()) do
					if v:IsA("BasePart") then
						v.CanCollide = false
					end
				end

				humanoid.Parent.HumanoidRootPart.CFrame = character.HumanoidRootPart.CFrame

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = character.HumanoidRootPart
				weld.Parent = character
				weld.Part1 = targetChar.HumanoidRootPart

				StateHandler.SetStun(targetChar, true, 2)
				StateHandler.SetState(targetChar, "CantAnything", true, 2)

				animationHandler.LoadAnim(
					character,
					"UltHitAttacker",
					"rbxassetid://101513335589823",
					nil,
					false
				)
				animationHandler.LoadAnim(
					targetChar,
					"UltHitDefender",
					"rbxassetid://73915210544765",
					nil,
					false
				)

				local Glow1 = game.ReplicatedStorage.Magic.PurpleGlow.Glow:Clone()

				Glow1.Parent = character["Left Arm"]
				Glow1.Position = character["Left Arm"].LeftGripAttachment.Position

				game.Debris:AddItem(Glow1, 2.15)

				playSound(character, ReplicatedStorage.assets.sounds.PunchHit)

				local voiceLinesFolder = ReplicatedStorage.assets.sounds.voiceLines
				local allSounds = voiceLinesFolder:GetChildren()

				if #allSounds > 0 then
					local randomSound = allSounds[math.random(1, #allSounds)]
					local soundClone = randomSound:Clone()
					soundClone.Parent = character.HumanoidRootPart
					soundClone:Play()
					game.Debris:AddItem(soundClone, soundClone.TimeLength)
				end

				task.wait(2)

				dmgCalculator.CalculateDamage(character, targetChar, 40, 0, true, "Skill")

				playSound(character, ReplicatedStorage.assets.sounds.DeadSound)

				if weld then
					weld:Destroy()
					weld = nil
				end
				for i, v in pairs(character:GetChildren()) do
					if v:IsA("Part") then
						v.CanCollide = true
					end
				end
				for i, v in pairs(targetChar:GetChildren()) do
					if v:IsA("Part") then
						v.CanCollide = true
					end
				end

				humanoid.AutoRotate = true
				character.Humanoid.AutoRotate = true

				ragdollManager.Ragdoll(targetChar, 2)

				local BV = Instance.new("BodyVelocity", targetChar.HumanoidRootPart)
				BV.MaxForce = Vector3.new(25000, 0, 25000)
				BV.Velocity = targetChar.HumanoidRootPart.CFrame.lookVector * 50
				game.Debris:AddItem(BV, 0.3)

				local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
				highlight.Parent = humanoid.Parent
				game.Debris:AddItem(highlight, 0.1)

				if targetChar.Humanoid.Health > 0 then
					require(game.ServerScriptService.modules.dataManager).AddWeaponXP(
						game.Players:GetPlayerFromCharacter(player.Character),
						"Fists",
						40
					)
				end

				local hitEff = game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
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

				helperModule.ResetSpeed(character)
				helperModule.ResetSpeed(targetChar)

				alreadyHit[targetChar] = true

				hitSomeone = false
			end
		end
	end)

	task.delay(0.4, function()
		Hitbox:Destroy()
		if not hitSomeone then
			helperModule.ResetSpeed(character)
		end
	end)
end

-- SkillFunctions.Zanshin() - cast Zanshin, a Vermillion skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Zanshin(player)
	local character = player.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChild("Humanoid")
	StateHandler.SetState(character, "CantAnything", true, 1)
	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://98387922517299", nil, false)
	playSound(character, ReplicatedStorage.assets.sounds.vermillion.UltStart)

	task.wait(0.2)
	hum.AutoRotate = false
	rootPart.Anchored = true
	helperModule.SetSpeed(character, 2, 16)
	task.wait(0.4)

	playSound(character, ReplicatedStorage.assets.sounds.vermillion.UltSlash)

	local vfxPart = ReplicatedStorage.assets.FX.skills.judgementCutVFX:Clone()
	vfxPart.Parent = workspace
	vfxPart.CFrame = rootPart.CFrame * CFrame.new(0, 0, -9)
	vfxPart.Attachment.Slashes:Emit(15)
	game.Debris:AddItem(vfxPart, 10)

	local hitboxParams = { SizeOrPart = 8, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(rootPart, CFrame.new(0, 0, -9))
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			10,
			"Katana",
			5,
			0.5,
			1,
			character.HumanoidRootPart,
			"LifeRegen"
		)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
		helperModule.ResetSpeed(character)
		hum.AutoRotate = true
		rootPart.Anchored = false
	end)
end

-- SkillFunctions.Kurai() - cast Kurai, the Vermillion teleport dash
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Kurai(player)
	local char = player.Character
	local root = char.HumanoidRootPart

	StateHandler.SetState(char, "Dodging", true, 0.5)
	StateHandler.SetState(char, "CantAnything", true, 0.5)

	animationHandler.LoadAnim(char, "LeanBack", "rbxassetid://139345216330283", nil, false)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local isAirborne = (
		char.Humanoid:GetState() == Enum.HumanoidStateType.Jumping
		or char.Humanoid:GetState() == Enum.HumanoidStateType.Freefall
	)

	applyDashEffect(char)

	playSound(char, ReplicatedStorage.assets.sounds.vermillion.dash)

	local BV = Instance.new("BodyVelocity", root)
	BV.MaxForce = Vector3.new(25000, 0, 25000)
	BV.Velocity = root.CFrame.lookVector * -40
	Debris:AddItem(BV, 0.3)

	-- How far forward to teleport, and how high when starting on the ground.
	local TELEPORT_DISTANCE = 20
	local AIR_HEIGHT = 10

	local forwardDir = root.CFrame.LookVector
	local targetPosition

	if not isAirborne then
		targetPosition = root.Position
			+ (forwardDir * TELEPORT_DISTANCE)
			+ Vector3.new(0, AIR_HEIGHT, 0)
	else
		local airForwardPos = root.Position + (forwardDir * TELEPORT_DISTANCE)

		local floorRay = workspace:Raycast(airForwardPos, Vector3.new(0, -100, 0), rayParams)

		if floorRay then
			targetPosition = floorRay.Position + Vector3.new(0, char.Humanoid.HipHeight + 1, 0)
		else
			targetPosition = airForwardPos
		end

		local eff = game.ReplicatedStorage.assets.dashEff2:Clone()
		for _, effect in pairs(eff:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				effect.Parent = char.Torso
				effect.EmissionDirection = Enum.NormalId.Front
				effect:Emit(9)
			elseif effect:IsA("Attachment") then
				effect.Parent = char.Torso
				effect:FindFirstChildWhichIsA("ParticleEmitter").EmissionDirection =
					Enum.NormalId.Front
				effect:FindFirstChildWhichIsA("ParticleEmitter"):Emit(9)
			end
		end
		game.Debris:AddItem(eff, 2)
	end

	task.wait(0.4)

	playSound(char, ReplicatedStorage.assets.sounds.katana.katanaLunge)

	root.CFrame = CFrame.new(targetPosition, targetPosition + forwardDir)

	applyDashEffect(char)

	local BV2 = Instance.new("BodyVelocity", root)
	BV2.MaxForce = Vector3.new(25000, 0, 25000)
	BV2.Velocity = root.CFrame.lookVector * 30
	Debris:AddItem(BV2, 0.3)

	animationHandler.LoadAnim(char, "LeanForward", "rbxassetid://77971444416399", nil, false)
end

-- SkillFunctions.Kirikizu() - cast Kirikizu, a Vermillion skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Kirikizu(player)
	local character = player.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	rootPart.Anchored = true

	StateHandler.SetState(character, "CantAnything", true, 1)
	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://89034380090419", nil, false)

	playSound(character, ReplicatedStorage.assets.sounds.DANGER)

	local NewShield2 = game.ReplicatedStorage.assets.FX.danger:Clone()
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
	game.Debris:AddItem(NewShield2, 2)

	task.wait(1)

	playSound(character, ReplicatedStorage.assets.sounds.vermillion.UltSlash)

	local vfxPart = ReplicatedStorage.assets.FX.skills.judgementCutEndVFX:Clone()
	vfxPart.Parent = workspace
	vfxPart.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 2, 0)
	for _, v in pairs(vfxPart:GetDescendants()) do
		if v:IsA("ParticleEmitter") and v:GetAttribute("EmitCount") then
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end

	game.Debris:AddItem(vfxPart, 10)

	local hitboxParams = { SizeOrPart = 12, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 2, 0))
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			15,
			"Katana",
			0,
			0.5,
			1,
			character.HumanoidRootPart,
			"LifeRegen"
		)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
		rootPart.Anchored = false
	end)
end

-- SkillFunctions.HiddenDaggers() - cast Hidden Daggers, a Tanto throw of three daggers
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.HiddenDaggers(player)
	local char = player.Character
	local root = char.HumanoidRootPart

	local DAMAGE = 7
	local THROW_SPEED = 250
	local WINDUP_TIME = 0.4

	StateHandler.SetState(char, "CantAnything", true, WINDUP_TIME + 0.2)
	helperModule.SetSpeed(char, 2, 16)

	animationHandler.LoadAnim(char, "DaggerThrow", "rbxassetid://116490680994705", nil, false)

	task.wait(WINDUP_TIME)

	StateHandler.SetState(char, "M1", true, 0.5)
	helperModule.ResetSpeed(char)

	playSound(char, ReplicatedStorage.assets.sounds.dagger.daggerLunge)

	-- Throw 3 daggers in a fan: -30, 0, and +30 degrees.
	local RunService = game:GetService("RunService")

	-- Spawn distance ahead of the torso. It is small, so point-blank targets still get hit.
	local SPAWN_FORWARD = 0.5
	-- Degrees between the center dagger and each side dagger.
	local FAN_ANGLE = 30
	-- The spherecast radius.
	local HITBOX_RADIUS = 2.0
	-- Seconds before a dagger despawns.
	local LIFETIME = 1.5
	-- Seconds a dagger stays stuck in a wall.
	local WALL_STICK = 1

	for i = -1, 1 do
		local projectile = game.ServerStorage.Extras.ThrowDagger:Clone()

		projectile.Transparency = 0.5
		projectile.Color = Color3.new(0, 0, 0)
		-- A Heartbeat loop moves the dagger and a spherecast finds hits, so the dagger is
		-- anchored and does not use Touched.
		projectile.Anchored = true
		projectile.CanCollide = false
		projectile.CanTouch = false

		local originCF = root.CFrame
			* CFrame.new(0, 0, -SPAWN_FORWARD)
			* CFrame.Angles(0, math.rad(i * FAN_ANGLE), 0)
		projectile.CFrame = originCF
		projectile.Parent = workspace.plrManager.projectiles

		if projectile:FindFirstChild("TestTrail") then
			projectile.TestTrail.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
			projectile.TestTrail.Enabled = true
		end

		local travelDir = originCF.LookVector
		local position = originCF.Position

		local hitDebounce = {}
		local alive = true
		local elapsed = 0

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { char, workspace.plrManager.projectiles }
		rayParams.IgnoreWater = true

		local function stopInWall(hitPos)
			alive = false
			projectile.Position = hitPos
			projectile.Transparency = 1
			if projectile:FindFirstChild("TestTrail") then
				projectile.TestTrail.Enabled = false
			end
			if projectile:FindFirstChild("ShadowEmitter") then
				projectile.ShadowEmitter:Emit(100)
			end
			Debris:AddItem(projectile, WALL_STICK)
		end

		-- Returns true if the hit consumes the dagger.
		local function onHitCharacter(enemyChar)
			if hitDebounce[enemyChar] then
				return false
			end
			hitDebounce[enemyChar] = true

			if StateHandler.GetState(enemyChar, "Dodging") then
				local sound = ReplicatedStorage.assets.sounds.Dodged:Clone()
				sound.Parent = enemyChar.HumanoidRootPart
				sound:Play()
				game.Debris:AddItem(sound, 3)
				-- A dodge lets the dagger fly on.
				return false
			end

			local function applyDamage(extraDmg)
				dmgCalculator.CalculateDamage(char, enemyChar, DAMAGE, extraDmg, false, "Skill")
				StateHandler.SetStun(enemyChar, true, 0.5, 8)

				local direction = (enemyChar.HumanoidRootPart.Position - root.Position).Unit
				helperModule.ApplyKnockback(enemyChar, direction, 10, 0.2)

				local animID = (math.random(1, 100) < 50) and "rbxassetid://96311777205911"
					or "rbxassetid://111089735892609"
				animationHandler.LoadAnim(enemyChar, "Hit", animID, nil, false)

				if enemyChar.Humanoid.Health > 0 then
					dataManager.AddWeaponXP(player, "Dagger", DAMAGE + extraDmg)
				end

				playSound(enemyChar, ReplicatedStorage.assets.sounds.PunchHit)

				local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
				highlight.Parent = enemyChar
				game.Debris:AddItem(highlight, 0.1)
			end

			if StateHandler.GetState(enemyChar, "Parrying") then
				local parryE = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
					:Clone()
				local effect2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit
					:Clone()
				local clash = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
					:Clone()
				local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
				h1.Parent = char
				game.Debris:AddItem(h1, 0.1)
				parryE.Parent = char:WaitForChild("Torso")
				effect2.Parent = char:WaitForChild("Torso")
				clash.Parent = char:WaitForChild("Right Arm")

				local clash2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
					:Clone()
				clash2.Parent = enemyChar:WaitForChild("Right Arm")
				clash2:Emit(30)
				game.Debris:AddItem(clash2, 0.7)

				parryE.Enabled = true
				effect2.Enabled = true
				clash:Emit(30)
				game.Debris:AddItem(clash, 0.7)
				game.Debris:AddItem(parryE, 0.7)
				game.Debris:AddItem(effect2, 0.7)

				-- A parry beats hyper armor: clear it so the punish stun lands.
				char:SetAttribute("HyperArmor", nil)
				StateHandler.SetStun(char, true, 0.5, 2)
				StateHandler.SetState(char, "CantAnything", true, 0.5)
				ParryService.ResetParry(game.Players:GetPlayerFromCharacter(enemyChar))
				require(game.ServerScriptService.modules.BlockResolver).OnParrySuccess(enemyChar)
				if game.Players:GetPlayerFromCharacter(enemyChar) then
					ReplicatedStorage.remotes.replicate:FireClient(
						game.Players:GetPlayerFromCharacter(enemyChar),
						{
							Type = "Combat",
							Action = "M1",
							Func = "Parry",
							FolderName = (
								enemyChar:FindFirstChildOfClass("Tool")
								and enemyChar:FindFirstChildOfClass("Tool").Name
							) or "Katana",
						},
						char,
						enemyChar
					)
				end

				local targetPlrData = game.Players:GetPlayerFromCharacter(enemyChar).PlayerStats
				if targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
					targetPlrData.Mana.Value += 8
				end

				animationHandler.StopAnim(char, "ALL")
				animationHandler.LoadAnim(
					char,
					"Parried",
					"rbxassetid://116383775729821",
					nil,
					false
				)
				return true
			elseif StateHandler.GetState(enemyChar, "Blocking") then
				-- BlockResolver checks facing and fills the guard bar. The dagger keeps its own
				-- fixed chip damage.
				local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
				local verdict = BlockResolver.Resolve({
					attacker = char,
					target = enemyChar,
					attackerPos = root.Position,
					targetHRP = enemyChar.HumanoidRootPart,
					guardbreak = false,
					attackClass = "Skill",
					dmg = 0,
				})

				if verdict.outcome == "Bypass" then
					applyDamage(0)
					return true
				elseif verdict.outcome == "GuardBreak" then
					applyDamage(-3)
					return true
				else
					BlockResolver.OnAttackerLandedHit(char)
					local sound = ReplicatedStorage.assets.sounds.BlockingHit2:Clone()
					sound.Parent = enemyChar
					sound:Play()
					game.Debris:AddItem(sound, 1)

					local parryE =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
							:Clone()
					local effect2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
					local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
					h1.Parent = enemyChar
					game.Debris:AddItem(h1, 0.1)
					parryE.Parent = enemyChar:FindFirstChild("Torso")
					effect2.Parent = enemyChar:FindFirstChild("Torso")
					parryE.Enabled = true
					effect2.Enabled = true
					game.Debris:AddItem(parryE, 0.7)
					game.Debris:AddItem(effect2, 0.7)

					applyDamage(-3)
					return true
				end
			else
				applyDamage(0)
				return true
			end
		end

		-- Move the dagger each frame and spherecast the segment it crosses, so it never
		-- passes through a target.
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			if not alive or not projectile.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end

			elapsed += dt
			if elapsed >= LIFETIME then
				alive = false
				conn:Disconnect()
				projectile:Destroy()
				return
			end

			local step = THROW_SPEED * dt
			local result =
				workspace:Spherecast(position, HITBOX_RADIUS, travelDir * step, rayParams)

			if result then
				local hitPart = result.Instance
				local model = hitPart:FindFirstAncestorOfClass("Model")
				local enemyHum = model and model:FindFirstChildOfClass("Humanoid")

				if enemyHum and model ~= char then
					local consumed = onHitCharacter(model)
					if consumed then
						alive = false
						conn:Disconnect()
						task.delay(0.05, function()
							if projectile.Parent then
								projectile:Destroy()
							end
						end)
						return
					end
					-- A dodge does not consume the dagger, so it moves on from the hit point.
					position = result.Position
					projectile.CFrame = CFrame.lookAt(position, position + travelDir)
				else
					-- A wall hit: stick at the impact point.
					conn:Disconnect()
					stopInWall(result.Position)
				end
			else
				position = position + travelDir * step
				projectile.CFrame = CFrame.lookAt(position, position + travelDir)
			end
		end)
	end
end

-- SkillFunctions.YingYangSpiral() - cast Ying Yang Spiral, a Tanto skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.YingYangSpiral(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	StateHandler.SetState(character, "Dodging", true, 0.5)
	StateHandler.SetState(character, "CantAnything", true, 0.5)

	animationHandler.LoadAnim(character, "SpecialAtk", "rbxassetid://115983114799315", nil, false)

	task.wait(0.1)

	SpeedService.Push(character, "SkillSlow", 2, SpeedService.Priority.SKILL)

	task.wait(0.4)

	SpeedService.Pop(character, "SkillSlow")

	local part = game:GetService("ReplicatedStorage").assets.FX.skills.tanto.ryougiDashPart:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.Parent = workspace
	part.CFrame = root.CFrame * CFrame.Angles(0, math.rad(90), 0)
	game.Debris:AddItem(part, 5)
	for _, v in pairs(part:GetChildren()) do
		if v:IsA("ParticleEmitter") and v:GetAttribute("EmitCount") then
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end

	applyDashEffect(character)
	local BV2 = Instance.new("BodyVelocity", character.HumanoidRootPart)
	BV2.MaxForce = Vector3.new(25000, 0, 25000)
	BV2.Velocity = character.HumanoidRootPart.CFrame.lookVector * 60
	Debris:AddItem(BV2, 0.3)

	playSound(character, ReplicatedStorage.assets.sounds.katana.katanaLunge)

	local hitboxParams =
		{ SizeOrPart = 10, Debug = false, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 0, -4))
	Hitbox:Start()

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			10,
			"Dagger",
			5,
			0.5,
			0,
			character.HumanoidRootPart
		)
	end)

	task.delay(0.3, function()
		Hitbox:Destroy()
	end)
end

-- SkillFunctions.MysticEyes() - cast Mystic Eyes, the Tanto buff skill
-- @player: the casting player
--
-- Return: nothing.
function module.MysticEyes(player)
	local character = player.Character
	if not character then
		return
	end
	-- Only the animation. BuffService owns the buff state and FX, so the buff works with
	-- every weapon of the class.
	animationHandler.LoadAnim(character, "Activate", "rbxassetid://97964685841149", nil, false)
end

-- SkillFunctions.DownwardCleave() - cast Downward Cleave, a Guandao skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.DownwardCleave(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	animationHandler.LoadAnim(character, "Activate", "rbxassetid://124210375406879", nil, false)

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

	task.wait(0.1)

	SpeedService.Push(character, "SkillSlow", 2, SpeedService.Priority.SKILL)

	task.wait(0.6)

	SpeedService.Pop(character, "SkillSlow")

	applyDashEffect(character)
	local BV2 = Instance.new("BodyVelocity", character.HumanoidRootPart)
	BV2.MaxForce = Vector3.new(25000, 0, 25000)
	BV2.Velocity = character.HumanoidRootPart.CFrame.lookVector * 30
	Debris:AddItem(BV2, 0.3)

	playSound(character, ReplicatedStorage.assets.sounds.katana.katanaLunge)

	local hitboxParams =
		{ SizeOrPart = 7, Debug = false, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 0, -4))
	Hitbox:Start()

	playSound(character, game.ReplicatedStorage.assets.sounds.skills.GroundImpact)

	local startPos = root.Position + (root.CFrame.LookVector * 12)
	local direction = Vector3.new(0, -15, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(startPos, direction, params)

	if result then
		local slamEff = ReplicatedStorage.assets.FX.guandao.guandaogroundSlam:Clone()
		slamEff.Parent = workspace
		slamEff.Position = result.Position + Vector3.new(0, 0.15, 0)
		for _, v in pairs(slamEff.floor:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				v:Emit(5)
			end
		end
		Debris:AddItem(slamEff, 3)
	end

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			20,
			"Sword",
			5,
			0.5,
			0,
			character.HumanoidRootPart
		)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
	end)
end

-- SkillFunctions.Tianshi() - cast Tianshi, a Guandao skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Tianshi(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	StateHandler.SetState(character, "CantAnything", true, 2)
	StateHandler.SetState(character, "Sliding", true, 2)

	animationHandler.LoadAnim(character, "JudgementCut", "rbxassetid://100711039492817", nil, false)
	playSound(character, ReplicatedStorage.assets.sounds.greatsword.woosh)

	task.delay(0.7, function()
		if not character or not root then
			return
		end
		local airborneVelocity = Instance.new("BodyVelocity")
		airborneVelocity.Parent = root
		airborneVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
		airborneVelocity.Velocity = (root.CFrame.LookVector * 60) + Vector3.new(0, 25, 0)
		Debris:AddItem(airborneVelocity, 0.4)

		applyDashEffect(character)
		task.delay(0.5, function()
			applyDashEffect(character)
		end)
	end)

	task.wait(1.5)
	playSound(character, ReplicatedStorage.assets.sounds.greatsword.GroundImpact)

	local hitboxParams = { SizeOrPart = 10, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(root, CFrame.new(0, 0, -4))
	Hitbox:Start()

	local startPos = root.Position + (root.CFrame.LookVector * 12)
	local direction = Vector3.new(0, -50, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(startPos, direction, params)

	if result then
		local slamEff = ReplicatedStorage.assets.FX.guandao.GuandaoS2:Clone()
		slamEff.Parent = workspace
		slamEff.Position = result.Position + Vector3.new(0, 1, 0)
		task.delay(0.3, function()
			for _, v in pairs(slamEff.Main:GetChildren()) do
				v.Enabled = false
			end
		end)
		Debris:AddItem(slamEff, 1)
	end

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(player, character, hitCharsTable, alreadyHit, 25, "Sword", 15, 0.5, 0, root)
	end)

	task.delay(0.3, function()
		Hitbox:Destroy()
		helperModule.ResetSpeed(character)
	end)
end

-- SkillFunctions.Dao() - cast Dao, a Guandao skill
-- @player: the casting player
--
-- Return: nothing. Yields during the cast.
function module.Dao(player)
	local character = player.Character
	local root = character.HumanoidRootPart

	animationHandler.LoadAnim(character, "Activate", "rbxassetid://72337130586284", nil, false)

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

	task.wait(0.1)

	SpeedService.Push(character, "SkillSlow", 2, SpeedService.Priority.SKILL)

	task.wait(0.9)

	SpeedService.Pop(character, "SkillSlow")

	applyDashEffect(character)
	local BV2 = Instance.new("BodyVelocity", character.HumanoidRootPart)
	BV2.MaxForce = Vector3.new(25000, 0, 25000)
	BV2.Velocity = character.HumanoidRootPart.CFrame.lookVector * 30
	Debris:AddItem(BV2, 0.3)

	playSound(character, ReplicatedStorage.assets.sounds.katana.katanaLunge)

	local hitboxParams =
		{ SizeOrPart = 7, Debug = false, SpatialOption = "InRadius", DebounceTime = 1 }
	local Hitbox = hitboxClass.new(hitboxParams)
	Hitbox:WeldTo(character.HumanoidRootPart, CFrame.new(0, 0, -4))
	Hitbox:Start()

	playSound(character, game.ReplicatedStorage.assets.sounds.skills.GroundImpact)

	local part = ReplicatedStorage.assets.FX.guandao.GuandaoS3:Clone()
	part.Parent = workspace
	part.CFrame = root.CFrame
	for _, v in pairs(part.Explosion:GetChildren()) do
		if v:IsA("ParticleEmitter") and v:GetAttribute("EmitCount") then
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end
	Debris:AddItem(part, 2)

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		processHit(
			player,
			character,
			hitCharsTable,
			alreadyHit,
			30,
			"Sword",
			5,
			0.5,
			0,
			character.HumanoidRootPart
		)
	end)

	task.delay(0.2, function()
		Hitbox:Destroy()
	end)
end

return module
