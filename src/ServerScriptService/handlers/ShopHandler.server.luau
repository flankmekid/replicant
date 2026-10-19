-- SPDX-License-Identifier: MIT
--
-- Sells race spins for Liturgy, in packs of 1 or 10.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.modules.dataManager)
local BuySpinsRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("BuySpins")

local SPIN_COST = 1000

BuySpinsRemote.OnServerEvent:Connect(function(player, amount)
	-- Only packs of 1 and 10 exist.
	if amount ~= 1 and amount ~= 10 then
		return
	end

	local totalCost = amount * SPIN_COST

	-- TODO: Tell the client when the player cannot afford the spins.
	if DataManager.GetLiturgy(player) >= totalCost then
		local success = DataManager.RemoveLiturgy(player, totalCost)
		if success then
			DataManager.UpdateSpins(player, amount)

			if player.Character and player.Character:FindFirstChild("Head") then
				local s = Instance.new("Sound", player.Character.Head)
				s.SoundId = "rbxassetid://10066947742"
				s:Play()
				game.Debris:AddItem(s, 1)
			end
		end
	end
end)
