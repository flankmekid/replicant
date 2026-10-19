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

		-- The server sends duration = nil for a Downed body, so no self-recovery
		-- gets scheduled at all. The re-check inside the delay covers the other
		-- case: a normal 2s ragdoll (Messatsu, a heavy hit) that lands first and
		-- is then followed by a knockdown inside the window. Without it, this
		-- timer would fire ChangeState(GettingUp) on a downed player and stand
		-- them up. The server cannot cancel a task.delay living on the client, so
		-- the check has to happen here, at fire time, not at schedule time.
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
