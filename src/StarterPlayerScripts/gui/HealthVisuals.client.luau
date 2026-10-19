-- SPDX-License-Identifier: MIT
--
-- The low-health effect: blurs the screen and types the race's panic messages in the
-- corners while the server keeps HealthAlertEvent started.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local AlertRemote = ReplicatedStorage:WaitForChild("HealthAlertEvent")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TEXT_FONT = Enum.Font.Merriweather
local TEXT_COLOR = Color3.fromRGB(255, 40, 40)
local TYPE_SPEED = 0.05
local LINGER_TIME = 3.0
local FADE_TIME = 1.5
local LOOP_DELAY_MIN = 1.0
local LOOP_DELAY_MAX = 3.0
local BLUR_SIZE = 8

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PanicOverlay"
screenGui.IgnoreGuiInset = true
-- CharacterAdded resets the effect, not the ScreenGui.
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local blurEffect = Lighting:FindFirstChild("LowHealthBlur")
if not blurEffect then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "LowHealthBlur"
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
end

local isPanicMode = false

-- Returns a random position in one of the four screen corners.
local function GetNonIntrusivePosition()
	local zone = math.random(1, 4)
	local xScale, yScale

	if zone == 1 then
		xScale = math.random(10, 35) / 100
		yScale = math.random(15, 35) / 100
	elseif zone == 2 then
		xScale = math.random(65, 90) / 100
		yScale = math.random(15, 35) / 100
	elseif zone == 3 then
		xScale = math.random(10, 35) / 100
		yScale = math.random(65, 85) / 100
	else
		xScale = math.random(65, 90) / 100
		yScale = math.random(65, 85) / 100
	end
	return UDim2.new(xScale, 0, yScale, 0)
end

local function PlayTypewriter(label, text)
	for i = 1, #text do
		if not label.Parent or not isPanicMode then
			break
		end
		label.Text = string.sub(text, 1, i)
		label.Rotation = label.Rotation + math.random(-1, 1)
		task.wait(TYPE_SPEED)
	end
end

local function SpawnSingleMessage(message)
	if not isPanicMode then
		return
	end

	local label = Instance.new("TextLabel")
	label.Text = ""
	label.BackgroundTransparency = 1
	label.TextColor3 = TEXT_COLOR
	label.Font = TEXT_FONT
	label.TextSize = 35
	label.Size = UDim2.new(0, 400, 0, 50)
	label.AnchorPoint = Vector2.new(0.5, 0.5)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	label.Position = GetNonIntrusivePosition()
	label.Rotation = math.random(-10, 10)
	label.Parent = screenGui

	PlayTypewriter(label, message)

	if isPanicMode then
		task.wait(LINGER_TIME)
	end

	if label.Parent then
		local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local t1 = TweenService:Create(label, info, { TextTransparency = 1 })
		local t2 = TweenService:Create(stroke, info, { Transparency = 1 })
		t1:Play()
		t2:Play()
		t1.Completed:Wait()
		label:Destroy()
	end
end

local function StartPanicLoop(messages)
	if isPanicMode then
		return
	end
	isPanicMode = true

	local blurInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blurEffect, blurInfo, { Size = BLUR_SIZE }):Play()

	task.spawn(function()
		while isPanicMode do
			if messages and #messages > 0 then
				local msg = messages[math.random(1, #messages)]
				task.spawn(function()
					SpawnSingleMessage(msg)
				end)
			end

			local waitTime = (TYPE_SPEED * 20)
				+ LINGER_TIME
				+ math.random(LOOP_DELAY_MIN, LOOP_DELAY_MAX)
			local elapsed = 0
			while elapsed < waitTime do
				if not isPanicMode then
					break
				end
				task.wait(0.1)
				elapsed += 0.1
			end
		end
	end)
end

local function StopPanicLoop(instant)
	isPanicMode = false

	if instant then
		-- An instant reset, on respawn.
		blurEffect.Size = 0
		screenGui:ClearAllChildren()
	else
		-- A smooth reset, after healing.
		local blurInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(blurEffect, blurInfo, { Size = 0 }):Play()
	end
end

AlertRemote.OnClientEvent:Connect(function(action, data)
	if action == "Start" then
		StartPanicLoop(data)
	elseif action == "Stop" then
		StopPanicLoop(false)
	end
end)

-- Reset the effect at once on respawn.
player.CharacterAdded:Connect(function()
	StopPanicLoop(true)
end)
