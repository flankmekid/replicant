local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules:WaitForChild("dataManager"))
local dropRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("DropLiturgy")

dropRemote.OnServerEvent:Connect(function(player : Player, amount : number)
	-- [[ 1. SECURITY VALIDATION ]] --
	-- Exploiters can bypass local scripts, so we strictly verify the data here
	if type(amount) ~= "number" then return end
	if amount <= 0 or amount ~= math.floor(amount) then return end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end -- Cannot drop while dead

	-- [[ 2. VERIFY & DEDUCT FUNDS ]] --
	local currentLiturgy = DataManager.GetLiturgy(player) 

	if currentLiturgy >= amount then
		-- Deduct the currency
		local success = DataManager.RemoveLiturgy(player, amount)

		if success then
			-- [[ 3. CREATE THE DROP IN FRONT OF PLAYER ]] --
			local rootPart = character.HumanoidRootPart
			-- Calculate a position 4 studs exactly in front of where the player is facing
			local dropPosition = rootPart.Position + (rootPart.CFrame.LookVector * 4)

			-- Generate the physical drop using your existing module function
			DataManager.CreateDrop(dropPosition, amount)

			-- Optional: Play a sound effect from the player
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742" 
			s.Parent = rootPart
			s:Play()
			game.Debris:AddItem(s, 2)
		end
	end
end)