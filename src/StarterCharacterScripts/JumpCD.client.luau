local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

-- CONFIGURATION
local JUMP_COOLDOWN = 0.65 -- How long to wait (in seconds)

-- VARIABLES
local lastJumpTime = 0

-- 1. DETECT WHEN PLAYER JUMPS
-- Listen for the moment the player enters the "Jumping" state
humanoid.StateChanged:Connect(function(oldState, newState)
	if newState == Enum.HumanoidStateType.Jumping then
		lastJumpTime = tick()
	end
end)

-- 2. CONSTANTLY UPDATE JUMP PERMISSION
RunService.Heartbeat:Connect(function()
	local timeSinceJump = tick() - lastJumpTime

	if timeSinceJump < JUMP_COOLDOWN then
		-- If we are still in the cooldown period, force Jumping to be disabled
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		-- Once time is up, allow jumping again
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)
