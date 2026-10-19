-- SPDX-License-Identifier: MIT
--
-- Tanto E. A two-dash multihit with its own hit resolution instead of CombatCore.RunE.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicateRemote = RP.remotes.replicate

local Helper = require(SSS.modules.helperModule)
local StateHandler = require(RP.modules.stateHandler)
local ParryService = require(SSS.modules.parryService)
local AnimationHandler = require(RP.modules.animationHandler)
local HitboxClass = require(RP.modules.hitboxClass)
local HitboxTypes = require(RP.modules.hitboxClass.Types)
local ragdollManager = require(SSS.modules.ragdollManager)
local DashConfig = require(RP.modules.DashConfig)

local danger = RP.assets.FX.danger
local TweenService = game:GetService("TweenService")

local hitboxParams = {
	SizeOrPart = Vector3.new(5, 4, 5),
	SpatialOption = "InBox",
	Debug = false,
	DebounceTime = 0.5,
} :: HitboxTypes.HitboxParams

local DataManager = require(game.ServerScriptService.modules.dataManager)

local dmg = 5
local guardBreak = false
local windupDelay = 0.5
local hitboxDuration = 1.1
local postAttackCooldown = 3

local v = {}
local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)

local function rightSwing(char)
	local attachment = game.ReplicatedStorage.assets.FX.slashFX.SlashFXLeft:Clone()
	attachment.CFrame = char.HumanoidRootPart.CFrame
	attachment.Parent = char.HumanoidRootPart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachment
	weld.Part1 = char.HumanoidRootPart
	weld.Parent = attachment
	for _, v in pairs(attachment:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 10)
		end
	end
	game.Debris:AddItem(attachment, 2)
end

local function leftSwing(char)
	local attachment = game.ReplicatedStorage.assets.FX.slashFX.SlashFXRight:Clone()
	attachment.CFrame = char.HumanoidRootPart.CFrame
	attachment.Parent = char.HumanoidRootPart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachment
	weld.Part1 = char.HumanoidRootPart
	weld.Parent = attachment
	for _, v in pairs(attachment:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 10)
		end
	end
	game.Debris:AddItem(attachment, 2)
end

-- E.ServerCheck() - run the Tanto E
-- @plr: the player who pressed E
--
-- Return: nothing. Yields until the second dash ends.
function module.ServerCheck(plr)
	local function getEquippedTool()
		local currentCharacter = plr.Character
		if not currentCharacter then
			return nil
		end
		local tool = currentCharacter:FindFirstChildOfClass("Tool")
		if tool and tool.Parent == currentCharacter then
			return tool.Name
		end
		return nil
	end

	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end
	local decision
	local isBusy = false

	if isBusy then
		decision = "Declined"
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "E",
			Func = "ServerResponse",
			FolderName = getEquippedTool(),
		}, plr, decision)
		return
	end

	local function dashEff()
		for _, v in pairs(plr.Character:GetChildren()) do
			if v:IsA("BasePart") then
				if v.Transparency ~= 1 then
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
					local tweenservice = game:GetService("TweenService")
					local goal = {}
					goal.Transparency = 1
					local tweeninfo = TweenInfo.new(0.6)
					local tween = tweenservice:Create(part, tweeninfo, goal)
					tween:Play()
					game.Debris:AddItem(part, 0.5)
				end
			end
		end
	end

	StateHandler.SetState(char, "CantAnything", true, 1)

	-- A stun or a down removes the dash mover and stops the swing animation.
	local stopWatch = StateHandler.WatchInterrupt(char, 3, function()
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, mover in ipairs(hrp:GetChildren()) do
				if mover:IsA("BodyVelocity") or mover:IsA("LinearVelocity") then
					mover:Destroy()
				end
			end
		end
		AnimationHandler.StopAnim(char, "ALL")
	end)

	task.delay(0.3, function()
		-- The Tanto E is two dashes: a short step here and a longer dash after the first
		-- hit window. DashConfig exempts both, because they are part of the move.
		local stepSpeed, stepLife = DashConfig.Get("TantoE1")
		if stepSpeed then
			local BV = Instance.new("BodyVelocity", char.HumanoidRootPart)
			BV.MaxForce = Vector3.new(25000, 0, 25000)
			BV.Velocity = char.HumanoidRootPart.CFrame.lookVector * stepSpeed
			game.Debris:AddItem(BV, stepLife)
		end
		dashEff()
	end)

	Helper.SetSpeed(char, 2, 16)

	task.delay(2, function()
		Helper.ResetSpeed(char)
	end)

	task.delay(0.25, function()
		ReplicateRemote:FireAllClients({
			Type = "Combat",
			Action = "E",
			Func = "Swing",
			FolderName = getEquippedTool(),
		}, char)
	end)

	task.wait(windupDelay)

	-- A stun or a down during the windup cancels the attack before the hitbox.
	if StateHandler.IsInterrupted(char) then
		stopWatch()
		Helper.ResetSpeed(char)
		if v[plr] then
			v[plr]:Destroy()
			v[plr] = nil
		end
		AnimationHandler.StopAnim(char, "ALL")
		return
	end

	stopWatch()

	leftSwing(char)

	local humrp = char.HumanoidRootPart
	local Hitbox, connected = HitboxClass.new(hitboxParams)

	Hitbox:WeldTo(humrp, CFrame.new(1, -1, -4))

	local alreadyHit = {}

	-- Connect before Start, so the first hit is not missed.
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

			local isPlayer = Players:GetPlayerFromCharacter(targetChar)

			if humanoid and (not isPlayer or isPlayer ~= plr) then
				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = char:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then
					return
				end

				if StateHandler.GetState(char, "Stunned") then
					continue
				end

				if StateHandler.GetState(targetChar, "Dodging") then
					local sound = RP.assets.sounds.Dodged:Clone()
					sound.Parent = targetHRP
					sound:Play()
					local effect = RP.assets.FX.Dodged:Clone()
					effect.Parent = targetHRP
					effect.Enabled = true
					game.Debris:AddItem(sound, 3)
					game.Debris:AddItem(effect, 0.3)
					return
				end

				local function doAttack(extraDmg, knockbackDistance)
					local direction = (targetHRP.Position - attackerHRP.Position).Unit
					Helper.ApplyKnockback(targetChar, direction, knockbackDistance, 0.2)
					-- The E hitstun pins WalkSpeed, so the victim cannot walk out of the combo.
					StateHandler.SetStun(targetChar, true, 0.8, 2)
					local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
					dmgModule.CalculateDamage(char, targetChar, dmg, extraDmg, false, "Weapon")

					if targetChar.Humanoid.Health > 0 and targetChar.Humanoid.MaxHealth < 10000 then
						DataManager.AddWeaponXP(
							game.Players:GetPlayerFromCharacter(char),
							"Dagger",
							dmg + extraDmg
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
				end

				if StateHandler.GetState(targetChar, "Parrying") then
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = "E",
						Func = "Parry",
						FolderName = getEquippedTool(),
					}, char, targetChar)

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
					h1.Parent = char
					game.Debris:AddItem(h1, 0.1)
					parryE.Parent = char:WaitForChild("Torso")
					effect2.Parent = char:WaitForChild("Torso")
					clash.Parent = char:WaitForChild("Right Arm")
					parryE.Enabled = true
					effect2.Enabled = true
					clash:Emit(30)
					game.Debris:AddItem(clash, 0.7)
					game.Debris:AddItem(parryE, 0.7)
					game.Debris:AddItem(effect2, 0.7)

					StateHandler.SetStun(char, true, 0.5, 2)
					StateHandler.SetState(char, "CantAnything", true, 0.5)
					ParryService.ResetParry(game.Players:GetPlayerFromCharacter(targetChar))
					require(game.ServerScriptService.modules.BlockResolver).OnParrySuccess(
						targetChar
					)

					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if
						targetPlrData
						and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8
					then
						targetPlrData.Mana.Value += 8
					end
					AnimationHandler.StopAnim(char, "ALL")
					AnimationHandler.LoadAnim(
						char,
						"Parried",
						"rbxassetid://125236478541602",
						nil,
						false
					)
				elseif
					StateHandler.GetState(targetChar, "M1")
					or StateHandler.GetState(targetChar, "E")
				then
					Hitbox:Destroy()
				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- BlockResolver applies the guard bar and returns the verdict.
					local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
					local verdict = BlockResolver.Resolve({
						attacker = char,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = guardBreak,
						attackClass = "E",
						dmg = dmg,
					})
					local extra = verdict.chipDamage - dmg

					if verdict.outcome == "GuardBreak" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						if verdict.broke then
							doAttack(extra, verdict.knockback)
						else
							local dmgModule =
								require(game.ServerScriptService.modules.damageCalculator)
							dmgModule.CalculateDamage(
								char,
								targetChar,
								dmg,
								verdict.knockback,
								false,
								"Weapon"
							)
						end
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "E",
							Func = "GB",
							FolderName = getEquippedTool(),
						}, char, targetChar)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "Block",
							Func = "GB",
							FolderName = getEquippedTool(),
						}, char, targetChar)
					elseif verdict.outcome == "Bypass" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "E",
							Func = "Hit",
							FolderName = getEquippedTool(),
						}, char, targetChar)
					else
						BlockResolver.OnAttackerLandedHit(char)
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "E",
							Func = "Blocked",
							FolderName = getEquippedTool(),
						}, char, targetChar)
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
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = "E",
						Func = "Hit",
						FolderName = getEquippedTool(),
					}, char, targetChar)
					doAttack(0, 15)
				end
			end
		end
	end)

	StateHandler.SetState(char, "E", true, 0.5)
	if not StateHandler.GetState(char, "Stunned") or StateHandler.GetState(char, "Parried") then
		Hitbox:Start()
	end

	task.wait(0.1)

	Hitbox:Stop()

	Hitbox:ClearTaggedChars()

	task.wait(0.2)

	-- The second, longer dash carries the multihit through.
	local lungeSpeed, lungeLife = DashConfig.Get("TantoE2")
	if lungeSpeed then
		local BV = Instance.new("BodyVelocity", char.HumanoidRootPart)
		BV.MaxForce = Vector3.new(25000, 0, 25000)
		BV.Velocity = char.HumanoidRootPart.CFrame.lookVector * lungeSpeed
		game.Debris:AddItem(BV, lungeLife)
	end

	rightSwing(char)

	if not StateHandler.GetState(char, "Stunned") or StateHandler.GetState(char, "Parried") then
		Hitbox:Start()
	end

	task.wait(0.2)

	Hitbox:Destroy()
	if v[plr] then
		v[plr]:Destroy()
		v[plr] = nil
	end
end

return module
