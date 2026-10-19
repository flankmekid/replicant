-- SPDX-License-Identifier: MIT
--
-- Shows the local player's guard bar: a vertical bar to the left of the character,
-- driven by the GuardBar attribute, which only the server writes. It is a BillboardGui
-- in PlayerGui, so only this client sees it, adorned to the root part, so it follows
-- the body under the over-the-shoulder lock-on camera.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RP = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")

-- Must match GuardBarService.MAX.
local MAX = 100

-- Gold when low, red near a break.
local LOW_COLOR = Color3.fromRGB(210, 200, 120)
local HIGH_COLOR = Color3.fromRGB(220, 60, 45)

-- Bar size in offset pixels. A BillboardGui scales offset sizes with camera distance.
local BAR_WIDTH = 12
local BAR_HEIGHT = 110

-- StudsOffset is relative to the camera, so a negative X keeps the bar on the screen
-- left of the body in every direction. StudsOffsetWorldSpace would swing it around.
local BAR_OFFSET = Vector3.new(-2.5, 0.5, 0)

-- Built once at start without an Adornee, so other scripts can find it by name.
-- ResetOnSpawn must be false: the GUI is created by code, so nothing would recreate it
-- after a reset.
local billboard = Instance.new("BillboardGui")
billboard.Name = "GuardBarBillboard"
billboard.Size = UDim2.new(0, BAR_WIDTH, 0, BAR_HEIGHT)
billboard.StudsOffset = BAR_OFFSET
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "GuardBar"
bar.Size = UDim2.new(1, 0, 1, 0)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel = 0
bar.Visible = false
bar.ZIndex = 3
bar.Parent = billboard

-- Square corners on purpose: no UICorner.
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Color = Color3.fromRGB(50, 50, 50)
stroke.Parent = bar

-- Anchored to the bottom, so a taller fill climbs the track.
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 0, 0)
fill.Position = UDim2.new(0.5, 0, 1, 0)
fill.AnchorPoint = Vector2.new(0.5, 1)
fill.BackgroundColor3 = LOW_COLOR
fill.BorderSizePixel = 0
fill.ZIndex = 4
fill.Parent = bar

local function render(value)
	local ratio = math.clamp(value / MAX, 0, 1)

	-- Hide the bar when empty.
	bar.Visible = ratio > 0.001

	TweenService:Create(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
		Size = UDim2.new(1, 0, ratio, 0),
	}):Play()
	fill.BackgroundColor3 = LOW_COLOR:Lerp(HIGH_COLOR, ratio)
end

-- Flashes the bar darker when the player presses block during break recovery. The
-- client Block module fires the GuardFlash BindableEvent.
local FLASH_COLOR = Color3.fromRGB(75, 66, 94)
local flashToken = 0
local function flash()
	-- Show the bar for the flash even when empty, so a denied press always gets feedback.
	bar.Visible = true

	flashToken += 1
	local myToken = flashToken

	local baseRatio =
		math.clamp((plr.Character and plr.Character:GetAttribute("GuardBar") or 0) / MAX, 0, 1)
	local baseColor = LOW_COLOR:Lerp(HIGH_COLOR, baseRatio)

	fill.BackgroundColor3 = FLASH_COLOR
	TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		BackgroundColor3 = baseColor,
	}):Play()

	-- Render the real value again after the flash.
	task.delay(0.3, function()
		if myToken ~= flashToken then
			return
		end
		render(plr.Character and plr.Character:GetAttribute("GuardBar") or 0)
	end)
end

RP.remotes:WaitForChild("GuardFlash").Event:Connect(flash)

-- Points the bar at the current body. A respawn gives a new root part, so this runs on
-- every CharacterAdded.
local function adorn(char)
	billboard.Adornee = char and char:FindFirstChild("HumanoidRootPart")
end

local currentConn
local function hook(char)
	if currentConn then
		currentConn:Disconnect()
		currentConn = nil
	end
	if not char then
		return
	end

	task.spawn(function()
		-- On a respawn the model can appear before its root part.
		char:WaitForChild("HumanoidRootPart", 10)
		adorn(char)
		render(char:GetAttribute("GuardBar") or 0)
	end)

	currentConn = char:GetAttributeChangedSignal("GuardBar"):Connect(function()
		render(char:GetAttribute("GuardBar") or 0)
	end)
end

if plr.Character then
	hook(plr.Character)
end
plr.CharacterAdded:Connect(hook)
