local stateHandler = require(game.ReplicatedStorage.modules.stateHandler) 

local Ragdoll = {}

function Ragdoll:Ragdoll(Duration)
	-- Ensure we have a humanoid to work with
	local humanoid = self:FindFirstChild("Humanoid")
	if not humanoid then return end

	local isDowned = self:GetAttribute("Downed")

	-- Re-entrancy guard. The old code bailed on "Downed" here, which was wrong:
	-- DownedManager.KnockDown sets Downed BEFORE calling Ragdoll, so this guard
	-- fired every single time and the knockdown ragdoll never ran at all. The
	-- actual intent was "don't stack ragdolls on an already-ragdolled body", so
	-- guard on Ragdolled instead.
	if self:GetAttribute("Ragdolled") then return end

	-- 1. Check Hyperarmor
	if self:GetAttribute("Hyperarmor") and not self:GetAttribute("Hyperarmor") then 
		return 
	end

	-- 2. Apply Stun States.
	-- A Downed body's ragdoll has NO duration and NO stun timer. DownedManager
	-- owns the whole lifecycle (Revive / Execute / Carry decide when they get up).
	-- Letting a stun timer expire here used to clear Stunned, which under the old
	-- stateHandler dropped the entire state table and silently un-Downed them:
	-- that is how a downed player could stand up and move mid-ragdoll.
	if isDowned then
		Duration = nil
		stateHandler.SetStun(self, true, nil, 0)
		stateHandler.SetState(self, "Ragdolled", true)
	else
		stateHandler.SetStun(self, true, Duration, 0)
		stateHandler.SetState(self, "Ragdolled", true, Duration)
	end

	-- 3. Humanoid Physics Setup (Crucial for preventing tweaking)
	humanoid.AutoRotate = false -- Stop them from spinning on floor
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Stop them from trying to stand up
	-- Optional: If they float, enable PlatformStand instead
	-- humanoid.PlatformStand = true 

	-- 4. Convert Joints to Constraints
	for i, v in pairs(self:GetDescendants()) do
		if v:IsA("Motor6D") and v.Name ~= "ToolGrip" and v.Name ~= "RootJoint" and v.Name ~= "Root" then
			local Attachment1 = Instance.new("Attachment")
			Attachment1.Name = "RagdollAttach"
			local Attachment2 = Instance.new("Attachment")
			Attachment2.Name = "RagdollAttach"

			Attachment1.CFrame = v.C0
			Attachment2.CFrame = v.C1
			Attachment1.Parent = v.Part0
			Attachment2.Parent = v.Part1

			local Socket = Instance.new("BallSocketConstraint")
			Socket.Attachment0 = Attachment1
			Socket.Attachment1 = Attachment2
			Socket.LimitsEnabled = true
			Socket.TwistLimitsEnabled = true
			Socket.MaxFrictionTorque = 30
			Socket.Restitution = 0.5

			if v.Name == "Right Shoulder" or v.Name == "Left Shoulder" then
				-- Socket.TwistUpperAngle = -30
			end

			Socket.Parent = v.Parent
			v.Enabled = false
		end
	end

	-- 5. Schedule Unragdoll (MOVED OUTSIDE THE LOOP)
	if Duration then
		task.delay(Duration, function()
			-- We check if self still exists to prevent errors if NPC died/despawned
			if self and self.Parent then 
				Ragdoll.UnRagdoll(self)
			end
		end)
	end
end

-- force = true lets DownedManager tear the ragdoll down deliberately (revive,
-- execute, pickup). Without it, an UnRagdoll fired by an unrelated expiring timer
-- would stand a downed player back up.
function Ragdoll:UnRagdoll(force)
	local humanoid = self:FindFirstChild("Humanoid")
	if not humanoid then return end

	if self:GetAttribute("Downed") and not force then return end

	stateHandler.SetStun(self, false)
	stateHandler.RemoveStates(self, "Ragdolled")

	-- 1. Reset Humanoid Properties
	humanoid.AutoRotate = true

	-- PlatformStand is what actually holds a body on the floor. Leaving it set here
	-- meant UnRagdoll tore down the constraints and re-enabled the Motor6Ds but left
	-- the humanoid platform-standing, so the character could act but not move: the
	-- exact "revived but still ragdolled" symptom. It also made the ChangeState below
	-- a no-op, because Roblox ignores GettingUp while PlatformStand is true.
	humanoid.PlatformStand = false

	-- 2. Force the "GettingUp" state
	-- This is the magic line that fixes the tweaking. 
	-- It tells Roblox "I am on the floor, help me stand up safely."
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	-- 3. Restore Joints
	for i, v in pairs(self:GetDescendants()) do
		if v.Name == "RagdollAttach" or v:IsA("BallSocketConstraint") then
			v:Destroy()
		elseif v:IsA("Motor6D") and v.Name ~= "ToolGrip" then
			v.Enabled = true
		end
	end
end

return Ragdoll