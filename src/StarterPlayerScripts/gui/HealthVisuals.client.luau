local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local AlertRemote = ReplicatedStorage:WaitForChild("HealthAlertEvent")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [[ CONFIGURATION ]] --
local TEXT_FONT = Enum.Font.Merriweather
local TEXT_COLOR = Color3.fromRGB(255, 40, 40)
local TYPE_SPEED = 0.05
local LINGER_TIME = 3.0
local FADE_TIME = 1.5
local LOOP_DELAY_MIN = 1.0
local LOOP_DELAY_MAX = 3.0
local BLUR_SIZE = 8

-- [[ SETUP VISUALS ]] --
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PanicOverlay"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false -- We handle the reset manually now
screenGui.Parent = playerGui

local blurEffect = Lighting:FindFirstChild("LowHealthBlur")
if not blurEffect then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "LowHealthBlur"
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
end

local isPanicMode = false

-- [[ HELPER FUNCTIONS ]] --

local function GetNonIntrusivePosition()
	local zone = math.random(1, 4)
	local xScale, yScale

	if zone == 1 then -- Top Left
		xScale = math.random(10, 35) / 100
		yScale = math.random(15, 35) / 100
	elseif zone == 2 then -- Top Right
		xScale = math.random(65, 90) / 100
		yScale = math.random(15, 35) / 100
	elseif zone == 3 then -- Bottom Left
		xScale = math.random(10, 35) / 100
		yScale = math.random(65, 85) / 100
	else -- Bottom Right
		xScale = math.random(65, 90) / 100
		yScale = math.random(65, 85) / 100
	end
	return UDim2.new(xScale, 0, yScale, 0)
end

local function PlayTypewriter(label, text)
	for i = 1, #text do
		if not label.Parent or not isPanicMode then
			break
		end -- Stop if destroyed or panic over
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

	-- 1. Typewriter Effect
	PlayTypewriter(label, message)

	-- 2. Linger
	if isPanicMode then
		task.wait(LINGER_TIME)
	end

	-- 3. Fade Out
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

-- [[ MAIN LOOP & CLEANUP ]] --

local function StartPanicLoop(messages)
	if isPanicMode then
		return
	end -- Don't start twice
	isPanicMode = true

	-- Tween Blur IN
	local blurInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blurEffect, blurInfo, { Size = BLUR_SIZE }):Play()

	-- Start Message Loop
	task.spawn(function()
		while isPanicMode do
			if messages and #messages > 0 then
				local msg = messages[math.random(1, #messages)]
				task.spawn(function()
					SpawnSingleMessage(msg)
				end)
			end

			-- Random Delay before next message
			local waitTime = (TYPE_SPEED * 20)
				+ LINGER_TIME
				+ math.random(LOOP_DELAY_MIN, LOOP_DELAY_MAX)
			local elapsed = 0
			while elapsed < waitTime do
				if not isPanicMode then
					break
				end -- Exit wait early if stopped
				task.wait(0.1)
				elapsed += 0.1
			end
		end
	end)
end

local function StopPanicLoop(instant)
	isPanicMode = false

	if instant then
		-- Instant reset (for death/respawn)
		blurEffect.Size = 0
		screenGui:ClearAllChildren() -- Deletes all active text immediately
	else
		-- Smooth reset (for healing up)
		local blurInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(blurEffect, blurInfo, { Size = 0 }):Play()
	end
end

-- [[ EVENT HANDLERS ]] --

AlertRemote.OnClientEvent:Connect(function(action, data)
	if action == "Start" then
		StartPanicLoop(data)
	elseif action == "Stop" then
		StopPanicLoop(false) -- False means "Tween out smoothly"
	end
end)

-- [FIX] Reset visuals immediately when the player respawns
player.CharacterAdded:Connect(function()
	StopPanicLoop(true) -- True means "Instant reset"
end)
