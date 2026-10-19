-- SPDX-License-Identifier: MIT
--
-- Shows the dash effect on the character for a ground dash.

script.Parent.OnServerEvent:Connect(function(plr)
	local char = plr.Character
	local Effect = game.ReplicatedStorage.effects.DashEffect:Clone()
	game.Debris:AddItem(Effect, 2)
	local Weld = Instance.new("Weld")
	Weld.Part0 = char.HumanoidRootPart
	Effect.Parent = char.HumanoidRootPart
	Weld.Parent = char.HumanoidRootPart.DashEffect
	Weld.Part1 = char.HumanoidRootPart.DashEffect
	wait(0.5)
	Effect.Attachment.ParticleEmitter.Enabled = false
	Weld:Destroy()
end)

script.Parent.Parent.EffectDelete.OnServerEvent:Connect(function(plr)
	local char = plr.Character
	if char.HumanoidRootPart:FindFirstChild("DashEffect") then
		char.HumanoidRootPart:FindFirstChild("DashEffect").Attachment.ParticleEmitter.Enabled =
			false
	end
end)
