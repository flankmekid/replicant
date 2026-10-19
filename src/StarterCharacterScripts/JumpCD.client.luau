-- SPDX-License-Identifier: MIT
--
-- Adds a cooldown between jumps by disabling the Jumping state for jumpCooldown
-- seconds after each jump.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

-- Seconds between jumps.
local jumpCooldown = 0.65

local lastJumpTime = 0

humanoid.StateChanged:Connect(function(oldState, newState)
	if newState == Enum.HumanoidStateType.Jumping then
		lastJumpTime = tick()
	end
end)

RunService.Heartbeat:Connect(function()
	local timeSinceJump = tick() - lastJumpTime

	if timeSinceJump < jumpCooldown then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)
