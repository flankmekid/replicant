-- SPDX-License-Identifier: MIT
--
-- Wall running: a space press in the air next to a wall runs along it while space is
-- held. Two wall runs are allowed before the player touches the ground, three with
-- Stamina 10. Ending a wall run arms the climb.

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

local AnimsFolder = script:WaitForChild("Anims")
local WallRunL = animator:LoadAnimation(AnimsFolder:WaitForChild("WallRunL"))
local WallRunR = animator:LoadAnimation(AnimsFolder:WaitForChild("WallRunR"))

local wallRunDistance = 3
local wallRunSpeed = 30
local wallRunYVelocity = 2
-- The wall must be nearly parallel to the facing direction.
local angleTolerance = 0.45
local wallRunDuration = 3
local COOLDOWN = 0.5
local ledgeThreshold = 2
-- A space press this many seconds before freefall still counts as a press in the air.
local bufferWindow = 0.5
-- The wall runs allowed before the player touches the ground.
local function getMaxWallRuns()
	local stam = 0
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			stam = sf.Stamina.Value
		end
	end
	return StatScaling.GetWallRunCount(stam)
end

local isWallRunning = false
local wallRunBV = nil
local startTime = 0
local lastWallRunTime = 0
local wallRunCount = 0

-- True when space was pressed while in freefall.
local spacePressedInAir = false
-- The time of a space press before freefall. If freefall starts within bufferWindow
-- and space is still held, it becomes a press in the air.
local spaceBufferedAt = nil

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

	if verticalDist < ledgeThreshold then
		return true
	end
	return false
end

local function createEffects()
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

	leftTrail = dashEff:Clone()
	leftTrail.Parent = char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand")
	leftTrail.Position = Vector3.new(-0.5, -1, 0)
	if leftTrail.Parent and leftTrail.Parent:FindFirstChild("LeftGripAttachment") then
		leftTrail.Trail.Attachment1 = leftTrail.Parent.LeftGripAttachment
	end

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

	-- Already running: update the direction, and fall off after wallRunDuration.
	if isWallRunning and wallRunBV then
		local elapsedTime = tick() - startTime

		local currentY = wallRunYVelocity
		if elapsedTime > wallRunDuration then
			currentY = -20
			if elapsedTime > (wallRunDuration + 0.5) then
				stopWallRun()
				return
			end
		end

		wallRunBV.Velocity = Vector3.new(runDir.X * wallRunSpeed, currentY, runDir.Z * wallRunSpeed)
		return
	end

	if tick() - lastWallRunTime < COOLDOWN then
		return
	end

	isWallRunning = true
	wallRunCount = wallRunCount + 1
	startTime = tick()
	hum.AutoRotate = false
	stateRemote:FireServer("StartWallR")

	createEffects()

	if not wallRunBV then
		wallRunBV = Instance.new("BodyVelocity")
		wallRunBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		wallRunBV.P = 20000
		wallRunBV.Parent = Root
	end

	wallRunBV.Velocity =
		Vector3.new(runDir.X * wallRunSpeed, wallRunYVelocity, runDir.Z * wallRunSpeed)

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

	-- Arm the climb: after a wall run, one press in the air climbs. The Climbing script
	-- reads and clears this.
	char:SetAttribute("WallRanRecently", true)

	removeEffects()

	if wallRunBV then
		wallRunBV:Destroy()
		wallRunBV = nil
	end

	WallRunR:Stop(0.2)
	WallRunL:Stop(0.2)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end

	if char:GetAttribute("Stunned") then
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		-- A wall run starts only from a press in the air.
		if hum:GetState() == Enum.HumanoidStateType.Freefall then
			spacePressedInAir = true
		else
			-- Pressed before freefall: buffer it.
			spaceBufferedAt = os.clock()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		spacePressedInAir = false
		spaceBufferedAt = nil
	end
end)

RunService.Heartbeat:Connect(function(dt)
	-- A buffered press counts once the player is in freefall, if space is still held.
	if spaceBufferedAt then
		if os.clock() - spaceBufferedAt > bufferWindow then
			spaceBufferedAt = nil
		elseif hum:GetState() == Enum.HumanoidStateType.Freefall then
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				spacePressedInAir = true
			end
			spaceBufferedAt = nil
		end
	end

	-- Touching the ground resets the wall run count and the press.
	if not isWallRunning and hum.FloorMaterial ~= Enum.Material.Air then
		wallRunCount = 0
		spacePressedInAir = false
		spaceBufferedAt = nil
	end

	local rightRay = Root.CFrame.RightVector * wallRunDistance
	local leftRay = -Root.CFrame.RightVector * wallRunDistance

	local leftWall = workspace:Raycast(Root.Position, leftRay, params)
	local rightWall = workspace:Raycast(Root.Position, rightRay, params)

	local WallHit = rightWall or leftWall
	local WallSide = if rightWall then "RightWall" else "LeftWall"

	local isHoldingSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local isFreefall = hum:GetState() == Enum.HumanoidStateType.Freefall

	local angleCheck = false
	if WallHit then
		local dot = Root.CFrame.LookVector:Dot(WallHit.Normal)
		if math.abs(dot) < angleTolerance then
			angleCheck = true
		end
	end

	local ledgeDetected = false
	if WallHit then
		ledgeDetected = isNearLedge(WallHit.Instance, WallHit.Position)
	end

	if isWallRunning then
		-- Keep running while a wall is there and space is held.
		if WallHit and isHoldingSpace then
			startWallRun(WallHit, WallSide)
		else
			stopWallRun()
		end
	else
		-- Start only from a press in the air.
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
