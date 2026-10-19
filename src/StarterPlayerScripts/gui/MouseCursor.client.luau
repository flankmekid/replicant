-- SPDX-License-Identifier: MIT
--
-- The custom mouse cursor: a default icon, a hover icon over buttons, and a lock icon
-- at the screen center while Shift Lock holds the mouse.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local DEFAULT_ICON = "rbxassetid://4127959394"
local HOVER_ICON = "rbxassetid://4127964114"
-- The Shift Lock icon, the same as the PlayerModule MouseLockController default.
local LOCK_ICON = "rbxassetid://4586653091"
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

-- The hovered buttons, as a set. MouseLeave does not fire when a hovered button is
-- destroyed, hidden, or its ScreenGui is disabled, so a counter could stick on the hover
-- icon.
local hovered = {}

-- A hovered button counts only if it is on screen: visible, with visible GuiObject
-- ancestors and an enabled ScreenGui.
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

-- The camera locks the mouse to the screen center during Shift Lock or right-click
-- pan. That is the signal for the lock icon.
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
		-- The mouse is pinned to the center, so put the icon there.
		local vp = workspace.CurrentCamera.ViewportSize
		cursor.Position = UDim2.fromOffset(vp.X / 2, vp.Y / 2)
	else
		local pos = UserInputService:GetMouseLocation()
		cursor.Position = UDim2.fromOffset(pos.X, pos.Y)
	end

	-- Drop any hovered button that is no longer on screen, whichever event fired.
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
