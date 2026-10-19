local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local DEFAULT_ICON = "rbxassetid://4127959394"
local HOVER_ICON = "rbxassetid://4127964114"
local LOCK_ICON = "rbxassetid://4586653091" -- shift-lock decal (was DEFAULT_MOUSE_LOCK_CURSOR in MouseLockController)
local CURSOR_SIZE = UDim2.new(0, 64, 0, 64)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomCursor"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999
screenGui.Parent = player:WaitForChild("PlayerGui")

local cursor = Instance.new("ImageLabel")
cursor.Name = "Icon"
cursor.BackgroundTransparency = 1
cursor.AnchorPoint = Vector2.new(0.5, 0.5)
cursor.Size = CURSOR_SIZE
cursor.Image = DEFAULT_ICON
cursor.Active = false
cursor.ZIndex = 999
cursor.Parent = screenGui

UserInputService.MouseIconEnabled = false

-- which buttons are currently hovered, keyed by the button instance.
-- a set (not a counter) so a button that disappears mid-hover can be
-- cleared cleanly. MouseLeave does NOT fire when a hovered button is
-- destroyed, hidden, or has its ScreenGui disabled (the menu Play button
-- hides itself, the controls X button disables its whole ScreenGui), which
-- is what kept getting the cursor stuck on HOVER_ICON.
local hovered = {}

-- a hovered button only counts if it's actually on screen: itself visible,
-- every GuiObject ancestor visible, and its ScreenGui still enabled.
local function isOnScreen(button)
	if not button.Parent then
		return false
	end
	local inst = button
	while inst and not inst:IsA("ScreenGui") do
		if inst:IsA("GuiObject") and not inst.Visible then
			return false
		end
		inst = inst.Parent
	end
	if inst and inst:IsA("ScreenGui") then
		return inst.Enabled
	end
	return false
end

-- the controller locks the mouse to screen centre when shift lock (or
-- right-click pan) is active. that's our signal to show the lock decal.
local function isLocked()
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function refresh()
	if isLocked() then
		cursor.Image = LOCK_ICON
	elseif next(hovered) then
		cursor.Image = HOVER_ICON
	else
		cursor.Image = DEFAULT_ICON
	end
end

RunService.RenderStepped:Connect(function()
	if isLocked() then
		-- mouse is pinned to centre by the camera, so park the decal there
		local vp = workspace.CurrentCamera.ViewportSize
		cursor.Position = UDim2.fromOffset(vp.X / 2, vp.Y / 2)
	else
		local pos = UserInputService:GetMouseLocation()
		cursor.Position = UDim2.fromOffset(pos.X, pos.Y)
	end

	-- safety net: drop any hovered button that's no longer on screen.
	-- catches destroy / Visible=false / ScreenGui disabled in one place,
	-- regardless of which (if any) event fired.
	for button in pairs(hovered) do
		if not isOnScreen(button) then
			hovered[button] = nil
		end
	end

	refresh()
end)

local function wireButton(button)
	button.MouseEnter:Connect(function()
		hovered[button] = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovered[button] = nil
		refresh()
	end)
end

local function process(instance)
	if instance:IsA("GuiButton") then
		wireButton(instance)
	end
end

for _, inst in ipairs(player.PlayerGui:GetDescendants()) do
	process(inst)
end
player.PlayerGui.DescendantAdded:Connect(process)
