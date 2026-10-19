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

local hitboxParams = {
	SizeOrPart = Vector3.new(5, 4, 5),
	SpatialOption = "InBox",
	Debug = false,
	DebounceTime = 0.5,
} :: HitboxTypes.HitboxParams

local DataManager = require(game.ServerScriptService.modules.dataManager)

local dmg = 6
local guardbreak = false
local windupDelay = 0.6
local playerM1Debounces = {}

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

local function upSwing(char)
	local attachment = game.ReplicatedStorage.assets.FX.slashFX.SlashFXUp:Clone()
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

function module.ServerCheck(plr)
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	local decision
	local isBusy = false

	local function getEquippedTool()
		local currentCharacter = plr.Character
		if not currentCharacter then
			return nil
		end

		local tool = currentCharacter:FindFirstChildOfClass("Tool")

		-- Crucial: Check if the tool is actually equipped (not just in Backpack/StarterGear)
		if tool and tool.Parent == currentCharacter then
			return tool.Name
		end
		return nil
	end

	if isBusy then
		decision = "Declined"
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "M1",
			Func = "ServerResponse",
			FolderName = getEquippedTool(),
		}, plr, decision)
		return
	end

	-- SET DEBOUNCE AND STATE IMMEDIATELY
	StateHandler.SetState(char, "CantAnything", true, 0.8)
	playerM1Debounces[plr] = true

	Helper.SetSpeed(char, 4, 16)

	-- Sound replication
	task.delay(0.4, function()
		ReplicateRemote:FireAllClients({
			Type = "Combat",
			Action = "M1",
			Func = "Swing",
			FolderName = getEquippedTool(),
		}, char)
	end)

	task.wait(windupDelay - 0.1)

	rightSwing(char)

	task.wait(0.1)

	Helper.ResetSpeed(char)

	-- INTERRUPT CHECK: stunned/downed during windup -> abort before the hitbox.
	if StateHandler.IsInterrupted(char) then
		playerM1Debounces[plr] = nil
		AnimationHandler.StopAnim(char, "ALL")
		return
	end

	local humrp = char.HumanoidRootPart
	local Hitbox, connected = HitboxClass.new(hitboxParams)
	Hitbox:WeldTo(humrp, CFrame.new(1, -1, -4))
	Hitbox:Start()

	StateHandler.SetState(char, "M1", true, 0.2)

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

			local isPlayer = Players:GetPlayerFromCharacter(targetChar)

			-- CHECK: Not self, Not already hit in this instance, Has Humanoid
			if humanoid and (not isPlayer or isPlayer ~= plr) and not alreadyHit[targetChar] then
				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = char:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then
					return
				end

				if StateHandler.GetState(char, "Stunned") then
					continue
				end

				if StateHandler.GetState(targetChar, "Dodging") then
					print("iframed lawl :p")

					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if
						targetPlrData
						and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8
					then
						targetPlrData.Mana.Value += 8
					end

					local sound = RP.assets.sounds.Dodged:Clone()
					sound.Parent = targetHRP
					sound:Play()
					local effect = RP.assets.FX.Dodged:Clone()
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

					continue
				end

				local function doAttack(extraDmg, knockbackDistance)
					local direction = (targetHRP.Position - attackerHRP.Position).Unit

					Helper.ApplyKnockback(targetChar, direction, knockbackDistance * 2, 0.2)
					--ragdollManager.Ragdoll(targetChar, 1)
					-- E hitstun (combo-starter); pinned walkspeed so they can't walk out.
					-- Matches CombatCore E_HITSTUN / HITSTUN_STUNSPEED for cross-weapon parity.
					StateHandler.SetStun(targetChar, true, 0.8, 2)

					local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
					dmgModule.CalculateDamage(char, targetChar, dmg, extraDmg, false, "Weapon")

					--targetChar:FindFirstChild("Humanoid"):TakeDamage(dmg + extraDmg)
					if targetChar.Humanoid.Health > 0 and targetChar.Humanoid.MaxHealth < 10000 then
						DataManager.AddWeaponXP(
							game.Players:GetPlayerFromCharacter(char),
							getEquippedTool(),
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

					alreadyHit[targetChar] = true
				end

				if StateHandler.GetState(targetChar, "Parrying") then
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = "M1",
						Func = "Parry",
						FolderName = getEquippedTool(), -- FIXED Action to M2
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
						"rbxassetid://74891530644094",
						nil,
						false
					)
				elseif
					StateHandler.GetState(targetChar, "M1")
					or StateHandler.GetState(targetChar, "M2")
				then
					Hitbox:Destroy()
					return
				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- Route through BlockResolver (single chokepoint + guard bar).
					-- Dagger E replicates under Action "M1" but IS an E for bar purposes.
					local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
					local verdict = BlockResolver.Resolve({
						attacker = char,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = guardbreak,
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
							Action = "M1",
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
							Action = "M1",
							Func = "Blocked",
							FolderName = getEquippedTool(),
						}, char, targetChar)
					else
						BlockResolver.OnAttackerLandedHit(char)
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "M1",
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
					-- Normal Hit
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = "M1",
						Func = "Hit",
						FolderName = getEquippedTool(),
					}, char, targetChar)
					doAttack(0, 5)
				end
			end
		end
	end)

	task.delay(0.1, function()
		Hitbox:Destroy()
	end)

	playerM1Debounces[plr] = nil -- CLEAR PER-PLAYER DEBOUNCE
end

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(plr)
	playerM1Debounces[plr] = nil
end)

return module
