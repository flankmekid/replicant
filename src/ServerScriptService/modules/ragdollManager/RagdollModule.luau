-- SPDX-License-Identifier: MIT
--
-- Turns a character's joints into ball sockets and back. Use it through
-- ragdollManager, which adds the NPC and client handling.

local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)

local Ragdoll = {}

-- RagdollModule.Ragdoll() - ragdoll a character
-- @self: the character, passed as the first argument
-- @Duration: seconds until UnRagdoll, or nil to stay ragdolled
--
-- Does nothing to a character that is already ragdolled.
--
-- Return: nothing.
function Ragdoll:Ragdoll(Duration)
	local humanoid = self:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local isDowned = self:GetAttribute("Downed")

	-- Do not stack a ragdoll on a body that is already ragdolled.
	if self:GetAttribute("Ragdolled") then
		return
	end

	if self:GetAttribute("Hyperarmor") and not self:GetAttribute("Hyperarmor") then
		return
	end

	-- A downed body's ragdoll has no duration and no stun timer, because DownedManager
	-- decides when it gets up.
	if isDowned then
		Duration = nil
		stateHandler.SetStun(self, true, nil, 0)
		stateHandler.SetState(self, "Ragdolled", true)
	else
		stateHandler.SetStun(self, true, Duration, 0)
		stateHandler.SetState(self, "Ragdolled", true, Duration)
	end

	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Replace the joints with ball sockets. ToolGrip and the root joint stay.
	for i, v in pairs(self:GetDescendants()) do
		if
			v:IsA("Motor6D")
			and v.Name ~= "ToolGrip"
			and v.Name ~= "RootJoint"
			and v.Name ~= "Root"
		then
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
			end

			Socket.Parent = v.Parent
			v.Enabled = false
		end
	end

	if Duration then
		task.delay(Duration, function()
			-- The character may be gone after the delay.
			if self and self.Parent then
				Ragdoll.UnRagdoll(self)
			end
		end)
	end
end

-- RagdollModule.UnRagdoll() - end a character's ragdoll
-- @self: the character, passed as the first argument
-- @force: true to tear down a Downed body's ragdoll (revive, execute, pickup)
--
-- Without force, a Downed body is left alone, so an unrelated timer cannot stand a
-- downed player up.
--
-- Return: nothing.
function Ragdoll:UnRagdoll(force)
	local humanoid = self:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if self:GetAttribute("Downed") and not force then
		return
	end

	stateHandler.SetStun(self, false)
	stateHandler.RemoveStates(self, "Ragdolled")

	humanoid.AutoRotate = true

	-- PlatformStand holds a body on the floor. Clear it, or the character cannot move and
	-- Roblox ignores the GettingUp below.
	humanoid.PlatformStand = false

	-- GettingUp makes the humanoid stand up safely from the floor.
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	for i, v in pairs(self:GetDescendants()) do
		if v.Name == "RagdollAttach" or v:IsA("BallSocketConstraint") then
			v:Destroy()
		elseif v:IsA("Motor6D") and v.Name ~= "ToolGrip" then
			v.Enabled = true
		end
	end
end

return Ragdoll
