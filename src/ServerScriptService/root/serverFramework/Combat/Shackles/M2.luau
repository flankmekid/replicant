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
	SizeOrPart = Vector3.new(6,7,6),
	SpatialOption = ("InBox"),
	Debug = false, DebounceTime = 0.5,
} :: HitboxTypes.HitboxParams

local DataManager = require(game.ServerScriptService.modules.dataManager)

-- M2 Specific Settings
local dmg = 12
local GUARD_BREAK = true
local WINDUP_DELAY = 0.9
local AERIAL_WINDUP = 0.4
local HITBOX_DURATION = 0.2 -- How long the hitbox is active
local POST_ATTACK_COOLDOWN = 3 -- The long cooldown after the attack finishes

local v = {}

local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)

local function rightSwing(char)
	local attachment = game.ReplicatedStorage.assets.FX.FistSlash.SlashLeft:Clone()
	attachment.Parent = char.Torso
	for _, v in pairs(attachment:GetChildren()) do
		if v:IsA("ParticleEmitter") and v:GetAttribute("EmitCount") then
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end
	game.Debris:AddItem(attachment,2)
end

local function leftSwing(char)
	local attachment = game.ReplicatedStorage.assets.FX.FistSlash.SlashRight:Clone()
	attachment.Parent = char.Torso
	for _, v in pairs(attachment:GetChildren()) do
		if v:IsA("ParticleEmitter") and v:GetAttribute("EmitCount") then
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end
	game.Debris:AddItem(attachment, 2)
end

local playerM2Debounces = {} -- PER-PLAYER DEBOUNCE FIX (Critical)

local aerial = false

function module.ServerCheck(plr)
	
	local function getEquippedTool()
		local currentCharacter = plr.Character
		if not currentCharacter then return nil end

		local tool = currentCharacter:FindFirstChildOfClass("Tool")

		-- Crucial: Check if the tool is actually equipped (not just in Backpack/StarterGear)
		if tool and tool.Parent == currentCharacter then
			return tool.Name
		end
		return nil
	end
	
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	local decision
	local isBusy = false

	if isBusy then
		decision = "Declined"
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "M2",
			Func = "ServerResponse",
			FolderName = getEquippedTool()
		}, plr, decision)
		return
	end
	
	if (char.Humanoid:GetState() == Enum.HumanoidStateType.Freefall) then
		aerial = true
	end
	
	if aerial then 
		local effect1 = game.ReplicatedStorage.assets.FX.fists.partic:Clone()
		local effect2 = game.ReplicatedStorage.assets.FX.fists.paricle:Clone()
		effect1.Parent = char:WaitForChild("Right Leg")
		effect2.Parent = char:WaitForChild("Right Leg")
		effect1.Enabled = true
		effect2.Enabled = true
		task.delay(AERIAL_WINDUP, function ()
			game:GetService("Debris"):AddItem(effect1, 0.2)
			game:GetService("Debris"):AddItem(effect2, 0.2)
		end)
		dmg /= 2 
	else
		local effect1 = game.ReplicatedStorage.assets.FX.fists.partic:Clone()
		local effect2 = game.ReplicatedStorage.assets.FX.fists.paricle:Clone()
		effect1.Parent = char:WaitForChild("Right Arm")
		effect2.Parent = char:WaitForChild("Right Arm")
		effect1.Enabled = true
		effect2.Enabled = true
		task.delay(WINDUP_DELAY, function ()
			game:GetService("Debris"):AddItem(effect1, 0.2)
			game:GetService("Debris"):AddItem(effect2, 0.2)
		end)
	end
	
	local function dashEff()
		for _,v in pairs(plr.Character:GetChildren()) do
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

	-- SET DEBOUNCE AND STATE IMMEDIATELY.
	-- The up-front CantAnything is the OLD long lock (windup + hitbox + 0.5). It gets
	-- torn down and re-applied once the hitbox resolves, so the endlag depends on
	-- whether the swing landed, exactly like the standard M2 in CombatCore. Shackles
	-- is a standalone M2 that never routes through CombatCore, so the same fix has to
	-- be duplicated here by hand.
	local M2_ENDLAG_HIT   = 0.1
	local M2_ENDLAG_WHIFF = 0.65  -- +0.2, matches CombatCore's standard M2 whiff recovery
	local didHit = false

	StateHandler.SetState(char, "CantAnything", true, WINDUP_DELAY + HITBOX_DURATION + 0.5) 
	playerM2Debounces[plr] = true -- Start the per-player debounce

	-- HYPERARMOR: Shackles M2 is a guardbreak, so it is armored. Set the attribute
	-- (SetStun no-ops on us for the window) and skip the interrupt cancel entirely so
	-- the swing rides through a hit. Cleared on a fixed timer past the commit window so
	-- every early-return path is covered without threading a flag through each.
	local hyperArmored = GUARD_BREAK and true or false
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
		task.delay(WINDUP_DELAY + HITBOX_DURATION + 0.3, function()
			if char then char:SetAttribute("HyperArmor", nil) end
		end)
	end

	-- Reactive interrupt: on stun/down during windup, cancel the dash mover
	-- (sweep self-applied BodyVelocity on our HRP) and stop the swing animation.
	-- Armored swings skip this so the interrupt can't cancel them.
	local stopWatch = StateHandler.WatchInterrupt(char, 3, function()
		if hyperArmored then return end
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
	
	-- FX handling
local NewShield2 = danger:Clone()
	game.Debris:AddItem(NewShield2, 1)	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = char
	v[plr] = NewShield2
	local parrysfx = Instance.new("Sound")
	parrysfx.Parent = char.Torso
	parrysfx.SoundId = "rbxassetid://7100154577" --5763723309
	parrysfx.Volume = 0.5
	parrysfx.RollOffMaxDistance = 60
	parrysfx.RollOffMinDistance = 10
	parrysfx.RollOffMode = Enum.RollOffMode.Inverse
	NewShield2.CFrame = char.HumanoidRootPart.CFrame * CFrame.new(0,5,0)
	WeldCon.Part0 = char.HumanoidRootPart
	WeldCon.Part1 = NewShield2
	TweenService:Create(NewShield2,InfoTween, {Transparency = 1, Color = Color3.fromRGB(255, 0, 0);}):Play()
	TweenService:Create(NewShield2,InfoTween, {Transparency = 1, Color = Color3.fromRGB(255, 0, 0);}):Play()
	parrysfx:Play()
	if not aerial then
		task.delay(0.75, function()
			-- Shackles M2 does not route through CombatCore, so it never read the
			-- shared M2 value and still does not. Its own DashConfig entry.
			local m2Speed, m2Life = DashConfig.Get("ShacklesM2")
			if m2Speed then
				local BV = Instance.new("BodyVelocity", char.HumanoidRootPart)
				BV.MaxForce = Vector3.new(25000, 0, 25000)
				BV.Velocity = char.HumanoidRootPart.CFrame.lookVector * m2Speed
				game.Debris:AddItem(BV, m2Life)
			end
		end)
		task.delay(1, function()
			dashEff()
		end)
	end

	Helper.SetSpeed(char, 4, 16)

	-- Windup logic and speed reset
	
	task.delay(1, function()
		parrysfx:Destroy()
		if v[plr] then
			v[plr]:Destroy()
			v[plr] = nil
		end
	end)
	
	if aerial then
		task.delay(AERIAL_WINDUP, function()
			Helper.ResetSpeed(char)
		end)
		task.delay(0.2, function()
			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "M2", -- FIXED
				Func = "PunchSound", 
				FolderName = getEquippedTool()
			}, char)
		end)
		task.wait(AERIAL_WINDUP)
		leftSwing(char)
		rightSwing(char)
	else
		task.delay(WINDUP_DELAY, function()
			Helper.ResetSpeed(char)
		end)
		task.delay(0.75, function()
			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "M2", -- FIXED
				Func = "PunchSound", 
				FolderName = getEquippedTool()
			}, char)
		end)
		task.wait(WINDUP_DELAY) -- Wait for the windup to complete

	-- INTERRUPT CHECK: stunned/downed during windup -> abort before the hitbox.
	-- Armored (guardbreak) swings ignore this: they commit through a hit.
	if not hyperArmored and StateHandler.IsInterrupted(char) then
		stopWatch()
		playerM2Debounces[plr] = nil
		Helper.ResetSpeed(char)
		if v[plr] then v[plr]:Destroy() v[plr] = nil end
		AnimationHandler.StopAnim(char, "ALL")
		return
	end

	-- swing committed: stop watching so a later unrelated stun can't fire the watcher
	stopWatch()
		leftSwing(char)
	end

	local humrp = char.HumanoidRootPart
	local Hitbox, connected = HitboxClass.new(hitboxParams)

	Hitbox:WeldTo(humrp, CFrame.new(1,-1,-3))
	Hitbox:Start()

	-- Set M2 state for the duration of the active hitbox
	StateHandler.SetState(char, "M2", true, HITBOX_DURATION)

	local alreadyHit = {}

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			local humanoid = hit:FindFirstChild("Humanoid")
			local targetChar = humanoid and humanoid.Parent
			if not targetChar or targetChar:IsA("Model") and not targetChar:FindFirstChild("Humanoid") then continue end

			local isPlayer = Players:GetPlayerFromCharacter(targetChar)

			-- CHECK: Not self, Not already hit in this instance, Has Humanoid
			if humanoid and (not isPlayer or isPlayer ~= plr) and not alreadyHit[targetChar] then

				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = char:FindFirstChild("HumanoidRootPart")
				if not targetHRP or not attackerHRP then return end

				if StateHandler.GetState(char, "Stunned") then continue end

				if StateHandler.GetState(targetChar, "Dodging") then
					print("iframed lawl :p")
					
					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if targetPlrData and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
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
							if part:IsA("BasePart") and part ~= targetHRP and part.Name ~= "Head" and part.Name ~= "Left Arm" then
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

					Helper.ApplyKnockback(targetChar, direction, knockbackDistance, 0.2)
					ragdollManager.Ragdoll(targetChar, 1)
					StateHandler.SetStun(targetChar, true, 1, 0)
					
					local mana = plr:FindFirstChild("PlayerStats"):FindFirstChild("Mana")
					if mana.Value < 80 then mana.Value += 20 end
					
					local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
					dmgModule.CalculateDamage(char, targetChar, dmg, extraDmg, false, "Weapon")
					didHit = true -- landed: earns the shorter endlag below
					
					--targetChar:FindFirstChild("Humanoid"):TakeDamage(dmg + extraDmg)
					if targetChar.Humanoid.Health > 0 and targetChar.Humanoid.MaxHealth < 10000 then DataManager.AddWeaponXP(game.Players:GetPlayerFromCharacter(char), "Fists", (dmg + extraDmg) / 2) end
					
					local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
					highlight.Parent = humanoid.Parent
					game.Debris:AddItem(highlight, 0.1)
					
					local hitEff = game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment:Clone()
					hitEff.Parent = targetChar:FindFirstChild("Torso")
					game:GetService("Debris"):AddItem(hitEff, 1)
					task.delay(0.5, function()
						for _,v in pairs(hitEff:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								v.Enabled = false
							end
						end
					end)

					alreadyHit[targetChar] = true
				end

				if StateHandler.GetState(targetChar, "Parrying") then
					ReplicateRemote:FireAllClients({
						Type = "Combat", Action = "M2", Func = "Parry", FolderName = getEquippedTool() -- FIXED Action to M2
					}, char, targetChar)
					
					local parryE = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry:Clone()
					local effect2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
					local clash =  game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash:Clone()
					local clash2 =  game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash:Clone()
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
					game.Debris:AddItem(parryE,0.7)
					game.Debris:AddItem(effect2, 0.7)

					StateHandler.SetStun(char, true, 0.5, 2)
					StateHandler.SetState(char, "CantAnything", true, 0.5)
					ParryService.ResetParry(game.Players:GetPlayerFromCharacter(targetChar))
					
					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if targetPlrData and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8 then
						targetPlrData.Mana.Value += 8
					end
				
					AnimationHandler.StopAnim(char, "ALL")
					AnimationHandler.LoadAnim(char, "Parried", "rbxassetid://74891530644094", nil, false)

				elseif StateHandler.GetState(targetChar, "M1") or StateHandler.GetState(targetChar, "M2") then
					Hitbox:Destroy()

				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- Route through BlockResolver (single chokepoint + guard bar).
					local BlockResolver = require(game.ServerScriptService.modules.BlockResolver)
					local verdict = BlockResolver.Resolve({
						attacker = char,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = GUARD_BREAK,
						attackClass = "M2",
						dmg = dmg,
					})
					local extra = verdict.chipDamage - dmg

					if verdict.outcome == "GuardBreak" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						if verdict.broke then
							doAttack(extra, verdict.knockback)
						else
							local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
							dmgModule.CalculateDamage(char, targetChar, dmg, verdict.knockback, false, "Weapon")
						end
						ReplicateRemote:FireAllClients({
							Type = "Combat", Action = "M2", Func = "GB", FolderName = getEquippedTool()
						}, char, targetChar)
						ReplicateRemote:FireAllClients({
							Type = "Combat", Action = "Block", Func = "GB", FolderName = getEquippedTool()
						}, char, targetChar)
					elseif verdict.outcome == "Bypass" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat", Action = "M2", Func = "Hit", FolderName = getEquippedTool()
						}, char, targetChar)
					else
						BlockResolver.OnAttackerLandedHit(char)
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat", Action = "M2", Func = "Blocked", FolderName = getEquippedTool()
						}, char, targetChar)
						local parryE = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry:Clone()
						local effect2 = game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
						local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
						h1.Parent = char
						game.Debris:AddItem(h1, 0.1)
						parryE.Parent = char:WaitForChild("Torso")
						effect2.Parent = char:WaitForChild("Torso")
						parryE.Enabled = true
						effect2.Enabled = true
						game.Debris:AddItem(parryE,0.7)
						game.Debris:AddItem(effect2, 0.7)
					end
				else
					-- Normal Hit
					ReplicateRemote:FireAllClients({
						Type = "Combat", Action = "M2", Func = "Hit", FolderName = getEquippedTool() -- FIXED Action to M2
					}, char, targetChar)
					doAttack(0, 15)
				end
			end
		end
	end)

	task.delay(HITBOX_DURATION, function() -- Hitbox ends after its duration
		Hitbox:Destroy()
		aerial = false

		-- Release the long lock and re-apply only the endlag we want. On hit you get a
		-- short recovery and can cancel Shackles M2 into M1 / E / a skill / a dash; on
		-- whiff it stays punishing. The M2 cooldown (POST_ATTACK_COOLDOWN) is untouched,
		-- so you still cannot chain M2 into M2.
		local endlag = didHit and M2_ENDLAG_HIT or M2_ENDLAG_WHIFF
		StateHandler.RemoveStates(char, "CantAnything")
		if endlag > 0 then
			StateHandler.SetState(char, "CantAnything", true, endlag)
		end
	end)

	-- POST ATTACK COOLDOWN
	task.delay(POST_ATTACK_COOLDOWN, function()
		playerM2Debounces[plr] = nil -- Clear per-player debounce after cooldown
	end)
end

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(plr)
	playerM2Debounces[plr] = nil
end)

return module