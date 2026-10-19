local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = script.Parent
local rootPart = character:WaitForChild("HumanoidRootPart")
local torso = character:WaitForChild("Torso")

-- Get Motors (Joints)
local rightHip = torso:WaitForChild("Right Hip")
local leftHip = torso:WaitForChild("Left Hip")

-- Store original C0 values (The default offset of the legs from the torso)
-- We need these so we can reset to a "base" state every frame before applying IK
local originRightHipC0 = rightHip.C0
local originLeftHipC0 = leftHip.C0

-- IK Settings
local RAY_LENGTH = 4 -- How far down to look for the ground
local LERP_SPEED = 0.5 -- How fast the legs react (0.1 = slow/heavy, 0.8 = snappy)
local STRIDE_OFFSET = 0.5 -- Adjusts where the ray shoots from relative to the leg center

-- Variables to store current offsets for smoothing (Linear Interpolation)
local rightLegOffset = 0
local leftLegOffset = 0
local rightLegRotation = CFrame.new()
local leftLegRotation = CFrame.new()

-- Params to ignore the character itself during raycasting
local rayParams = RaycastParams.new()
rayParams.FilterDescendantsInstances = {character}
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Function to calculate the IK for a single leg
local function solveIK(hipC0, hipPosition, currentOffset, currentRot)
	-- 1. Determine start point for the ray
	-- We want to shoot from the hip's position downwards
	local rayOrigin = hipPosition
	local rayDirection = Vector3.new(0, -RAY_LENGTH, 0)

	local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

	local targetOffset = 0
	local targetRotation = CFrame.new()

	if rayResult then
		-- 2. Calculate Distance to ground
		-- The distance from the hip to the floor
		local distanceToGround = (rayOrigin.Y - rayResult.Position.Y)

		-- R6 Legs are usually 2 studs tall (Height of Torso to floor is usually 3 studs)
		-- We calculate how much we need to move the leg up or down
		-- 3 is roughly the distance from Center Torso to Ground in R6
		local heightDiff = distanceToGround - 2 -- 2 is the length of the leg

		-- Clamp values to prevent legs stretching too far into infinity
		targetOffset = math.clamp(heightDiff, -1, 1) 

		-- 3. Calculate Surface Rotation (Optional: Makes feet tilt on slopes)
		local normal = rayResult.Normal
		local rightVector = rootPart.CFrame.RightVector
		local upVector = normal
		local backVector = -rootPart.CFrame.LookVector

		-- Create a rotation CFrame based on the surface normal
		-- We cross product the vectors to find a perpendicular rotation
		local surfaceRight = backVector:Cross(upVector).Unit
		local surfaceBack = upVector:Cross(surfaceRight).Unit

		targetRotation = CFrame.fromMatrix(Vector3.zero, surfaceRight, upVector, surfaceBack)
	end

	-- 4. Smooth out the movement (Lerp)
	local smoothedOffset = currentOffset + (targetOffset - currentOffset) * LERP_SPEED
	local smoothedRot = currentRot:Lerp(targetRotation, LERP_SPEED)

	return smoothedOffset, smoothedRot
end

RunService.RenderStepped:Connect(function()
	if not character or not character:FindFirstChild("Torso") then return end

	-- Calculate world positions of the hips for Raycasting
	-- (Torso CFrame * Hip Offset)
	local rightHipPos = (torso.CFrame * CFrame.new(0.5, -1, 0)).Position
	local leftHipPos = (torso.CFrame * CFrame.new(-0.5, -1, 0)).Position

	-- Calculate new offsets
	local rOffset, rRot = solveIK(originRightHipC0, rightHipPos, rightLegOffset, rightLegRotation)
	local lOffset, lRot = solveIK(originLeftHipC0, leftHipPos, leftLegOffset, leftLegRotation)

	-- Update stored values for next frame smoothing
	rightLegOffset = rOffset
	rightLegRotation = rRot
	leftLegOffset = lOffset
	leftLegRotation = lRot

	-- Apply changes to the Motor6D C0
	-- R6 C0 Logic: OriginalC0 * VerticalOffset * Rotation
	-- We subtract Y to move the leg down, add Y to pull it up

	rightHip.C0 = originRightHipC0 * CFrame.new(0, -rightLegOffset, 0) * rightLegRotation.Rotation
	leftHip.C0 = originLeftHipC0 * CFrame.new(0, -leftLegOffset, 0) * leftLegRotation.Rotation
end)