local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Load your existing modules
local StateHandler = require(ReplicatedStorage.modules.stateHandler)
local StatScaling = require(ReplicatedStorage.modules.StatScaling)
local RagdollManager = require(ServerScriptService.modules.ragdollManager)
local SpeedService = require(ServerScriptService.modules.SpeedService)

local DownedManager = {}
local DownedData = {}

-- forward declarations: defined below, used by StopCarrying above their definition
local pinDown
local unpin
local ActiveCarryTracks = {}
local ActiveCarriedTracks = {}
local ActiveExecuteTracks = {}

-- [[ CONFIGURATION ]] --
local DOWNED_THRESHOLD_PCT = 0.01
local REVIVE_TIMER = 30
local REVIVE_HP_PCT = 0.30
local EXECUTE_RANGE = 5
local CARRY_OFFSET = Vector3.new(2, 2, 0)

-- [[ HELPER: STOP CARRYING ]] --
local function StopCarrying(carrierChar, victimChar)
	if ActiveCarryTracks[carrierChar] then
		ActiveCarryTracks[carrierChar]:Stop()
		ActiveCarryTracks[carrierChar] = nil
	end

	if ActiveCarriedTracks[victimChar] then
		ActiveCarriedTracks[victimChar]:Stop()
		ActiveCarriedTracks[victimChar] = nil
	end

	if DownedData[victimChar] then
		if DownedData[victimChar].VictimDiedConn then
			DownedData[victimChar].VictimDiedConn:Disconnect()
			DownedData[victimChar].VictimDiedConn = nil
		end
		if DownedData[victimChar].CarrierDiedConn then
			DownedData[victimChar].CarrierDiedConn:Disconnect()
			DownedData[victimChar].CarrierDiedConn = nil
		end

		if DownedData[victimChar].StateGuardConn then
			DownedData[victimChar].StateGuardConn:Disconnect()
			DownedData[victimChar].StateGuardConn = nil
		end
		if DownedData[victimChar].CarryGuardConn then
			DownedData[victimChar].CarryGuardConn:Disconnect()
			DownedData[victimChar].CarryGuardConn = nil
		end

		DownedData[victimChar].Carrier = nil
	end

	StateHandler.RemoveStates(carrierChar, "Carrying")
	StateHandler.RemoveStates(carrierChar, "CantAnything")
	StateHandler.RemoveStates(victimChar, "Carried")

	-- Put the dropped body back into a proper downed ragdoll. AttemptCarry called
	-- UnRagdoll to pick them up, so Ragdolled is clear and this will actually run
	-- (the re-entrancy guard would otherwise swallow it). No duration: a Downed
	-- body never auto-recovers, so they stay on the floor. The revive countdown
	-- resumes by itself, because the KnockDown loop only ticks while
	-- data.Carrier is nil, and we clear Carrier just above.
	RagdollManager.Ragdoll(victimChar)
	pinDown(victimChar)

	-- Clean up Align Constraints
	if carrierChar and carrierChar:FindFirstChild("HumanoidRootPart") then
		local att = carrierChar.HumanoidRootPart:FindFirstChild("CarryAtt")
		if att then
			att:Destroy()
		end
	end

	if victimChar and victimChar:FindFirstChild("HumanoidRootPart") then
		local root = victimChar.HumanoidRootPart
		local att = root:FindFirstChild("CarryAtt")
		if att then
			att:Destroy()
		end
		local pos = root:FindFirstChild("CarryPos")
		if pos then
			pos:Destroy()
		end
		local ori = root:FindFirstChild("CarryOri")
		if ori then
			ori:Destroy()
		end

		-- [[ FIX: Return Network Ownership to Victim or Server ]]
		if root:CanSetNetworkOwnership() then
			local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
			if victimPlayer then
				root:SetNetworkOwner(victimPlayer)
			else
				root:SetNetworkOwner(nil) -- Give it to server if it's an NPC
			end
		end
	end

	-- Restore Mass and Collisions safely
	if victimChar then
		for _, v in pairs(victimChar:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Massless = false
				if
					v.Name == "Head"
					or v.Name == "Torso"
					or v.Name == "UpperTorso"
					or v.Name == "LowerTorso"
				then
					v.CanCollide = true
				else
					v.CanCollide = false
				end
			end
		end
	end
end

-- [[ HELPER: PIN A DOWNED BODY TO THE FLOOR ]] --
-- Called on knockdown and re-asserted whenever something else may have stomped
-- the humanoid (a ragdoll teardown, a client GettingUp, a carry drop). A downed
-- player must be immovable until Revive / Execute / Carry says otherwise.
function pinDown(char)
	local hum = char and char:FindFirstChild("Humanoid")
	if not hum then
		return
	end

	-- PIN priority: the top of the stack. Once pushed, a stun-pop or hitstop-pop or
	-- block-pop can't recompute a downed player back to a walkable speed. This replaces
	-- the old "re-assert WalkSpeed = 0 whenever something might have stomped it" pattern.
	SpeedService.Push(char, "Downed", 0, SpeedService.Priority.PIN)
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.PlatformStand = true
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum:ChangeState(Enum.HumanoidStateType.Physics)
end

-- [[ HELPER: RELEASE A BODY FROM THE PIN ]] --
function unpin(char)
	local hum = char and char:FindFirstChild("Humanoid")
	if not hum then
		return
	end

	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
	hum.PlatformStand = false
	hum.AutoRotate = true
end

-- [[ RESET THE REVIVE TIMER ]] --
-- Called from damageCalculator when a downed body takes another hit. Beating on
-- someone who is already down keeps them down.
function DownedManager.ResetReviveTimer(char)
	local data = DownedData[char]
	if not data then
		return
	end
	data.Timer = REVIVE_TIMER
end

-- [[ 1. MAIN CHECK ]] --
function DownedManager.CheckDownedCondition(char, damage, isInstantKill)
	if not char then
		return false
	end
	local hum = char:FindFirstChild("Humanoid")
	if not hum then
		return false
	end

	local player = Players:GetPlayerFromCharacter(char)
	if not player then
		return false
	end

	local potentialHealth = hum.Health - damage
	local maxHealth = hum.MaxHealth
	local threshold = maxHealth * DOWNED_THRESHOLD_PCT

	if isInstantKill then
		return false
	end
	if StateHandler.GetState(char, "Downed") then
		return false
	end

	if potentialHealth <= threshold then
		DownedManager.KnockDown(char)
		hum.Health = math.max(1, threshold)
		return true
	end

	return false
end

-- [[ 2. KNOCKDOWN LOGIC ]] --
function DownedManager.KnockDown(char)
	local player = Players:GetPlayerFromCharacter(char)
	local hum = char:FindFirstChild("Humanoid")

	-- Anyone going down drops whatever they were carrying. Covers every knockdown
	-- path, not just the damage one (damageCalculator returns early on a fresh
	-- knockdown, so a drop placed further down that function would be skipped).
	DownedManager.DropIfCarrying(char)

	-- ORDER MATTERS. RagdollModule used to early-return on Downed, so setting
	-- Downed before calling Ragdoll meant the knockdown ragdoll never ran. That
	-- guard is now a Ragdolled re-entrancy check instead, but we still ragdoll
	-- FIRST so the body is on the floor before anything can observe it as Downed.
	-- Clear any prior ragdoll so the fresh one is not swallowed by the guard.
	RagdollManager.UnRagdoll(char, true)
	RagdollManager.Ragdoll(char)

	StateHandler.SetState(char, "Downed", true)
	StateHandler.SetStun(char, true, nil, 0)
	StateHandler.SetState(char, "CantAnything", true)

	pinDown(char)

	DownedData[char] = {
		Timer = REVIVE_TIMER,
		Carrier = nil,
		BeingExecuted = false,
	}

	task.spawn(function()
		while DownedData[char] and StateHandler.GetState(char, "Downed") do
			task.wait(1)
			local data = DownedData[char]
			if not data then
				break
			end

			-- Bail if the body is gone or dead.
			--
			-- Only Revive and PlayerRemoving ever cleared DownedData, and the two
			-- execution paths zero health and clear it themselves. Every OTHER way a
			-- downed player can die (fall damage, a mob finishing them, a boss AoE,
			-- ON_DEATH_EVENT) left the entry standing and this thread ticking. At T=0
			-- it would call Revive on a corpse: UnRagdoll, unpin, ChangeState(GettingUp)
			-- and Jump, all fighting the 10s death ragdoll, on a character that is
			-- supposed to stay down. It also kept the loop spinning for up to 30s
			-- against a character that may already be destroyed.
			local liveHum = char:FindFirstChild("Humanoid")
			if not char.Parent or not liveHum or liveHum.Health <= 0 then
				DownedData[char] = nil
				break
			end

			if not data.Carrier and not data.BeingExecuted then
				data.Timer = data.Timer - 1
				if data.Timer <= 0 then
					DownedManager.Revive(char)
					break
				end
			end
		end
	end)
end

-- [[ 3. REVIVE LOGIC ]] --
function DownedManager.Revive(char)
	local hum = char:FindFirstChild("Humanoid")

	print("revived")

	if not char.Parent or not hum or hum.Health <= 0 then
		DownedData[char] = nil
		return
	end

	DownedData[char] = nil

	-- Clear Downed BEFORE tearing the ragdoll down, so the ragdoll module's
	-- Downed guards do not block the teardown.
	StateHandler.RemoveStates(char, "Downed")
	StateHandler.RemoveStates(char, "CantAnything")
	StateHandler.SetStun(char, false)

	RagdollManager.UnRagdoll(char, true)
	unpin(char)

	if hum then
		-- Restore movement. Pop the Downed PIN and let SpeedService recompute to the
		-- live base (Stamina + race bonus): the Stun modifier was already dropped by the
		-- SetStun(false) above, so with Downed gone the stack resolves to full speed.
		SpeedService.Pop(char, "Downed")
		hum.JumpPower = 50
		hum.JumpHeight = 7.2
		hum.PlatformStand = false
		hum.AutoRotate = true

		hum.Health = hum.MaxHealth * REVIVE_HP_PCT

		-- GettingUp is re-issued here, AFTER PlatformStand is down. Roblox ignores a
		-- GettingUp request while PlatformStand is true, so the one fired inside
		-- UnRagdoll landed on a still-platform-standing humanoid and did nothing.
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)

		-- Force the client's network-owned Humanoid to recognize the ground
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local _, y, _ = root.CFrame:ToEulerAnglesYXZ()
			root.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, y, 0)
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

			-- Briefly bouncing Sit triggers a replicated state reset for clients stuck in Freefall
			hum.Sit = true
			task.wait()
			hum.Sit = false
		end

		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hum:ChangeState(Enum.HumanoidStateType.Running)
		hum.Jump = true
	end
end

-- [[ 4. STOP EXECUTION ]] --
function DownedManager.StopExecution(executorChar)
	if not executorChar then
		return
	end

	if ActiveExecuteTracks[executorChar] then
		ActiveExecuteTracks[executorChar]:Stop()
		ActiveExecuteTracks[executorChar] = nil
	end

	StateHandler.RemoveStates(executorChar, "Executing")
	StateHandler.SetStun(executorChar, false)
	if executorChar:FindFirstChild("HumanoidRootPart") then
		executorChar.HumanoidRootPart.Anchored = false
	end

	for vChar, data in pairs(DownedData) do
		if data.BeingExecuted and data.Executor == executorChar then
			data.BeingExecuted = false
			data.Executor = nil
			StateHandler.RemoveStates(vChar, "BeingExecuted")
		end
	end
end

-- [[ 5. PLAYER EXECUTION LOGIC ]] --
function DownedManager.AttemptExecute(executorChar, victimChar)
	if not DownedData[victimChar] then
		return
	end
	if not StateHandler.GetState(victimChar, "Downed") then
		return
	end

	-- Ensure executor is allowed to act
	if StateHandler.GetState(executorChar, "Stunned") then
		return
	end
	if StateHandler.GetState(executorChar, "CantAnything") then
		return
	end
	if StateHandler.GetState(executorChar, "Downed") then
		return
	end

	if StateHandler.GetState(executorChar, "Executing") then
		DownedManager.StopExecution(executorChar)
		return
	end

	if StateHandler.GetState(victimChar, "BeingExecuted") then
		return
	end
	if
		DownedData[victimChar].Carrier == executorChar
		or StateHandler.GetState(victimChar, "Carried")
	then
		return
	end

	local dist = (executorChar.HumanoidRootPart.Position - victimChar.HumanoidRootPart.Position).Magnitude
	if dist > EXECUTE_RANGE then
		return
	end

	StateHandler.SetState(executorChar, "Executing", true)
	StateHandler.SetState(victimChar, "BeingExecuted", true)
	StateHandler.SetStun(executorChar, true, 2.5, 0)

	DownedData[victimChar].BeingExecuted = true
	DownedData[victimChar].Executor = executorChar

	local anim = executorChar.Humanoid:LoadAnimation(script.ExecuteAnim)
	anim.Priority = Enum.AnimationPriority.Action4
	anim:Play()
	ActiveExecuteTracks[executorChar] = anim

	executorChar.HumanoidRootPart.Anchored = true

	task.wait(2)

	if StateHandler.GetState(executorChar, "Executing") then
		local sound = game.ReplicatedStorage.assets.sounds.DeadSoundOLD:Clone()
		sound.Parent = executorChar.HumanoidRootPart
		sound:Play()
		game.Debris:AddItem(sound, sound.TimeLength)

		local vHum = victimChar:FindFirstChild("Humanoid")
		if vHum then
			vHum.Health = 0

			DownedData[victimChar] = nil
			StateHandler.RemoveStates(victimChar, "Downed")
			StateHandler.RemoveStates(victimChar, "CantAnything")
			StateHandler.RemoveStates(victimChar, "BeingExecuted")
			executorChar.HumanoidRootPart.Anchored = false
		end

		if ActiveExecuteTracks[executorChar] then
			ActiveExecuteTracks[executorChar] = nil
		end
		StateHandler.RemoveStates(executorChar, "Executing")
		StateHandler.SetStun(executorChar, false)
	end
end

-- [[ 6. FORCE DROP IF CARRYING ]] --
function DownedManager.DropIfCarrying(carrierChar)
	if not carrierChar then
		return false
	end

	for vChar, data in pairs(DownedData) do
		if data.Carrier == carrierChar then
			StopCarrying(carrierChar, vChar)
			return true
		end
	end
	return false
end

-- [[ 7. CARRY LOGIC ]] --
function DownedManager.AttemptCarry(carrierChar, victimChar)
	if DownedManager.DropIfCarrying(carrierChar) then
		return
	end

	-- FIX 2: Validate the carrier's state before they try to pick someone up
	if StateHandler.GetState(carrierChar, "CantAnything") then
		return
	end
	if StateHandler.GetState(carrierChar, "Stunned") then
		return
	end
	if StateHandler.GetState(carrierChar, "Downed") then
		return
	end

	if not victimChar or not DownedData[victimChar] then
		return
	end
	if StateHandler.GetState(victimChar, "Downed") == nil then
		return
	end

	-- A. PICK UP
	if not DownedData[victimChar].Carrier then
		local dist = (carrierChar.HumanoidRootPart.Position - victimChar.HumanoidRootPart.Position).Magnitude
		if dist > EXECUTE_RANGE then
			return
		end

		local anim = carrierChar.Humanoid:LoadAnimation(script.CarryAnim)
		anim.Priority = Enum.AnimationPriority.Action4
		anim.Looped = true
		anim:Play()
		ActiveCarryTracks[carrierChar] = anim

		local anim2 = victimChar.Humanoid:LoadAnimation(script.CarriedAnim)
		anim2.Priority = Enum.AnimationPriority.Action4
		anim2.Looped = true
		anim2:Play()
		ActiveCarriedTracks[victimChar] = anim2

		DownedData[victimChar].Carrier = carrierChar

		local vHum = victimChar:FindFirstChild("Humanoid")
		local cHum = carrierChar:FindFirstChild("Humanoid")

		if vHum then
			DownedData[victimChar].VictimDiedConn = vHum.Died:Connect(function()
				StopCarrying(carrierChar, victimChar)
			end)
		end

		if cHum then
			DownedData[victimChar].CarrierDiedConn = cHum.Died:Connect(function()
				StopCarrying(carrierChar, victimChar)
			end)
		end

		StateHandler.SetState(carrierChar, "Carrying", true)
		StateHandler.SetState(carrierChar, "CantAnything", true)
		StateHandler.SetState(victimChar, "Carried", true)

		DownedData[victimChar].StateGuardConn = carrierChar
			:GetAttributeChangedSignal("CantAnything")
			:Connect(function()
				if
					not carrierChar:GetAttribute("CantAnything")
					and carrierChar:GetAttribute("Carrying")
				then
					DownedManager.DropIfCarrying(carrierChar)
				end
			end)

		DownedData[victimChar].CarryGuardConn = carrierChar
			:GetAttributeChangedSignal("Carrying")
			:Connect(function()
				if not carrierChar:GetAttribute("Carrying") then
					DownedManager.DropIfCarrying(carrierChar)
				end
			end)

		-- force = true: the victim IS Downed, and UnRagdoll refuses to disturb a
		-- Downed body unless the teardown is deliberate. A pickup is deliberate.
		RagdollManager.UnRagdoll(victimChar, true)

		if vHum then
			vHum.PlatformStand = true
			vHum.AutoRotate = false
			vHum:ChangeState(Enum.HumanoidStateType.Physics)
		end

		local carrierRoot = carrierChar.HumanoidRootPart
		local victimRoot = victimChar.HumanoidRootPart

		victimRoot.CFrame = carrierRoot.CFrame * CFrame.new(CARRY_OFFSET) * CFrame.Angles(0, 0, 0)

		-- [[ FIX: Give Network Ownership to the Carrier so it doesn't lag ]]
		local carrierPlayer = Players:GetPlayerFromCharacter(carrierChar)
		if carrierPlayer and victimRoot:CanSetNetworkOwnership() then
			victimRoot:SetNetworkOwner(carrierPlayer)
		end

		local carrierAtt = Instance.new("Attachment")
		carrierAtt.Name = "CarryAtt"
		carrierAtt.CFrame = CFrame.new(CARRY_OFFSET)
		carrierAtt.Parent = carrierRoot

		local victimAtt = Instance.new("Attachment")
		victimAtt.Name = "CarryAtt"
		victimAtt.Parent = victimRoot

		local alignPos = Instance.new("AlignPosition")
		alignPos.Name = "CarryPos"
		alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPos.Attachment0 = victimAtt
		alignPos.Attachment1 = carrierAtt
		alignPos.RigidityEnabled = true
		alignPos.Parent = victimRoot

		local alignOri = Instance.new("AlignOrientation")
		alignOri.Name = "CarryOri"
		alignOri.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOri.Attachment0 = victimAtt
		alignOri.Attachment1 = carrierAtt
		alignOri.RigidityEnabled = true
		alignOri.Parent = victimRoot

		for _, v in pairs(victimChar:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Massless = true
				v.CanCollide = false
			end
		end
	elseif DownedData[victimChar].Carrier == carrierChar then
		print("dropping player")
		StopCarrying(carrierChar, victimChar)
	end
end

-- [[ 8. NPC EXECUTION LOGIC ]] --
function DownedManager.NPCExecute(npcModel, victimChar)
	if not DownedData[victimChar] then
		return
	end

	StateHandler.SetState(npcModel, "Executing", true)
	StateHandler.SetState(victimChar, "BeingExecuted", true)

	DownedData[victimChar].BeingExecuted = true
	DownedData[victimChar].Executor = npcModel

	local anim = npcModel.Humanoid:LoadAnimation(script.ExecuteAnim)
	anim.Priority = Enum.AnimationPriority.Action4
	anim:Play()
	ActiveExecuteTracks[npcModel] = anim

	task.delay(2, function()
		if not StateHandler.GetState(npcModel, "Executing") then
			return
		end

		if victimChar and victimChar:FindFirstChild("Humanoid") then
			victimChar.Humanoid.Health = 0
			DownedData[victimChar] = nil

			StateHandler.RemoveStates(victimChar, "Downed")
			StateHandler.RemoveStates(victimChar, "CantAnything")
			StateHandler.RemoveStates(victimChar, "BeingExecuted")

			local sound = game.ReplicatedStorage.assets.sounds.DeadSoundOLD:Clone()
			sound.Parent = npcModel.HumanoidRootPart
			sound:Play()
			game.Debris:AddItem(sound, sound.TimeLength)
		end

		StateHandler.RemoveStates(npcModel, "Executing")
		if ActiveExecuteTracks[npcModel] then
			ActiveExecuteTracks[npcModel] = nil
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local char = player.Character
	if not char then
		return
	end

	-- If they were carrying someone, drop them cleanly
	DownedManager.DropIfCarrying(char)

	-- If they were being carried, stop the carry from the carrier's side
	local data = DownedData[char]
	if data and data.Carrier then
		StopCarrying(data.Carrier, char)
	end

	-- If they were executing someone, cancel the execution
	if ActiveExecuteTracks[char] then
		DownedManager.StopExecution(char)
	end

	-- If they were being executed, cancel from the executor's side
	if data and data.BeingExecuted and data.Executor then
		DownedManager.StopExecution(data.Executor)
	end

	-- Clean up their DownedData entry last
	DownedData[char] = nil
end)

return DownedManager
