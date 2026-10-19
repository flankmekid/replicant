-- // ServerScriptService.InventoryManager
local InventoryManager = {}
InventoryManager.__index = InventoryManager

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Remote Functions/Events (Ensure these exist in ReplicatedStorage)
local InventoryRemotes = ReplicatedStorage:WaitForChild("remotes")
local UpdateUIEvent = InventoryRemotes:WaitForChild("UpdateUI")

-- Holds all active player inventories
local PlayerInventories = {}

-- // Constructor
-- // Constructor
function InventoryManager.new(player, savedData)
	local self = setmetatable({}, InventoryManager)
	self.Player = player

	savedData = savedData or { Items = {}, Hotbar = {}, Equipment = {} }
	self.Inventory = savedData.Items or {}

	self.Hotbar = {}
	local isHotbarEmpty = true

	for i = 1, 9 do
		local savedItem = savedData.Hotbar[tostring(i)] or savedData.Hotbar[i]
		if savedItem then
			self.Hotbar[i] = savedItem
			isHotbarEmpty = false
		end
	end

	if isHotbarEmpty and #self.Inventory == 0 then
		self.Hotbar[1] = {
			Id = game:GetService("HttpService"):GenerateGUID(false),
			Name = "Fists",
			Amount = 1,
		}
	end

	self.Equipment = savedData.Equipment
		or {
			Head = nil,
			Torso = nil,
			Legs = nil,
			Back = nil,
		}

	-- When true, the Backpack ChildAdded hook ignores additions.
	-- Set during a weapon swap so a deferred UnequipTools() dropping the
	-- old tool back into the Backpack can't re-register it after ClearWeapons.
	self.IsSwapping = false

	PlayerInventories[player.UserId] = self
	return self
end

-- // Get a player's inventory instance
function InventoryManager.GetInventory(player)
	return PlayerInventories[player.UserId]
end

function InventoryManager:AddItem(toolName, amount)
	amount = amount or 1
	local toolPrefab = ServerStorage.Weapons:FindFirstChild(toolName)
		or ServerStorage:FindFirstChild("Equipment"):FindFirstChild(toolName)

	if not toolPrefab then
		return false
	end

	local isStackable = toolPrefab:GetAttribute("IsStackable")
	local maxStack = toolPrefab:GetAttribute("MaxStack")

	-- [[ 1. UPDATE THE DATA ]] --
	if isStackable then
		-- Find existing stack
		for _, item in ipairs(self.Inventory) do
			if item.Name == toolName and item.Amount < maxStack then
				local spaceLeft = maxStack - item.Amount
				if amount <= spaceLeft then
					item.Amount += amount
					self:SaveState()
					return true
				else
					item.Amount = maxStack
					amount -= spaceLeft
				end
			end
		end
	end

	-- Create new slot if amount remains
	while amount > 0 do
		local stackAmount = isStackable and math.min(amount, maxStack) or 1
		local newItemData = {
			Name = toolName,
			Amount = stackAmount,
			Id = game:GetService("HttpService"):GenerateGUID(false), -- Unique ID
		}

		-- Prioritize Hotbar
		local placedInHotbar = false
		for i = 1, 9 do
			if self.Hotbar[i] == nil and self.Hotbar[tostring(i)] == nil then
				self.Hotbar[i] = newItemData
				placedInHotbar = true
				break
			end
		end

		-- Fallback to Inventory Grid
		if not placedInHotbar then
			table.insert(self.Inventory, newItemData)
		end

		amount -= stackAmount
	end

	-- [[ 2. HYBRID LOGIC: GIVE THE PHYSICAL TOOL ]] --
	-- Now that the data is saved, we safely grant the physical tool.
	-- We check if they already physically have it so we don't spam the Backpack with duplicates of stackable items.
	local backpack = self.Player:FindFirstChild("Backpack")
	local starterGear = self.Player:FindFirstChild("StarterGear")

	if backpack and not backpack:FindFirstChild(toolName) then
		toolPrefab:Clone().Parent = backpack
	end

	if starterGear and not starterGear:FindFirstChild(toolName) then
		toolPrefab:Clone().Parent = starterGear
	end

	self:SaveState()
	return true
end

function InventoryManager:SaveState()
	local DataManager = require(game.ServerScriptService.modules:WaitForChild("dataManager"))

	DataManager.SaveInventoryData(self.Player, {
		Items = self.Inventory,
		Hotbar = self.Hotbar,
		Equipment = self.Equipment,
	})

	self:Sync()
end

-- // Equip Item to Hotbar or Equipment Slot
function InventoryManager:Equip(itemId, slotType, slotIndex)
	local itemIndex, itemData = self:GetItemById(itemId)
	if not itemData then
		return false
	end

	local toolPrefab = ServerStorage.Weapons:FindFirstChild(itemData.Name)
	local itemCategory = toolPrefab:GetAttribute("ItemType")

	if slotType == "Hotbar" and slotIndex then
		self.Hotbar[slotIndex] = itemData
	elseif slotType == "Equipment" and self.Equipment[itemCategory] ~= nil then
		self.Equipment[itemCategory] = itemData
		self:ApplyCharacterVisuals(itemData.Name, itemCategory)
	end

	self:Sync()
end

-- // Equip a Spell to the Hotbar
function InventoryManager:EquipSpell(spellName, slotIndex)
	local playerStats = self.Player:FindFirstChild("PlayerStats")
	if not playerStats then
		return false
	end

	local skillsFolder = playerStats:FindFirstChild("UnlockedSkills")
	if not skillsFolder or not skillsFolder:FindFirstChild(spellName) then
		warn("[Inventory] Player attempted to equip locked spell: " .. tostring(spellName))
		return false
	end

	-- Format the spell to match the expected Hotbar data structure
	local spellData = {
		Name = spellName,
		Amount = 1, -- Spells don't deplete in quantity
		Id = "Spell_" .. spellName, -- Unique ID pattern for spells
		IsSpell = true, -- Tells the Client UI this is a spell, not a physical Tool
	}

	-- Assign to the target hotbar slot (1 through 9)
	self.Hotbar[slotIndex] = spellData

	-- Save data and update the Client UI
	self:SaveState()
	return true
end

-- // Hook onto the current Backpack (Call this whenever the player respawns)
function InventoryManager:HookBackpack()
	local backpack = self.Player:WaitForChild("Backpack", 10)
	if not backpack then
		return
	end

	-- Disconnect old connection if it exists to prevent memory leaks
	if self.BackpackConnection then
		self.BackpackConnection:Disconnect()
	end

	-- Listen to the NEW Backpack
	self.BackpackConnection = backpack.ChildAdded:Connect(function(child)
		-- Ignore tools re-parented into the Backpack mid weapon-swap
		-- (deferred UnequipTools dropping the old tool back in).
		if self.IsSwapping then
			return
		end

		if child:IsA("Tool") then
			local isInData = false
			for _, item in ipairs(self.Inventory) do
				if item.Name == child.Name then
					isInData = true
					break
				end
			end
			for _, item in pairs(self.Hotbar) do
				if item and item.Name == child.Name then
					isInData = true
					break
				end
			end

			if not isInData then
				self:AddItem(child.Name, 1)
			end
		end
	end)
end

-- // Wipes all Weapons (Preserves Spells and non-weapon Items)
function InventoryManager:ClearWeapons()
	local weaponsFolder = game:GetService("ServerStorage"):FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	-- Helper function to check if an item is strictly a weapon
	local function isWeapon(itemName)
		return weaponsFolder:FindFirstChild(itemName) ~= nil
	end

	-- 1. Remove from Inventory Data Array
	for i = #self.Inventory, 1, -1 do
		if isWeapon(self.Inventory[i].Name) then
			table.remove(self.Inventory, i)
		end
	end

	-- 2. Remove from Hotbar Dictionary
	for i = 1, 9 do
		local item = self.Hotbar[tostring(i)] or self.Hotbar[i]
		if item and not item.IsSpell and isWeapon(item.Name) then
			self.Hotbar[tostring(i)] = nil
			self.Hotbar[i] = nil
		end
	end

	-- 3. Physically remove from Character
	local backpack = self.Player:FindFirstChild("Backpack")
	local starterGear = self.Player:FindFirstChild("StarterGear")
	local char = self.Player.Character

	local function clearPhysicalTools(parent)
		if not parent then
			return
		end
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Tool") and isWeapon(child.Name) then
				child:Destroy()
			end
		end
	end

	clearPhysicalTools(backpack)
	clearPhysicalTools(starterGear)
	if char then
		clearPhysicalTools(char)
	end -- Catches the weapon if they are currently holding it

	-- Save the newly wiped data state
	self:SaveState()
end

-- // Post-swap reconcile: force the end-state to be "keepName is the ONLY weapon".
-- The swap sequence (deferred UnequipTools + destroy + AddItem) is timing-sensitive;
-- a stray unequip can drop the old tool back into the Backpack a frame late, or a
-- Sync can land out of order, leaving the old weapon visible for one player. This
-- runs AFTER the swap settles and makes the result deterministic: any weapon that is
-- not keepName is purged from data (Inventory + Hotbar) and from every physical
-- location (Backpack, StarterGear, Character), then the client is re-synced. Safe to
-- call redundantly. Does not touch spells or non-weapon equipment.
function InventoryManager:ReconcileWeapons(keepName)
	local weaponsFolder = game:GetService("ServerStorage"):FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	-- A newer swap is mid-flight; let its own reconcile settle the end-state instead.
	-- Prevents a stale reconcile from purging the weapon a later swap just granted.
	if self.IsSwapping then
		return
	end

	local function isWeapon(itemName)
		return weaponsFolder:FindFirstChild(itemName) ~= nil
	end

	local changed = false

	-- Data: Inventory grid.
	for i = #self.Inventory, 1, -1 do
		local it = self.Inventory[i]
		if isWeapon(it.Name) and it.Name ~= keepName then
			table.remove(self.Inventory, i)
			changed = true
		end
	end

	-- Data: Hotbar dictionary (both numeric and string keys are used elsewhere).
	for i = 1, 9 do
		local item = self.Hotbar[tostring(i)] or self.Hotbar[i]
		if item and not item.IsSpell and isWeapon(item.Name) and item.Name ~= keepName then
			self.Hotbar[tostring(i)] = nil
			self.Hotbar[i] = nil
			changed = true
		end
	end

	-- Physical: purge stray weapon tools from every location.
	local function purge(parent)
		if not parent then
			return
		end
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Tool") and isWeapon(child.Name) and child.Name ~= keepName then
				child:Destroy()
				changed = true
			end
		end
	end
	purge(self.Player:FindFirstChild("Backpack"))
	purge(self.Player:FindFirstChild("StarterGear"))
	purge(self.Player.Character)

	if changed then
		self:SaveState()
	end
end

-- // Handle Drag-and-Drop Movements
function InventoryManager:MoveItem(itemId, sourceType, sourceIndex, targetType, targetIndex)
	local itemData = nil
	local invIndex = nil

	-- [[ 1. LOCATE AND VERIFY THE ITEM ]] --
	if sourceType == "Inventory" then
		for i, item in ipairs(self.Inventory) do
			if item.Id == itemId then
				itemData = item
				invIndex = i
				break
			end
		end
	elseif sourceType == "Hotbar" and self.Hotbar[tonumber(sourceIndex)] then
		if self.Hotbar[tonumber(sourceIndex)].Id == itemId then
			itemData = self.Hotbar[tonumber(sourceIndex)]
		end
	elseif sourceType == "Equipment" and self.Equipment[sourceIndex] then
		if self.Equipment[sourceIndex].Id == itemId then
			itemData = self.Equipment[sourceIndex]
		end
	end

	if not itemData then
		return false
	end

	-- [[ 2. VALIDATE TARGET (Equipment Only) ]] --
	if targetType == "Equipment" then
		local toolPrefab = game:GetService("ServerStorage").Weapons:FindFirstChild(itemData.Name)
			or game:GetService("ServerStorage")
				:FindFirstChild("Equipment")
				:FindFirstChild(itemData.Name)

		if not toolPrefab then
			return false
		end

		local itemCategory = toolPrefab:GetAttribute("ItemType")
		if itemCategory ~= targetIndex then
			self:Sync()
			return false
		end
	end

	-- [[ 3. EXTRACT FROM SOURCE ]] --
	if sourceType == "Inventory" then
		table.remove(self.Inventory, invIndex)
	elseif sourceType == "Hotbar" then
		self.Hotbar[tonumber(sourceIndex)] = nil
	elseif sourceType == "Equipment" then
		self.Equipment[sourceIndex] = nil
		self:RemoveCharacterVisuals(sourceIndex)
	end

	-- [[ 4. INSERT INTO TARGET & HANDLE SWAPS ]] --
	local swappedItem = nil

	if targetType == "Hotbar" then
		local numTarget = tonumber(targetIndex)
		if self.Hotbar[numTarget] ~= nil then
			swappedItem = self.Hotbar[numTarget]
		end
		self.Hotbar[numTarget] = itemData
	elseif targetType == "Equipment" then
		if self.Equipment[targetIndex] ~= nil then
			swappedItem = self.Equipment[targetIndex]
		end
		self.Equipment[targetIndex] = itemData
		self:ApplyCharacterVisuals(itemData.Name, targetIndex)
	elseif targetType == "Inventory" then
		table.insert(self.Inventory, itemData)
	end

	-- [[ 5. ROUTE THE SWAPPED ITEM BACK ]] --
	if swappedItem then
		if sourceType == "Hotbar" then
			self.Hotbar[tonumber(sourceIndex)] = swappedItem
		elseif sourceType == "Equipment" then
			self.Equipment[sourceIndex] = swappedItem
		else
			table.insert(self.Inventory, swappedItem)
		end
	end

	-- [[ 6. RESOLVE PHYSICAL TOOLS SAFELY ]] --
	-- Now that the data is 100% secure in its new location, we handle the physical objects

	local function GrantPhysicalTool(name)
		local toolPrefab = game:GetService("ServerStorage").Weapons:FindFirstChild(name)
			or game:GetService("ServerStorage"):FindFirstChild("Equipment"):FindFirstChild(name)
		if toolPrefab then
			if not self.Player:FindFirstChild("Backpack"):FindFirstChild(name) then
				toolPrefab:Clone().Parent = self.Player:FindFirstChild("Backpack")
			end
			if not self.Player:FindFirstChild("StarterGear"):FindFirstChild(name) then
				toolPrefab:Clone().Parent = self.Player:FindFirstChild("StarterGear")
			end
		end
	end

	local function RemovePhysicalTool(name)
		local backpack = self.Player:FindFirstChild("Backpack")
		local starterGear = self.Player:FindFirstChild("StarterGear")
		local char = self.Player.Character

		-- Destroy from inventory
		if backpack and backpack:FindFirstChild(name) then
			backpack[name]:Destroy()
		end
		if starterGear and starterGear:FindFirstChild(name) then
			starterGear[name]:Destroy()
		end

		-- [[ CRITICAL FIX: Destroy right out of the player's hands to prevent the crash ]]
		if char and char:FindFirstChild(name) then
			char[name]:Destroy()
		end

		-- Erase "currently holding" status from database
		local DataManager = require(game.ServerScriptService.modules:WaitForChild("dataManager"))
		if DataManager.GetCurrentWeapon(self.Player) == name then
			DataManager.SetCurrentWeapon(self.Player, "")
		end
	end

	-- Process the item the player dragged
	if targetType == "Equipment" then
		RemovePhysicalTool(itemData.Name) -- Going on the back, take away the tool
	elseif sourceType == "Equipment" then
		GrantPhysicalTool(itemData.Name) -- Coming off the back, give them the tool
	end

	-- Process the item that got swapped (if any)
	if swappedItem then
		if sourceType == "Equipment" then
			RemovePhysicalTool(swappedItem.Name)
		elseif targetType == "Equipment" then
			GrantPhysicalTool(swappedItem.Name)
		end
	end

	-- [[ 7. SAVE AND SYNC ]] --
	self:SaveState()
	return true
end

-- // Remove Item Logic
function InventoryManager:RemoveItem(itemId, amount)
	for i, item in ipairs(self.Inventory) do
		if item.Id == itemId then
			item.Amount -= amount
			if item.Amount <= 0 then
				table.remove(self.Inventory, i)
				-- Also clear from hotbar/equip if it was there
				self:ClearFromQuickSlots(itemId)
			end
			self:Sync()
			return true
		end
	end
	return false
end

-- // Utility: Find item by unique ID
function InventoryManager:GetItemById(itemId)
	for i, item in ipairs(self.Inventory) do
		if item.Id == itemId then
			return i, item
		end
	end
	return nil, nil
end

-- // Auto-sort tools from the Backpack
function InventoryManager:BuildFromBackpack()
	local backpack = self.Player:WaitForChild("Backpack")
	local tools = backpack:GetChildren()

	-- Check if the player already has a saved hotbar layout
	local hasSavedHotbar = false
	for i = 1, 9 do
		if self.Hotbar[tostring(i)] ~= nil or self.Hotbar[i] ~= nil then
			hasSavedHotbar = true
			break
		end
	end

	-- If they have no saved layout, generate it based on Backpack order
	if not hasSavedHotbar then
		self.Inventory = {} -- Clear existing just in case

		for index, tool in ipairs(tools) do
			if not tool:IsA("Tool") then
				continue
			end

			local itemData = {
				Id = game:GetService("HttpService"):GenerateGUID(false),
				Name = tool.Name,
				Amount = 1, -- Assuming tools don't stack natively in your current setup
			}

			if index <= 9 then
				-- First 9 go to Hotbar
				self.Hotbar[index] = itemData
			else
				-- Overflow goes to Inventory
				table.insert(self.Inventory, itemData)
			end
		end

		-- Save this new layout so it persists next time they join
		self:SaveState()
	else
		-- If they DO have a saved layout, we just sync it to the UI
		self:Sync()
	end
end

-- // Utility: Clean up hotbar/equipment if item is dropped/removed
function InventoryManager:ClearFromQuickSlots(itemId)
	for i, v in pairs(self.Hotbar) do
		if v and v.Id == itemId then
			self.Hotbar[i] = nil
		end
	end
	for k, v in pairs(self.Equipment) do
		if v and v.Id == itemId then
			self.Equipment[k] = nil
		end
	end
end

-- // Remove Visual 3D Equipment
function InventoryManager:RemoveCharacterVisuals(category)
	local char = self.Player.Character
	if not char then
		return
	end

	-- 1. Check for manual welds (like the Lantern) in the visual folder
	local visFolder = char:FindFirstChild("VisualEquipment")
	if visFolder then
		local existingVisual = visFolder:FindFirstChild(category)
		if existingVisual then
			existingVisual:Destroy()
		end
	end

	-- 2. [[ FIXED: Loop to destroy ALL segmented accessories for this slot ]]
	local safeName = "EquipSlot_" .. category
	for _, child in ipairs(char:GetChildren()) do
		if child.Name == safeName and child:IsA("Accessory") then
			child:Destroy()
		end
	end
end

-- // Weld or Wrap 3D Equipment to Character
function InventoryManager:ApplyCharacterVisuals(itemName, category)
	self:RemoveCharacterVisuals(category)

	local char = self.Player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")
	if not char or not humanoid then
		return
	end

	-- [[ ACCESSORY PATH: Equipments/<category>/<itemName> ]]
	-- Handles Head, Torso, Legs, or any future accessory-based slot generically.
	-- Just put a matching subfolder under ServerStorage.Equipments and it works automatically.
	local equipmentsFolder = ServerStorage:FindFirstChild("Equipments")
	local categoryFolder = equipmentsFolder and equipmentsFolder:FindFirstChild(category)
	local itemPrefab = categoryFolder and categoryFolder:FindFirstChild(itemName)

	if itemPrefab then
		local slotName = "EquipSlot_" .. category
		if itemPrefab:IsA("Folder") then
			-- Multi-piece item (e.g. Black Trench Coat with 3 accessory children)
			for _, piece in ipairs(itemPrefab:GetChildren()) do
				if piece:IsA("Accessory") then
					local clone = piece:Clone()
					clone.Name = slotName
					humanoid:AddAccessory(clone)
				end
			end
		elseif itemPrefab:IsA("Accessory") then
			-- Single-piece item (e.g. Prayer Beads)
			local clone = itemPrefab:Clone()
			clone.Name = slotName
			humanoid:AddAccessory(clone)
		end
		return
	end

	-- [[ WELD PATH: For non-accessory items (Back, Lanterns, etc.) ]]
	local weldPrefab = ServerStorage.Weapons:FindFirstChild(itemName)
		or ServerStorage:FindFirstChild("Equipment")
			and ServerStorage.Equipment:FindFirstChild(itemName)
	if not weldPrefab then
		return
	end

	local visFolder = char:FindFirstChild("VisualEquipment") or Instance.new("Folder")
	visFolder.Name = "VisualEquipment"
	visFolder.Parent = char

	local visualModel = Instance.new("Model")
	visualModel.Name = category

	local tempTool = weldPrefab:Clone()
	for _, child in ipairs(tempTool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("MeshPart") then
			child.Parent = visualModel
			child.Massless = true
			child.CanCollide = false
			child.Anchored = false
		end
	end
	tempTool:Destroy()

	visualModel.PrimaryPart = visualModel:FindFirstChild("Handle")
	visualModel.Parent = visFolder

	local root = char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso")
	if root and visualModel.PrimaryPart then
		if category == "Back" then
			visualModel:PivotTo(
				root.CFrame * CFrame.new(1.3, -1.5, 0) * CFrame.Angles(0, 0, math.rad(30))
			)
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = visualModel.PrimaryPart
		weld.Parent = visualModel.PrimaryPart
	end
end

-- // Load all visuals on spawn
function InventoryManager:LoadAllVisuals()
	for category, itemData in pairs(self.Equipment) do
		if itemData then
			self:ApplyCharacterVisuals(itemData.Name, category)
		end
	end
end

-- // Resolve an item's slot category for the client.
-- Weapons (ServerStorage.Weapons) return nil; equipment (ServerStorage.Equipment)
-- returns its ItemType attribute (Head/Torso/Legs/Back). Used by the client UI
-- for tooltips and click-to-equip.
local function GetItemCategory(itemName)
	local equipmentFolder = ServerStorage:FindFirstChild("Equipment")
	local prefab = equipmentFolder and equipmentFolder:FindFirstChild(itemName)
	if prefab then
		return prefab:GetAttribute("ItemType")
	end
	return nil
end

-- Shallow-copy an item and attach its Category without mutating stored data.
local function DecorateItem(item)
	if not item then
		return nil
	end
	local copy = {}
	for k, v in pairs(item) do
		copy[k] = v
	end
	copy.Category = GetItemCategory(item.Name)
	return copy
end

-- // Sync Data to Client UI
function InventoryManager:Sync()
	local UpdateUIEvent =
		game:GetService("ReplicatedStorage"):WaitForChild("remotes"):WaitForChild("UpdateUI")

	local decoratedItems = {}
	for i, item in ipairs(self.Inventory) do
		decoratedItems[i] = DecorateItem(item)
	end

	local decoratedHotbar = {}
	for k, item in pairs(self.Hotbar) do
		decoratedHotbar[k] = DecorateItem(item)
	end

	local decoratedEquipment = {}
	for slot, item in pairs(self.Equipment) do
		decoratedEquipment[slot] = DecorateItem(item)
	end

	UpdateUIEvent:FireClient(self.Player, {
		Items = decoratedItems,
		Hotbar = decoratedHotbar,
		Equipment = decoratedEquipment,
	})
end

return InventoryManager
