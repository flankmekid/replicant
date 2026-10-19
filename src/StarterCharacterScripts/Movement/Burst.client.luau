-- SPDX-License-Identifier: MIT
--
-- Client side of Burst, the universal combo breaker on T. It sends the request and
-- shows the cooldown on the HUD. The server (BurstHandler and SkillFunctions.Burst)
-- owns the cost, the cooldown, the i-frames, and the hitbox.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local modules = ReplicatedStorage:WaitForChild("modules")
local CooldownTracker = require(modules:WaitForChild("CooldownTracker"))
local BurstRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("Burst")

local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()

-- A local copy of the cooldown, so the client does not send requests the server would
-- reject. The server still decides.
local localReadyAt = 0

local function onInput(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	local char = Player.Character
	if not char then
		return
	end
	-- Not while downed. Stunned is allowed, because breaking out of a combo is the point.
	if char:GetAttribute("Downed") then
		return
	end
	if os.clock() < localReadyAt then
		return
	end
	BurstRemote:FireServer()
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		onInput(nil, Enum.UserInputState.Begin)
	end
end)

-- Show the cooldown only when the server accepted the burst.
BurstRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.Func ~= "BurstResponse" then
		return
	end
	if payload.Decision == "Accepted" and payload.Cooldown then
		localReadyAt = os.clock() + payload.Cooldown
		CooldownTracker.Register("Burst", "Burst", payload.Cooldown)
	end
end)
