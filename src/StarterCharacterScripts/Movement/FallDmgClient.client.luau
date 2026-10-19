-- SPDX-License-Identifier: MIT
--
-- Measures falls on the client and reports them to the server, which applies the fall
-- damage. Pressing Ctrl just before landing rolls, which reduces the damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Seconds before landing in which a Ctrl press counts as a roll.
local ROLL_WINDOW = 0.2
-- TODO: Replace the placeholder roll animation.
local ANIMATION_ID = "rbxassetid://78977275276675"

local fallEvent = ReplicatedStorage.remotes:WaitForChild("FallDmg")

local lastCtrlPress = 0
local isFalling = false
local fallStartY = 0

local rollAnimation = Instance.new("Animation")
rollAnimation.AnimationId = ANIMATION_ID
local rollTrack = humanoid:LoadAnimation(rollAnimation)
rollTrack.Priority = Enum.AnimationPriority.Action4

local camera = game.Workspace.CurrentCamera

local TS = game:GetService("TweenService")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		lastCtrlPress = tick()
	end
end)

humanoid.StateChanged:Connect(function(oldState, newState)
	if newState == Enum.HumanoidStateType.Freefall then
		isFalling = true
		fallStartY = rootPart.Position.Y
	elseif newState == Enum.HumanoidStateType.Landed then
		if isFalling then
			isFalling = false
			local originalFOV = camera.FieldOfView
			local landY = rootPart.Position.Y
			local fallDistance = fallStartY - landY

			local timeSincePress = tick() - lastCtrlPress
			local successfulRoll = timeSincePress <= ROLL_WINDOW

			-- Roll only after a fall of more than 30 studs.
			if successfulRoll and fallDistance > 30 then
				rollTrack:Play()
				TS:Create(
					camera,
					TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true),
					{ FieldOfView = 90 }
				):Play()

				local sound = Instance.new("Sound")
				sound.SoundId = "rbxassetid://104298925753512"
				sound.Parent = workspace
				sound.Volume = 0.5
				sound:Play()
				game.Debris:AddItem(sound, 1.2)
			end

			-- Not in the menu, where HasPressedPlay is false.
			if player:GetAttribute("HasPressedPlay") then
				fallEvent:FireServer(fallDistance, successfulRoll)
			end
		end
	end
end)
