-- SPDX-License-Identifier: MIT
--
-- Server side of the weapon throw: a short-range grab that ragdolls and flings the
-- target. A whiff has a long recovery.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicateRemote = RP.remotes.replicate
local Debris = game:GetService("Debris")

local Helper = require(SSS.modules.helperModule)
local StateHandler = require(RP.modules.stateHandler)
local ParryService = require(SSS.modules.parryService)
local AnimationHandler = require(RP.modules.animationHandler)
local HitboxClass = require(RP.modules.hitboxClass)
local HitboxTypes = require(RP.modules.hitboxClass.Types)
local ragdollManager = require(SSS.modules.ragdollManager)

-- TODO: Replace the placeholder attacker animation.
local ANIM_ATTACKER_SUCCESS = "rbxassetid://0000000001"
local ANIM_VICTIM_THROWN = "rbxassetid://96311777205911"

local DataManager = require(game.ServerScriptService.modules.dataManager)

local DAMAGE = 10
-- The grab is active only briefly, and a miss has a long recovery.
local ACTIVE_FRAMES = 0.15
local RECOVERY_TIME = 1.5
local RAGDOLL_DURATION = 2.5
-- Fling velocity relative to the attacker's facing: up and backward.
local FLING_FORCE_RELATIVE = Vector3.new(0, 15, -30)

local danger = RP.assets.FX.danger

local v = {}

local TweenService = game:GetService("TweenService")
local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)

local hitboxParams = {
	SizeOrPart = Vector3.new(3, 4, 3),
	SpatialOption = "InBox",
	Debug = false,
	-- The hitbox is destroyed on the first hit, so the debounce is only a safeguard.
	DebounceTime = 0.5,
} :: HitboxTypes.HitboxParams

local playerThrowDebounces = {}

-- Throw.ServerCheck() - attempt a throw
-- @plr: the player who pressed throw
--
-- Return: nothing. Yields until the grab starts.
function module.ServerCheck(plr)
	local char = plr.Character
	if
		not char
		or not char:FindFirstChild("HumanoidRootPart")
		or not char:FindFirstChild("Humanoid")
	then
		return
	end

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

	local isBusy = false
	if
		playerThrowDebounces[plr]
		or StateHandler.GetState(char, "M1")
		or StateHandler.GetState(char, "M2")
		or StateHandler.GetState(char, "CantAnything")
		or StateHandler.GetState(char, "Sliding")
		or StateHandler.GetState(char, "Stunned")
		or StateHandler.GetState(char, "Dodging")
	then
		isBusy = true
	end

	if isBusy then
		-- TODO: Tell the client that the throw was declined.
		return
	end

	local NewShield2 = danger:Clone()
	game.Debris:AddItem(NewShield2, 1)
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = char
	v[plr] = NewShield2
	local parrysfx = Instance.new("Sound")
	parrysfx.Parent = char.Torso
	parrysfx.SoundId = "rbxassetid://7100154577"
	parrysfx.Volume = 0.5
	parrysfx.RollOffMaxDistance = 60
	parrysfx.RollOffMinDistance = 10
	parrysfx.RollOffMode = Enum.RollOffMode.Inverse

	NewShield2.CFrame = char.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = char.HumanoidRootPart
	WeldCon.Part1 = NewShield2

	TweenService
		:Create(NewShield2, InfoTween, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()
	TweenService
		:Create(NewShield2, InfoTween, { Transparency = 1, Color = Color3.fromRGB(255, 0, 0) })
		:Play()
	parrysfx:Play()
	task.delay(0.1, function()
		local BV = Instance.new("BodyVelocity", char.HumanoidRootPart)
		BV.MaxForce = Vector3.new(25000, 0, 25000)
		BV.Velocity = char.HumanoidRootPart.CFrame.lookVector * 5
		game.Debris:AddItem(BV, 0.1)
	end)
	task.delay(1, function()
		parrysfx:Destroy()
		if v[plr] then
			v[plr]:Destroy()
			v[plr] = nil
		end
	end)

	Helper.SetSpeed(char, 2, 16)

	playerThrowDebounces[plr] = true

	-- The lock covers the active frames and the recovery. A hit shortens it.
	StateHandler.SetState(char, "Attacking", true, ACTIVE_FRAMES + RECOVERY_TIME)
	StateHandler.SetState(char, "CantAnything", true, ACTIVE_FRAMES + RECOVERY_TIME)

	local humrp = char.HumanoidRootPart
	local Hitbox, connected = HitboxClass.new(hitboxParams)

	task.wait(0.2)
	Hitbox:WeldTo(humrp, CFrame.new(0, 0, -2.5))
	Hitbox:Start()

	local hasHit = false

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		-- A throw grabs only one target.
		if hasHit then
			return
		end

		for _, hit in pairs(hitCharsTable) do
			local targetHum = hit:FindFirstChild("Humanoid")
			local targetChar = targetHum and targetHum.Parent
			if not targetChar or targetChar == char then
				continue
			end

			local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetHRP then
				continue
			end

			-- A dodging target cannot be grabbed.
			if StateHandler.GetState(targetChar, "Dodging") then
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
						if
							part:IsA("BasePart")
							and part ~= targetHRP
							and part.Name ~= "Head"
							and part.Name ~= "Left Arm"
						then
							part.Transparency = 0.7
							task.delay(0.3, function()
								part.Transparency = 0
							end)
						end
					end
				end

				return
			end
			-- A target that is being thrown or stunned cannot be grabbed, so throws cannot loop.
			if
				StateHandler.GetState(targetChar, "BeingThrown")
				or StateHandler.GetState(targetChar, "Stunned")
			then
				continue
			end

			hasHit = true
			Hitbox:Destroy()

			Helper.ResetSpeed(char)

			-- A hit shortens the attacker's lock to the length of the success animation.
			StateHandler.SetState(char, "M1", true, 1)
			StateHandler.SetState(char, "CantAnything", true, 1)

			-- BeingThrown stops the victim from being grabbed again right away.
			StateHandler.SetState(targetChar, "BeingThrown", true, 1)
			StateHandler.SetStun(targetChar, true, 1.5, 0)
			AnimationHandler.LoadAnim(targetChar, "Reaction", ANIM_VICTIM_THROWN, nil, false)

			local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
			dmgModule.CalculateDamage(char, targetChar, DAMAGE, 5, false)

			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "Throw",
				Func = "ExecuteEffect",
				FolderName = getEquippedTool(),
			}, char, "Hit")

			-- Let the animations start before the fling.
			task.delay(0.15, function()
				if targetChar and targetHRP then
					ragdollManager.Ragdoll(targetChar, RAGDOLL_DURATION)

					local flingVelocityWorld = humrp.CFrame:VectorToWorldSpace(FLING_FORCE_RELATIVE)
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
					bv.Velocity = flingVelocityWorld
					bv.Parent = targetHRP
					Debris:AddItem(bv, 0.3)
				end
			end)

			break
		end
	end)

	task.delay(ACTIVE_FRAMES, function()
		if not hasHit then
			Helper.SetSpeed(char, 0, 16)
			Hitbox:Destroy()
			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "Throw",
				Func = "ExecuteEffect",
				FolderName = getEquippedTool(),
			}, char, "Whiff")
			-- The Attacking and CantAnything states expire on their own after RECOVERY_TIME.
		end

		task.delay(RECOVERY_TIME, function()
			playerThrowDebounces[plr] = nil
			Helper.ResetSpeed(char)
		end)
	end)
end

Players.PlayerRemoving:Connect(function(plr)
	playerThrowDebounces[plr] = nil
end)

return module
