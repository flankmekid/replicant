-- SPDX-License-Identifier: MIT
--
-- Sprint on double-tap W: builds speed up to 1.75x the base WalkSpeed (faster with
-- Stamina), slows at low HP, and adds the sprint FOV, camera bob, and arm trails.

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local camera = game.Workspace.CurrentCamera

local BaseFOV = 80
local SprintFOV = 85
local FOVTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local rs = game:GetService("ReplicatedStorage")
local stateHandler =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("stateHandler"))
local StatScaling =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("StatScaling"))

-- The base WalkSpeed with the Stamina bonus. Walking and sprinting both build on it.
local function getBaseSpeed()
	return StatScaling.GetBaseWalkSpeed(char)
end

local conn
local airborneStates = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local LastTapped, Tapped = false, false
local NotRun = 16
-- The default momentum build-up time. Each sprint uses getAccelerationTime.
local accelerationTime = 0.5

-- Stamina lowers the momentum build-up time from 0.5 seconds to about 0.25, mostly by
-- level 20 and a little more up to 50.
local fastAccel = 0.25
local function getAccelerationTime()
	local stam = 0
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			stam = sf.Stamina.Value
		end
	end
	local progress = StatScaling.GetVelocityProgress(stam)
	return 0.5 - (0.5 - fastAccel) * progress
end

local bobbingSpeed = 12
local bobbingIntensity = 0.3
local bobTick = 0
local leftParticle, rightParticle = nil, nil
local particlesSpawned = false

local function cleanupParticles()
	if leftParticle then
		leftParticle:Destroy()
		leftParticle = nil
	end
	if rightParticle then
		rightParticle:Destroy()
		rightParticle = nil
	end
	particlesSpawned = false
end

local function stopSprint()
	LastTapped = false
	-- Restore the base speed only when no server speed modifier is active. The server
	-- (SpeedService) pins the speed during block, stun, downed, and skill states, and
	-- writing the base speed here would undo the pin, for example while blocking.
	if
		not char:GetAttribute("Blocking")
		and not char:GetAttribute("Stunned")
		and not char:GetAttribute("Downed")
		and not char:GetAttribute("CantAnything")
	then
		hum.WalkSpeed = getBaseSpeed()
	end
	stateHandler.SetState(char, "Running", false, 999999999)

	if Track1 then
		Track1:Stop()
	end
	if conn then
		conn:Disconnect()
	end

	cleanupParticles()

	TweenService:Create(hum, TweenInfo.new(0.3), { CameraOffset = Vector3.new(0, 0, 0) }):Play()
	TweenService:Create(camera, FOVTweenInfo, { FieldOfView = BaseFOV }):Play()
end

UIS.InputBegan:Connect(function(input, isTyping)
	if isTyping then
		return
	end
	if input.KeyCode == Enum.KeyCode.W and hum.WalkSpeed ~= 0 then
		if char:GetAttribute("CantAnything") and not char:GetAttribute("Carrying") then
			return
		end
		if char:GetAttribute("Blocking") then
			return
		end
		if char:GetAttribute("Stunned") then
			return
		end
		if char:GetAttribute("Carried") and not char:GetAttribute("Carrying") then
			return
		end

		if Tapped == false then
			Tapped = true
		else
			stateHandler.SetState(char, "Running", true, 999999999)
			LastTapped = true
			Tapped = false

			TweenService:Create(camera, FOVTweenInfo, { FieldOfView = SprintFOV }):Play()

			Track1 = hum:LoadAnimation(script.Regular)
			Track1.Priority = Enum.AnimationPriority.Movement
			Track1:Play(0.25)

			local sprintTimer = 0
			local thisAccelTime = getAccelerationTime()

			conn = RunService.RenderStepped:Connect(function(dt)
				if hum.MoveDirection.Magnitude > 0 then
					if char:GetAttribute("CantAnything") then
						stopSprint()
						return
					end
					if char:GetAttribute("Blocking") then
						stopSprint()
						return
					end
					if char:GetAttribute("Stunned") then
						stopSprint()
						return
					end
					if char:GetAttribute("Downed") then
						stopSprint()
						return
					end

					-- The sprint slows at low HP.
					local hpPercentage = hum.Health / hum.MaxHealth
					local healthMultiplier = ((hpPercentage <= 0.7) and 0.9)
						or ((hpPercentage <= 0.5) and 0.85)
						or ((hpPercentage <= 0.3) and 0.75)
						or 1

					local baseNow = getBaseSpeed()
					local CurrentMaxSpeed = (baseNow * 1.75) * healthMultiplier
					if char:GetAttribute("MoveSpeedBuff") == true then
						CurrentMaxSpeed = (baseNow * 2.25) * healthMultiplier
					end

					sprintTimer = math.min(sprintTimer + dt, thisAccelTime)
					local alpha = sprintTimer / thisAccelTime

					hum.WalkSpeed = baseNow + ((CurrentMaxSpeed - baseNow) * alpha)

					if airborneStates[hum:GetState()] then
						Track1:AdjustSpeed(0.25)
					else
						local animSpeed = 0.5 + (0.5 * alpha)
						Track1:AdjustSpeed(animSpeed)
					end

					-- Show the arm trails at full speed.
					if alpha >= 1 and not particlesSpawned then
						particlesSpawned = true
						local dashEff = rs.assets.Dash.Attachment

						leftParticle = dashEff:Clone()
						leftParticle.Parent = char:FindFirstChild("Left Arm")
							or char:FindFirstChild("LeftHand")
						leftParticle.Position = Vector3.new(-0.5, -1, 0)
						if leftParticle.Parent:FindFirstChild("LeftGripAttachment") then
							leftParticle.Trail.Attachment1 = leftParticle.Parent.LeftGripAttachment
						end

						rightParticle = dashEff:Clone()
						rightParticle.Parent = char:FindFirstChild("Right Arm")
							or char:FindFirstChild("RightHand")
						rightParticle.Position = Vector3.new(0.5, -1, 0)
						if rightParticle.Parent:FindFirstChild("RightGripAttachment") then
							rightParticle.Trail.Attachment1 =
								rightParticle.Parent.RightGripAttachment
						end
					end

					bobTick = bobTick + dt * bobbingSpeed
					local currentIntensity = bobbingIntensity * alpha
					local x = math.cos(bobTick * 0.5) * currentIntensity
					local y = math.abs(math.sin(bobTick)) * currentIntensity
					hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.new(x, y, 0), 0.1)
				else
					stopSprint()
				end
			end)
		end

		delay(0.3, function()
			if Tapped then
				Tapped = false
			end
		end)
	end
end)

UIS.InputEnded:Connect(function(input, isTyping)
	if input.KeyCode == Enum.KeyCode.W and LastTapped and not Tapped then
		stopSprint()
	end
end)

char:GetAttributeChangedSignal("Stunned"):Connect(function()
	if char:GetAttribute("Stunned") then
		stopSprint()
	end
end)
