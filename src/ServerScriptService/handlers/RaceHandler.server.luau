local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local DataManager = require(ServerScriptService.modules.dataManager)
local RaceConfig = require(ReplicatedStorage.modules.RaceConfig)
local RaceAssets = ServerStorage:FindFirstChild("RaceAssets")
local FacesFolder = ReplicatedStorage:WaitForChild("faces")

-- [[ REMOTE SETUP ]] --
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

-- [[ CONFIGURATION ]] --
local PITY_THRESHOLD = 30
local DYE_COST = 1000
local FEMALE_TORSO_ID = 48112070
local playerPity = {}

-- [[ --------------------- HELPER FUNCTIONS --------------------- ]] --

-- 1. DATA WAITER
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

-- 2. RNG & PITY
local function GetRandomRace(player)
	-- Check Pity
	local currentPity = DataManager.GetPity(player)
	local forceLegendary = false

	if currentPity >= PITY_THRESHOLD then
		forceLegendary = true
		print(player.Name .. " hit pity! Guaranteeing Legendary.")
	end

	-- Select Rarity
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

	-- Pick Race
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

-- 3. FACE SELECTION
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

-- [[ HELPER: CLEAN ACCESSORIES ]] --
local function CleanAccessories(char, keepDefaultHair)
	local hum = char:FindFirstChild("Humanoid")
	local player = game:GetService("Players"):GetPlayerFromCharacter(char)
	if not player then
		return
	end

	-- Create the cache folder inside the PLAYER object, safely out of the Workspace
	local hairCache = player:FindFirstChild("HairCache")
	if not hairCache then
		hairCache = Instance.new("Folder")
		hairCache.Name = "HairCache"
		hairCache.Parent = player
	end

	-- 1. If we are resetting, bring the default hair out of hiding
	if keepDefaultHair then
		for _, cachedHair in pairs(hairCache:GetChildren()) do
			cachedHair.Parent = char
			if hum then
				hum:AddAccessory(cachedHair)
			end
		end
	end

	-- 2. Loop through and clean up
	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Accessory") then
			-- Tag the player's original avatar hair so we don't confuse it with Barber hair
			if
				child.AccessoryType == Enum.AccessoryType.Hair
				and not child:GetAttribute("IsBarberHair")
				and not child:GetAttribute("IsRaceItem")
			then
				if not child:GetAttribute("IsDefaultHair") then
					child:SetAttribute("IsDefaultHair", true)
				end
			end

			-- Handle the default hair securely
			if child:GetAttribute("IsDefaultHair") then
				if keepDefaultHair then
					continue -- Leave it safely on their head
				else
					child.Parent = hairCache -- Hide it in the Player folder (removes it from the physical world!)
					continue
				end
			end

			-- Destroy everything else (like old barber hair, hats, etc.)
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

-- 5. LOAD HAIR ASSET (Barber Logic)
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
					-- Color
					if raceColor then
						handle.Color = raceColor
					end
					-- Texture Removal
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

-- [[ --------------------- MAIN VISUAL UPDATE --------------------- ]] --

local function UpdateCharacterVisuals(player)
	-- Safety Checks
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

	-- Wait for Data
	if not WaitForData(player) then
		return
	end

	-- Fetch Data
	local profile = DataManager.GetProfile(player)
	local appData = DataManager.GetAppearance(player) -- Barber Data
	local raceName = profile.Data.Race or "Human"
	local raceConfig = RaceConfig.Races[raceName]
	local visuals = raceConfig.Visuals or {}

	-- [[ NEW: DETERMINE HAIR STATUS BEFORE CLEANUP ]] --
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

	-- We only keep default hair if they don't have custom hair AND their race allows hair
	local keepDefaultHair = (not hasCustomHair) and not invisibleHair

	-- [[ 1. CLEANUP ]] --
	CleanAccessories(char, keepDefaultHair) -- Passes our new parameter

	-- Cleanup Character Meshes (Gender)
	for _, v in pairs(char:GetChildren()) do
		if v:IsA("CharacterMesh") and v.BodyPart == Enum.BodyPart.Torso then
			v:Destroy()
		end
	end

	-- Cleanup Default Face
	local defaultFace = char.Head:FindFirstChild("face")
	if defaultFace then
		defaultFace:Destroy()
	end

	-- Reset Limb Transparency
	local rArm = char:FindFirstChild("Right Arm")
	if rArm then
		rArm.Transparency = 0
	end

	local headPart = char:FindFirstChild("Head")
	if headPart then
		headPart.Transparency = 0
	end

	-- [[ 2. GENDER LOGIC ]] --
	if appData and appData.Gender == "Female" then
		local mesh = Instance.new("CharacterMesh")
		mesh.BodyPart = Enum.BodyPart.Torso
		mesh.MeshId = FEMALE_TORSO_ID
		mesh.Parent = char
	end

	-- [[ 3. SKIN COLOR ]] --
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

	-- [[ 4. FACE & EYES ]] --
	local face = char.Head:FindFirstChild("Face")
	if not face then
		face = Instance.new("Decal")
		face.Name = "Face"
		face.Face = Enum.NormalId.Front
		face.Parent = char.Head
	end

	-- Texture
	local savedFace = DataManager.GetFace(player)
	if savedFace then
		face.Texture = savedFace
	end

	-- Eye Color Tint
	if raceName == "Ancestor" then
		face.Color3 = Color3.fromRGB(200, 0, 0)
	else
		local eyeColor = DataManager.GetEyeColor(player)
		face.Color3 = eyeColor or Color3.new(0, 0, 0)
	end

	-- [[ 5. INVISIBILITY FLAGS ]] --
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

	-- [[ 6. HAIR LOGIC (UPDATED) ]] --
	local raceHairCol = visuals.HairColor or Color3.fromRGB(160, 160, 160)

	if not invisibleHair then
		if hasCustomHair then
			-- Load Custom Barber Hair
			for _, id in ipairs(appData.Hair) do
				LoadAccessoryById(hum, id, raceHairCol)
			end
		else
			-- Modify the Default Avatar Hair we spared earlier
			for _, child in pairs(char:GetChildren()) do
				if child:IsA("Accessory") and child:GetAttribute("IsDefaultHair") then
					local handle = child:FindFirstChild("Handle")
					if handle then
						-- Color
						if raceHairCol then
							handle.Color = raceHairCol
						end
						-- Texture Removal
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

	-- [[ 7. RACE ASSETS (Horns, Tails, etc.) ]] --
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

		-- Right Arm Replacement
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

		-- Head Asset Replacement
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

	-- [[ 8. ARMOR DYE LOGIC ]] --
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

-- [[ RACE PASSIVES ]] --
-- Passive stat flags live as Character attributes. They used to be applied by two
-- hand-maintained lists (one on reroll, one on spawn) that had drifted apart:
--
--   * Reroll cleared Hyperarmor / Lifesteal / SeerESP, but never touched
--     ManaWhenHit, so an Aegir who rerolled kept mana-on-hit forever.
--   * Spawn only ever SET flags (`if raceStats.X then set(X) end`) and never
--     cleared them, and also never set ManaWhenHit at all, so Aegir never actually
--     got its passive on respawn.
--
-- Both lists are now derived from RaceConfig itself. Every known passive is cleared
-- first, then only the current race's are set. Adding a passive to a race in
-- RaceConfig is enough; nothing here needs editing.

-- Stats key in RaceConfig -> Character attribute name. Anything not listed here is
-- a numeric stat handled through PlayerStats, not an attribute.
local RACE_PASSIVE_ATTRS = {
	Hyperarmor = "Hyperarmor",
	Lifesteal = "Lifesteal",
	ESP = "SeerESP",
	ManaWhenHit = "ManaWhenHit",
}

-- Clears every passive attribute, then applies the ones the given race actually has.
-- Clearing first is what makes rerolls safe: a race that simply lacks a field must
-- REMOVE the previous race's flag, not silently leave it standing.
local function ApplyRacePassives(char, raceName)
	if not char then
		return
	end
	local raceInfo = RaceConfig.Races[raceName]
	local stats = raceInfo and raceInfo.Stats

	for statKey, attrName in pairs(RACE_PASSIVE_ATTRS) do
		if stats and stats[statKey] then
			char:SetAttribute(attrName, true)
		else
			char:SetAttribute(attrName, nil)
		end
	end
end

-- [[ --------------------- EVENT HANDLERS --------------------- ]] --

-- 1. ROLL RACE
RollRaceFunction.OnServerInvoke = function(player)
	local spins = DataManager.GetSpins(player)
	if spins > 0 then
		DataManager.UpdateSpins(player, -1)

		-- RNG
		local newRace, rarity = GetRandomRace(player)
		local raceInfo = RaceConfig.Races[newRace]

		-- Update Pity
		if rarity == "Legendary" then
			DataManager.UpdatePity(player, 0, true)
		else
			DataManager.UpdatePity(player, 1, false)
		end

		-- Face Reroll
		local newFace = GetRandomFace(newRace)
		DataManager.SetFace(player, newFace)

		-- Save Data
		DataManager.SetRaceStats(player, newRace, raceInfo.Stats)

		-- Update PlayerStats Folder (For Client Visuals/Replication)
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

			-- Max Mana Recalc
			if statsFolder:FindFirstChild("MaxMana") then
				local baseMana = 100
				local newMax = baseMana * (s.ManaBoost or 1)
				statsFolder.MaxMana.Value = newMax
				statsFolder.Mana.Value = newMax
			end
		end

		-- Start Bonus
		if raceInfo.StartBonus and raceInfo.StartBonus.Liturgy then
			DataManager.AddLiturgy(player, raceInfo.StartBonus.Liturgy)
		end

		-- Update Attributes. Clears the OLD race's passives before applying the new
		-- race's, so a reroll off Ancestor drops Lifesteal and a reroll off Aegir
		-- drops ManaWhenHit.
		if player.Character then
			ApplyRacePassives(player.Character, newRace)

			-- Drop any active buff. BuffService keys its state to the PLAYER, not the
			-- character, so a buff running across a reroll carried the OLD race's
			-- damage/heal modifier onto the new one.
			local BuffService = require(game.ServerScriptService.modules.BuffService)
			BuffService.ClearAll(player, player.Character)

			-- Full Visual Refresh
			UpdateCharacterVisuals(player)

			-- Push the new race's stats into the Humanoid. The block above only wrote
			-- the PlayerStats value objects; applyStats is what turns HPBoost into
			-- Humanoid.MaxHealth. Skipping it left MaxHealth on the PREVIOUS race's
			-- value while the stat object read the new one, so the HP bar and the
			-- humanoid disagreed (the "low HP text" after rerolling into Maw/Seer).
			if _G.ApplyStats then
				_G.ApplyStats(player.Character)
			end
		end

		return newRace
	else
		return "NoSpins"
	end
end

-- 2. BARBER EVENTS
BarberEvent.OnServerEvent:Connect(function(player, action, payload)
	if action == "UpdateHair" then
		DataManager.SetHair(player, 1, payload[1] or 0)
		DataManager.SetHair(player, 2, payload[2] or 0)
		DataManager.SetHair(player, 3, payload[3] or 0)
		UpdateCharacterVisuals(player)
	elseif action == "ResetHair" then
		DataManager.ResetHair(player)
		UpdateCharacterVisuals(player)
	elseif action == "UpdateGender" then
		DataManager.SetGender(player, payload)
		UpdateCharacterVisuals(player)
	elseif action == "DyeArmor" then
		if DataManager.GetLiturgy(player) >= DYE_COST then
			DataManager.RemoveLiturgy(player, DYE_COST)
			DataManager.SetArmorColor(player, payload)
			UpdateCharacterVisuals(player)
		end
	end
end)

-- 3. PLAYER SPAWN
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		if WaitForData(player) then
			-- Wait for mainGameHandler to finish its half of the character setup.
			--
			-- Both scripts have their own CharacterAdded and both write appearance.
			-- mainGameHandler owns armor (Shirt/Pants), stats, and inventory visuals;
			-- this script owns skin, face, hair, race items, and runs CleanAccessories,
			-- which DESTROYS any accessory not named EquipSlot_*.
			--
			-- The ordering used to rest on nothing but this script waiting 0.5s while
			-- the other waited 0.3s. That is a race, not coordination: if
			-- HandleCharacterLoad yielded long enough (WaitForChild with 10s timeouts,
			-- a spin on IsDescendantOf), LoadAllVisuals would land after our wipe and
			-- the player's equipment would vanish.
			--
			-- Wait on the explicit flag instead, with a bounded fallback so a failure
			-- over there cannot hang appearance over here forever.
			local waited = 0
			while not char:GetAttribute("BaseSetupComplete") and waited < 10 do
				task.wait(0.1)
				waited += 0.1
			end
			if not char:GetAttribute("BaseSetupComplete") then
				warn(
					"[RaceHandler] BaseSetupComplete never set for "
						.. player.Name
						.. "; applying visuals anyway (appearance may race)."
				)
			end

			-- Apply everything
			UpdateCharacterVisuals(player)

			-- Apply Stat-based Physical Attributes
			local profile = DataManager.GetProfile(player)
			local hum = char:WaitForChild("Humanoid")

			if profile.Data.JumpBoost and profile.Data.JumpBoost > 1 then
				hum.JumpHeight = 7.2 * profile.Data.JumpBoost
			end

			local race = profile.Data.Race or "Human"
			ApplyRacePassives(char, race)

			-- Refresh Stats Folder visuals
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

-- Handle players already in server
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		task.spawn(function()
			if WaitForData(player) then
				UpdateCharacterVisuals(player)
			end
		end)
	end
end
