-- SPDX-License-Identifier: MIT
--
-- Fades a soft light on the character's head in at night and out in the day.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- The night window in ClockTime hours: from about 17:54 to about 06:18.
local startTime = 17.9
local endTime = 6.3
local maxBrightness = 1
-- The fade length in seconds.
local fadeDuration = 3

local character = script.Parent
local head = character:WaitForChild("Head")

local light = Instance.new("PointLight")
light.Name = "AutoFadeLight"
light.Range = 18
light.Color = Color3.fromRGB(205, 201, 255)
light.Shadows = false
-- Start dark, so the light can fade in.
light.Brightness = 0
light.Parent = head

-- Tween only when the state changes.
local isLightOn = false

local function updateLight()
	local currentTime = Lighting.ClockTime

	-- The night window wraps past midnight.
	local shouldBeOn = (currentTime >= startTime or currentTime <= endTime)

	if shouldBeOn ~= isLightOn then
		isLightOn = shouldBeOn

		local targetBrightness = shouldBeOn and maxBrightness or 0

		local tweenInfo =
			TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local tween = TweenService:Create(light, tweenInfo, { Brightness = targetBrightness })
		tween:Play()
	end
end

updateLight()

Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateLight)
