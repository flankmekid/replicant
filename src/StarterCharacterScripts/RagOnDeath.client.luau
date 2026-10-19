-- SPDX-License-Identifier: MIT
--
-- Client side of the ragdoll: puts the local humanoid into Physics when the server
-- ragdolls it, stands it up again afterwards, applies the death push, and reports death.

local player = game.Players.LocalPlayer
local Remote = game.ReplicatedStorage.remotes:WaitForChild("Ragdoll")
local Char = player.Character or player.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local Root = Char:WaitForChild("HumanoidRootPart")

Remote.OnClientEvent:Connect(function(duration)
	if Hum.Health > 0 then
		Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		Hum:ChangeState(Enum.HumanoidStateType.Physics)
		Hum.AutoRotate = false

		-- A downed body gets no duration, so it never gets up on its own. The check in the
		-- delay covers a short ragdoll followed by a knockdown: the server cannot cancel a
		-- client task.delay, so the check runs when the timer fires.
		if duration then
			task.delay(duration, function()
				if Char:GetAttribute("Downed") then
					return
				end
				if Hum.Health <= 0 then
					return
				end
				Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				Hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
				Hum.AutoRotate = true
			end)
		end
	end
end)

game.ReplicatedStorage.remotes.RagdollForce.OnClientEvent:Connect(function()
	local Force = Instance.new("LinearVelocity", Root:FindFirstChild("ForceAttachment"))
	Force.Attachment0 = Root:FindFirstAncestor("ForceAttachment")
	Force.RelativeTo = Enum.ActuatorRelativeTo.World
	Force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	Force.MaxForce = math.huge
	Force.VectorVelocity = Root.CFrame.LookVector * 5
	Force.Enabled = true
	game.Debris:AddItem(Force, 0.1)
end)

Hum.Died:Connect(function()
	game.ReplicatedStorage.remotes.OnDeath:FireServer(Char)
end)

Char:GetAttributeChangedSignal("Ragdolled"):Connect(function()
	if not Char:GetAttribute("Ragdolled") and Hum.Health > 0 then
		Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		Hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		Hum.AutoRotate = true
	end
end)
