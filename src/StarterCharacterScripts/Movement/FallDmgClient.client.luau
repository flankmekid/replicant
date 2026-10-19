-- LocalScript in StarterCharacterScripts
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Configuration
local ROLL_WINDOW = 0.2 -- Time in seconds player has to press Ctrl before landing
local ANIMATION_ID = "rbxassetid://78977275276675" -- REPLACE THIS

-- Services & Events
local fallEvent = ReplicatedStorage.remotes:WaitForChild("FallDmg")

-- State Variables
local lastCtrlPress = 0
local isFalling = false
local fallStartY = 0

-- Setup Animation
local rollAnimation = Instance.new("Animation")
rollAnimation.AnimationId = ANIMATION_ID
local rollTrack = humanoid:LoadAnimation(rollAnimation)
rollTrack.Priority = Enum.AnimationPriority.Action4

local camera = game.Workspace.CurrentCamera

local TS = game:GetService("TweenService")

-- 1. Detect Input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftControl then
		-- Record the timestamp when Ctrl was pressed
		lastCtrlPress = tick()
	end
end)

-- 2. Detect Falling State
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
			
			-- Check if the player pressed Ctrl recently (within the window)
			local timeSincePress = tick() - lastCtrlPress
			local successfulRoll = timeSincePress <= ROLL_WINDOW
			
			-- Visuals and Animation
			if successfulRoll and fallDistance > 30 then -- Only roll if fall was significant
				rollTrack:Play()
				TS:Create(camera, TweenInfo.new(.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), {FieldOfView = 90}):Play()
				
				-- Optional: Add a "woosh" sound effect here
				local sound = Instance.new("Sound")
				sound.SoundId = "rbxassetid://104298925753512" -- Wind woosh ID
				sound.Parent = workspace
				sound.Volume = 0.5
				sound:Play()
				game.Debris:AddItem(sound, 1.2)
			end

			-- Tell the server we landed, how far we fell, and if we rolled
			if player:GetAttribute("HasPressedPlay") then
				fallEvent:FireServer(fallDistance, successfulRoll)
			end
		end
	end
end)