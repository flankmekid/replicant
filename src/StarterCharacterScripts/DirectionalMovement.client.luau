-- SPDX-License-Identifier: MIT
--
-- Tilts the R6 joints toward the move direction, relative to the root part, at up to
-- 60 updates a second. Set the script's Toggle attribute to false to return the joints
-- to rest.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Torso = Character:WaitForChild("Torso")

local RootJoint = HumanoidRootPart:WaitForChild("RootJoint")
local Neck = Torso:WaitForChild("Neck")
local RightShoulder = Torso:WaitForChild("Right Shoulder")
local LeftShoulder = Torso:WaitForChild("Left Shoulder")
local RightHip = Torso:WaitForChild("Right Hip")
local LeftHip = Torso:WaitForChild("Left Hip")

local RootJointC0 = RootJoint.C0
local NeckC0 = Neck.C0
local RightShoulderC0 = RightShoulder.C0
local LeftShoulderC0 = LeftShoulder.C0
local RightHipC0 = RightHip.C0
local LeftHipC0 = LeftHip.C0

local RootJointTilt = CFrame.new()
local NeckTilt = CFrame.new()
local RightShoulderTilt = CFrame.new()
local LeftShoulderTilt = CFrame.new()
local RightHipTilt = CFrame.new()
local LeftHipTilt = CFrame.new()

local DefaultLerpAlpha = 0.145
-- The minimum dot product between the move direction and a direction to tilt that way.
local dotThreshold = 0.9
local lastTime = 0
local tickRate = 1 / 60

local function UpdateDirectionalMovement(DeltaTime)
	local Now = workspace:GetServerTimeNow()

	if Now - lastTime >= tickRate then
		lastTime = Now

		local MoveDirection = HumanoidRootPart.CFrame:VectorToObjectSpace(Humanoid.MoveDirection)

		if MoveDirection:Dot(Vector3.new(1, 0, -1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 5, 0, math.rad(-MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt = NeckTilt:Lerp(
				CFrame.Angles(math.rad(MoveDirection.Z) * 5, 0, math.rad(MoveDirection.X) * 15),
				DefaultLerpAlpha
			)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(1, 0, 1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 5, 0, math.rad(MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt = NeckTilt:Lerp(
				CFrame.Angles(math.rad(MoveDirection.Z) * 5, 0, math.rad(-MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(-1, 0, 1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 5, 0, math.rad(MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt = NeckTilt:Lerp(
				CFrame.Angles(math.rad(MoveDirection.Z) * 5, 0, math.rad(-MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(-1, 0, -1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 5, 0, math.rad(-MoveDirection.X) * 25),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt = NeckTilt:Lerp(
				CFrame.Angles(math.rad(MoveDirection.Z) * 5, 0, math.rad(MoveDirection.X) * 15),
				DefaultLerpAlpha
			)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 10, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(0, 0, -1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 10, 0, 0),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt =
				NeckTilt:Lerp(CFrame.Angles(math.rad(MoveDirection.Z) * 10, 0, 0), DefaultLerpAlpha)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(1, 0, 0).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(0, 0, math.rad(-MoveDirection.X) * 35),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt =
				NeckTilt:Lerp(CFrame.Angles(0, 0, math.rad(MoveDirection.X) * 35), DefaultLerpAlpha)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(0, 0, 1).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(math.rad(-MoveDirection.Z) * 10, 0, 0),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt =
				NeckTilt:Lerp(CFrame.Angles(math.rad(MoveDirection.Z) * 10, 0, 0), DefaultLerpAlpha)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection:Dot(Vector3.new(-1, 0, 0).Unit) > dotThreshold then
			RootJointTilt = RootJointTilt:Lerp(
				CFrame.Angles(0, 0, math.rad(-MoveDirection.X) * 35),
				DefaultLerpAlpha
			)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt =
				NeckTilt:Lerp(CFrame.Angles(0, 0, math.rad(MoveDirection.X) * 35), DefaultLerpAlpha)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(
				CFrame.Angles(0, math.rad(-MoveDirection.X) * 15, 0),
				DefaultLerpAlpha
			)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		elseif MoveDirection == Vector3.new(0, 0, 0) or script:GetAttribute("Toggle") == false then
			RootJointTilt = RootJointTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RootJoint.C0 = RootJointC0 * RootJointTilt

			NeckTilt = NeckTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			Neck.C0 = NeckC0 * NeckTilt

			RightShoulderTilt = RightShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightShoulder.C0 = RightShoulderC0 * RightShoulderTilt

			LeftShoulderTilt = LeftShoulderTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftShoulder.C0 = LeftShoulderC0 * LeftShoulderTilt

			RightHipTilt = RightHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			RightHip.C0 = RightHipC0 * RightHipTilt

			LeftHipTilt = LeftHipTilt:Lerp(CFrame.Angles(0, 0, 0), DefaultLerpAlpha)
			LeftHip.C0 = LeftHipC0 * LeftHipTilt
		end
	end
end

RunService.Heartbeat:Connect(UpdateDirectionalMovement)
