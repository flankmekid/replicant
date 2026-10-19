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

local DefaultLerpAlpha = 0.145 -- Lerping Speed
local dotThreshold = 0.9 -- dotThreshold (Do not edit)
local lastTime = 0 -- Last Time (Do not edit)
local tickRate = 1 / 60 -- 60 fps limit

local function UpdateDirectionalMovement(DeltaTime)
	local Now = workspace:GetServerTimeNow() -- os.clock Instead? Idrk

	if Now - lastTime >= tickRate then
		lastTime = Now

		local MoveDirection = HumanoidRootPart.CFrame:VectorToObjectSpace(Humanoid.MoveDirection)

		if MoveDirection:Dot(Vector3.new(1, 0, -1).Unit) > dotThreshold then
			-- print("Forwards-Right")

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
			-- print("Backwards-Right")

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
			-- print("Backwards-Left")

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
			-- print("Forwards-Left")

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
			-- print("Forwards")

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
			-- print("Right")

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
			-- print("Backwards")

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
			-- print("Left")

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
