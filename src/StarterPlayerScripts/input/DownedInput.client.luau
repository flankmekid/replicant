-- SPDX-License-Identifier: MIT
--
-- Execute (B) and carry or drop (N) for a downed player within SEARCH_RADIUS, with the
-- prompt on the DownedInteractionHUD.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local InteractionRemote = Remotes:WaitForChild("DownedInteraction")

local interactionGui = playerGui:WaitForChild("DownedInteractionHUD", 10)
local promptLabel = interactionGui and interactionGui.Container.PromptText

local SEARCH_RADIUS = 5

-- Returns the nearest downed player within SEARCH_RADIUS, or nil.
local function GetNearestDownedPlayer()
	local char = player.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local nearestChar = nil
	local minDist = SEARCH_RADIUS

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local pChar = otherPlayer.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart")

			local isDowned = pChar:GetAttribute("Downed") == true

			if pRoot and isDowned then
				local dist = (pRoot.Position - root.Position).Magnitude
				if dist < minDist then
					minDist = dist
					nearestChar = pChar
				end
			end
		end
	end

	return nearestChar
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		local target = GetNearestDownedPlayer()
		if target then
			InteractionRemote:FireServer("Execute", target)
		end
	elseif input.KeyCode == Enum.KeyCode.N then
		-- N drops the body the player carries, or picks up the nearest one.
		local isCarrying = player.Character and player.Character:GetAttribute("Carrying")

		if isCarrying then
			InteractionRemote:FireServer("Carry", nil)
		else
			local target = GetNearestDownedPlayer()
			if target then
				InteractionRemote:FireServer("Carry", target)
			end
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if not interactionGui or not promptLabel then
		return
	end
	local char = player.Character
	if not char then
		interactionGui.Enabled = false
		return
	end

	local isCarrying = char:GetAttribute("Carrying")
	if isCarrying then
		interactionGui.Enabled = true
		promptLabel.Text = "N - Drop"
		return
	end

	local target = GetNearestDownedPlayer()
	if target then
		interactionGui.Enabled = true
		promptLabel.Text = "B - Grip   |   N - Carry"
	else
		interactionGui.Enabled = false
	end
end)
