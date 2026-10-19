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

-- Placeholder Animation IDs (REPLACE THESE)
local ANIM_ATTACKER_SUCCESS = "rbxassetid://0000000001" -- Attacker performs throw
local ANIM_VICTIM_THROWN = "rbxassetid://96311777205911" -- Victim getting thrown

local DataManager = require(game.ServerScriptService.modules.dataManager)

-- Throw Specs (Fighting Game Style)
local DAMAGE = 10
local ACTIVE_FRAMES = 0.15 -- Extremely short time the grab is active
local RECOVERY_TIME = 1.5 -- Long punishment time if you miss
local RAGDOLL_DURATION = 2.5
-- The force applied relative to the attacker's facing direction.
-- This tosses them Up (Y=60) and Backward (Z=-80)
local FLING_FORCE_RELATIVE = Vector3.new(0, 15, -30)

local danger = RP.assets.FX.danger

local v = {}

local TweenService = game:GetService("TweenService")
local InfoTween = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)

local hitboxParams = {
	-- VERY SMALL HITBOX
	SizeOrPart = Vector3.new(3, 4, 3),
	SpatialOption = "InBox",
	Debug = false,
	-- Debounce isn't strictly needed as we destroy on first hit, but good practice
	DebounceTime = 0.5,
} :: HitboxTypes.HitboxParams

local playerThrowDebounces = {}

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

		-- Crucial: Check if the tool is actually equipped (not just in Backpack/StarterGear)
		if tool and tool.Parent == currentCharacter then
			return tool.Name
		end
		return nil
	end

	-- 1. Busy Check
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
		-- Optional: Fire "Declined" back to client
		return
	end

	-- FX handling
	local NewShield2 = danger:Clone()
	game.Debris:AddItem(NewShield2, 1)
	local WeldCon = Instance.new("WeldConstraint", NewShield2)
	NewShield2.Parent = char
	v[plr] = NewShield2
	local parrysfx = Instance.new("Sound")
	parrysfx.Parent = char.Torso
	parrysfx.SoundId = "rbxassetid://7100154577" --5763723309
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

	-- EXECUTION START
	playerThrowDebounces[plr] = true

	-- Set state to Attacking immediately. The duration is initially set to
	-- cover the active frames + recovery. It will be shortened if a hit occurs.
	StateHandler.SetState(char, "Attacking", true, ACTIVE_FRAMES + RECOVERY_TIME)
	-- Also set CantAnything so they can't move during the attempt
	StateHandler.SetState(char, "CantAnything", true, ACTIVE_FRAMES + RECOVERY_TIME)

	local humrp = char.HumanoidRootPart
	local Hitbox, connected = HitboxClass.new(hitboxParams)

	task.wait(0.2)
	-- Weld very close in front of the player
	Hitbox:WeldTo(humrp, CFrame.new(0, 0, -2.5))
	Hitbox:Start()

	local hasHit = false

	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		if hasHit then
			return
		end -- Throws only grab one person

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

			-- FIGHTING GAME CHECKS:
			-- 1. Can they be grabbed? (Not iframed/dodging)
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
			-- 2. Are they already being thrown or deeply stunned? (Prevent infinite throw loops)
			if
				StateHandler.GetState(targetChar, "BeingThrown")
				or StateHandler.GetState(targetChar, "Stunned")
			then
				continue
			end

			-- SUCCESSFUL THROW!
			hasHit = true
			Hitbox:Destroy() -- Stop hitbox immediately

			Helper.ResetSpeed(char)

			-- A. Update Attacker State (Shorten recovery on success)
			-- We reset the states to a shorter duration, just enough for the success animation
			StateHandler.SetState(char, "M1", true, 1)
			StateHandler.SetState(char, "CantAnything", true, 1)
			-- Play success animation on attacker, overwriting the whiff animation

			--AnimationHandler.LoadAnim(char, "Action", ANIM_ATTACKER_SUCCESS, nil, false)

			-- B. Update Victim State
			-- Set a specific state so they can't be grabbed again immediately
			StateHandler.SetState(targetChar, "BeingThrown", true, 1)
			-- Hard stun them so they can't act while being thrown
			StateHandler.SetStun(targetChar, true, 1.5, 0)
			-- Play being thrown animation
			AnimationHandler.LoadAnim(targetChar, "Reaction", ANIM_VICTIM_THROWN, nil, false)

			local dmgModule = require(game.ServerScriptService.modules.damageCalculator)
			dmgModule.CalculateDamage(char, targetChar, DAMAGE, 0, false)

			-- C. Replicate Effects
			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "Throw",
				Func = "ExecuteEffect",
				FolderName = getEquippedTool(),
			}, char, "Hit")

			-- D. Apply Physics (Fling & Ragdoll)
			-- Wait a tiny fraction for animations to start before flinging
			task.delay(0.15, function()
				if targetChar and targetHRP then
					ragdollManager.Ragdoll(targetChar, RAGDOLL_DURATION)

					-- Calculate fling direction relative to attacker facing
					-- This converts the relative vector (Up and Back) into world space based on where the attacker is looking
					local flingVelocityWorld = humrp.CFrame:VectorToWorldSpace(FLING_FORCE_RELATIVE)

					-- Apply velocity. We use a generic BodyVelocity approach here.
					-- If your HelperModule has a specific velocity setter, use that instead.
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
					bv.Velocity = flingVelocityWorld
					bv.Parent = targetHRP
					Debris:AddItem(bv, 0.3) -- Apply force briefly
				end
			end)

			break -- Stop iterating after finding one valid target
		end
	end)

	-- WHIFF (RECOVERY) HANDLER
	task.delay(ACTIVE_FRAMES, function()
		-- If active frames finish and we haven't hit anyone
		if not hasHit then
			Helper.SetSpeed(char, 0, 16)
			Hitbox:Destroy()
			-- Replicate whiff sound/effect
			ReplicateRemote:FireAllClients({
				Type = "Combat",
				Action = "Throw",
				Func = "ExecuteEffect",
				FolderName = getEquippedTool(),
			}, char, "Whiff")
			-- The Attacking/CantAnything states will naturally expire after RECOVERY_TIME
			-- because we set them for (ACTIVE_FRAMES + RECOVERY_TIME) initially.
		end

		-- Clear server debounce after recovery time passes
		task.delay(RECOVERY_TIME, function()
			playerThrowDebounces[plr] = nil
			Helper.ResetSpeed(char)
		end)
	end)
end

-- Cleanup
Players.PlayerRemoving:Connect(function(plr)
	playerThrowDebounces[plr] = nil
end)

return module
