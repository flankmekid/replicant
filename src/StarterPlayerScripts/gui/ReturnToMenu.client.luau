local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local player = Players.LocalPlayer
local ReturnToMenuRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("ReturnToMenu")

local menuIcon = Icon.new()
--menuIcon:setImage("rbxassetid://114967221912590")
menuIcon:setLabel("Menu")
menuIcon:setOrder(-1)
menuIcon:setEnabled(false)

player:GetAttributeChangedSignal("HasPressedPlay"):Connect(function()
	if player:GetAttribute("HasPressedPlay") == true then
		menuIcon:setEnabled(true)
	else
		menuIcon:setEnabled(false)
	end
end)

menuIcon.selected:Connect(function()
	menuIcon:deselect()
	ReturnToMenuRemote:FireServer()
end)
