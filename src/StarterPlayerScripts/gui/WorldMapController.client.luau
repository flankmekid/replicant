--!strict
-- WorldMapController
-- Phase 3: full-screen world map UI (toggle, tween, pan, zoom).
-- Phase 4: live player position marker with facing arrow.
--
--   * Toggled with N (M is taken by ChronicleUI; rebind later if desired).
--   * Smooth open/close tween.
--   * Drag to pan, scroll wheel to zoom THE MAP (character camera zoom is
--     locked while the map is open so the world doesn't zoom underneath).
--   * Pan clamped so the map image can never be dragged off into empty space.
--   * Player marker tracks the local character every frame, mapped through
--     MapTransform, and rides inside MarkerLayer so it pans/zooms with the map.
--   * Facing arrow is drawn from a rotated frame (no external image asset),
--     so it renders identically on every client.
--
-- POIs and fog of war are Phases 5-6 and will hook into MarkerLayer too.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.modules.MapConfig)
local MapTransform = require(ReplicatedStorage.modules.MapTransform)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------------
local TOGGLE_KEY = Enum.KeyCode.Tab
local OPEN_TIME = 0.28
local CLOSE_TIME = 0.20
local MIN_ZOOM = 1.0
local MAX_ZOOM = 4.0
local ZOOM_STEP = 0.15
local ZOOM_LERP = 0.18
local MARKER_SIZE_PX = 18

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local isOpen = false
local currentZoom = 1.0
local targetZoom = 1.0
local panOffset = Vector2.new(0, 0)
local dragging = false
local lastDragPos: Vector2? = nil

local savedMinZoom: number? = nil
local savedMaxZoom: number? = nil

-- ---------------------------------------------------------------------------
-- Build the GUI in code
-- ---------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WorldMapGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimmer.BackgroundTransparency = 1
dimmer.BorderSizePixel = 0
dimmer.Parent = screenGui

local viewport = Instance.new("Frame")
viewport.Name = "Viewport"
viewport.AnchorPoint = Vector2.new(0.5, 0.5)
viewport.Position = UDim2.fromScale(0.5, 0.5)
viewport.Size = UDim2.fromScale(0.7, 0.82)
viewport.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
viewport.BackgroundTransparency = 1
viewport.BorderSizePixel = 0
viewport.ClipsDescendants = true
viewport.Parent = dimmer

local vpCorner = Instance.new("UICorner")
vpCorner.CornerRadius = UDim.new(0, 8)
vpCorner.Parent = viewport

local vpStroke = Instance.new("UIStroke")
vpStroke.Color = Color3.fromRGB(120, 90, 60)
vpStroke.Thickness = 2
vpStroke.Transparency = 1
vpStroke.Parent = viewport

local mapImage = Instance.new("ImageLabel")
mapImage.Name = "MapImage"
mapImage.AnchorPoint = Vector2.new(0.5, 0.5)
mapImage.Position = UDim2.fromScale(0.5, 0.5)
mapImage.BackgroundTransparency = 1
mapImage.Image = MapConfig.IMAGE_ID
mapImage.ScaleType = Enum.ScaleType.Stretch
mapImage.Parent = viewport

local markerLayer = Instance.new("Frame")
markerLayer.Name = "MarkerLayer"
markerLayer.AnchorPoint = Vector2.new(0.5, 0.5)
markerLayer.Position = UDim2.fromScale(0.5, 0.5)
markerLayer.Size = UDim2.fromScale(1, 1)
markerLayer.BackgroundTransparency = 1
markerLayer.Parent = mapImage

local playerMarker = Instance.new("Frame")
playerMarker.Name = "PlayerMarker"
playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
playerMarker.Size = UDim2.fromOffset(MARKER_SIZE_PX, MARKER_SIZE_PX)
playerMarker.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
playerMarker.BorderSizePixel = 0
playerMarker.ZIndex = 5
playerMarker.Visible = false
playerMarker.Parent = markerLayer

local pmCorner = Instance.new("UICorner")
pmCorner.CornerRadius = UDim.new(1, 0)
pmCorner.Parent = playerMarker

local pmStroke = Instance.new("UIStroke")
pmStroke.Color = Color3.fromRGB(255, 255, 255)
pmStroke.Thickness = 2
pmStroke.Parent = playerMarker

-- Facing arrow: a pivot frame centered on the dot. Rotating THIS aims a small
-- diamond pointer that sits just above the dot. No external image asset.
local facingArrow = Instance.new("Frame")
facingArrow.Name = "FacingArrow"
facingArrow.AnchorPoint = Vector2.new(0.5, 0.5)
facingArrow.Size = UDim2.fromOffset(MARKER_SIZE_PX, MARKER_SIZE_PX)
facingArrow.Position = UDim2.fromScale(0.5, 0.5)
facingArrow.BackgroundTransparency = 1
facingArrow.ZIndex = 4
facingArrow.Parent = playerMarker

local pointer = Instance.new("Frame")
pointer.Name = "Pointer"
pointer.AnchorPoint = Vector2.new(0.5, 0.5)
pointer.Size = UDim2.fromScale(0.6, 0.6)
pointer.Position = UDim2.fromScale(0.5, -0.2) -- above the dot center
pointer.Rotation = 45 -- square -> diamond -> reads as a tip
pointer.BackgroundColor3 = Color3.fromRGB(140, 205, 255)
pointer.BorderSizePixel = 0
pointer.ZIndex = 4
pointer.Parent = facingArrow

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -10)
hint.Size = UDim2.fromScale(0.6, 0.05)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(200, 180, 150)
hint.TextTransparency = 1
hint.Text = "Drag to pan  -  Scroll to zoom  -  N to close"
hint.Parent = dimmer

-- ---------------------------------------------------------------------------
-- Sizing & transform
-- ---------------------------------------------------------------------------
local function baseImageSize(): Vector2
	local vpAbs = viewport.AbsoluteSize
	local mapAspect = MapConfig.getImageAspect()
	local vpAspect = vpAbs.X / vpAbs.Y
	local w, h
	if mapAspect > vpAspect then
		w = vpAbs.X
		h = w / mapAspect
	else
		h = vpAbs.Y
		w = h * mapAspect
	end
	return Vector2.new(w, h)
end

local function clampPan(offset: Vector2, scaledSize: Vector2): Vector2
	local vpAbs = viewport.AbsoluteSize
	local maxX = math.max(0, (scaledSize.X - vpAbs.X) / 2)
	local maxY = math.max(0, (scaledSize.Y - vpAbs.Y) / 2)
	return Vector2.new(
		math.clamp(offset.X, -maxX, maxX),
		math.clamp(offset.Y, -maxY, maxY)
	)
end

local function applyTransform()
	local base = baseImageSize()
	local scaled = Vector2.new(base.X * currentZoom, base.Y * currentZoom)
	mapImage.Size = UDim2.fromOffset(scaled.X, scaled.Y)
	panOffset = clampPan(panOffset, scaled)
	mapImage.Position = UDim2.new(0.5, panOffset.X, 0.5, panOffset.Y)
	-- Counter-scale the marker so the dot stays a constant on-screen size
	-- regardless of map zoom.
	local s = MARKER_SIZE_PX / currentZoom
	playerMarker.Size = UDim2.fromOffset(s, s)
	facingArrow.Size = UDim2.fromOffset(s, s)
end

-- ---------------------------------------------------------------------------
-- Player marker update (Phase 4)
-- ---------------------------------------------------------------------------
local function getRootPart(): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function updatePlayerMarker()
	local hrp = getRootPart()
	if not hrp then
		playerMarker.Visible = false
		return
	end

	local u, v = MapTransform.vectorToNormalized(hrp.Position)
	local cu, cv = MapTransform.clampNormalized(u, v)
	playerMarker.Position = UDim2.fromScale(cu, cv)
	playerMarker.Visible = true

	-- Heading. Map orientation: +X = screen right, +Z = screen down.
	-- World north (-Z) should point the arrow UP (rotation 0).
	-- A frame's Rotation is clockwise-positive in screen space.
	-- look = (lookX, _, lookZ). Screen vector = (lookX -> right, lookZ -> down).
	-- atan2(screenRight, -screenDown) gives clockwise-from-up angle.
	local look = hrp.CFrame.LookVector
	local angle = math.deg(math.atan2(look.X, look.Z))
	facingArrow.Rotation = angle
end

-- ---------------------------------------------------------------------------
-- Camera zoom lock
-- ---------------------------------------------------------------------------
local function lockCameraZoom()
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance
	local current = player.CameraMaxZoomDistance
	local cam = Workspace.CurrentCamera
	if cam and player.Character then
		local head = player.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			current = (cam.CFrame.Position - head.Position).Magnitude
		end
	end
	-- Avoid pinning to 0 (would force first person); keep a sane floor.
	current = math.max(current, 0.5)
	player.CameraMinZoomDistance = current
	player.CameraMaxZoomDistance = current
end

local function restoreCameraZoom()
	if savedMinZoom then player.CameraMinZoomDistance = savedMinZoom end
	if savedMaxZoom then player.CameraMaxZoomDistance = savedMaxZoom end
	savedMinZoom = nil
	savedMaxZoom = nil
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------
local function openMap()
	if isOpen then return end
	isOpen = true
	screenGui.Enabled = true
	lockCameraZoom()

	currentZoom = MIN_ZOOM
	targetZoom = MIN_ZOOM
	panOffset = Vector2.new(0, 0)
	applyTransform()
	updatePlayerMarker()

	dimmer.BackgroundTransparency = 1
	viewport.BackgroundTransparency = 1
	vpStroke.Transparency = 1
	hint.TextTransparency = 1
	viewport.Size = UDim2.fromScale(0.62, 0.74)

	local ti = TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(dimmer, ti, { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(viewport, ti, {
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0.7, 0.82),
	}):Play()
	TweenService:Create(vpStroke, ti, { Transparency = 0 }):Play()
	TweenService:Create(hint, ti, { TextTransparency = 0.15 }):Play()
end

local function closeMap()
	if not isOpen then return end
	isOpen = false
	dragging = false
	lastDragPos = nil
	restoreCameraZoom()

	local ti = TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	TweenService:Create(dimmer, ti, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(viewport, ti, {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.62, 0.74),
	}):Play()
	TweenService:Create(vpStroke, ti, { Transparency = 1 }):Play()
	local fade = TweenService:Create(hint, ti, { TextTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		if not isOpen then
			screenGui.Enabled = false
		end
	end)
end

local function toggleMap()
	if isOpen then closeMap() else openMap() end
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------
local function isInsideViewport(pos: Vector2): boolean
	local tl = viewport.AbsolutePosition
	local br = tl + viewport.AbsoluteSize
	return pos.X >= tl.X and pos.X <= br.X and pos.Y >= tl.Y and pos.Y <= br.Y
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == TOGGLE_KEY then
		toggleMap()
		return
	elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
		closeMap()
		return
	end

	if not isOpen then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if isInsideViewport(p) then
			dragging = true
			lastDragPos = p
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isOpen then return end

	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if lastDragPos then
			local delta = p - lastDragPos
			panOffset = panOffset + delta
			applyTransform()
		end
		lastDragPos = p
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if isInsideViewport(p) then
			targetZoom = math.clamp(targetZoom + input.Position.Z * ZOOM_STEP * targetZoom, MIN_ZOOM, MAX_ZOOM)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		lastDragPos = nil
	end
end)

-- ---------------------------------------------------------------------------
-- Per-frame: smooth zoom, live marker, resize safety
-- ---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	if not isOpen then return end
	if math.abs(currentZoom - targetZoom) > 0.001 then
		currentZoom = currentZoom + (targetZoom - currentZoom) * ZOOM_LERP
		applyTransform()
	end
	updatePlayerMarker()
end)

viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if isOpen then applyTransform() end
end)

player.CharacterRemoving:Connect(function()
	if isOpen then
		restoreCameraZoom()
	end
end)
player.CharacterAdded:Connect(function()
	if isOpen then
		task.wait(0.2)
		lockCameraZoom()
	end
end)

print("[WorldMapController] Ready. Press '" .. TOGGLE_KEY.Name .. "' to open the map.")
