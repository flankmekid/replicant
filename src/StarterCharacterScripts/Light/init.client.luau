local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- Configuration
local START_TIME = 17.9 -- Approx 5:54 PM
local END_TIME = 6.3 -- Approx 6:18 AM
local MAX_BRIGHTNESS = 1 -- How bright the light gets
local FADE_DURATION = 3 -- How many seconds the fade takes

-- Setup Character and Light
local character = script.Parent
local head = character:WaitForChild("Head")

local light = Instance.new("PointLight")
light.Name = "AutoFadeLight"
light.Range = 18
light.Color = Color3.fromRGB(205, 201, 255)
light.Shadows = false
light.Brightness = 0 -- Start at 0 so it can fade in if needed
light.Parent = head

-- State tracking to prevent spamming animations
local isLightOn = false

local function updateLight()
	local currentTime = Lighting.ClockTime

	-- Determine if it should be night (Logic handles the midnight wrap-around)
	local shouldBeOn = (currentTime >= START_TIME or currentTime <= END_TIME)

	-- Only run the tween if the state has actually changed
	if shouldBeOn ~= isLightOn then
		isLightOn = shouldBeOn

		local targetBrightness = shouldBeOn and MAX_BRIGHTNESS or 0

		-- Create and play the animation
		local tweenInfo =
			TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local tween = TweenService:Create(light, tweenInfo, { Brightness = targetBrightness })
		tween:Play()
	end
end

-- Run once immediately to set initial state
updateLight()

-- Check continuously as time changes
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateLight)
