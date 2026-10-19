-- SPDX-License-Identifier: MIT
--
-- Creates the ToolGrip Motor6Ds in both arms and connects them to the weapon parts
-- that the client names through the ConnectM6D remotes. Only parts of the player's own
-- tools are accepted.

game.Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local M6D = Instance.new("Motor6D")
		M6D.Name = "ToolGrip"
		M6D.Parent = char["Right Arm"]
		local M6D2 = Instance.new("Motor6D")
		M6D2.Name = "ToolGrip"
		M6D2.Parent = char["Left Arm"]
	end)
	plr.CharacterRemoving:Connect(function(char)
		char.Humanoid:UnequipTools()
		char:FindFirstChild("Right Arm"):FindFirstChild("ToolGrip"):Destroy()
		char:FindFirstChild("Left Arm"):FindFirstChild("ToolGrip"):Destroy()
	end)
end)

-- Returns true if part belongs to a Tool of the player, held or in the Backpack. The
-- client names the part, and a Motor6D to any other part would weld it to the arm.
local function isOwnToolPart(plr, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end
	local tool = part:FindFirstAncestorOfClass("Tool")
	if not tool then
		return false
	end
	return tool.Parent == plr.Character or tool.Parent == plr:FindFirstChild("Backpack")
end

-- Returns the ToolGrip of an arm, or nil.
local function getGrip(char, armName)
	local arm = char and char:FindFirstChild(armName)
	return arm and arm:FindFirstChild("ToolGrip"), arm
end

game.ReplicatedStorage.remotes.ConnectM6D.OnServerEvent:Connect(function(plr, location)
	local grip, arm = getGrip(plr.Character, "Right Arm")
	if not grip or not isOwnToolPart(plr, location) then
		return
	end
	grip.Part1 = nil
	grip.Part0 = arm
	grip.Part1 = location
end)

game.ReplicatedStorage.remotes.DisconnectM6D.OnServerEvent:Connect(function(plr)
	local grip = getGrip(plr.Character, "Right Arm")
	if grip then
		grip.Part1 = nil
	end
end)

game.ReplicatedStorage.remotes.ConnectM6D2.OnServerEvent:Connect(function(plr, location, location2)
	local rightGrip, rightArm = getGrip(plr.Character, "Right Arm")
	local leftGrip, leftArm = getGrip(plr.Character, "Left Arm")
	if not rightGrip or not leftGrip then
		return
	end
	if not isOwnToolPart(plr, location) or not isOwnToolPart(plr, location2) then
		return
	end
	rightGrip.Part1 = nil
	leftGrip.Part1 = nil
	rightGrip.Part0 = rightArm
	rightGrip.Part1 = location
	leftGrip.Part0 = leftArm
	leftGrip.Part1 = location2
end)

game.ReplicatedStorage.remotes.DisconnectM6D2.OnServerEvent:Connect(function(plr)
	local grip = getGrip(plr.Character, "Left Arm")
	if grip then
		grip.Part1 = nil
	end
end)
