-- SPDX-License-Identifier: MIT
--
-- Adds the topbar Controls button, which opens and closes the tutorial panel through
-- the TutorialState BindableFunction of TutorialTrigger.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("TutorialGui")
local api = gui:WaitForChild("TutorialState")

local controlIcon = Icon.new()
controlIcon:setLabel("Controls")
controlIcon:align("Left")

controlIcon.selected:Connect(function()
	local isOpen = api:Invoke("toggle")
	-- Keep the icon in step with the panel.
	if not isOpen then
		controlIcon:deselect()
	end
end)

controlIcon.deselected:Connect(function()
	api:Invoke("close")
end)

-- The panel's close button fires RequestClose. Deselecting the icon closes the panel
-- through the handler above and leaves the icon deselected.
local requestClose = gui:WaitForChild("RequestClose")
requestClose.Event:Connect(function()
	controlIcon:deselect()
end)
