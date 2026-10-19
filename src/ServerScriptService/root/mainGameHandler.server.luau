-- SPDX-License-Identifier: MIT
--
-- Owns the player life cycle on the server: data load, spawning, stats, armor, loot on
-- death, and the shop remotes. All shop prices are set here, never by the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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
	"Whirlwind",
	"Abyssal Scream",
	"Berserker Armor",
	"Elfin Dance",
	"Air Wave",
	"Morgan",
	"Gohadoken",
	"Asura Glide",
	"Messatsu",
	"Zanshin",
	"Kurai",
	"Kirikizu",
	"Monastic Stance",
	"Mantra Palm",
	"Rising Dragon",
}

local function UpdateArmorVisuals(character, armorName)
	if not character then
		return
	end
	local armorData = ArmorConfig.Armors[armorName] or ArmorConfig.Armors["Rags"]

	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "ArmorShirt"
		shirt.Parent = character
	end
	shirt.ShirtTemplate = armorData.ShirtID

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
	if not stats then
		return
	end

	local armorBuffs = stats:WaitForChild("ArmorBuffs", 5)
	if not armorBuffs then
		warn(`[mainGameHandler] ArmorBuffs folder missing for {player.Name}.`)
		return
	end

	local armorData = ArmorConfig.Armors[armorName]

	if not armorData then
		warn(`[mainGameHandler] Armor {armorName} not found in ArmorConfig. Using Rags.`)
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

local function applyStats(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local statsFolder = player:WaitForChild("PlayerStats", 10)
	if not statsFolder then
		return
	end

	local armorBuffs = statsFolder:WaitForChild("ArmorBuffs")

	local humanoid = character:WaitForChild("Humanoid")

	local raceName = statsFolder:WaitForChild("Race").Value
	local raceData = RaceConfig.Races[raceName] or RaceConfig.Races["Human"]
	local targetStats = raceData.Stats or {}

	local statDefaults = {
		{ Name = "HPBoost", Default = 0 },
		{ Name = "ManaBoost", Default = 1 },
		{ Name = "SpeedBoost", Default = 1 },
		{ Name = "DamageBoost", Default = 1 },
		{ Name = "DefenseBoost", Default = 1 },
		{ Name = "RegenMultiplier", Default = 1 },
		{ Name = "LiturgyMultiplier", Default = 1 },
		{ Name = "JumpBoost", Default = 1 },
		{ Name = "DashDuration", Default = 0.2 },
		{ Name = "SlideDuration", Default = 2.0 },
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

	local function updateHealth()
		local raceBoost = statsFolder:FindFirstChild("HPBoost") and statsFolder.HPBoost.Value or 0
		local armorMult = 1
		if armorBuffs:FindFirstChild("HPBuff") then
			armorMult = armorBuffs.HPBuff.Value
		end

		-- Vitality adds flat HP before the armor multiplier.
		local vitPoints = 0
		local sf = statsFolder:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Vitality") then
			vitPoints = sf.Vitality.Value
		end
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
		armorBuffs.DefenseBuff.Changed:Connect(function()
			updateAttribute("DefenseBoost", "DefenseMultiplier", "DefenseBuff")
		end)
	end

	if armorBuffs:FindFirstChild("DamageBuff") then
		armorBuffs.DamageBuff.Changed:Connect(function()
			updateAttribute("DamageBoost", "DamageMultiplier", "DamageBuff")
		end)
	end

	local function updateJump()
		local jumpMult = statsFolder:FindFirstChild("JumpBoost") and statsFolder.JumpBoost.Value
			or 1
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = BASE_JUMP_HEIGHT * jumpMult
	end
	if statsFolder:FindFirstChild("JumpBoost") then
		statsFolder.JumpBoost.Changed:Connect(updateJump)
	end
	updateJump()

	local function updateSpeed()
		-- SpeedService keeps an active stun, block, or skill speed, and otherwise sets the
		-- full speed.
		SpeedService.Resolve(humanoid.Parent)
	end
	if statsFolder:FindFirstChild("SpeedBoost") then
		statsFolder.SpeedBoost.Changed:Connect(updateSpeed)
	end
	-- Re-apply the speed when Stamina changes on level-up or respec.
	do
		local sf = statsFolder:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			sf.Stamina.Changed:Connect(updateSpeed)
		end
	end
	updateSpeed()
end

-- RaceHandler calls this after a reroll, because only applyStats pushes HPBoost into
-- Humanoid.MaxHealth.
_G.ApplyStats = applyStats

local function WaitForData(player)
	local timeout = 0
	while not DataManager.GetProfile(player) do
		task.wait(0.2)
		timeout += 0.2
		if timeout > 30 then
			return false
		end
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
			if not char then
				continue
			end

			local humanoid = char:FindFirstChild("Humanoid")
			local rootPart = char:FindFirstChild("HumanoidRootPart")
			if not humanoid or not rootPart then
				continue
			end

			-- Save the position only when the player is alive, not downed, out of combat, and on
			-- the ground.
			if player:GetAttribute("HasPressedPlay") ~= true then
				continue
			end

			if humanoid.Health <= 0 then
				DataManager.ClearLastPosition(player)
				continue
			end

			if StateHandler.GetState(char, "Downed") then
				DataManager.ClearLastPosition(player)
				continue
			end

			local combatExpiry = player:GetAttribute("CombatLogExpiry")
			if combatExpiry and os.clock() < combatExpiry then
				DataManager.ClearLastPosition(player)
				continue
			end

			local state = humanoid:GetState()
			local isGrounded = (
				state == Enum.HumanoidStateType.Running
				or state == Enum.HumanoidStateType.RunningNoPhysics
				or state == Enum.HumanoidStateType.Landed
				or state == Enum.HumanoidStateType.Seated
			)

			if not isGrounded then
				continue
			end

			DataManager.SaveLastPosition(player, rootPart.Position)
		end
	end)
end

local function SafeTeleport(rootPart, cframe, description)
	rootPart.Anchored = true
	rootPart.CFrame = cframe
	task.wait(0.1)
	rootPart.Anchored = false
end

local function SendToGameSpawn(character)
	character.Parent = workspace.plrManager.alive
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	local raceName = "Human"

	if player then
		local stats = player:FindFirstChild("PlayerStats")
		if stats and stats:FindFirstChild("Race") then
			raceName = stats.Race.Value
		end
	end

	local allSpawnsFolder = workspace:FindFirstChild(RACE_SPAWNS_FOLDER_NAME)

	if allSpawnsFolder then
		local validSpawns = {}

		local raceSpecificFolder = allSpawnsFolder:FindFirstChild(raceName)

		if raceSpecificFolder then
			for _, child in ipairs(raceSpecificFolder:GetChildren()) do
				if child:IsA("BasePart") then
					table.insert(validSpawns, child)
				end
			end
		else
			-- Without a race folder, use the spawn parts directly in the main folder. Race
			-- folders are not BaseParts, so they are skipped.
			for _, child in ipairs(allSpawnsFolder:GetChildren()) do
				if child:IsA("BasePart") then
					table.insert(validSpawns, child)
				end
			end
		end

		if #validSpawns > 0 then
			local randomSpawn = validSpawns[math.random(1, #validSpawns)]
			local targetCF = CFrame.new(randomSpawn.Position + Vector3.new(0, 4, 0))
			SafeTeleport(rootPart, targetCF, "GameSpawn (" .. raceName .. ")")
		else
			warn(`[mainGameHandler] No spawn parts found for race {raceName}.`)
			-- TODO: Add a fallback spawn for when no spawn part exists.
		end
	else
		warn(`[mainGameHandler] Folder {RACE_SPAWNS_FOLDER_NAME} is missing in Workspace.`)
	end
end

local function SendToTutorialSpawn(character)
	character.Parent = workspace.plrManager.noPVP
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

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

	if not rootPart or not humanoid then
		return
	end

	while not character:IsDescendantOf(workspace) do
		task.wait()
	end

	character.Archivable = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local attach = Instance.new("Attachment", rootPart)
	attach.Name = "ForceAttachment"

	-- GuardBarService.Init sets the GuardBar attribute that the HUD reads.
	GuardBarService.Init(character)

	-- Stats come from the armor. Visuals come from the vanity, which can be a transmog.
	local currentArmor = DataManager.GetCurrentArmor(player)
	local currentVanity = DataManager.GetCurrentVanity(player)
	UpdateArmorVisuals(character, currentVanity)
	UpdateArmorStats(player, currentArmor)

	if player:GetAttribute("HasPressedPlay") == false then
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

	humanoid.Died:Connect(function()
		RagdollManager.Ragdoll(character, 10)
		if not rootPart.Anchored then
			rootPart:SetNetworkOwner(player)
		end
		ReplicatedStorage.remotes.RagdollForce:FireClient(player)

		DataManager.ClearLastPosition(player)

		local TagManager = require(ServerScriptService.modules.combatTagManager)

		local player = Players:GetPlayerFromCharacter(character)
		if player then
			-- Remove the dead player as an attacker from others, and clear their own tag, so
			-- death ends combat and stops the combat music.
			TagManager.UntagIfAttackerDied(player)
			TagManager.ClearPlayerTag(player)
		end
	end)
end

local function connectLootLogic(humanoid)
	if humanoid:GetAttribute("LootLinked") then
		return
	end
	humanoid:SetAttribute("LootLinked", true)

	humanoid.Died:Connect(function()
		if humanoid:GetAttribute("HasDroppedLoot") then
			return
		end
		humanoid:SetAttribute("HasDroppedLoot", true)

		local model = humanoid.Parent
		if not model or not model:FindFirstChild("HumanoidRootPart") then
			return
		end

		local dyingPlayer = Players:GetPlayerFromCharacter(model)

		if dyingPlayer then
			if DataManager and TitleManager then
				DataManager.AddDeath(dyingPlayer)
				TitleManager.CheckDeaths(dyingPlayer)
			end

			DataManager.HandlePlayerDeath(dyingPlayer, model.HumanoidRootPart.Position)

			local killTag = humanoid:FindFirstChild("KillTag")
			if killTag and killTag.Value ~= "" then
				local killer = Players:FindFirstChild(killTag.Value)
				if killer and killer ~= dyingPlayer then
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
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end
	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then
		return
	end

	char.Humanoid:UnequipTools()
	task.wait(0.1)

	if deleteOld then
		DataManager.ClearInventory(player)
	end

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
	if not WaitForData(player) then
		return
	end
	local savedData = DataManager.GetInventoryData(player) or {}

	InventoryManager.new(player, savedData)
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasPressedPlay", false)
	task.spawn(function()
		DataManager.PlayerAdded(player)
	end)
	task.delay(0.2, function()
		LoadInventory(player)
	end)
	task.delay(5, function()
		StartPositionTracker(player)
	end)

	player.CharacterAdded:Connect(function(character)
		-- Clear the buffs of the previous life, so they do not carry over to the new body.
		BuffService.ClearAll(player, nil)

		local diedConn
		local hum0 = character:WaitForChild("Humanoid")
		diedConn = hum0.Died:Connect(function()
			if diedConn then
				diedConn:Disconnect()
				diedConn = nil
			end
			-- Sweep this body explicitly. A later cleanup sees plr.Character as the new
			-- character, so the aura would stay on the corpse.
			BuffService.ClearAll(player, character)
		end)

		WaitForData(player)
		task.wait(0.3)

		TitleManager.CheckSpecUnlock(player)
		TitleManager.UpdateAura(player, DataManager.GetCurrentTitle())

		HandleCharacterLoad(player, character)
		applyStats(character)
		connectLootLogic(character:WaitForChild("Humanoid"))

		local hum = character:FindFirstChild("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
		player:FindFirstChild("PlayerStats").Mana.Value =
			player:FindFirstChild("PlayerStats").MaxMana.Value

		-- Wait for the saved weapon to reach the Backpack before equipping, for at most
		-- 3 seconds.
		local currentWeapon = DataManager.GetCurrentWeapon(player)
		if currentWeapon and currentWeapon ~= "" then
			local backpack = player:FindFirstChild("Backpack")
			if backpack and not backpack:FindFirstChild(currentWeapon) then
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

		-- RaceHandler waits for this attribute before it writes the appearance, so its
		-- CleanAccessories cannot remove the inventory visuals. See docs/systems-design.md.
		character:SetAttribute("BaseSetupComplete", true)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	DataManager.PlayerRemoving(player)
end)

local MENU_AREA_CENTER = Vector3.new(-3232.061, 6, -1263.206)
-- Half the menu area size (164 x 158), with a generous Y.
local MENU_AREA_HALF_SIZE = Vector3.new(82, 20, 79)

local function IsInMenuArea(position)
	local diff = position - MENU_AREA_CENTER
	return math.abs(diff.X) <= MENU_AREA_HALF_SIZE.X
		and math.abs(diff.Y) <= MENU_AREA_HALF_SIZE.Y
		and math.abs(diff.Z) <= MENU_AREA_HALF_SIZE.Z
end

SPAWN_EVENT.OnServerEvent:Connect(function(player)
	task.delay(2.1, function()
		player:SetAttribute("HasPressedPlay", true)
	end)
	local char = player.Character
	if char then
		local ff = char:FindFirstChild("MenuProtection")
		if ff then
			ff:Destroy()
		end

		local isComplete = DataManager.GetTutorialComplete(player)
		if not isComplete then
			SendToTutorialSpawn(char)
			return
		end

		local savedPos = DataManager.GetLastPosition(player)
		if savedPos and IsInMenuArea(savedPos) then
			DataManager.ClearLastPosition(player)
			savedPos = nil
		end
		if savedPos then
			local rootPart = char:FindFirstChild("HumanoidRootPart")
			if rootPart then
				GROUND_CHECK_RAYCAST.FilterDescendantsInstances = { char }
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

BUY_ARMOR_EVENT.OnServerEvent:Connect(function(player, armorName)
	local armorData = ArmorConfig.Armors[armorName]
	if not armorData then
		return
	end

	if DataManager.OwnsArmor(player, armorName) then
		DataManager.SetCurrentArmor(player, armorName)
		-- Equipping armor resets the transmog.
		DataManager.SetCurrentVanity(player, nil)
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
		-- Equipping armor resets the transmog.
		DataManager.SetCurrentVanity(player, nil)

		UpdateArmorVisuals(player.Character, armorName)
		UpdateArmorStats(player, armorName)
		applyStats(player.Character)
	end
end)

-- Clears the tool-grip welds on the server instead of waiting for the client's
-- DisconnectM6D, which races the tool destroy. Then tells the client to stop the old
-- weapon's idle animation.
local function cleanupWeaponVisuals(player)
	local char = player.Character
	if char then
		local rArm = char:FindFirstChild("Right Arm")
		local lArm = char:FindFirstChild("Left Arm")
		local rGrip = rArm and rArm:FindFirstChild("ToolGrip")
		local lGrip = lArm and lArm:FindFirstChild("ToolGrip")
		if rGrip then
			rGrip.Part1 = nil
		end
		if lGrip then
			lGrip.Part1 = nil
		end
	end
	STOP_WEAPON_IDLE_EVENT:FireClient(player)
end

-- UnequipTools is deferred: the tool returns to the Backpack on a later frame. Wait
-- until no Tool is equipped, with a bound so a stuck tool cannot hang the handler.
local function waitForNoEquippedTool(player)
	for _ = 1, 8 do
		local char = player.Character
		if not char or not char:FindFirstChildOfClass("Tool") then
			return
		end
		task.wait()
	end
end

-- The server owns every price, and the client's price argument is ignored. Seed
-- weapons are free from the tutorial NPCs. A shop reaches only players who skipped
-- the tutorial, because HasItem blocks a second purchase.
local WEAPON_PRICES = {
	-- Seed weapons.
	["Fists"] = 0,
	["Sword"] = 0,
	["Katana"] = 0,
	["Dagger"] = 0,
	["Greatsword"] = 0,

	-- Branch weapons from the class vendors, gated on family level 10.
	["Caestus"] = 1000,
	["Shackles"] = 1000,
	["Excalibur"] = 1000,
	["Vermillion"] = 1000,
	["Tanto"] = 1000,
	["Dragon Slayer"] = 1000,
	["Deathbringer"] = 1500,

	-- Hybrid weapons, gated by trainers and found in the world.
	["Guandao"] = 2500,
	["Scythe"] = 2500,
}

BUY_WEAPON_EVENT.OnServerEvent:Connect(function(player, weaponName, price)
	-- A table here would throw inside FindFirstChild.
	if type(weaponName) ~= "string" then
		return
	end

	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then
		return
	end

	-- A weapon that is not in the table is not for sale.
	price = WEAPON_PRICES[weaponName]
	if not price then
		warn(`[mainGameHandler] {player.Name} tried to buy {weaponName}, which has no price.`)
		return
	end

	if DataManager.HasItem(player, weaponName) then
		return
	end

	local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)

	if stateHandler.GetState(player.Character, "CantAnything") then
		return
	end

	local inv = InventoryManager.GetInventory(player)

	-- Guard the Backpack hook, so the deferred UnequipTools cannot register the old tool
	-- again after ClearWeapons removes it.
	if inv then
		inv.IsSwapping = true
	end

	player.Character.Humanoid:UnequipTools()
	waitForNoEquippedTool(player)

	if DataManager.RemoveLiturgy(player, price) then
		if player.Character and player.Character:FindFirstChild("Torso") then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://10066947742"
			s.Parent = player.Character.Torso
			s:Play()
			game.Debris:AddItem(s, 2)
		end

		if inv then
			inv:ClearWeapons()
			-- Stop the old idle only after the old tool is destroyed.
			cleanupWeaponVisuals(player)
			inv:AddItem(weaponName, 1)
		end

		-- Buying a branch weapon completes the level 10 class quest of its family. It is
		-- done here, at the only server purchase path, so a client cannot fake it. See
		-- docs/systems-design.md.
		local SkillConfig = require(game.ReplicatedStorage.modules.SkillConfig)
		local family = SkillConfig.GetXPFamily(weaponName)
		-- Seed weapons map to themselves and are not a branch purchase.
		if family and family ~= weaponName then
			local qm = _G.QuestManager
			if qm then
				local questId = "ClassQuest_" .. family .. "_10"
				if DataManager.IsQuestActive(player, questId) then
					qm.CompleteQuest(player, questId)
				end
			end
		end

		-- Reconcile one frame later, after the swap guard is released. Only a real purchase
		-- does this, so a failed purchase does not remove the player's weapon.
		if inv then
			task.spawn(function()
				task.wait()
				inv:ReconcileWeapons(weaponName)
			end)
		end
	end

	-- Release the swap guard even when the purchase failed, because the player was
	-- already unequipped.
	if inv then
		inv.IsSwapping = false
	end
end)

-- The server owns every price, and the client's price argument is ignored. An item
-- that is not in the table is not for sale.
local ITEM_PRICES = {
	-- Free with the Hoss armor, which BuyArmor charges for.
	["Prayer Beads"] = 0,
	["Abyssal Helmet"] = 500,
	-- Black Trench Coat, Lantern, and Void Spire have no vendor. They are granted
	-- elsewhere.
}

BUY_ITEM_EVENT.OnServerEvent:Connect(function(player, itemName, price)
	if type(itemName) ~= "string" then
		return
	end

	local template = EQUIPMENT_FOLDER:FindFirstChild(itemName)
	if not template then
		return
	end

	if DataManager.HasItem(player, itemName) then
		return
	end

	price = ITEM_PRICES[itemName]
	if not price then
		warn(`[mainGameHandler] {player.Name} tried to buy {itemName}, which has no price.`)
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

		local inv = InventoryManager.GetInventory(player)
		if inv then
			inv:AddItem(itemName, 1)
		end
	end
end)

-- Skills are priced by slot, the same as the trainer dialogues. The slot is the
-- skill's index in SkillConfig.WeaponSkills, so a new skill gets a price on its own.
local SKILL_SLOT_PRICES = { [1] = 1000, [2] = 1500, [3] = 2500 }

-- The family mastery level needed for each slot, the same as the trainer.
local SKILL_SLOT_LEVELS = { [1] = 15, [2] = 20, [3] = 25 }

BUY_SPELL_EVENT.OnServerEvent:Connect(function(player, spellName, price)
	if type(spellName) ~= "string" then
		return
	end

	if DataManager.HasSpell(player, spellName) then
		return
	end

	local SkillConfig = require(ReplicatedStorage.modules:WaitForChild("SkillConfig"))

	-- An unknown skill is not for sale.
	local family, slot
	for weaponName, skills in pairs(SkillConfig.WeaponSkills) do
		for i, name in ipairs(skills) do
			if name == spellName then
				family = SkillConfig.WeaponFamily[weaponName] or weaponName
				slot = i
				break
			end
		end
		if family then
			break
		end
	end

	if not family or not slot then
		-- Racial skills and other skills are granted elsewhere, not bought.
		warn(`[mainGameHandler] {player.Name} tried to buy {spellName}, which is not for sale.`)
		return
	end

	price = SKILL_SLOT_PRICES[slot]
	if not price then
		return
	end

	-- The trainer checks the level only on the client, so check it here too.
	local level = DataManager.GetWeaponLevel(player, family)
	local required = SKILL_SLOT_LEVELS[slot]
	if required and level < required then
		warn(`[mainGameHandler] {player.Name} needs {family} level {required} for {spellName}.`)
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

		DataManager.UnlockSpell(player, spellName)
	end
end)

CHANGE_WEAPON_EVENT.OnServerEvent:Connect(function(player, weaponName)
	if type(weaponName) ~= "string" then
		return
	end

	-- ChangeWeapon is the free tutorial path for seed weapons, so it must not grant
	-- anything else. Branch and hybrid weapons go through BuyWeapon.
	local SkillConfig = require(ReplicatedStorage.modules:WaitForChild("SkillConfig"))
	local isSeed = (not SkillConfig.IsHybrid(weaponName))
		and (SkillConfig.WeaponFamily[weaponName] == weaponName)

	if not isSeed then
		warn(`[mainGameHandler] {player.Name} asked ChangeWeapon for {weaponName}, not a seed.`)
		return
	end

	local weaponTemplate = WEAPON_FOLDER:FindFirstChild(weaponName)
	if not weaponTemplate then
		return
	end

	if DataManager.HasItem(player, weaponName) then
		return
	end

	local inv = InventoryManager.GetInventory(player)
	if inv then
		-- Guard the Backpack hook against the deferred unequip re-adding the old tool.
		inv.IsSwapping = true

		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid:UnequipTools()
			waitForNoEquippedTool(player)
		end

		-- Destroy the old tools before stopping the idle. Otherwise the old tool's Equipped
		-- handler can restart the idle a frame later.
		inv:ClearWeapons()
		cleanupWeaponVisuals(player)

		inv:AddItem(weaponName, 1)

		inv.IsSwapping = false

		-- One frame after the guard is released, make weaponName the only weapon, in case a
		-- late unequip put an old tool back.
		task.wait()
		if inv then
			inv:ReconcileWeapons(weaponName)
		end
	end
end)

MOVE_ITEM_EVENT.OnServerEvent:Connect(
	function(player, itemId, sourceType, sourceIndex, targetType, targetIndex)
		if
			typeof(itemId) ~= "string"
			or typeof(sourceType) ~= "string"
			or typeof(targetType) ~= "string"
		then
			return
		end

		local playerInventory = InventoryManager.GetInventory(player)
		if playerInventory then
			playerInventory:MoveItem(itemId, sourceType, sourceIndex, targetType, targetIndex)
		end
	end
)

USE_HOTBAR_EVENT.OnServerEvent:Connect(function(player, slotNumber)
	if type(slotNumber) ~= "number" or slotNumber < 1 or slotNumber > 9 then
		return
	end

	local playerInv = InventoryManager.GetInventory(player)
	if not playerInv then
		return
	end

	local itemData = playerInv.Hotbar[slotNumber] or playerInv.Hotbar[tostring(slotNumber)]
	if not itemData then
		return
	end

	if itemData.IsSpell then
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

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
	if hum and hum.Health > 0 and player.Character == char then
		hum.Health = 0
	end
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

RETURN_TO_MENU_EVENT.OnServerEvent:Connect(function(player)
	local combatExpiry = player:GetAttribute("CombatLogExpiry")
	if combatExpiry and os.clock() < combatExpiry then
		return
	end

	player:SetAttribute("HasPressedPlay", false)

	local char = player.Character

	-- Drop every buff before the move to the menu, so no modifier or aura carries into
	-- the next run. Pass char, so the cleanup sweeps this body.
	BuffService.ClearAll(player, char)

	if not char then
		return
	end

	local rootPart = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChild("Humanoid")

	if humanoid then
		humanoid:UnequipTools()
	end

	char.Parent = workspace.plrManager.noPVP
	local menuSpawn = workspace.spawnRoom:FindFirstChild(MENU_SPAWN_NAME)
	if menuSpawn and rootPart then
		SafeTeleport(
			rootPart,
			CFrame.new(menuSpawn.Position + Vector3.new(0, 3, 0)),
			"MenuSpawn (ReturnToMenu)"
		)
		rootPart.Anchored = true
	end

	if char:FindFirstChild("MenuProtection") then
		char.MenuProtection:Destroy()
	end
	local ff = Instance.new("ForceField")
	ff.Name = "MenuProtection"
	ff.Visible = false
	ff.Parent = char
end)
