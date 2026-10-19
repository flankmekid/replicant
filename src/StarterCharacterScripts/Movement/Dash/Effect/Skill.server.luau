-- SPDX-License-Identifier: MIT
--
-- Shows the dash effect on the character for a ground dash.

-- Each character has its own copy of this script, so a copy serves only the player of
-- its own character. An honest client fires this at most once per 0.3 s, so faster
-- requests are spam that would flood the server with effects.
local ownerChar = script:FindFirstAncestorOfClass("Model")
local minInterval = 0.25
local lastEffect = 0

script.Parent.OnServerEvent:Connect(function(plr)
	local char = plr.Character
	if char ~= ownerChar or not char:FindFirstChild("HumanoidRootPart") then
		return
	end
	local now = os.clock()
	if now - lastEffect < minInterval then
		return
	end
	lastEffect = now
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

local lastDelete = 0

script.Parent.Parent.EffectDelete.OnServerEvent:Connect(function(plr)
	local char = plr.Character
	if char ~= ownerChar or not char:FindFirstChild("HumanoidRootPart") then
		return
	end
	local now = os.clock()
	if now - lastDelete < minInterval then
		return
	end
	lastDelete = now
	if char.HumanoidRootPart:FindFirstChild("DashEffect") then
		char.HumanoidRootPart:FindFirstChild("DashEffect").Attachment.ParticleEmitter.Enabled =
			false
	end
end)
