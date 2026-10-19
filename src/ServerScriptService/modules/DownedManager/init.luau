-- SPDX-License-Identifier: MIT
--
-- Owns the downed state: knockdown at low HP, the revive timer, execution by players
-- and NPCs, and carrying. A downed body never gets up on its own. Only Revive,
-- an execution, or a carry changes it. The design is in docs/systems-design.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StateHandler = require(ReplicatedStorage.modules.stateHandler)
local StatScaling = require(ReplicatedStorage.modules.StatScaling)
local RagdollManager = require(ServerScriptService.modules.ragdollManager)
local SpeedService = require(ServerScriptService.modules.SpeedService)
local FallTracker = require(ServerScriptService.modules.FallTracker)

local DownedManager = {}
local DownedData = {}

-- Defined below, but StopCarrying uses them first.
local pinDown
local unpin
local ActiveCarryTracks = {}
local ActiveCarriedTracks = {}
local ActiveExecuteTracks = {}

local downedThresholdPct = 0.01
local reviveTimer = 30
local reviveHpPct = 0.30
local executeRange = 5
local carryOffset = Vector3.new(2, 2, 0)

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

	-- Put the dropped body back into a downed ragdoll with no duration, so it stays on
	-- the floor. AttemptCarry already removed the old ragdoll, so the re-entrancy guard
	-- does not block this. The revive timer resumes, because it ticks only while the
	-- body has no carrier.
	RagdollManager.Ragdoll(victimChar)
	pinDown(victimChar)

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

		-- Give network ownership back to the victim, or to the server for an NPC.
		if root:CanSetNetworkOwnership() then
			local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
			if victimPlayer then
				root:SetNetworkOwner(victimPlayer)
			else
				root:SetNetworkOwner(nil)
			end
		end
	end

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

-- Holds a downed body on the floor. It runs on knockdown and again whenever something
-- may have changed the humanoid: a ragdoll teardown, a client GettingUp, or a drop.
function pinDown(char)
	local hum = char and char:FindFirstChild("Humanoid")
	if not hum then
		return
	end

	-- PIN is the top priority, so no other speed modifier can make a downed player walk.
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

-- DownedManager.ResetReviveTimer() - restart the revive timer of a downed body
-- @char: the downed character
--
-- damageCalculator calls this when a downed body is hit, so beating on a downed
-- player keeps them down.
--
-- Return: nothing.
function DownedManager.ResetReviveTimer(char)
	local data = DownedData[char]
	if not data then
		return
	end
	data.Timer = reviveTimer
end

-- DownedManager.CheckDownedCondition() - knock a player down instead of killing them
-- @char: the character about to take damage
-- @damage: the incoming damage
-- @isInstantKill: true to skip the downed state
--
-- Only players go down. A hit that would leave them at or below
-- downedThresholdPct of max HP knocks them down instead.
--
-- Return: true if this hit knocked the character down.
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
	local threshold = maxHealth * downedThresholdPct

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

-- DownedManager.KnockDown() - put a character into the downed state
-- @char: the character
--
-- Starts the revive timer. The timer pauses while the body is carried or executed.
--
-- Return: nothing.
function DownedManager.KnockDown(char)
	local player = Players:GetPlayerFromCharacter(char)
	local hum = char:FindFirstChild("Humanoid")

	-- Anyone who goes down drops what they carry. This covers every knockdown path,
	-- because damageCalculator returns early on a fresh knockdown.
	DownedManager.DropIfCarrying(char)

	-- Ragdoll first, so the body is on the floor before anything sees it as Downed. Clear
	-- any old ragdoll, or the re-entrancy guard swallows the new one.
	RagdollManager.UnRagdoll(char, true)
	RagdollManager.Ragdoll(char)

	StateHandler.SetState(char, "Downed", true)
	StateHandler.SetStun(char, true, nil, 0)
	StateHandler.SetState(char, "CantAnything", true)

	pinDown(char)

	DownedData[char] = {
		Timer = reviveTimer,
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

			-- Stop if the body is gone or dead. A downed player can die in many ways (fall
			-- damage, a mob, an AoE), and Revive must never run on a corpse.
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

-- DownedManager.Revive() - stand a downed character back up
-- @char: the character
--
-- Restores reviveHpPct of max HP. Does nothing to a dead body.
--
-- Return: nothing. Yields for one frame.
function DownedManager.Revive(char)
	local hum = char:FindFirstChild("Humanoid")

	if not char.Parent or not hum or hum.Health <= 0 then
		DownedData[char] = nil
		return
	end

	DownedData[char] = nil

	-- Clear Downed before the ragdoll teardown, so its Downed guards do not block it.
	StateHandler.RemoveStates(char, "Downed")
	StateHandler.RemoveStates(char, "CantAnything")
	StateHandler.SetStun(char, false)

	RagdollManager.UnRagdoll(char, true)
	unpin(char)

	if hum then
		-- Pop the Downed pin. The stun was already cleared, so SpeedService settles to full
		-- speed.
		SpeedService.Pop(char, "Downed")
		hum.JumpPower = 50
		hum.JumpHeight = 7.2
		hum.PlatformStand = false
		hum.AutoRotate = true

		hum.Health = hum.MaxHealth * reviveHpPct

		-- Roblox ignores GettingUp while PlatformStand is true, so request it again here,
		-- after PlatformStand is off.
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)

		-- Make the client-owned Humanoid see the ground.
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local _, y, _ = root.CFrame:ToEulerAnglesYXZ()
			FallTracker.Reset(char)
			root.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, y, 0)
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

			-- A short Sit resets the replicated state of a client stuck in Freefall.
			hum.Sit = true
			task.wait()
			hum.Sit = false
		end

		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hum:ChangeState(Enum.HumanoidStateType.Running)
		hum.Jump = true
	end
end

-- DownedManager.StopExecution() - cancel an execution
-- @executorChar: the executing character
--
-- Return: nothing.
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

-- DownedManager.AttemptExecute() - start or cancel a player's execution of a downed body
-- @executorChar: the executing character
-- @victimChar: the downed character
--
-- Calling it again during an execution cancels it. The execution kills the victim
-- after 2 seconds unless it is cancelled.
--
-- Return: nothing. Yields for 2 seconds.
function DownedManager.AttemptExecute(executorChar, victimChar)
	if not DownedData[victimChar] then
		return
	end
	if not StateHandler.GetState(victimChar, "Downed") then
		return
	end

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

	local executorRoot = executorChar:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	local executorHum = executorChar:FindFirstChild("Humanoid")
	if not executorRoot or not victimRoot or not executorHum then
		return
	end
	local dist = (executorRoot.Position - victimRoot.Position).Magnitude
	if dist > executeRange then
		return
	end

	StateHandler.SetState(executorChar, "Executing", true)
	StateHandler.SetState(victimChar, "BeingExecuted", true)
	StateHandler.SetStun(executorChar, true, 2.5, 0)

	DownedData[victimChar].BeingExecuted = true
	DownedData[victimChar].Executor = executorChar

	local anim = executorHum:LoadAnimation(script.ExecuteAnim)
	anim.Priority = Enum.AnimationPriority.Action4
	anim:Play()
	ActiveExecuteTracks[executorChar] = anim

	executorRoot.Anchored = true

	task.wait(2)

	if StateHandler.GetState(executorChar, "Executing") then
		local sound = game.ReplicatedStorage.assets.sounds.DeadSoundOLD:Clone()
		sound.Parent = executorRoot
		sound:Play()
		game.Debris:AddItem(sound, sound.TimeLength)

		local vHum = victimChar:FindFirstChild("Humanoid")
		if vHum then
			vHum.Health = 0

			DownedData[victimChar] = nil
			StateHandler.RemoveStates(victimChar, "Downed")
			StateHandler.RemoveStates(victimChar, "CantAnything")
			StateHandler.RemoveStates(victimChar, "BeingExecuted")
		end
		-- Free the executor even when the victim lost its Humanoid during the wait.
		executorRoot.Anchored = false

		if ActiveExecuteTracks[executorChar] then
			ActiveExecuteTracks[executorChar] = nil
		end
		StateHandler.RemoveStates(executorChar, "Executing")
		StateHandler.SetStun(executorChar, false)
	end
end

-- DownedManager.DropIfCarrying() - drop the body a character carries
-- @carrierChar: the character
--
-- Return: true if the character was carrying someone.
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

-- DownedManager.AttemptCarry() - pick up a downed body, or drop it
-- @carrierChar: the carrying character
-- @victimChar: the downed character
--
-- A carrier who already carries someone drops them instead.
--
-- Return: nothing.
function DownedManager.AttemptCarry(carrierChar, victimChar)
	if DownedManager.DropIfCarrying(carrierChar) then
		return
	end

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

	if not DownedData[victimChar].Carrier then
		local carrierRoot = carrierChar:FindFirstChild("HumanoidRootPart")
		local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
		if
			not carrierRoot
			or not victimRoot
			or not carrierChar:FindFirstChild("Humanoid")
			or not victimChar:FindFirstChild("Humanoid")
		then
			return
		end
		local dist = (carrierRoot.Position - victimRoot.Position).Magnitude
		if dist > executeRange then
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

		-- UnRagdoll leaves a Downed body alone unless forced. A pickup is deliberate.
		RagdollManager.UnRagdoll(victimChar, true)

		if vHum then
			vHum.PlatformStand = true
			vHum.AutoRotate = false
			vHum:ChangeState(Enum.HumanoidStateType.Physics)
		end

		FallTracker.Reset(victimChar)
		victimRoot.CFrame = carrierRoot.CFrame * CFrame.new(carryOffset) * CFrame.Angles(0, 0, 0)

		-- The carrier owns the victim's physics, so the carry does not lag.
		local carrierPlayer = Players:GetPlayerFromCharacter(carrierChar)
		if carrierPlayer and victimRoot:CanSetNetworkOwnership() then
			victimRoot:SetNetworkOwner(carrierPlayer)
		end

		local carrierAtt = Instance.new("Attachment")
		carrierAtt.Name = "CarryAtt"
		carrierAtt.CFrame = CFrame.new(carryOffset)
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
		StopCarrying(carrierChar, victimChar)
	end
end

-- DownedManager.NPCExecute() - let an NPC execute a downed body
-- @npcModel: the NPC
-- @victimChar: the downed character
--
-- Return: nothing.
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

	DownedManager.DropIfCarrying(char)

	local data = DownedData[char]
	if data and data.Carrier then
		StopCarrying(data.Carrier, char)
	end

	if ActiveExecuteTracks[char] then
		DownedManager.StopExecution(char)
	end

	if data and data.BeingExecuted and data.Executor then
		DownedManager.StopExecution(data.Executor)
	end

	DownedData[char] = nil
end)

return DownedManager
