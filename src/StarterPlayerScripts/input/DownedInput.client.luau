local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for Remotes
local Remotes = ReplicatedStorage:WaitForChild("remotes")
local InteractionRemote = Remotes:WaitForChild("DownedInteraction")

-- Wait for the GUI we just created
local interactionGui = playerGui:WaitForChild("DownedInteractionHUD", 10)
local promptLabel = interactionGui and interactionGui.Container.PromptText

local SEARCH_RADIUS = 5

-- [[ HELPER: Find Target ]] --
local function GetNearestDownedPlayer()
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local nearestChar = nil
	local minDist = SEARCH_RADIUS

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local pChar = otherPlayer.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart")

			-- Check Attribute set by StateHandler
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

-- [[ INPUT LISTENER ]] --
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	-- EXECUTE (B)
	if input.KeyCode == Enum.KeyCode.B then
		local target = GetNearestDownedPlayer()
		if target then
			InteractionRemote:FireServer("Execute", target)
		end

		-- CARRY (N)
	elseif input.KeyCode == Enum.KeyCode.N then
		-- Check if WE are currently carrying someone
		local isCarrying = player.Character and player.Character:GetAttribute("Carrying")

		if isCarrying then
			InteractionRemote:FireServer("Carry", nil) -- Drop
		else
			local target = GetNearestDownedPlayer()
			if target then
				InteractionRemote:FireServer("Carry", target) -- Pickup
			end
		end
	end
end)

-- [[ UI UPDATE LOOP ]] --
RunService.RenderStepped:Connect(function()
	if not interactionGui or not promptLabel then return end
	local char = player.Character
	if not char then 
		interactionGui.Enabled = false
		return 
	end

	-- Check 1: Are we carrying someone?
	local isCarrying = char:GetAttribute("Carrying")
	if isCarrying then
		interactionGui.Enabled = true
		promptLabel.Text = "N - Drop"
		return
	end

	-- Check 2: Is a downed player nearby?
	local target = GetNearestDownedPlayer()
	if target then
		interactionGui.Enabled = true
		promptLabel.Text = "B - Grip   |   N - Carry"
	else
		interactionGui.Enabled = false
	end
end)