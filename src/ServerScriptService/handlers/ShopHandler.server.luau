local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.modules.dataManager)
local BuySpinsRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("BuySpins")

local SPIN_COST = 1000

BuySpinsRemote.OnServerEvent:Connect(function(player, amount)
	-- 1. Validate Amount (Prevent exploiting)
	if amount ~= 1 and amount ~= 10 then return end

	local totalCost = amount * SPIN_COST

	-- 2. Check Funds
	if DataManager.GetLiturgy(player) >= totalCost then
		-- 3. Transaction
		local success = DataManager.RemoveLiturgy(player, totalCost)
		if success then
			DataManager.UpdateSpins(player, amount)

			-- Optional: Play a "Ka-ching" sound at the player's position
			if player.Character and player.Character:FindFirstChild("Head") then
				local s = Instance.new("Sound", player.Character.Head)
				s.SoundId = "rbxassetid://10066947742" -- Generic purchase sound
				s:Play()
				game.Debris:AddItem(s, 1)
			end

			print(player.Name .. " purchased " .. amount .. " spins.")
		end
	else
		-- Optional: Send a 'Not Enough Money' notification back
		print(player.Name .. " failed purchase: Not enough Liturgy.")
	end
end)