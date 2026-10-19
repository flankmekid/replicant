--[[
	CooldownGui
	DISPLAY ONLY. Reads CooldownTracker each frame and renders cooldown bars.
	Bottom-right, nudged up. Invisible when nothing active.

	Stacking: newest bar enters at the TOP of the stack, older bars sit below it. When a bar
	expires the bars above it slide down to fill the gap. (Newest-on-top toast stack.)

	Each bar: a horizontal fill spanning the full height. Starts FULLY red and drains away
	LEFT->RIGHT as the cooldown counts down (full at cast, empty when ready). The red is
	anchored to the RIGHT edge, so it shrinks off the left side. Centered label
	"<name> (<countdown>)" on top.

	Animations: bars tween in on appear and tween out on expire; the fill glides smoothly
	rather than snapping. Because exit is animated, the GUI keeps a bar alive briefly after
	the tracker drops it (during the exit tween), so it does not purely mirror the tracker.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CooldownTracker = require(ReplicatedStorage.modules.CooldownTracker)

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")

-- ---- tunables ----------------------------------------------------------------
local BAR_WIDTH = 160
local BAR_HEIGHT = 30
local BAR_PADDING = 6
local CONTAINER_OFFSET_X = -24
local CONTAINER_OFFSET_Y = -140
local COLOR_BG = Color3.fromRGB(36, 36, 36)
local COLOR_FILL = Color3.fromRGB(220, 60, 60)
local COLOR_TEXT = Color3.fromRGB(230, 230, 230)
local COLOR_STROKE = Color3.fromRGB(50, 50, 50)
local FONT = Enum.Font.RobotoMono

local ENTER_TIME = 0.18
local EXIT_TIME = 0.18
local FILL_SMOOTH = 0.1
-- ------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CooldownGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(1, CONTAINER_OFFSET_X, 1, CONTAINER_OFFSET_Y)
container.Size = UDim2.new(0, BAR_WIDTH, 1, 0)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, BAR_PADDING)
layout.Parent = container

-- frames[id] = { root, fill, label, stroke, order, exiting }
local frames = {}
local seq = 0 -- monotonic; newer bars get higher seq -> lower LayoutOrder -> render on top

local function makeBar(id)
	local root = Instance.new("Frame")
	root.Name = id
	root.Size = UDim2.new(0, BAR_WIDTH, 0, BAR_HEIGHT)
	root.BackgroundColor3 = COLOR_BG
	root.BackgroundTransparency = 0.4
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Color = COLOR_STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = root

	-- horizontal fill: full height, anchored RIGHT, starts full width and drains off the
	-- left as the cooldown counts down (red recedes left->right).
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(1, 0)
	fill.Position = UDim2.new(1, 0, 0, 0)
	fill.Size = UDim2.new(1, 0, 1, 0) -- full width at start
	fill.BackgroundColor3 = COLOR_FILL
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = root

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextColor3 = COLOR_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextSize = 15
	label.ZIndex = 2
	label.Text = ""
	label.Parent = root

	-- enter animation
	root.BackgroundTransparency = 1
	stroke.Transparency = 1
	label.TextTransparency = 1
	fill.BackgroundTransparency = 1
	root.Size = UDim2.new(0, BAR_WIDTH, 0, 0)

	local info = TweenInfo.new(ENTER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(root, info, {
		Size = UDim2.new(0, BAR_WIDTH, 0, BAR_HEIGHT),
		BackgroundTransparency = 0.4,
	}):Play()
	TweenService:Create(stroke, info, { Transparency = 0.5 }):Play()
	TweenService:Create(label, info, { TextTransparency = 0 }):Play()
	TweenService:Create(fill, info, { BackgroundTransparency = 0.45 }):Play()

	return { root = root, fill = fill, label = label, stroke = stroke, exiting = false }
end

local function exitBar(f)
	if f.exiting then return end
	f.exiting = true
	local info = TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(f.root, info, {
		Size = UDim2.new(0, BAR_WIDTH, 0, 0),
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(f.stroke, info, { Transparency = 1 }):Play()
	TweenService:Create(f.label, info, { TextTransparency = 1 }):Play()
	local fillTween = TweenService:Create(f.fill, info, { BackgroundTransparency = 1 })
	fillTween:Play()
	fillTween.Completed:Connect(function()
		f.root:Destroy()
	end)
end

local function fmt(remaining)
	if remaining < 1 then
		return string.format("%.1f", remaining)
	else
		return tostring(math.ceil(remaining))
	end
end

RunService.RenderStepped:Connect(function()
	local list = CooldownTracker.GetActive()

	local present = {}
	for _, entry in ipairs(list) do
		present[entry.id] = true
		local f = frames[entry.id]
		if not f then
			seq += 1
			f = makeBar(entry.id)
			f.order = seq
			frames[entry.id] = f
		end
		f.root.LayoutOrder = -f.order

		-- fill drains left->right: width = fraction (full at cast, 0 when ready), anchored right
		local target = math.clamp(entry.fraction, 0, 1)
		TweenService:Create(
			f.fill,
			TweenInfo.new(FILL_SMOOTH, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(target, 0, 1, 0) }
		):Play()

		f.label.Text = string.format("%s (%s)", entry.label, fmt(entry.remaining))
	end

	for id, f in pairs(frames) do
		if not present[id] then
			exitBar(f)
			frames[id] = nil
		end
	end
end)
