-- GuardBarController (client): reads the server-authoritative GuardBar character
-- attribute and drives a VERTICAL bar that hovers to the left of your own character.
--
-- The bar is a BillboardGui adorned to the local character's HumanoidRootPart and
-- parented to PlayerGui. Parenting to PlayerGui rather than into the character model
-- means only THIS client ever renders it. Adorning it to the root means it tracks the
-- body in 3D instead of sitting at a fixed screen slot, which matters because the
-- lock-on camera is over-the-shoulder and the character is NOT at screen centre.
--
-- It no longer lives under WeaponSkillHUD, so the old destroy-and-rebuild dance with
-- SkillHUDHandler is gone. READ-ONLY on the attribute. It never writes the value.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RP = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")

local MAX = 100 -- must match GuardBarService.MAX

-- Colours: calm gold when low, hot red as it approaches break.
local LOW_COLOR = Color3.fromRGB(210, 200, 120)
local HIGH_COLOR = Color3.fromRGB(220, 60, 45)

-- Bar geometry, in offset pixels. A BillboardGui scales offset sizes with camera
-- distance, the same way DamageNumberController's damage numbers scale.
local BAR_WIDTH = 12
local BAR_HEIGHT = 110

-- StudsOffset is CAMERA-relative, not world-relative. Negative X is always screen
-- left, so the bar stays on the left of the body whichever way the character faces
-- and wherever the lock-on camera has swung to. StudsOffsetWorldSpace would let the
-- bar swing around the character and end up in front of them or behind them.
local BAR_OFFSET = Vector3.new(-2.5, 0.5, 0)

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------

-- Built once, eagerly, with no Adornee yet, so the instance exists from the first
-- frame and other scripts can find it by name.
--
-- ResetOnSpawn MUST be false. This GUI is created by code, not copied from
-- StarterGui, so a respawn reset would destroy it and nothing would ever put it back.
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

-- No UICorner on the track or on the fill. Square corners, by request. The stroke
-- stays.
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Color = Color3.fromRGB(50, 50, 50)
stroke.Parent = bar

-- Anchored to the BOTTOM edge, so growing the Y size climbs the track instead of
-- dropping down from the top.
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 0, 0)
fill.Position = UDim2.new(0.5, 0, 1, 0)
fill.AnchorPoint = Vector2.new(0.5, 1)
fill.BackgroundColor3 = LOW_COLOR
fill.BorderSizePixel = 0
fill.ZIndex = 4
fill.Parent = bar

--------------------------------------------------------------------------------
-- RENDER
--------------------------------------------------------------------------------

local function render(value)
	local ratio = math.clamp(value / MAX, 0, 1)

	-- Hide entirely when empty so it does not clutter the view at rest.
	bar.Visible = ratio > 0.001

	-- Height tween now, not width. The bottom anchor turns this into a climb.
	TweenService:Create(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
		Size = UDim2.new(1, 0, ratio, 0),
	}):Play()
	fill.BackgroundColor3 = LOW_COLOR:Lerp(HIGH_COLOR, ratio)
end

-- Flash the bar darker then ease back, as feedback for pressing block while the
-- guard is still broken (recovering). Fired by the client Block module via the
-- GuardFlash BindableEvent.
local FLASH_COLOR = Color3.fromRGB(75, 66, 94)
local flashToken = 0
local function flash()
	-- Force the bar visible for the flash even if it is empty, so the player always
	-- gets feedback on the denied press.
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

	-- After easing back, re-render so visibility and height settle to the true value.
	task.delay(0.3, function()
		if myToken ~= flashToken then
			return
		end
		render(plr.Character and plr.Character:GetAttribute("GuardBar") or 0)
	end)
end

RP.remotes:WaitForChild("GuardFlash").Event:Connect(flash)

--------------------------------------------------------------------------------
-- CHARACTER HOOK
--------------------------------------------------------------------------------

-- Point the billboard at the current body. A respawn hands us a brand new root, so
-- this has to run again on every CharacterAdded.
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
		-- On a respawn the model can be parented before the root part lands inside it.
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
