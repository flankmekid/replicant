-- wall running

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local Root = char:WaitForChild("HumanoidRootPart")
local Head = char:WaitForChild("Head")
local animator = hum:WaitForChild("Animator")
local stateRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("stateRepl")
local StatScaling = require(ReplicatedStorage:WaitForChild("modules"):WaitForChild("StatScaling"))

-- Animation Setup
local AnimsFolder = script:WaitForChild("Anims")
local WallRunL = animator:LoadAnimation(AnimsFolder:WaitForChild("WallRunL"))
local WallRunR = animator:LoadAnimation(AnimsFolder:WaitForChild("WallRunR"))

-- CONFIGS
local WALL_RUN_DISTANCE = 3
local WALL_RUN_SPEED = 30
local WALL_RUN_Y_VELOCITY = 2
local ANGLE_TOLERANCE = 0.45 -- Strict angle
local WALL_RUN_DURATION = 3
local COOLDOWN = 0.5
local LEDGE_THRESHOLD = 2
-- Input buffer window: a space tap this many seconds BEFORE entering freefall still
-- counts as a "pressed in air" intent once freefall begins.
local BUFFER_WINDOW = 0.5
-- Max consecutive wall runs before needing to touch ground. Stamina >= 10 grants a 3rd.
local function getMaxWallRuns()
	local stam = 0
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			stam = sf.Stamina.Value
		end
	end
	return StatScaling.GetWallRunCount(stam) -- 2, or 3 at stamina >= 10
end

-- STATE
local isWallRunning = false
local wallRunBV = nil
local startTime = 0
local lastWallRunTime = 0
local wallRunCount = 0

-- INPUT STATE
local spacePressedInAir = false -- Tracks if space was pressed specifically while in freefall
-- Buffer: timestamp of a space press that happened while NOT yet in freefall. If freefall
-- begins within BUFFER_WINDOW and the key is still held, it promotes to spacePressedInAir.
local spaceBufferedAt = nil

-- VISUALS STATE
local leftTrail = nil
local rightTrail = nil

player.CharacterAdded:Connect(function(newChar)
	char = newChar
	hum = char:WaitForChild("Humanoid")
	Root = char:WaitForChild("HumanoidRootPart")
	Head = char:WaitForChild("Head")
	animator = hum:WaitForChild("Animator")
	wallRunCount = 0
	spacePressedInAir = false
	spaceBufferedAt = nil
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { char }

local function getWallRunDirection(forward, normal)
	local dir = (forward - forward:Dot(normal) * normal)
	return dir.Unit
end

local function isNearLedge(hitPart, hitPos)
	if not hitPart then
		return false
	end
	local localPos = hitPart.CFrame:PointToObjectSpace(hitPos)
	local localLedgePos = Vector3.new(localPos.X, hitPart.Size.Y / 2, localPos.Z)
	local ledgePos = hitPart.CFrame:PointToWorldSpace(localLedgePos)
	local verticalDist = math.abs(ledgePos.Y - Head.Position.Y)

	if verticalDist < LEDGE_THRESHOLD then
		return true
	end
	return false
end

-- VISUAL EFFECTS FUNCTIONS
local function createEffects()
	-- Clean up old ones just in case
	if leftTrail then
		leftTrail:Destroy()
	end
	if rightTrail then
		rightTrail:Destroy()
	end

	local dashEff = ReplicatedStorage.assets.Dash.Attachment
	local dashEffect2 = ReplicatedStorage.assets.dashEff2

	local eff = dashEffect2:Clone()
	for _, effect in pairs(eff:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			effect.Parent = char.Torso
			effect.EmissionDirection = Enum.NormalId.Back
			effect:Emit(9)
		elseif effect:IsA("Attachment") then
			effect.Parent = char.Torso
			effect:FindFirstChildWhichIsA("ParticleEmitter").EmissionDirection = Enum.NormalId.Back
			effect:FindFirstChildWhichIsA("ParticleEmitter"):Emit(9)
		end
	end

	game.Debris:AddItem(eff, 5)

	-- Left Arm Effect
	leftTrail = dashEff:Clone()
	leftTrail.Parent = char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand") -- R6/R15 Fallback
	leftTrail.Position = Vector3.new(-0.5, -1, 0)
	if leftTrail.Parent and leftTrail.Parent:FindFirstChild("LeftGripAttachment") then
		leftTrail.Trail.Attachment1 = leftTrail.Parent.LeftGripAttachment
	end

	-- Right Arm Effect
	rightTrail = dashEff:Clone()
	rightTrail.Parent = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
	rightTrail.Position = Vector3.new(0.5, -1, 0)
	if rightTrail.Parent and rightTrail.Parent:FindFirstChild("RightGripAttachment") then
		rightTrail.Trail.Attachment1 = rightTrail.Parent.RightGripAttachment
	end

	game.Debris:AddItem(leftTrail, 5)
	game.Debris:AddItem(rightTrail, 5)
end

local function removeEffects()
	if leftTrail then
		leftTrail:Destroy()
		leftTrail = nil
	end
	if rightTrail then
		rightTrail:Destroy()
		rightTrail = nil
	end
end

function startWallRun(WallHit, WallSide)
	local forward = Root.CFrame.LookVector
	local runDir = getWallRunDirection(forward, WallHit.Normal)

	-- UPDATE EXISTING RUN
	if isWallRunning and wallRunBV then
		local elapsedTime = tick() - startTime

		-- Gravity / Duration Logic
		local currentY = WALL_RUN_Y_VELOCITY
		if elapsedTime > WALL_RUN_DURATION then
			currentY = -20
			if elapsedTime > (WALL_RUN_DURATION + 0.5) then
				stopWallRun()
				return
			end
		end

		wallRunBV.Velocity =
			Vector3.new(runDir.X * WALL_RUN_SPEED, currentY, runDir.Z * WALL_RUN_SPEED)
		return
	end

	-- DEBOUNCE
	if tick() - lastWallRunTime < COOLDOWN then
		return
	end

	-- INITIALIZE NEW RUN
	isWallRunning = true
	wallRunCount = wallRunCount + 1
	startTime = tick()
	hum.AutoRotate = false
	stateRemote:FireServer("StartWallR")

	-- Trigger Visuals
	createEffects()

	if not wallRunBV then
		wallRunBV = Instance.new("BodyVelocity")
		wallRunBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		wallRunBV.P = 20000
		wallRunBV.Parent = Root
	end

	wallRunBV.Velocity =
		Vector3.new(runDir.X * WALL_RUN_SPEED, WALL_RUN_Y_VELOCITY, runDir.Z * WALL_RUN_SPEED)

	-- Animations
	if WallSide == "RightWall" then
		if not WallRunR.IsPlaying then
			WallRunR:Play(0.2)
			WallRunL:Stop(0.2)
		end
	else
		if not WallRunL.IsPlaying then
			WallRunL:Play(0.2)
			WallRunR:Stop(0.2)
		end
	end
end

function stopWallRun()
	if not isWallRunning then
		return
	end

	isWallRunning = false
	lastWallRunTime = tick()
	hum.AutoRotate = true
	stateRemote:FireServer("StopWallR")

	-- Re-arm the climb: finishing a wall run leaves you airborne and lets a SINGLE
	-- mid-air space press climb again (read + consumed by the Climbing script).
	char:SetAttribute("WallRanRecently", true)

	-- Clean Visuals
	removeEffects()

	if wallRunBV then
		wallRunBV:Destroy()
		wallRunBV = nil
	end

	WallRunR:Stop(0.2)
	WallRunL:Stop(0.2)
end

-- INPUT HANDLING
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end

	if char:GetAttribute("Stunned") then
		return
	end
	--if char:GetAttribute("CantAnything") then return end

	if input.KeyCode == Enum.KeyCode.Space then
		-- Only register valid wallrun input if we press space WHILE in the air
		if hum:GetState() == Enum.HumanoidStateType.Freefall then
			spacePressedInAir = true
		else
			-- Pressed too early (still grounded/jumping). Buffer the intent: if freefall
			-- starts within BUFFER_WINDOW and space is still held, it promotes below.
			spaceBufferedAt = os.clock()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		spacePressedInAir = false
		spaceBufferedAt = nil -- releasing space cancels any buffered tap
	end
end)

RunService.Heartbeat:Connect(function(dt)
	-- 0. Buffer promotion: a space tap made just before freefall counts once we're
	-- actually airborne (and only while the key is still held).
	if spaceBufferedAt then
		if os.clock() - spaceBufferedAt > BUFFER_WINDOW then
			spaceBufferedAt = nil
		elseif hum:GetState() == Enum.HumanoidStateType.Freefall then
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				spacePressedInAir = true
			end
			spaceBufferedAt = nil
		end
	end

	-- 1. Check Ground Status to Reset Counter
	if not isWallRunning and hum.FloorMaterial ~= Enum.Material.Air then
		wallRunCount = 0
		spacePressedInAir = false -- Reset air press if we hit ground
		spaceBufferedAt = nil
	end

	-- Raycasting
	local rightRay = Root.CFrame.RightVector * WALL_RUN_DISTANCE
	local leftRay = -Root.CFrame.RightVector * WALL_RUN_DISTANCE

	local leftWall = workspace:Raycast(Root.Position, leftRay, params)
	local rightWall = workspace:Raycast(Root.Position, rightRay, params)

	local WallHit = rightWall or leftWall
	local WallSide = if rightWall then "RightWall" else "LeftWall"

	local isHoldingSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local isFreefall = hum:GetState() == Enum.HumanoidStateType.Freefall

	-- Angle Check
	local angleCheck = false
	if WallHit then
		local dot = Root.CFrame.LookVector:Dot(WallHit.Normal)
		if math.abs(dot) < ANGLE_TOLERANCE then
			angleCheck = true
		end
	end

	-- Ledge Check
	local ledgeDetected = false
	if WallHit then
		ledgeDetected = isNearLedge(WallHit.Instance, WallHit.Position)
	end

	-- Logic Loop
	if isWallRunning then
		-- Maintain Run: As long as we hold space (even if we started it earlier)
		if WallHit and isHoldingSpace then
			startWallRun(WallHit, WallSide)
		else
			stopWallRun()
		end
	else
		-- Start Run: Requires specific "Pressed In Air" flag
		if
			WallHit
			and spacePressedInAir
			and angleCheck
			and isFreefall
			and wallRunCount < getMaxWallRuns()
		then
			startWallRun(WallHit, WallSide)
		end
	end
end)
