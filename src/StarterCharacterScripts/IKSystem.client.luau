-- SPDX-License-Identifier: MIT
--
-- Leg IK for R6 characters: each frame, raycasts below each hip and moves and tilts the
-- leg to the ground, smoothed with a lerp.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = script.Parent
local rootPart = character:WaitForChild("HumanoidRootPart")
local torso = character:WaitForChild("Torso")

local rightHip = torso:WaitForChild("Right Hip")
local leftHip = torso:WaitForChild("Left Hip")

-- The original hip C0s. Every frame starts from these before the IK applies.
local originRightHipC0 = rightHip.C0
local originLeftHipC0 = leftHip.C0

-- How far down the ray looks for the ground, in studs.
local rayLength = 4
-- How fast the legs follow: 0.1 is slow and heavy, 0.8 is snappy.
local lerpSpeed = 0.5
local strideOffset = 0.5

-- The current offsets, for smoothing.
local rightLegOffset = 0
local leftLegOffset = 0
local rightLegRotation = CFrame.new()
local leftLegRotation = CFrame.new()

local rayParams = RaycastParams.new()
rayParams.FilterDescendantsInstances = { character }
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Returns the smoothed vertical offset and rotation of one leg.
local function solveIK(hipC0, hipPosition, currentOffset, currentRot)
	local rayOrigin = hipPosition
	local rayDirection = Vector3.new(0, -rayLength, 0)

	local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

	local targetOffset = 0
	local targetRotation = CFrame.new()

	if rayResult then
		local distanceToGround = (rayOrigin.Y - rayResult.Position.Y)

		-- An R6 leg is 2 studs long.
		local heightDiff = distanceToGround - 2

		-- Clamp, so a leg never stretches too far.
		targetOffset = math.clamp(heightDiff, -1, 1)

		-- Tilt the foot to the slope.
		local normal = rayResult.Normal
		local rightVector = rootPart.CFrame.RightVector
		local upVector = normal
		local backVector = -rootPart.CFrame.LookVector

		local surfaceRight = backVector:Cross(upVector).Unit
		local surfaceBack = upVector:Cross(surfaceRight).Unit

		targetRotation = CFrame.fromMatrix(Vector3.zero, surfaceRight, upVector, surfaceBack)
	end

	local smoothedOffset = currentOffset + (targetOffset - currentOffset) * lerpSpeed
	local smoothedRot = currentRot:Lerp(targetRotation, lerpSpeed)

	return smoothedOffset, smoothedRot
end

RunService.RenderStepped:Connect(function()
	if not character or not character:FindFirstChild("Torso") then
		return
	end

	local rightHipPos = (torso.CFrame * CFrame.new(0.5, -1, 0)).Position
	local leftHipPos = (torso.CFrame * CFrame.new(-0.5, -1, 0)).Position

	local rOffset, rRot = solveIK(originRightHipC0, rightHipPos, rightLegOffset, rightLegRotation)
	local lOffset, lRot = solveIK(originLeftHipC0, leftHipPos, leftLegOffset, leftLegRotation)

	rightLegOffset = rOffset
	rightLegRotation = rRot
	leftLegOffset = lOffset
	leftLegRotation = lRot

	-- C0 = original C0 * vertical offset * rotation. A negative Y moves the leg down.
	rightHip.C0 = originRightHipC0 * CFrame.new(0, -rightLegOffset, 0) * rightLegRotation.Rotation
	leftHip.C0 = originLeftHipC0 * CFrame.new(0, -leftLegOffset, 0) * leftLegRotation.Rotation
end)
