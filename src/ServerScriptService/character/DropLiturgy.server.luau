-- SPDX-License-Identifier: MIT
--
-- Lets a player drop Liturgy in front of them as a pickup. The server checks the
-- amount and the balance, because the client can send anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules:WaitForChild("dataManager"))
local dropRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("DropLiturgy")

dropRemote.OnServerEvent:Connect(function(player: Player, amount: number)
	if type(amount) ~= "number" then
		return
	end
	if amount <= 0 or amount ~= math.floor(amount) then
		return
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local currentLiturgy = DataManager.GetLiturgy(player)

	if currentLiturgy >= amount then
		local success = DataManager.RemoveLiturgy(player, amount)

		if success then
			local rootPart = character.HumanoidRootPart
			local dropPosition = rootPart.Position + (rootPart.CFrame.LookVector * 4)

			DataManager.CreateDrop(dropPosition, amount)

			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = rootPart
			s:Play()
			game.Debris:AddItem(s, 2)
		end
	end
end)
