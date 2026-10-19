-- SPDX-License-Identifier: MIT
--
-- Owns race appearance and race rolls: the spin with pity, the race visuals (skin,
-- face, eyes, hair, race items, armor dye), the race passives, and the barber remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local DataManager = require(ServerScriptService.modules.dataManager)
local RaceConfig = require(ReplicatedStorage.modules.RaceConfig)
local RaceAssets = ServerStorage:FindFirstChild("RaceAssets")
local FacesFolder = ReplicatedStorage:WaitForChild("faces")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local RollRaceFunction = Remotes:FindFirstChild("RollRace")
	or Instance.new("RemoteFunction", Remotes)
RollRaceFunction.Name = "RollRace"

if not ReplicatedStorage:FindFirstChild("BarberEvent") then
	local BarberEvent = Instance.new("RemoteEvent")
	BarberEvent.Name = "BarberEvent"
	BarberEvent.Parent = ReplicatedStorage
end
local BarberEvent = ReplicatedStorage.BarberEvent

local pityThreshold = 30
local dyeCost = 1000
local femaleTorsoId = 48112070
local playerPity = {}

local function WaitForData(player)
	local timeout = 0
	while not DataManager.GetProfile(player) do
		task.wait(0.2)
		timeout += 0.2
		if timeout > 10 then
			return false
		end
	end
	return true
end

-- Rolls a race by rarity weight. A full pity counter guarantees a Legendary race.
local function GetRandomRace(player)
	local currentPity = DataManager.GetPity(player)
	local forceLegendary = false

	if currentPity >= pityThreshold then
		forceLegendary = true
	end

	local selectedRarity = "Common"
	if forceLegendary then
		selectedRarity = "Legendary"
	else
		local totalWeight = 0
		for _, rarity in ipairs(RaceConfig.Rarities) do
			totalWeight += rarity.Weight
		end
		local r = math.random(1, totalWeight)
		local acc = 0
		for _, rarity in ipairs(RaceConfig.Rarities) do
			acc += rarity.Weight
			if r <= acc then
				selectedRarity = rarity.Name
				break
			end
		end
	end

	local possible = {}
	for race, data in pairs(RaceConfig.Races) do
		if data.Rarity == selectedRarity then
			table.insert(possible, race)
		end
	end

	if #possible == 0 then
		return "Human", "Common"
	end
	return possible[math.random(1, #possible)], selectedRarity
end

local function GetRandomFace(raceName)
	local folder = FacesFolder:FindFirstChild(string.lower(raceName))
	if not folder or #folder:GetChildren() == 0 then
		folder = FacesFolder:FindFirstChild("default")
	end

	if folder then
		local faces = folder:GetChildren()
		if #faces > 0 then
			local randomDecal = faces[math.random(1, #faces)]
			if randomDecal:IsA("Decal") then
				return randomDecal.Texture
			end
		end
	end
	return "rbxassetid://0"
end

-- Removes every accessory except equipment (EquipSlot_*). The player's own avatar hair
-- is kept on the head if keepDefaultHair is true, and otherwise stored in the player.
local function CleanAccessories(char, keepDefaultHair)
	local hum = char:FindFirstChild("Humanoid")
	local player = game:GetService("Players"):GetPlayerFromCharacter(char)
	if not player then
		return
	end

	-- The hair cache is in the Player object, out of Workspace.
	local hairCache = player:FindFirstChild("HairCache")
	if not hairCache then
		hairCache = Instance.new("Folder")
		hairCache.Name = "HairCache"
		hairCache.Parent = player
	end

	-- When the default hair is kept, bring it back from the cache.
	if keepDefaultHair then
		for _, cachedHair in pairs(hairCache:GetChildren()) do
			cachedHair.Parent = char
			if hum then
				hum:AddAccessory(cachedHair)
			end
		end
	end

	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Accessory") then
			-- Tag the original avatar hair, so it is not confused with barber hair.
			if
				child.AccessoryType == Enum.AccessoryType.Hair
				and not child:GetAttribute("IsBarberHair")
				and not child:GetAttribute("IsRaceItem")
			then
				if not child:GetAttribute("IsDefaultHair") then
					child:SetAttribute("IsDefaultHair", true)
				end
			end

			if child:GetAttribute("IsDefaultHair") then
				if keepDefaultHair then
					continue
				else
					child.Parent = hairCache
					continue
				end
			end

			-- Destroy everything else, such as old barber hair and hats.
			if not string.find(child.Name, "EquipSlot_") then
				child:Destroy()
			end
		elseif child:IsA("ShirtGraphic") then
			child:Destroy()
		elseif child:GetAttribute("IsRaceItem") == true then
			child:Destroy()
		elseif child.Name == "RightArmSpike" then
			child:Destroy()
		end
	end
end

-- Loads a barber hair accessory by asset ID and tints it with the race color.
local function LoadAccessoryById(hum, id, raceColor)
	if not id or id == 0 then
		return
	end

	local success, model = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if success and model then
		for _, item in ipairs(model:GetChildren()) do
			if item:IsA("Accessory") then
				item:SetAttribute("IsBarberHair", true)

				local handle = item:FindFirstChild("Handle")
				if handle then
					if raceColor then
						handle.Color = raceColor
					end
					-- Remove the texture so the color shows.
					local mesh = handle:FindFirstChildOfClass("SpecialMesh")
					if mesh then
						mesh.TextureId = ""
					end
					if handle:IsA("MeshPart") then
						handle.TextureID = ""
					end
				end
				hum:AddAccessory(item)
			end
		end
		model:Destroy()
	end
end

local function UpdateCharacterVisuals(player)
	if not player or not player.Parent then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then
		return
	end

	if not WaitForData(player) then
		return
	end

	local profile = DataManager.GetProfile(player)
	local appData = DataManager.GetAppearance(player)
	local raceName = profile.Data.Race or "Human"
	local raceConfig = RaceConfig.Races[raceName]
	local visuals = raceConfig.Visuals or {}

	-- Decide about the hair before the cleanup.
	local invisibleHair = visuals.InvisibleHair or false
	local hasCustomHair = false

	if appData and appData.Hair then
		for _, id in ipairs(appData.Hair) do
			if id > 0 then
				hasCustomHair = true
				break
			end
		end
	end

	-- Keep the default hair only without custom hair, and only if the race allows hair.
	local keepDefaultHair = (not hasCustomHair) and not invisibleHair

	CleanAccessories(char, keepDefaultHair)

	for _, v in pairs(char:GetChildren()) do
		if v:IsA("CharacterMesh") and v.BodyPart == Enum.BodyPart.Torso then
			v:Destroy()
		end
	end

	local defaultFace = char.Head:FindFirstChild("face")
	if defaultFace then
		defaultFace:Destroy()
	end

	local rArm = char:FindFirstChild("Right Arm")
	if rArm then
		rArm.Transparency = 0
	end

	local headPart = char:FindFirstChild("Head")
	if headPart then
		headPart.Transparency = 0
	end

	if appData and appData.Gender == "Female" then
		local mesh = Instance.new("CharacterMesh")
		mesh.BodyPart = Enum.BodyPart.Torso
		mesh.MeshId = femaleTorsoId
		mesh.Parent = char
	end

	if visuals.SkinColor then
		for _, part in ipairs(char:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				if raceName == "Maw" and player.UserId == 1526974131 then
					part.Color = Color3.fromRGB(166, 7, 14)
				else
					part.Color = visuals.SkinColor
				end
			end
		end
	end

	local face = char.Head:FindFirstChild("Face")
	if not face then
		face = Instance.new("Decal")
		face.Name = "Face"
		face.Face = Enum.NormalId.Front
		face.Parent = char.Head
	end

	local savedFace = DataManager.GetFace(player)
	if savedFace then
		face.Texture = savedFace
	end

	if raceName == "Ancestor" then
		face.Color3 = Color3.fromRGB(200, 0, 0)
	else
		local eyeColor = DataManager.GetEyeColor(player)
		face.Color3 = eyeColor or Color3.new(0, 0, 0)
	end

	-- Some races hide body parts.
	local function setTransparency(partName, value)
		local part = char:FindFirstChild(partName)
		if part then
			part.Transparency = value
		end
	end

	if visuals.InvisibleHead then
		setTransparency("Head", 1)
		face.Transparency = 1
	else
		setTransparency("Head", 0)
		face.Transparency = 0
	end

	if visuals.InvisibleRArm then
		setTransparency("Right Arm", 1)
	else
		setTransparency("Right Arm", 0)
	end

	local raceHairCol = visuals.HairColor or Color3.fromRGB(160, 160, 160)

	if not invisibleHair then
		if hasCustomHair then
			for _, id in ipairs(appData.Hair) do
				LoadAccessoryById(hum, id, raceHairCol)
			end
		else
			-- Tint the default avatar hair that the cleanup kept.
			for _, child in pairs(char:GetChildren()) do
				if child:IsA("Accessory") and child:GetAttribute("IsDefaultHair") then
					local handle = child:FindFirstChild("Handle")
					if handle then
						if raceHairCol then
							handle.Color = raceHairCol
						end
						-- Remove the texture so the color shows.
						local mesh = handle:FindFirstChildOfClass("SpecialMesh")
						if mesh then
							mesh.TextureId = ""
						end
						if handle:IsA("MeshPart") then
							handle.TextureID = ""
						end
					end
				end
			end
		end
	end

	-- Race items, such as horns and tails.
	if RaceAssets then
		local accessoriesToLoad = {}
		if visuals.Accessories then
			for _, name in ipairs(visuals.Accessories) do
				table.insert(accessoriesToLoad, name)
			end
		end
		if visuals.Accessory then
			table.insert(accessoriesToLoad, visuals.Accessory)
		end

		if RaceAssets:FindFirstChild("Accessory") then
			for _, accName in ipairs(accessoriesToLoad) do
				local template = RaceAssets.Accessory:FindFirstChild(accName)
				if template then
					local clone = template:Clone()
					clone:SetAttribute("IsRaceItem", true)
					if raceName == "Maw" and player.UserId == 1526974131 then
						clone:FindFirstChild("Handle").Color = Color3.fromRGB(143, 6, 13)
					end
					clone.Parent = char
				end
			end
		end

		if visuals.RightArm and RaceAssets:FindFirstChild("RightArm") then
			local armAsset = RaceAssets.RightArm:FindFirstChild(visuals.RightArm)
			if armAsset then
				local rArm = char:FindFirstChild("Right Arm")
				if rArm then
					local clone = armAsset:Clone()
					clone:SetAttribute("IsRaceItem", true)
					clone.CFrame = rArm.CFrame * CFrame.new(0.3, 0, 0)
					local weld = Instance.new("WeldConstraint", clone)
					weld.Part0 = rArm
					weld.Part1 = clone
					clone.Parent = char
				end
			end
		else
			if char:FindFirstChild("RightArmSpike") then
				game.Debris:AddItem(char:FindFirstChild("RightArmSpike"))
			end
		end

		if visuals.HeadAsset and RaceAssets:FindFirstChild("HeadAsset") then
			local asset = RaceAssets.HeadAsset:FindFirstChild(visuals.HeadAsset)
			if asset then
				local head = char:FindFirstChild("Head")
				if head then
					head.Transparency = 1
					local clone = asset:Clone()
					clone:SetAttribute("IsRaceItem", true)
					clone.CFrame = head.CFrame
					local weld = Instance.new("WeldConstraint", clone)
					weld.Part0 = head
					weld.Part1 = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
					clone.Parent = char
				end
			end
		end
	end

	if appData and appData.ArmorColor then
		for _, child in pairs(char:GetChildren()) do
			local isHair = false
			local handle = child:FindFirstChild("Handle")
			if handle and handle:FindFirstChild("HairAttachment") then
				isHair = true
			end

			local isBarber = child:GetAttribute("IsBarberHair")
			local isRaceItem = child:GetAttribute("IsRaceItem")
			local isDefaultHair = child:GetAttribute("IsDefaultHair")

			if
				child:IsA("Accessory")
				and not isBarber
				and not isRaceItem
				and not isHair
				and not isDefaultHair
				and child.AccessoryType ~= Enum.AccessoryType.Hair
			then
				if handle then
					handle.Color = appData.ArmorColor
				end
			end
		end
	end
end

-- Race passives are character attributes, derived from RaceConfig. Every known passive
-- is cleared first and then only the current race's are set, so a reroll never keeps
-- the old race's passive. Adding a passive to a race in RaceConfig is enough.

-- RaceConfig Stats key to character attribute name. Any other key is a numeric stat in
-- PlayerStats, not an attribute.
local racePassiveAttrs = {
	Hyperarmor = "Hyperarmor",
	Lifesteal = "Lifesteal",
	ESP = "SeerESP",
	ManaWhenHit = "ManaWhenHit",
}

local function ApplyRacePassives(char, raceName)
	if not char then
		return
	end
	local raceInfo = RaceConfig.Races[raceName]
	local stats = raceInfo and raceInfo.Stats

	for statKey, attrName in pairs(racePassiveAttrs) do
		if stats and stats[statKey] then
			char:SetAttribute(attrName, true)
		else
			char:SetAttribute(attrName, nil)
		end
	end
end

RollRaceFunction.OnServerInvoke = function(player)
	local spins = DataManager.GetSpins(player)
	if spins > 0 then
		DataManager.UpdateSpins(player, -1)

		local newRace, rarity = GetRandomRace(player)
		local raceInfo = RaceConfig.Races[newRace]

		if rarity == "Legendary" then
			DataManager.UpdatePity(player, 0, true)
		else
			DataManager.UpdatePity(player, 1, false)
		end

		local newFace = GetRandomFace(newRace)
		DataManager.SetFace(player, newFace)

		DataManager.SetRaceStats(player, newRace, raceInfo.Stats)

		-- The client reads the race stats from PlayerStats.
		local statsFolder = player:FindFirstChild("PlayerStats")
		if statsFolder then
			if statsFolder:FindFirstChild("Race") then
				statsFolder.Race.Value = newRace
			end

			local function setVal(name, value)
				local obj = statsFolder:FindFirstChild(name)
				if obj then
					obj.Value = value
				end
			end
			local s = raceInfo.Stats
			setVal("HPBoost", s.HPBoost or 0)
			setVal("ManaBoost", s.ManaBoost or 1)
			setVal("DefenseBoost", s.DefenseBoost or 1)
			setVal("LiturgyMultiplier", s.LiturgyMultiplier or 1)
			setVal("RegenMultiplier", s.RegenMultiplier or 1)
			setVal("JumpBoost", s.JumpBoost or 1)
			setVal("DashDuration", s.DashDuration or 0.2)
			setVal("SlideDuration", s.SlideDuration or 2.0)

			if statsFolder:FindFirstChild("MaxMana") then
				local baseMana = 100
				local newMax = baseMana * (s.ManaBoost or 1)
				statsFolder.MaxMana.Value = newMax
				statsFolder.Mana.Value = newMax
			end
		end

		if raceInfo.StartBonus and raceInfo.StartBonus.Liturgy then
			DataManager.AddLiturgy(player, raceInfo.StartBonus.Liturgy)
		end

		if player.Character then
			ApplyRacePassives(player.Character, newRace)

			-- Drop every buff. BuffService keys buffs to the player, so a buff would carry the old
			-- race's modifier onto the new race.
			local BuffService = require(game.ServerScriptService.modules.BuffService)
			BuffService.ClearAll(player, player.Character)

			UpdateCharacterVisuals(player)

			-- Only applyStats turns HPBoost into Humanoid.MaxHealth.
			if _G.ApplyStats then
				_G.ApplyStats(player.Character)
			end
		end

		return newRace
	else
		return "NoSpins"
	end
end

-- Returns true for a hair asset ID, or 0 for an empty slot. The ID goes into the save.
local function isHairId(id)
	return typeof(id) == "number" and id >= 0 and id % 1 == 0 and id < 2 ^ 53
end

-- The payload goes into the player's save, so every field is checked first.
BarberEvent.OnServerEvent:Connect(function(player, action, payload)
	if action == "UpdateHair" then
		if typeof(payload) ~= "table" then
			return
		end
		for slot = 1, 3 do
			if payload[slot] ~= nil and not isHairId(payload[slot]) then
				warn(`[RaceHandler] {player.Name} sent a bad hair ID.`)
				return
			end
		end
		DataManager.SetHair(player, 1, payload[1] or 0)
		DataManager.SetHair(player, 2, payload[2] or 0)
		DataManager.SetHair(player, 3, payload[3] or 0)
		UpdateCharacterVisuals(player)
	elseif action == "ResetHair" then
		DataManager.ResetHair(player)
		UpdateCharacterVisuals(player)
	elseif action == "UpdateGender" then
		if payload ~= "Male" and payload ~= "Female" then
			return
		end
		DataManager.SetGender(player, payload)
		UpdateCharacterVisuals(player)
	elseif action == "DyeArmor" then
		if typeof(payload) ~= "Color3" then
			return
		end
		if DataManager.GetLiturgy(player) >= dyeCost then
			DataManager.RemoveLiturgy(player, dyeCost)
			DataManager.SetArmorColor(player, payload)
			UpdateCharacterVisuals(player)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		if WaitForData(player) then
			-- Wait for mainGameHandler to finish its part of the character setup, so
			-- CleanAccessories cannot remove the inventory visuals. The wait is bounded, so a
			-- failure there cannot block the appearance forever. See docs/systems-design.md.
			local waited = 0
			while not char:GetAttribute("BaseSetupComplete") and waited < 10 do
				task.wait(0.1)
				waited += 0.1
			end
			if not char:GetAttribute("BaseSetupComplete") then
				warn(
					`[RaceHandler] BaseSetupComplete never set for {player.Name}. Applying visuals.`
				)
			end

			UpdateCharacterVisuals(player)

			local profile = DataManager.GetProfile(player)
			local hum = char:WaitForChild("Humanoid")

			if profile.Data.JumpBoost and profile.Data.JumpBoost > 1 then
				hum.JumpHeight = 7.2 * profile.Data.JumpBoost
			end

			local race = profile.Data.Race or "Human"
			ApplyRacePassives(char, race)

			local statsFolder = player:FindFirstChild("PlayerStats")
			if statsFolder then
				for _, child in pairs(statsFolder:GetChildren()) do
					if child:IsA("NumberValue") then
						child.Value = child.Value
					end
				end
			end
		end
	end)
end)

-- Also set up players who joined before this script ran.
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		task.spawn(function()
			if WaitForData(player) then
				UpdateCharacterVisuals(player)
			end
		end)
	end
end
