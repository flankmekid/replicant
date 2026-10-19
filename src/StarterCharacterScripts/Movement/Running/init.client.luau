-- sprinting

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local camera = game.Workspace.CurrentCamera

-- // FOV CONFIGURATION //
local BaseFOV = 80 
local SprintFOV = 85 
local FOVTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local rs = game:GetService("ReplicatedStorage")
local stateHandler = require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("stateHandler"))
local StatScaling = require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("StatScaling"))

-- Canonical base walk speed (16 + stamina bonus). Used for both the stop-sprint
-- speed and the sprint floor so the stamina walkspeed bonus flows through.
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
-- We don't define 'Normal' here anymore as a static variable
local accelerationTime = 0.5 -- base; overridden per-sprint by stamina (see getAccelerationTime)

-- Stamina lowers momentum build-up time: 0.5s at 0 stamina down to ~0.25s,
-- with most of the gain by the velocity soft cap (level 20), continuing slightly to 50.
local FAST_ACCEL = 0.25
local function getAccelerationTime()
	local stam = 0
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then stam = sf.Stamina.Value end
	end
	local progress = StatScaling.GetVelocityProgress(stam) -- 0..1, soft-capped at 20
	return 0.5 - (0.5 - FAST_ACCEL) * progress
end

-- Bobbing & Particle Variables
local bobbingSpeed = 12
local bobbingIntensity = 0.3
local bobTick = 0
local leftParticle, rightParticle = nil, nil
local particlesSpawned = false

local function cleanupParticles()
	if leftParticle then leftParticle:Destroy(); leftParticle = nil end
	if rightParticle then rightParticle:Destroy(); rightParticle = nil end
	particlesSpawned = false
end

local function stopSprint()
	LastTapped = false
	-- Only restore the client-owned sprint boost back to base when NO server-owned
	-- speed modifier is active. The server (SpeedService) authoritatively pins speed
	-- for block/stun/downed/skill states and replicates it via these attributes; if we
	-- blindly wrote getBaseSpeed() here we'd stomp that pin locally. The classic case:
	-- sprint -> block. The RenderStepped loop calls stopSprint() on seeing Blocking, and
	-- the old base-speed write left the player walking at full speed while blocking.
	if not char:GetAttribute("Blocking")
		and not char:GetAttribute("Stunned")
		and not char:GetAttribute("Downed")
		and not char:GetAttribute("CantAnything") then
		hum.WalkSpeed = getBaseSpeed()
	end
	stateHandler.SetState(char, "Running", false, 999999999)

	if Track1 then Track1:Stop() end
	if conn then conn:Disconnect() end

	cleanupParticles() 

	-- // TWEEN CAMERA BACK TO NORMAL //
	TweenService:Create(hum, TweenInfo.new(0.3), {CameraOffset = Vector3.new(0, 0, 0)}):Play()
	TweenService:Create(camera, FOVTweenInfo, {FieldOfView = BaseFOV}):Play()
end

UIS.InputBegan:Connect(function(input, isTyping)
	if isTyping then return end
	if input.KeyCode == Enum.KeyCode.W and hum.WalkSpeed ~= 0 then
		if char:GetAttribute("CantAnything") and not char:GetAttribute("Carrying") then return end
		if char:GetAttribute("Blocking") then return end
		if char:GetAttribute("Stunned") then return end 
		if char:GetAttribute("Carried") and not char:GetAttribute("Carrying") then return end 

		if Tapped == false then
			Tapped = true
		else
			-- // START SPRINT //
			stateHandler.SetState(char, "Running", true, 999999999)
			LastTapped = true
			Tapped = false

			-- // TWEEN CAMERA TO SPRINT FOV //
			TweenService:Create(camera, FOVTweenInfo, {FieldOfView = SprintFOV}):Play()

			Track1 = hum:LoadAnimation(script.Regular)
			Track1.Priority = Enum.AnimationPriority.Movement
			Track1:Play(0.25)

			local sprintTimer = 0 
			local thisAccelTime = getAccelerationTime() -- stamina-scaled momentum build-up

			-- We removed the static calculation of "Normal" here.

			conn = RunService.RenderStepped:Connect(function(dt)
				if hum.MoveDirection.Magnitude > 0 then

					if char:GetAttribute("CantAnything") then stopSprint() return end
					if char:GetAttribute("Blocking") then stopSprint() return end
					if char:GetAttribute("Stunned") then stopSprint() return end 
					if char:GetAttribute("Downed") then stopSprint() return end 

					-- // DYNAMIC SPEED CHECK //
					-- NEW: Calculate health multiplier dynamically every frame
					local hpPercentage = hum.Health / hum.MaxHealth
					local healthMultiplier = ((hpPercentage <= 0.7) and 0.9)  or ((hpPercentage <= 0.5) and 0.85) or ((hpPercentage <= 0.3) and 0.75) or 1

					-- Apply the health multiplier to whatever the max speed is.
					-- Sprint cap builds on the canonical base (so stamina bonus carries through).
					local baseNow = getBaseSpeed()
					local CurrentMaxSpeed = (baseNow * 1.75) * healthMultiplier
					if char:GetAttribute("MoveSpeedBuff") == true then
						CurrentMaxSpeed = (baseNow * 2.25) * healthMultiplier
					end

					-- 1. MOMENTUM CALCULATION
					sprintTimer = math.min(sprintTimer + dt, thisAccelTime)
					local alpha = sprintTimer / thisAccelTime -- Progress: 0 to 1

					-- Walkspeed scales from Walk to the DYNAMIC CurrentMaxSpeed
					hum.WalkSpeed = baseNow + ((CurrentMaxSpeed - baseNow) * alpha)

					-- 2. ANIMATION SPEED LOGIC 
					if airborneStates[hum:GetState()] then
						Track1:AdjustSpeed(0.25)
					else
						local animSpeed = 0.5 + (0.5 * alpha)
						Track1:AdjustSpeed(animSpeed)
					end

					-- 3. PARTICLE LOGIC
					if alpha >= 1 and not particlesSpawned then
						particlesSpawned = true
						local dashEff = rs.assets.Dash.Attachment

						-- Left Arm Particles
						leftParticle = dashEff:Clone()
						leftParticle.Parent = char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand")
						leftParticle.Position = Vector3.new(-.5,-1,0)
						if leftParticle.Parent:FindFirstChild("LeftGripAttachment") then
							leftParticle.Trail.Attachment1 = leftParticle.Parent.LeftGripAttachment
						end

						-- Right Arm Particles
						rightParticle = dashEff:Clone()
						rightParticle.Parent = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
						rightParticle.Position = Vector3.new(.5,-1,0)
						if rightParticle.Parent:FindFirstChild("RightGripAttachment") then
							rightParticle.Trail.Attachment1 = rightParticle.Parent.RightGripAttachment
						end
					end

					-- 4. CAMERA BOBBING
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

		delay(.3, function()
			if Tapped then Tapped = false end
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