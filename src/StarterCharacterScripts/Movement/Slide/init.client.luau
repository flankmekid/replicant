-- SPDX-License-Identifier: MIT
--
-- The slide: a velocity along the ground that slows on flat ground and uphill and
-- speeds up downhill, up to the race SlideDuration multiplier. Space cancels the slide,
-- and a cancel inside the slide-jump window gives a bigger leap.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local animationHandler = require(game.ReplicatedStorage.modules.animationHandler)

local Plr = game.Players.LocalPlayer
local Char = Plr.Character
if not Char then
	repeat
		wait()
	until Char
end
local RootPart = Char:FindFirstChild("HumanoidRootPart")
local Humanoid = Char:FindFirstChildOfClass("Humanoid")
local SlideAnim = Humanoid:LoadAnimation(script:WaitForChild("Anim"))
local stateRemote = game:GetService("ReplicatedStorage").remotes.stateRepl

local isSliding = false
local CanSlide = true
local PosCheck
local CurrentMultiplier = 1
local BaseSoundVolume = script.Slide_Loop.Volume
local slideStartTime = 0

local slidingAnimID = "rbxassetid://136848049831912"

local SlideVelocity
local AlignGyro

local raceConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("modules").RaceConfig)

local Settings = {
	Cooldown = 0.1,
	BaseSpeed = 55,
	HipHeight = {
		Normal = 0,
		Slide = -2,
	},
	MaxMultiplier = 2, -- The race SlideDuration replaces this.
	SpeedChangeRate = {
		Forward = 1,
		Upward = 2,
		Downward = 1,
	},
	PushOnCancel = true,
	PushVelocity = {
		Forward = 50,
		Up = 50,
	},
	SlideJump = {
		WindowStart = 0.25,
		WindowEnd = 0.6,
		BoostForward = 120,
		BoostUp = 70,
	},
}

local debounce = false
local cdTime = 3

local Params = RaycastParams.new()
Params.FilterDescendantsInstances = { Char }
Params.FilterType = Enum.RaycastFilterType.Exclude

function StopSlide()
	task.delay(0.25, function()
		stateRemote:FireServer("SlideOff")
	end)
	isSliding = false
	if PosCheck then
		PosCheck:Disconnect()
	end
	if SlideVelocity then
		SlideVelocity:Destroy()
	end
	if AlignGyro then
		AlignGyro:Destroy()
	end
	animationHandler.StopAnim(Char, "Sliding", slidingAnimID)
	script.Slide_Loop:Stop()
	Humanoid.HipHeight = Settings.HipHeight.Normal

	task.delay(Settings.Cooldown, function()
		CanSlide = true
	end)
end

-- The M1 uppercut fires this to end the slide before its own launch. The event is a
-- BindableEvent, so the slide velocity is gone before the uppercut mover starts.
game:GetService("ReplicatedStorage"):WaitForChild("UppercutStopSlide").Event:Connect(function()
	if isSliding then
		StopSlide()
	end
end)

UserInputService.InputBegan:Connect(function(Input, istyping)
	if istyping then
		return
	end
	if
		Input.KeyCode == Enum.KeyCode.LeftControl
		and debounce == false
		and UserInputService:IsKeyDown(Enum.KeyCode.W)
		and Char.Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
		and Char.Humanoid:GetState() ~= Enum.HumanoidStateType.Landed
		and Char.Humanoid.WalkSpeed > 18
	then
		if Char:GetAttribute("CantAnything") then
			return
		end
		if Char:GetAttribute("Blocking") then
			return
		end
		if Char:GetAttribute("Stunned") then
			return
		end
		if Char:GetAttribute("M1") then
			return
		end
		if Char:GetAttribute("M2") then
			return
		end
		if Char:GetAttribute("Carried") then
			return
		end
		if Char:GetAttribute("Downed") then
			return
		end
		if not RootPart then
			return
		end

		-- Only slide on the ground.
		local RayDirection = -RootPart.CFrame.UpVector * 5
		local GroundRay = workspace:Raycast(RootPart.Position, RayDirection, Params)

		if isSliding or not CanSlide or not GroundRay then
			return
		end

		-- The race SlideDuration sets the maximum speed multiplier.
		local stats = Plr:FindFirstChild("PlayerStats")
		if stats then
			local durVal = stats:FindFirstChild("SlideDuration")
			if durVal then
				Settings.MaxMultiplier = durVal.Value
			end
		end

		debounce = true
		task.delay(cdTime, function()
			debounce = false
		end)

		isSliding = true
		CanSlide = false
		slideStartTime = os.clock()

		animationHandler.LoadAnim(Char, "Sliding", slidingAnimID, nil, false)
		stateRemote:FireServer("SlideOn")
		script.Effect:FireServer()
		script.Slide_Loop:Play()
		Humanoid.HipHeight = Settings.HipHeight.Slide

		SlideVelocity = Instance.new("BodyVelocity", RootPart)
		SlideVelocity.MaxForce = Vector3.new(40000, 0, 40000)
		SlideVelocity.Velocity = RootPart.CFrame.LookVector * Settings.BaseSpeed

		AlignGyro = Instance.new("BodyGyro", RootPart)
		AlignGyro.MaxTorque = Vector3.new(3e5, 3e5, 3e5)
		AlignGyro.P = 10000

		local PreviousY = 0
		CurrentMultiplier = 1

		PosCheck = RunService.Heartbeat:Connect(function(deltaTime)
			local CurrentY = RootPart.Position.Y
			local VerticalChange = (CurrentY - PreviousY)
			PreviousY = CurrentY

			local RayDirection = -RootPart.CFrame.UpVector * 10
			local GroundRay = workspace:Raycast(RootPart.Position, RayDirection, Params)

			-- Align the character to the slope.
			if GroundRay then
				local CurrentRightVector = RootPart.CFrame.RightVector
				local UpVector = GroundRay.Normal
				local NewFacialVector = CurrentRightVector:Cross(UpVector)
				AlignGyro.CFrame = CFrame.fromMatrix(
					RootPart.Position,
					CurrentRightVector,
					UpVector,
					NewFacialVector
				)
			end

			SlideVelocity.Velocity = RootPart.CFrame.LookVector
				* (Settings.BaseSpeed * CurrentMultiplier)

			-- On flat ground the slide slows down, and faster while above the base speed.
			if VerticalChange < 0.1 and VerticalChange > -0.1 then
				if CurrentMultiplier > 1 then
					CurrentMultiplier = math.clamp(
						CurrentMultiplier - (Settings.SpeedChangeRate.Forward * 2) * deltaTime,
						0,
						Settings.MaxMultiplier
					)
				end
				CurrentMultiplier = math.clamp(
					CurrentMultiplier - Settings.SpeedChangeRate.Forward * deltaTime,
					0,
					Settings.MaxMultiplier
				)
			elseif VerticalChange > 0 then
				-- Uphill the slide slows down faster.
				if CurrentMultiplier > 1 then
					CurrentMultiplier = math.clamp(
						CurrentMultiplier - (Settings.SpeedChangeRate.Upward * 2) * deltaTime,
						0,
						Settings.MaxMultiplier
					)
				end
				CurrentMultiplier = math.clamp(
					CurrentMultiplier - Settings.SpeedChangeRate.Upward * deltaTime,
					0,
					Settings.MaxMultiplier
				)
			else
				-- Downhill the slide speeds up to the maximum.
				CurrentMultiplier = math.clamp(
					CurrentMultiplier + Settings.SpeedChangeRate.Downward * deltaTime,
					0,
					Settings.MaxMultiplier
				)
			end

			CurrentMultiplier = math.clamp(CurrentMultiplier, 0, Settings.MaxMultiplier)
			script.Slide_Loop.Volume = (BaseSoundVolume * CurrentMultiplier)

			if CurrentMultiplier < 0.1 or not GroundRay then
				StopSlide()
				stateHandler.RemoveStates(Char, "Sliding")
			end
		end)
	elseif Input.KeyCode == Enum.KeyCode.Space and isSliding then
		local CancelMultiplier = CurrentMultiplier
		local timeSinceSlide = os.clock() - slideStartTime

		local isPerfectJump = (timeSinceSlide >= Settings.SlideJump.WindowStart)
			and (timeSinceSlide <= Settings.SlideJump.WindowEnd)

		-- At 50% HP or less, a cancel is always the standard push, never the slide jump.
		local hpPercentage = Humanoid.Health / Humanoid.MaxHealth
		local slideJumpHealthMultiplier = 1

		if hpPercentage <= 0.5 then
			isPerfectJump = false
		end

		script.Slide_Cancel:Play()
		StopSlide()
		stateHandler.RemoveStates(Char, "Sliding")

		if isPerfectJump then
			local BoostVelocity = Instance.new("BodyVelocity", RootPart)
			BoostVelocity.MaxForce = Vector3.new(40000, 2000, 40000)

			local finalForwardBoost = (Settings.SlideJump.BoostForward * CancelMultiplier)
				* slideJumpHealthMultiplier
			local finalUpBoost = Settings.SlideJump.BoostUp * slideJumpHealthMultiplier

			BoostVelocity.Velocity = (RootPart.CFrame.LookVector * finalForwardBoost)
				+ (RootPart.CFrame.UpVector * finalUpBoost)

			Debris:AddItem(BoostVelocity, 0.15)

			local leapAnim = script.Leap
			Humanoid:LoadAnimation(leapAnim):Play(0.05)
		elseif Settings.PushOnCancel == true then
			local PushVelocity = Instance.new("BodyVelocity", RootPart)
			PushVelocity.MaxForce = Vector3.new(40000, 2000, 40000)
			PushVelocity.Velocity = (
				RootPart.CFrame.LookVector * (Settings.PushVelocity.Forward * CancelMultiplier)
			) + (RootPart.CFrame.UpVector * Settings.PushVelocity.Up)
			Debris:AddItem(PushVelocity, 0.1)
		end
	end
end)
