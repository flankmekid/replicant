-- SPDX-License-Identifier: MIT
--
-- Creates the ToolGrip Motor6Ds in both arms and connects them to the weapon parts
-- that the client names through the ConnectM6D remotes.

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

game.ReplicatedStorage.remotes.ConnectM6D.OnServerEvent:Connect(function(plr, location)
	plr.Character["Right Arm"].ToolGrip.Part1 = nil
	local char = plr.Character
	char["Right Arm"].ToolGrip.Part0 = char["Right Arm"]
	char["Right Arm"].ToolGrip.Part1 = location
end)

game.ReplicatedStorage.remotes.DisconnectM6D.OnServerEvent:Connect(function(plr)
	plr.Character["Right Arm"].ToolGrip.Part1 = nil
end)

game.ReplicatedStorage.remotes.ConnectM6D2.OnServerEvent:Connect(function(plr, location, location2)
	plr.Character["Right Arm"].ToolGrip.Part1 = nil
	plr.Character["Left Arm"].ToolGrip.Part1 = nil
	local char = plr.Character
	char["Right Arm"].ToolGrip.Part0 = char["Right Arm"]
	char["Right Arm"].ToolGrip.Part1 = location
	char["Left Arm"].ToolGrip.Part0 = char["Left Arm"]
	char["Left Arm"].ToolGrip.Part1 = location2
end)

game.ReplicatedStorage.remotes.DisconnectM6D2.OnServerEvent:Connect(function(plr)
	plr.Character["Left Arm"].ToolGrip.Part1 = nil
end)
