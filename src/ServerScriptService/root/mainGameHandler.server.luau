-- [[ MAIN GAME HANDLER ]] --
-- Location: ServerScriptService (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Modules
local DataManager = require(ServerScriptService.modules:WaitForChild("dataManager"))
local InventoryManager = require(ServerScriptService.modules:WaitForChild("inventoryManager"))
local RagdollManager = require(ServerScriptService.modules:WaitForChild("ragdollManager"))
local RaceConfig = require(ReplicatedStorage.modules:WaitForChild("RaceConfig"))
local ArmorConfig = require(ReplicatedStorage.modules:WaitForChild("ArmorConfig"))
local TitleManager = require(ServerScriptService.modules:WaitForChild("TitleManager"))
local StateHandler = require(ReplicatedStorage.modules:WaitForChild("stateHandler"))
local StatScaling = require(ReplicatedStorage.modules:WaitForChild("StatScaling"))
local BuffService = require(ServerScriptService.modules:WaitForChild("BuffService"))
local GuardBarService = require(ServerScriptService.modules:WaitForChild("GuardBarService"))
local SpeedService = require(ServerScriptService.modules:WaitForChild("SpeedService"))

local BASE_WALKSPEED = 16
local BASE_JUMP_HEIGHT = 7.2 
local BASE_HP = 100

-- Configuration
local EVENTS_FOLDER = ReplicatedStorage:WaitForChild("remotes")
local SPAWN_EVENT = EVENTS_FOLDER:WaitForChild("SpawnPlayer")
local CHANGE_WEAPON_EVENT = EVENTS_FOLDER:WaitForChild("ChangeWeapon")
local BUY_WEAPON_EVENT = EVENTS_FOLDER:WaitForChild("BuyWeapon")
local BUY_SPELL_EVENT = EVENTS_FOLDER:WaitForChild("BuySpell")
local ON_DEATH_EVENT = EVENTS_FOLDER:WaitForChild("OnDeath")
local BUY_ARMOR_EVENT = EVENTS_FOLDER:WaitForChild("BuyArmor")
local MOVE_ITEM_EVENT = EVENTS_FOLDER:WaitForChild("MoveItem")
local BUY_ITEM_EVENT = EVENTS_FOLDER:WaitForChild("BuyItem")
local USE_HOTBAR_EVENT = EVENTS_FOLDER:WaitForChild("UseHotbar")
local REQUEST_SYNC_EVENT = EVENTS_FOLDER:WaitForChild("RequestSync")
local RETURN_TO_MENU_EVENT = EVENTS_FOLDER:WaitForChild("ReturnToMenu")
local STOP_WEAPON_IDLE_EVENT = EVENTS_FOLDER:WaitForChild("StopWeaponIdle")

local WEAPON_FOLDER = ServerStorage:WaitForChild("Weapons")
local EQUIPMENT_FOLDER = ServerStorage:WaitForChild("Equipment")
local MENU_SPAWN_NAME = "MenuSpawn"
local RACE_SPAWNS_FOLDER_NAME = "raceSpawns" 
local TUTORIAL_SPAWN_LOC = workspace:WaitForChild("tutorialSpawn"):WaitForChild("Spawn")

local SPELLS_LIST = {
	"Whirlwind", "Abyssal Scream", "Berserker Armor", "Elfin Dance", "Air Wave", "Morgan",
	"Gohadoken", "Asura Glide", "Messatsu", "Zanshin", "Kurai", "Kirikizu",
	"Monastic Stance", "Mantra Palm", "Rising Dragon",
}

-- [[ ARMOR LOGIC ]] --

local function UpdateArmorVisuals(character, armorName)
	if not character then return end
	local armorData = ArmorConfig.Armors[armorName] or ArmorConfig.Armors["Rags"]

	-- Handle Shirt
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "ArmorShirt"
		shirt.Parent = character
	end
	shirt.ShirtTemplate = armorData.ShirtID

	-- Handle Pants
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "ArmorPants"
		pants.Parent = character
	end
	pants.PantsTemplate = armorData.PantsID
end

local function UpdateArmorStats(player, armorName)
	local stats = player:WaitForChild("PlayerStats", 5)
	if not stats then return end

	local armorBuffs = stats:WaitForChild("ArmorBuffs", 5)
	if not armorBuffs then 
		warn("ArmorBuffs folder missing for " .. player.Name)
		return 
	end

	local armorData = ArmorConfig.Armors[armorName]

	if not armorData then
		warn("Armor [" .. tostring(armorName) .. "] not found in Config! Defaulting to Rags.")
		armorData = ArmorConfig.Armors["Rags"]
	end

	if armorBuffs:FindFirstChild("HPBuff") then
		armorBuffs.HPBuff.Value = armorData.HPBuff
	end
	if armorBuffs:FindFirstChild("DefenseBuff") then
		armorBuffs.DefenseBuff.Value = armorData.DefBuff
	end
	if armorBuffs:FindFirstChild("DamageBuff") then
		armorBuffs.DamageBuff.Value = armorData.DmgBuff
	end
end

-- [[ STATS & RACE APPLICATION ]] --
local function applyStats(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local statsFolder = player:WaitForChild("PlayerStats", 10)
	if not statsFolder then return end

	local armorBuffs = statsFolder:WaitForChild("ArmorBuffs") 

	local humanoid = character:WaitForChild("Humanoid")

	-- [[ 2. VALIDATE & ENFORCE CONFIG ]] --
	local raceName = statsFolder:WaitForChild("Race").Value
	local raceData = RaceConfig.Races[raceName] or RaceConfig.Races["Human"]
	local targetStats = raceData.Stats or {}

	local statDefaults = {
		{Name = "HPBoost", Default = 0},
		{Name = "ManaBoost", Default = 1},
		{Name = "SpeedBoost", Default = 1},
		{Name = "DamageBoost", Default = 1},
		{Name = "DefenseBoost", Default = 1},
		{Name = "RegenMultiplier", Default = 1},
		{Name = "LiturgyMultiplier", Default = 1},
		{Name = "JumpBoost", Default = 1},
		{Name = "DashDuration", Default = 0.2},
		{Name = "SlideDuration", Default = 2.0}
	}

	for _, statDef in ipairs(statDefaults) do
		local name = statDef.Name
		local default = statDef.Default
		local expectedValue = targetStats[name] or default

		local valObj = statsFolder:FindFirstChild(name)
		if valObj then
			if valObj.Value ~= expectedValue then
				valObj.Value = expectedValue
			end
		end
	end

	-- [[ 3. HEALTH LOGIC ]] --
	local function updateHealth()
		local raceBoost = statsFolder:FindFirstChild("HPBoost") and statsFolder.HPBoost.Value or 0
		local armorMult = 1
		if armorBuffs:FindFirstChild("HPBuff") then
			armorMult = armorBuffs.HPBuff.Value
		end

		-- [[ STAT SPREAD: Vitality adds flat HP additively, BEFORE the armor multiply ]] --
		local vitPoints = 0
		local sf = statsFolder:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Vitality") then vitPoints = sf.Vitality.Value end
		local vitBonus = StatScaling.GetHPBonus(vitPoints)

		local newMax = (BASE_HP + raceBoost + vitBonus) * armorMult

		if math.abs(humanoid.MaxHealth - newMax) > 0.1 then
			local oldMax = humanoid.MaxHealth
			local oldHealth = humanoid.Health

			humanoid.MaxHealth = newMax

			if newMax > oldMax then
				humanoid.Health = humanoid.Health + (newMax - oldMax)
			elseif humanoid.Health > newMax then
				humanoid.Health = newMax
			end
		end
	end

	if statsFolder:FindFirstChild("HPBoost") then
		statsFolder.HPBoost.Changed:Connect(updateHealth)
	end
	if armorBuffs:FindFirstChild("HPBuff") then
		armorBuffs.HPBuff.Changed:Connect(updateHealth)
	end
	do
		local sf = statsFolder:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Vitality") then
			sf.Vitality.Changed:Connect(updateHealth)
		end
	end

	updateHealth()

	-- [[ 4. BIND ATTRIBUTES ]] --
	local function updateAttribute(statName, attributeName, armorStatName)
		local raceVal = statsFolder:FindFirstChild(statName) and statsFolder[statName].Value or 1
		local armorVal = 1

		if armorStatName and armorBuffs:FindFirstChild(armorStatName) then
			armorVal = armorBuffs[armorStatName].Value
		end

		character:SetAttribute(attributeName, raceVal * armorVal)
	end

	updateAttribute("DefenseBoost", "DefenseMultiplier", "DefenseBuff")
	updateAttribute("DamageBoost", "DamageMultiplier", "DamageBuff") 
	updateAttribute("RegenMultiplier", "RegenMultiplier", "N/A")

	if armorBuffs:FindFirstChild("DefenseBuff") then
		armorBuffs.DefenseBuff.Changed:Connect(function() updateAttribute("DefenseBoost", "DefenseMultiplier", "DefenseBuff") end)
	end
	
	if armorBuffs:FindFirstChild("DamageBuff") then
		armorBuffs.DamageBuff.Changed:Connect(function() updateAttribute("DamageBoost", "DamageMultiplier", "DamageBuff") end)
	end

	-- [[ 5. MOVEMENT STATS ]] --
	local function updateJump()
		local jumpMult = statsFolder:FindFirstChild("JumpBoost") and statsFolder.JumpBoost.Value or 1
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = BASE_JUMP_HEIGHT * jumpMult
	end
	if statsFolder:FindFirstChild("JumpBoost") then
		statsFolder.JumpBoost.Changed:Connect(updateJump)
	end
	updateJump() 

	local function updateSpeed()
		-- Route through SpeedService so a Stamina/SpeedBoost change re-settles the
		-- character to the correct value WITHOUT stomping an active stun/block/skill
		-- pin. Resolve computes GetFullSpeed (GetBaseWalkSpeed * SpeedBoost) when the
		-- modifier stack is empty, which is exactly the old behavior, and keeps the
		-- higher-priority modifier's speed when one is live.
		SpeedService.Resolve(humanoid.Parent)
	end
	if statsFolder:FindFirstChild("SpeedBoost") then
		statsFolder.SpeedBoost.Changed:Connect(updateSpeed)
	end
	-- re-apply when Stamina changes (level-up / respec)
	do
		local sf = statsFolder:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			sf.Stamina.Changed:Connect(updateSpeed)
		end
	end
	updateSpeed()
end

-- Exposed so other server scripts can force a stat re-apply. RaceHandler needs this:
-- a reroll changes HPBoost/ManaBoost on the PlayerStats value objects, but only
-- applyStats pushes those into Humanoid.MaxHealth. Without it, rerolling from Maw
-- (HPBoost 35) to Human (HPBoost 10) left MaxHealth stuck at the old value while the
-- stat object read the new one, so the HP bar and the actual humanoid disagreed.
-- (Same _G pattern the codebase already uses for QuestManager and TitleManager.)
_G.ApplyStats = applyStats

-- [[ HELPER: DATA WAITER ]] --
local function WaitForData(player)
	local timeout = 0
	while not DataManager.GetProfile(player) do
		task.wait(0.2)
		timeout += 0.2
		if timeout > 30 then return false end
	end
	return true
end

local GROUND_CHECK_RAYCAST = RaycastParams.new()
GROUND_CHECK_RAYCAST.FilterType = Enum.RaycastFilterType.Exclude

local function StartPositionTracker(player)
	task.spawn(function()
		while player and player.Parent do
			task.wait(1)
			
			local char = player.Character
			if not char then continue end

			local humanoid = char:FindFirstChild("Humanoid")
			local rootPart = char:FindFirstChild("HumanoidRootPart")
			if not humanoid or not rootPart then continue end
			
			if player:GetAttribute("HasPressedPlay") ~= true then continue end

			-- not dead
			if humanoid.Health <= 0 then 
				DataManager.ClearLastPosition(player)
				continue 
			end

			-- not downed
			if StateHandler.GetState(char, "Downed") then 
				DataManager.ClearLastPosition(player)
				continue 
			end

			-- not in combat
			local combatExpiry = player:GetAttribute("CombatLogExpiry")
			if combatExpiry and os.clock() < combatExpiry then 
				DataManager.ClearLastPosition(player)
				continue 
			end

			-- only save when grounded
			local state = humanoid:GetState()
			local isGrounded = (
				state == Enum.HumanoidStateType.Running or
					state == Enum.HumanoidStateType.RunningNoPhysics or
					state == Enum.HumanoidStateType.Landed or
					state == Enum.HumanoidStateType.Seated
			)

			if not isGrounded then continue end

			-- All conditions passed — save this position
			DataManager.SaveLastPosition(player, rootPart.Position)
		end
	end)
end

-- [[ SPAWNING LOGIC ]] --
local function SafeTeleport(rootPart, cframe, description)
	rootPart.Anchored = true
	rootPart.CFrame = cframe
	task.wait(0.1) 
	rootPart.Anchored = false
	print(string.format("[GAME] Teleported %s to %s", rootPart.Parent.Name, description))
end

local function SendToGameSpawn(character)
	character.Parent = workspace.plrManager.alive
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- 1. Get Player & Race
	local player = Players:GetPlayerFromCharacter(character)
	local raceName = "Human" -- Default fallback

	if player then
		local stats = player:FindFirstChild("PlayerStats")
		if stats and stats:FindFirstChild("Race") then
			raceName = stats.Race.Value
		end
	end

	-- 2. Find the main Spawns folder
	local allSpawnsFolder = workspace:FindFirstChild(RACE_SPAWNS_FOLDER_NAME)

	if allSpawnsFolder then
		local validSpawns = {}

		-- 3. Check for specific Race Folder
		local raceSpecificFolder = allSpawnsFolder:FindFirstChild(raceName)

		if raceSpecificFolder then
			-- A: Folder Exists -> Collect spawns ONLY from this folder
			for _, child in ipairs(raceSpecificFolder:GetChildren()) do
				if child:IsA("BasePart") then
					table.insert(validSpawns, child)
				end
			end
		else
			-- B: Folder Does Not Exist -> Collect spawns from Main Folder (ignoring sub-folders)
			for _, child in ipairs(allSpawnsFolder:GetChildren()) do
				if child:IsA("BasePart") then -- This ensures we don't pick other Race Folders
					table.insert(validSpawns, child)
				end
			end
		end

		-- 4. Pick Random
		if #validSpawns > 0 then
			local randomSpawn = validSpawns[math.random(1, #validSpawns)]
			local targetCF = CFrame.new(randomSpawn.Position + Vector3.new(0, 4, 0))
			SafeTeleport(rootPart, targetCF, "GameSpawn (" .. raceName .. ")")
		else
			warn("[GAME] No valid spawn parts found for race: " .. raceName)
			-- Optional: Add a fallback here if absolutely no spawns exist
		end

	else
		warn("[GAME] '" .. RACE_SPAWNS_FOLDER_NAME .. "' folder missing in Workspace!")
	end
end

local function SendToTutorialSpawn(character)
	character.Parent = workspace.plrManager.noPVP
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if TUTORIAL_SPAWN_LOC then
		local targetCF = CFrame.new(TUTORIAL_SPAWN_LOC.Position + Vector3.new(0, 4, 0))
		SafeTeleport(rootPart, targetCF, "TutorialSpawn")
	else
		SendToGameSpawn(character)
	end
end

local function HandleCharacterLoad(player, character)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not rootPart or not humanoid then return end

	while not character:IsDescendantOf(workspace) do task.wait() end

	-- Character Config
	character.Archivable = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local attach = Instance.new("Attachment", rootPart)
	attach.Name = "ForceAttachment"

	-- Guard meter: establish the GuardBar attribute so the HUD controller can read
	-- it and GuardBarService's regen loop will service this character.
	GuardBarService.Init(character)

	-- [[ ARMOR SETUP ON SPAWN ]] --
	-- Stats come from the stats-armor; visuals from the (possibly transmogged) vanity.
	local currentArmor = DataManager.GetCurrentArmor(player)
	local currentVanity = DataManager.GetCurrentVanity(player)
	UpdateArmorVisuals(character, currentVanity)
	UpdateArmorStats(player, currentArmor) 

	if player:GetAttribute("HasPressedPlay") == false then
		-- MENU SPAWN
		local menuSpawn = workspace.spawnRoom:FindFirstChild(MENU_SPAWN_NAME)
		if menuSpawn then
			rootPart.CFrame = CFrame.new(menuSpawn.Position + Vector3.new(0, 3, 0))
			rootPart.Anchored = true
			if not character:FindFirstChild("MenuProtection") then
				local ff = Instance.new("ForceField")
				ff.Name = "MenuProtection"
				ff.Visible = true 
				ff.Parent = character
			end
		end
	else
		if WaitForData(player) then
			local isComplete = DataManager.GetTutorialComplete(player)
			if isComplete then
				SendToGameSpawn(character)
			else
				SendToTutorialSpawn(character)
			end
		else
			player:Kick("Data load timeout. Please rejoin.")
		end
	end

	-- Death
	humanoid.Died:Connect(function()
		RagdollManager.Ragdoll(character, 10)
		if not rootPart.Anchored then rootPart:SetNetworkOwner(player) end
		ReplicatedStorage.remotes.RagdollForce:FireClient(player)
		
		DataManager.ClearLastPosition(player)
		
		local TagManager = require(ServerScriptService.modules.combatTagManager)

		local player = Players:GetPlayerFromCharacter(character)
		if player then
			TagManager.UntagIfAttackerDied(player) -- remove the dead player as an attacker from others
			TagManager.ClearPlayerTag(player)      -- and clear their OWN tag so death ends combat (stops music)
		end
	end)
end

-- [[ LOOT & INVENTORY ]] --
local function connectLootLogic(humanoid)
	if humanoid:GetAttribute("LootLinked") then return end
	humanoid:SetAttribute("LootLinked", true)
 
	humanoid.Died:Connect(function()
		if humanoid:GetAttribute("HasDroppedLoot") then return end
		humanoid:SetAttribute("HasDroppedLoot", true)
 
		local model = humanoid.Parent
		if not model or not model:FindFirstChild("HumanoidRootPart") then return end
 
		local dyingPlayer = Players:GetPlayerFromCharacter(model)
 
		if dyingPlayer then
			-- [[ DEATH TRACKING ]]
			if DataManager and TitleManager then
				DataManager.AddDeath(dyingPlayer)
				TitleManager.CheckDeaths(dyingPlayer)
			end
 
			DataManager.HandlePlayerDeath(dyingPlayer, model.HumanoidRootPart.Position)
 
			-- [[ KILL CREDIT ]]
			local killTag = humanoid:FindFirstChild("KillTag")
			if killTag and killTag.Value ~= "" then
				local killer = Players:FindFirstChild(killTag.Value)
				if killer and killer ~= dyingPlayer then
					print(killer.Name .. " KILLED " .. model.Name)
					if DataManager and TitleManager then
						DataManager.AddKill(killer)
						TitleManager.CheckKills(killer)
					end
				end
			end
		else
			local worth = model:GetAttribute("LiturgyWorth")
			if worth and worth > 0 then
				DataManager.CreateDrop(model.HumanoidRootPart.Position, worth)
			end
		end
	end)
end

local function EquipWeapon(player, weaponName, deleteOld)
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then return end
	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then return end

	char.Humanoid:UnequipTools()
	task.wait(0.1)

	if deleteOld then DataManager.ClearInventory(player) end

	-- Cleaner function
	local function clean(parent)
		for _, item in pairs(parent:GetChildren()) do
			if WEAPON_FOLDER:FindFirstChild(item.Name) then
				if deleteOld or not table.find(SPELLS_LIST, item.Name) then
					item:Destroy() 
				end
			end
		end
	end

	clean(player.Backpack)
	clean(player.StarterGear)
	clean(char)

	weaponTemplate:Clone().Parent = player.Backpack
	weaponTemplate:Clone().Parent = player.StarterGear
	DataManager.SetCurrentWeapon(player, weaponName)
end

local function LoadInventory(player)
	if not WaitForData(player) then return end
	local savedData = DataManager.GetInventoryData(player) or {}

	InventoryManager.new(player, savedData)
end

-- [[ EVENT LISTENERS ]] --
Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasPressedPlay", false)
	task.spawn(function() DataManager.PlayerAdded(player) end)
	task.delay(0.2, function() LoadInventory(player) end)
	task.delay(5, function()
		StartPositionTracker(player)
	end)

	player.CharacterAdded:Connect(function(character)
		-- Tear down any buff left standing from the PREVIOUS life. Buffs were only
		-- ever cleared by their own expiry timer, so dying mid-buff left the entry
		-- in BuffService (still applying its damage/heal modifier on the new body)
		-- and left the aura particles welded to the corpse.
		BuffService.ClearAll(player, nil)

		local diedConn
		local hum0 = character:WaitForChild("Humanoid")
		diedConn = hum0.Died:Connect(function()
			if diedConn then diedConn:Disconnect() diedConn = nil end
			-- Sweep THIS body explicitly: the corpse persists after death, and by the
			-- time a later teardown runs, plr.Character is already the new character,
			-- so an un-swept aura would stay on the old one forever.
			BuffService.ClearAll(player, character)
		end)

		WaitForData(player)
		task.wait(0.3) 
		
		TitleManager.CheckSpecUnlock(player)
		TitleManager.UpdateAura(player, DataManager.GetCurrentTitle())

		-- 1. Apply Appearance and Stats
		HandleCharacterLoad(player, character) 
		applyStats(character) 
		connectLootLogic(character:WaitForChild("Humanoid"))

		local hum = character:FindFirstChild("Humanoid")
		if hum then hum.Health = hum.MaxHealth end
		player:FindFirstChild("PlayerStats").Mana.Value = player:FindFirstChild("PlayerStats").MaxMana.Value
		
		-- Wait for the expected weapon to land in the Backpack before equipping
		local currentWeapon = DataManager.GetCurrentWeapon(player)
		if currentWeapon and currentWeapon ~= "" then
			local backpack = player:FindFirstChild("Backpack")
			if backpack and not backpack:FindFirstChild(currentWeapon) then
				-- Wait up to 3 seconds for the grant block to finish
				local waited = 0
				repeat
					task.wait(0.1)
					waited += 0.1
				until (backpack:FindFirstChild(currentWeapon)) or waited >= 3
			end
		end
		
		DataManager.EquipLoadout(player, character)
		
		local currentArmor = DataManager.GetCurrentArmor(player)
		local currentVanity = DataManager.GetCurrentVanity(player)
		UpdateArmorVisuals(character, currentVanity)
		UpdateArmorStats(player, currentArmor) 

		local playerInv = InventoryManager.GetInventory(player)
		if playerInv then
			playerInv:HookBackpack()
			playerInv:LoadAllVisuals()
			playerInv:Sync()
		end

		-- Handshake for RaceHandler. Both scripts have their own CharacterAdded and
		-- both write appearance: this one owns armor (Shirt/Pants), stats, inventory
		-- visuals; RaceHandler owns skin, face, hair, race items, and runs
		-- CleanAccessories, which destroys any accessory not named EquipSlot_*.
		--
		-- The ordering used to rest entirely on one script waiting 0.3s and the other
		-- 0.5s, which is not coordination, it is a race that usually wins. If
		-- HandleCharacterLoad yielded long enough (it has WaitForChild calls with 10s
		-- timeouts and a spin on IsDescendantOf), LoadAllVisuals could land AFTER
		-- CleanAccessories and get wiped.
		--
		-- RaceHandler now waits on this attribute instead of a magic number.
		character:SetAttribute("BaseSetupComplete", true)
	end)
end)

Players.PlayerRemoving:Connect(function(player) DataManager.PlayerRemoving(player) end)

local MENU_AREA_CENTER = Vector3.new(-3232.061, 6, -1263.206)
local MENU_AREA_HALF_SIZE = Vector3.new(82, 20, 79) -- Half of 164, generous Y, half of 158

local function IsInMenuArea(position)
	local diff = position - MENU_AREA_CENTER
	return 
		math.abs(diff.X) <= MENU_AREA_HALF_SIZE.X and
		math.abs(diff.Y) <= MENU_AREA_HALF_SIZE.Y and
		math.abs(diff.Z) <= MENU_AREA_HALF_SIZE.Z
end


SPAWN_EVENT.OnServerEvent:Connect(function(player)
	task.delay(2.1, function()
		player:SetAttribute("HasPressedPlay", true)
	end)
	local char = player.Character
	if char then
		local ff = char:FindFirstChild("MenuProtection")
		if ff then ff:Destroy() end

		local isComplete = DataManager.GetTutorialComplete(player)
		if not isComplete then
			SendToTutorialSpawn(char)
			return
		end

		-- [[ SAVED POSITION RESTORE ]] --
		local savedPos = DataManager.GetLastPosition(player)
		if savedPos and IsInMenuArea(savedPos) then
			print("[GAME] Saved position was inside menu area, clearing.")
			DataManager.ClearLastPosition(player)
			savedPos = nil
		end
		if savedPos then
			local rootPart = char:FindFirstChild("HumanoidRootPart")
			if rootPart then
				GROUND_CHECK_RAYCAST.FilterDescendantsInstances = {char}
				local rayResult = workspace:Raycast(
					savedPos + Vector3.new(0, 5, 0),
					Vector3.new(0, -20, 0),
					GROUND_CHECK_RAYCAST
				)

				local targetPos
				if rayResult then
					targetPos = rayResult.Position + Vector3.new(0, 3, 0)
				else
					targetPos = savedPos + Vector3.new(0, 3, 0)
				end

				print("[GAME] Restoring " .. player.Name .. " to saved position: " .. tostring(targetPos))
				char.Parent = workspace.plrManager.alive
				SafeTeleport(rootPart, CFrame.new(targetPos), "SavedPosition")
				return
			end
		end
		SendToGameSpawn(char)
	end
end)

REQUEST_SYNC_EVENT.OnServerEvent:Connect(function(player)
	local inv = InventoryManager.GetInventory(player)
	if inv then
		inv:Sync()
	end
end)

-- [[ BUYING ARMOR EVENT ]] --
BUY_ARMOR_EVENT.OnServerEvent:Connect(function(player, armorName)
	local armorData = ArmorConfig.Armors[armorName]
	if not armorData then return end

	if DataManager.OwnsArmor(player, armorName) then
		DataManager.SetCurrentArmor(player, armorName)
		DataManager.SetCurrentVanity(player, nil) -- equipping resets transmog
		UpdateArmorVisuals(player.Character, armorName)
		UpdateArmorStats(player, armorName)
		applyStats(player.Character) 
		return
	end

	if DataManager.RemoveLiturgy(player, armorData.Cost) then
		if player.Character and player.Character:FindFirstChild("Torso") then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = player.Character.Torso
			s:Play()
			game.Debris:AddItem(s, 2)
		end

		DataManager.AddArmor(player, armorName)
		DataManager.SetCurrentArmor(player, armorName)
		DataManager.SetCurrentVanity(player, nil) -- equipping resets transmog

		UpdateArmorVisuals(player.Character, armorName)
		UpdateArmorStats(player, armorName)
		applyStats(player.Character)
	end
end)

-- Deterministic server-side cleanup when swapping weapons.
-- Clears the arm tool-grip welds directly (instead of waiting for the client
-- DisconnectM6D round-trip, which races the tool destroy) and tells the client
-- to stop the old weapon's looping idle track.
local function cleanupWeaponVisuals(player)
	local char = player.Character
	if char then
		local rArm = char:FindFirstChild("Right Arm")
		local lArm = char:FindFirstChild("Left Arm")
		local rGrip = rArm and rArm:FindFirstChild("ToolGrip")
		local lGrip = lArm and lArm:FindFirstChild("ToolGrip")
		if rGrip then rGrip.Part1 = nil end
		if lGrip then lGrip.Part1 = nil end
	end
	STOP_WEAPON_IDLE_EVENT:FireClient(player)
end

-- Humanoid:UnequipTools() is deferred: the old tool re-parents to the Backpack on a
-- later frame, not synchronously. A blind single task.wait() sometimes returned before
-- that settled, so ClearWeapons ran against a character that still held the old tool and
-- the swap left stale equipped state (new weapon then needed a manual unequip+re-equip).
-- Yield until the character genuinely has no equipped Tool, bounded so a stuck tool can
-- never hang the handler.
local function waitForNoEquippedTool(player)
	for _ = 1, 8 do
		local char = player.Character
		if not char or not char:FindFirstChildOfClass("Tool") then return end
		task.wait()
	end
end

-- [[ AUTHORITATIVE WEAPON PRICES ]] --
-- The client used to send the price along with the purchase, and the server charged
-- whatever it was told. A crafted BuyWeapon fire with price 0 bought anything free.
-- The price now lives here and the client's number is ignored entirely.
--
-- Seeds are granted free by the tutorial NPCs and also sold for 500 in the shops.
-- HasItem blocks re-purchase, so the shop is only ever reachable by someone who
-- skipped the tutorial. Both doors resolve to this one entry.
local WEAPON_PRICES = {
	-- seeds (free from the tutorial NPCs)
	["Fists"]         = 0,
	["Sword"]         = 0,
	["Katana"]        = 0,
	["Dagger"]        = 0,
	["Greatsword"]    = 0,

	-- branch weapons (class vendors, gated on family level 10)
	["Caestus"]       = 1000,
	["Shackles"]      = 1000,
	["Excalibur"]     = 1000,
	["Vermillion"]    = 1000,
	["Tanto"]         = 1000,
	["Dragon Slayer"] = 1000,
	["Deathbringer"]  = 1500,

	-- hybrids (trainer-gated, world-discovered)
	["Guandao"]       = 2500,
	["Scythe"]        = 2500,
}

BUY_WEAPON_EVENT.OnServerEvent:Connect(function(player, weaponName, price)
	-- Never trust the shape of client input either: a table here would throw inside
	-- FindFirstChild.
	if type(weaponName) ~= "string" then return end

	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then return end

	-- The client's `price` argument is deliberately discarded. A weapon absent from
	-- the table is simply not for sale, rather than falling back to a client claim.
	price = WEAPON_PRICES[weaponName]
	if not price then
		warn("[BuyWeapon] no server price for '" .. weaponName .. "'; refusing sale to " .. player.Name)
		return
	end

	-- Optional: Check if they already own it
	if DataManager.HasItem(player, weaponName) then return end 

	local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)

	if stateHandler.GetState(player.Character, "CantAnything") then return end

	local inv = InventoryManager.GetInventory(player)

	-- Guard the Backpack hook so the deferred UnequipTools below can't
	-- re-register the old tool after ClearWeapons wipes it.
	if inv then inv.IsSwapping = true end

	player.Character.Humanoid:UnequipTools()
	-- Wait until the old tool has actually left the character, not just one frame.
	waitForNoEquippedTool(player)

	if DataManager.RemoveLiturgy(player, price) then
		if player.Character and player.Character:FindFirstChild("Torso") then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = player.Character.Torso
			s:Play()
			game.Debris:AddItem(s, 2)
		end

		-- [[ HYBRID REPLACEMENT LOGIC ]] --
		if inv then
			inv:ClearWeapons() -- Wipes the old weapons securely
			-- Stop the orphaned idle AFTER the old tool is destroyed (see ChangeWeapon).
			cleanupWeaponVisuals(player)
			inv:AddItem(weaponName, 1) -- Grants the new physical tool and logs the data
		end

		-- [[ LEVEL 10 CLASS QUEST ]] --
		-- The 10 milestone is "you may now be armed", so BUYING the branch weapon is
		-- what closes it. The trainer has nothing to teach until 15 and cannot be the
		-- completion. Handled here, at the single server-side purchase chokepoint, so
		-- it fires for every branch weapon and cannot be spoofed by a client firing
		-- QuestAction directly.
		--
		-- Completion is family-scoped, not weapon-scoped: buying EITHER fist weapon
		-- closes ClassQuest_Fists_10. A player who ignores the marker and finds the
		-- Oni on their own still gets credit. The quest is a hint, not a rail, and
		-- Akuma is never surfaced by the UI.
		--
		-- Completing it hands control back to the reconciler, so a player who is
		-- already past 15 immediately gets the next checkpoint rather than waiting
		-- for a level-up that already happened.
		local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
		local family = SkillConfig.GetXPFamily(weaponName)
		-- Seeds (Fists, Sword, ...) map to themselves and are not a branch purchase.
		if family and family ~= weaponName then
			local qm = _G.QuestManager
			if qm then
				local questId = "ClassQuest_" .. family .. "_10"
				if DataManager.IsQuestActive(player, questId) then
					qm.CompleteQuest(player, questId)
				end
			end
		end

		-- Deterministic post-swap reconcile (see ChangeWeapon). Only after a real
		-- purchase, so an unaffordable attempt does not wipe the player's weapon.
		-- Runs a frame later, after the unconditional IsSwapping release below.
		if inv then
			task.spawn(function()
				task.wait()
				inv:ReconcileWeapons(weaponName)
			end)
		end
	end

	-- Always release the swap guard, even if they couldn't afford it
	-- (they were already unequipped above).
	if inv then inv.IsSwapping = false end
end)

-- [[ AUTHORITATIVE EQUIPMENT PRICES ]] --
-- The old handler took the client's price and, worse, had a `price == 0` branch that
-- granted the item with NO liturgy check at all: firing BuyItem("Void Spire", 0) got
-- it free. Prices live here now and the client's number is ignored.
-- Only what an actual vendor sells. Anything absent is not purchasable, and the
-- handler refuses rather than trusting a client-supplied price.
local ITEM_PRICES = {
	-- Free, bundled with the Hoss armor (which is charged separately via BuyArmor).
	["Prayer Beads"]   = 0,
	["Abyssal Helmet"] = 500,
	-- Black Trench Coat / Lantern / Void Spire exist in ServerStorage.Equipment but
	-- have no vendor. Deliberately absent: they are granted elsewhere, not bought.
}

BUY_ITEM_EVENT.OnServerEvent:Connect(function(player, itemName, price)
	if type(itemName) ~= "string" then return end

	local template = EQUIPMENT_FOLDER:FindFirstChild(itemName)
	if not template then return end

	-- Optional: Check if they already own it
	if DataManager.HasItem(player, itemName) then return end 

	price = ITEM_PRICES[itemName]
	if not price then
		warn("[BuyItem] no server price for '" .. itemName .. "'; refusing sale to " .. player.Name)
		return
	end

	if DataManager.RemoveLiturgy(player, price) then
		if player.Character and player.Character:FindFirstChild("Torso") then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = player.Character.Torso
			s:Play()
			game.Debris:AddItem(s, 2)
		end

		-- [[ HYBRID REPLACEMENT LOGIC ]] --
		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem(itemName, 1) -- Grants the new physical tool and logs the data
		end
	end

end)

-- [[ AUTHORITATIVE SKILL PRICES ]] --
-- Priced by SLOT, matching the trainer dialogues (Z = 1000, X = 1500, C = 2500).
-- The slot comes from the skill's index in SkillConfig.WeaponSkills, so there is no
-- second list to keep in sync: add a skill to a family and it is priced automatically.
local SKILL_SLOT_PRICES = { [1] = 1000, [2] = 1500, [3] = 2500 }

-- Mastery level a family must have reached to be taught the skill in each slot.
-- Mirrors the trainer state machine (15 / 20 / 25).
local SKILL_SLOT_LEVELS = { [1] = 15, [2] = 20, [3] = 25 }

BUY_SPELL_EVENT.OnServerEvent:Connect(function(player, spellName, price)
	if type(spellName) ~= "string" then return end

	-- Check if they already own it using the new DataManager function
	if DataManager.HasSpell(player, spellName) then return end

	local SkillConfig = require(ReplicatedStorage.modules:WaitForChild("SkillConfig"))

	-- Resolve the skill to its family and slot. An unknown skill name is not for sale.
	local family, slot
	for weaponName, skills in pairs(SkillConfig.WeaponSkills) do
		for i, name in ipairs(skills) do
			if name == spellName then
				family = SkillConfig.WeaponFamily[weaponName] or weaponName
				slot = i
				break
			end
		end
		if family then break end
	end

	if not family or not slot then
		-- Racial skills and anything not in WeaponSkills are granted elsewhere, not
		-- bought. Refuse rather than charging a client-supplied price.
		warn("[BuySpell] '" .. spellName .. "' is not a purchasable weapon skill; refusing.")
		return
	end

	-- The client's `price` is discarded. It used to be charged verbatim, so a crafted
	-- BuySpell fire with price 0 unlocked any skill for free.
	price = SKILL_SLOT_PRICES[slot]
	if not price then return end

	-- And the client cannot skip the level gate by talking straight to the remote:
	-- the trainer checks mastery on its side, but that check lived only on the client.
	local level = DataManager.GetWeaponLevel(player, family)
	local required = SKILL_SLOT_LEVELS[slot]
	if required and level < required then
		warn("[BuySpell] " .. player.Name .. " tried to buy '" .. spellName ..
			"' at " .. family .. " " .. level .. " (needs " .. required .. "); refusing.")
		return
	end

	if DataManager.RemoveLiturgy(player, price) then
		if player.Character and player.Character:FindFirstChild("Torso") then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = player.Character.Torso
			s:Play()
			game.Debris:AddItem(s, 2)
		end

		-- Grant the spell
		DataManager.UnlockSpell(player, spellName)
	end
end)

CHANGE_WEAPON_EVENT.OnServerEvent:Connect(function(player, weaponName)
	if type(weaponName) ~= "string" then return end

	-- ChangeWeapon is the TUTORIAL grant path: the five starter NPCs hand out the
	-- seed weapons for free. It charges nothing, so it must never be able to hand
	-- out anything else. Previously it would grant ANY of the 14 weapons, meaning a
	-- crafted ChangeWeapon("Dragon Slayer") fire got a 1000-liturgy branch weapon for
	-- nothing. Branch weapons and hybrids go through BuyWeapon, which prices them.
	local SkillConfig = require(ReplicatedStorage.modules:WaitForChild("SkillConfig"))
	local isSeed = (not SkillConfig.IsHybrid(weaponName))
		and (SkillConfig.WeaponFamily[weaponName] == weaponName)

	if not isSeed then
		warn("[ChangeWeapon] " .. player.Name .. " requested non-seed weapon '" ..
			weaponName .. "'; refusing (branch weapons must be bought).")
		return
	end

	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then return end

	-- Optional: Check if they already own it
	if DataManager.HasItem(player, weaponName) then return end 
	
	local inv = InventoryManager.GetInventory(player)
	if inv then
		-- Guard the Backpack hook against the deferred unequip re-adding the old tool.
		inv.IsSwapping = true

		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid:UnequipTools()
			-- Wait until the old tool has actually left the character, not just one frame.
			waitForNoEquippedTool(player)
		end

		-- Destroy the old physical tools FIRST, then stop the orphaned idle. The idle
		-- stopper must run after the tool is gone: if it fires before the destroy, the
		-- old tool's Equipped handler can restart the idle a frame later and survive.
		inv:ClearWeapons()
		cleanupWeaponVisuals(player)

		inv:AddItem(weaponName, 1)

		inv.IsSwapping = false

		-- Deterministic post-swap reconcile: after the guard is released and one frame
		-- has passed, force the end-state to "weaponName is the only weapon", sweeping
		-- any stray old tool a late unequip may have dropped back in.
		task.wait()
		if inv then inv:ReconcileWeapons(weaponName) end
	end
end)

MOVE_ITEM_EVENT.OnServerEvent:Connect(function(player, itemId, sourceType, sourceIndex, targetType, targetIndex)
	-- Basic type validation to prevent RemoteEvent exploit spam
	if typeof(itemId) ~= "string" or typeof(sourceType) ~= "string" or typeof(targetType) ~= "string" then return end

	local playerInventory = InventoryManager.GetInventory(player)
	if playerInventory then
		playerInventory:MoveItem(itemId, sourceType, sourceIndex, targetType, targetIndex)
	end
end)

USE_HOTBAR_EVENT.OnServerEvent:Connect(function(player, slotNumber)
	if type(slotNumber) ~= "number" or slotNumber < 1 or slotNumber > 9 then return end

	local playerInv = InventoryManager.GetInventory(player)
	if not playerInv then return end

	local itemData = playerInv.Hotbar[slotNumber] or playerInv.Hotbar[tostring(slotNumber)]
	if not itemData then return end

	if itemData.IsSpell then
		print(player.Name .. " casted spell: " .. itemData.Name)
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")
	if not humanoid then return end

	local currentlyEquipped = char:FindFirstChildOfClass("Tool")

	if currentlyEquipped and currentlyEquipped.Name == itemData.Name then
		humanoid:UnequipTools()
		DataManager.SetCurrentWeapon(player, "") 
	else
		humanoid:UnequipTools()
		task.wait(0.05)

		local toolToEquip = player.Backpack:FindFirstChild(itemData.Name)
		if toolToEquip then
			humanoid:EquipTool(toolToEquip)
			DataManager.SetCurrentWeapon(player, itemData.Name)
		end
	end
end)

ON_DEATH_EVENT.OnServerEvent:Connect(function(player, char)
	local hum = char:FindFirstChild("Humanoid")
	if hum and hum.Health > 0 and player.Character == char then hum.Health = 0 end
end)

for _, d in ipairs(workspace.plrManager.alive:GetDescendants()) do
	if d:FindFirstChild("Humanoid") then 
		applyStats(d)
		connectLootLogic(d.Humanoid) 
	end
end

workspace.plrManager.alive.DescendantAdded:Connect(function(descendant)
	if descendant:FindFirstChild("Humanoid") then
		task.wait()
		connectLootLogic(descendant.Humanoid)
	end
end)

-- [[ RETURN TO MENU ]] --
RETURN_TO_MENU_EVENT.OnServerEvent:Connect(function(player)
	local combatExpiry = player:GetAttribute("CombatLogExpiry")
	if combatExpiry and os.clock() < combatExpiry then return end

	player:SetAttribute("HasPressedPlay", false)

	local char = player.Character

	-- Drop every active buff before moving them to the menu. Buffs were previously
	-- only ever torn down by their own expiry timer, so returning to menu mid-buff
	-- kept the damage/heal modifier AND the aura FX, and carried both into the next
	-- run. Pass char explicitly: teardown must sweep THIS body, not a future one.
	BuffService.ClearAll(player, char)

	if not char then return end

	local rootPart = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChild("Humanoid")

	if humanoid then humanoid:UnequipTools() end

	char.Parent = workspace.plrManager.noPVP
	local menuSpawn = workspace.spawnRoom:FindFirstChild(MENU_SPAWN_NAME)
	if menuSpawn and rootPart then
		SafeTeleport(rootPart, CFrame.new(menuSpawn.Position + Vector3.new(0, 3, 0)), "MenuSpawn (ReturnToMenu)")
		rootPart.Anchored = true
	end

	if char:FindFirstChild("MenuProtection") then char.MenuProtection:Destroy() end
	local ff = Instance.new("ForceField")
	ff.Name = "MenuProtection"
	ff.Visible = false
	ff.Parent = char
end)
