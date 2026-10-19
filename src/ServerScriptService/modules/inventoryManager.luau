-- SPDX-License-Identifier: MIT
--
-- Owns each player's inventory: the item grid, the 9-slot hotbar, and the equipment
-- slots. It keeps the saved data, the physical tools, and the 3D equipment visuals in
-- step, and sends the client UI every change.

local InventoryManager = {}
InventoryManager.__index = InventoryManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryRemotes = ReplicatedStorage:WaitForChild("remotes")
local UpdateUIEvent = InventoryRemotes:WaitForChild("UpdateUI")

-- Active inventories by UserId.
local PlayerInventories = {}

-- InventoryManager.new() - create the inventory of a player
-- @player: the player
-- @savedData: the saved Items, Hotbar, and Equipment, or nil for a new player
--
-- A new player with nothing saved gets Fists in hotbar slot 1.
--
-- Return: the inventory.
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

	-- While true, the Backpack hook ignores new tools. A weapon swap sets it, so the
	-- deferred UnequipTools cannot register the old tool again after ClearWeapons.
	self.IsSwapping = false

	PlayerInventories[player.UserId] = self
	return self
end

-- InventoryManager.GetInventory() - get the inventory of a player
-- @player: the player
--
-- Return: the inventory, or nil.
function InventoryManager.GetInventory(player)
	return PlayerInventories[player.UserId]
end

-- InventoryManager:AddItem() - add an item and give the physical tool
-- @toolName: the item name in ServerStorage.Weapons or ServerStorage.Equipment
-- @amount: the amount, 1 by default
--
-- Fills existing stacks first, then free hotbar slots, then the grid. Saves and syncs.
--
-- Return: true if the item exists, false otherwise.
function InventoryManager:AddItem(toolName, amount)
	amount = amount or 1
	local toolPrefab = ServerStorage.Weapons:FindFirstChild(toolName)
		or ServerStorage:FindFirstChild("Equipment"):FindFirstChild(toolName)

	if not toolPrefab then
		return false
	end

	local isStackable = toolPrefab:GetAttribute("IsStackable")
	local maxStack = toolPrefab:GetAttribute("MaxStack")

	if isStackable then
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

	while amount > 0 do
		local stackAmount = isStackable and math.min(amount, maxStack) or 1
		local newItemData = {
			Name = toolName,
			Amount = stackAmount,
			Id = game:GetService("HttpService"):GenerateGUID(false),
		}

		local placedInHotbar = false
		for i = 1, 9 do
			if self.Hotbar[i] == nil and self.Hotbar[tostring(i)] == nil then
				self.Hotbar[i] = newItemData
				placedInHotbar = true
				break
			end
		end

		if not placedInHotbar then
			table.insert(self.Inventory, newItemData)
		end

		amount -= stackAmount
	end

	-- Give the physical tool only once, so stackable items do not fill the Backpack with
	-- copies.
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

-- InventoryManager:SaveState() - save the inventory and sync the client
--
-- Return: nothing.
function InventoryManager:SaveState()
	local DataManager = require(game.ServerScriptService.modules:WaitForChild("dataManager"))

	DataManager.SaveInventoryData(self.Player, {
		Items = self.Inventory,
		Hotbar = self.Hotbar,
		Equipment = self.Equipment,
	})

	self:Sync()
end

-- InventoryManager:Equip() - put an item in a hotbar or equipment slot
-- @itemId: the item ID
-- @slotType: "Hotbar" or "Equipment"
-- @slotIndex: the hotbar slot, for "Hotbar"
--
-- Return: false if the item is not in the grid, nil otherwise.
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

-- InventoryManager:EquipSpell() - put an unlocked spell in a hotbar slot
-- @spellName: the spell name
-- @slotIndex: the hotbar slot, 1 to 9
--
-- Return: true on success, false if the spell is locked or stats are missing.
function InventoryManager:EquipSpell(spellName, slotIndex)
	local playerStats = self.Player:FindFirstChild("PlayerStats")
	if not playerStats then
		return false
	end

	local skillsFolder = playerStats:FindFirstChild("UnlockedSkills")
	if not skillsFolder or not skillsFolder:FindFirstChild(spellName) then
		warn(`[inventoryManager] {self.Player.Name} tried to equip locked spell {spellName}.`)
		return false
	end

	-- Spells use the hotbar item format. IsSpell tells the client UI that there is no
	-- physical tool.
	local spellData = {
		Name = spellName,
		Amount = 1,
		Id = "Spell_" .. spellName,
		IsSpell = true,
	}

	self.Hotbar[slotIndex] = spellData

	self:SaveState()
	return true
end

-- InventoryManager:HookBackpack() - register tools added to the current Backpack
--
-- Call this on every respawn. A tool that is not in the data is added as an item.
--
-- Return: nothing. Yields up to 10 seconds for the Backpack.
function InventoryManager:HookBackpack()
	local backpack = self.Player:WaitForChild("Backpack", 10)
	if not backpack then
		return
	end

	if self.BackpackConnection then
		self.BackpackConnection:Disconnect()
	end

	self.BackpackConnection = backpack.ChildAdded:Connect(function(child)
		-- Ignore the old tool that a deferred UnequipTools drops back during a swap.
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

-- InventoryManager:ClearWeapons() - remove every weapon from the data and the player
--
-- Keeps spells and items that are not weapons. Saves and syncs.
--
-- Return: nothing.
function InventoryManager:ClearWeapons()
	local weaponsFolder = game:GetService("ServerStorage"):FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	local function isWeapon(itemName)
		return weaponsFolder:FindFirstChild(itemName) ~= nil
	end

	for i = #self.Inventory, 1, -1 do
		if isWeapon(self.Inventory[i].Name) then
			table.remove(self.Inventory, i)
		end
	end

	for i = 1, 9 do
		local item = self.Hotbar[tostring(i)] or self.Hotbar[i]
		if item and not item.IsSpell and isWeapon(item.Name) then
			self.Hotbar[tostring(i)] = nil
			self.Hotbar[i] = nil
		end
	end

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
	-- Also remove the weapon the player is holding.
	if char then
		clearPhysicalTools(char)
	end

	self:SaveState()
end

-- InventoryManager:ReconcileWeapons() - make one weapon the only weapon
-- @keepName: the weapon to keep
--
-- The swap (deferred UnequipTools, destroy, AddItem) depends on timing: a late
-- unequip can drop the old tool back, or a Sync can arrive out of order. Run this after
-- the swap settles. It removes every other weapon from the data and from the Backpack,
-- StarterGear, and character, then syncs. Spells and equipment are not touched. Safe
-- to call more than once.
--
-- Return: nothing.
function InventoryManager:ReconcileWeapons(keepName)
	local weaponsFolder = game:GetService("ServerStorage"):FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	-- A newer swap is in progress, and its own reconcile settles the result. This stops an
	-- old reconcile from removing the weapon that the newer swap granted.
	if self.IsSwapping then
		return
	end

	local function isWeapon(itemName)
		return weaponsFolder:FindFirstChild(itemName) ~= nil
	end

	local changed = false

	for i = #self.Inventory, 1, -1 do
		local it = self.Inventory[i]
		if isWeapon(it.Name) and it.Name ~= keepName then
			table.remove(self.Inventory, i)
			changed = true
		end
	end

	-- The hotbar uses both number and string keys.
	for i = 1, 9 do
		local item = self.Hotbar[tostring(i)] or self.Hotbar[i]
		if item and not item.IsSpell and isWeapon(item.Name) and item.Name ~= keepName then
			self.Hotbar[tostring(i)] = nil
			self.Hotbar[i] = nil
			changed = true
		end
	end

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

-- InventoryManager:MoveItem() - move an item between grid, hotbar, and equipment
-- @itemId: the item ID
-- @sourceType: "Inventory", "Hotbar", or "Equipment"
-- @sourceIndex: the source hotbar slot or equipment category
-- @targetType: "Inventory", "Hotbar", or "Equipment"
-- @targetIndex: the target hotbar slot or equipment category
--
-- An item in the target slot swaps back to the source. Moving a tool into equipment
-- takes the physical tool away, and moving it out gives it back. Saves and syncs.
--
-- Return: true on success, false if the item or target is not valid.
function InventoryManager:MoveItem(itemId, sourceType, sourceIndex, targetType, targetIndex)
	local itemData = nil
	local invIndex = nil

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

	-- An equipment slot accepts only items of its category.
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

	if sourceType == "Inventory" then
		table.remove(self.Inventory, invIndex)
	elseif sourceType == "Hotbar" then
		self.Hotbar[tonumber(sourceIndex)] = nil
	elseif sourceType == "Equipment" then
		self.Equipment[sourceIndex] = nil
		self:RemoveCharacterVisuals(sourceIndex)
	end

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

	if swappedItem then
		if sourceType == "Hotbar" then
			self.Hotbar[tonumber(sourceIndex)] = swappedItem
		elseif sourceType == "Equipment" then
			self.Equipment[sourceIndex] = swappedItem
		else
			table.insert(self.Inventory, swappedItem)
		end
	end

	-- Change the physical tools only after the data is in its new place.
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

		if backpack and backpack:FindFirstChild(name) then
			backpack[name]:Destroy()
		end
		if starterGear and starterGear:FindFirstChild(name) then
			starterGear[name]:Destroy()
		end

		-- Also destroy the tool in the player's hands.
		if char and char:FindFirstChild(name) then
			char[name]:Destroy()
		end

		-- The player no longer holds this weapon.
		local DataManager = require(game.ServerScriptService.modules:WaitForChild("dataManager"))
		if DataManager.GetCurrentWeapon(self.Player) == name then
			DataManager.SetCurrentWeapon(self.Player, "")
		end
	end

	if targetType == "Equipment" then
		RemovePhysicalTool(itemData.Name)
	elseif sourceType == "Equipment" then
		GrantPhysicalTool(itemData.Name)
	end

	if swappedItem then
		if sourceType == "Equipment" then
			RemovePhysicalTool(swappedItem.Name)
		elseif targetType == "Equipment" then
			GrantPhysicalTool(swappedItem.Name)
		end
	end

	self:SaveState()
	return true
end

-- InventoryManager:RemoveItem() - remove an amount of an item from the grid
-- @itemId: the item ID
-- @amount: the amount to remove
--
-- An empty stack is also cleared from the hotbar and equipment. Syncs, does not save.
--
-- Return: true if the item was found, false otherwise.
function InventoryManager:RemoveItem(itemId, amount)
	for i, item in ipairs(self.Inventory) do
		if item.Id == itemId then
			item.Amount -= amount
			if item.Amount <= 0 then
				table.remove(self.Inventory, i)
				self:ClearFromQuickSlots(itemId)
			end
			self:Sync()
			return true
		end
	end
	return false
end

-- InventoryManager:GetItemById() - find an item in the grid
-- @itemId: the item ID
--
-- Return: the grid index and the item, or nil, nil.
function InventoryManager:GetItemById(itemId)
	for i, item in ipairs(self.Inventory) do
		if item.Id == itemId then
			return i, item
		end
	end
	return nil, nil
end

-- InventoryManager:BuildFromBackpack() - build the hotbar from the Backpack
--
-- Only for a player with no saved hotbar: the first 9 tools go to the hotbar and the
-- rest to the grid, and the layout is saved. Otherwise it only syncs.
--
-- Return: nothing. Yields for the Backpack.
function InventoryManager:BuildFromBackpack()
	local backpack = self.Player:WaitForChild("Backpack")
	local tools = backpack:GetChildren()

	local hasSavedHotbar = false
	for i = 1, 9 do
		if self.Hotbar[tostring(i)] ~= nil or self.Hotbar[i] ~= nil then
			hasSavedHotbar = true
			break
		end
	end

	if not hasSavedHotbar then
		self.Inventory = {}

		for index, tool in ipairs(tools) do
			if not tool:IsA("Tool") then
				continue
			end

			local itemData = {
				Id = game:GetService("HttpService"):GenerateGUID(false),
				Name = tool.Name,
				Amount = 1,
			}

			if index <= 9 then
				self.Hotbar[index] = itemData
			else
				table.insert(self.Inventory, itemData)
			end
		end

		self:SaveState()
	else
		self:Sync()
	end
end

-- InventoryManager:ClearFromQuickSlots() - remove an item from the hotbar and equipment
-- @itemId: the item ID
--
-- Return: nothing.
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

-- InventoryManager:RemoveCharacterVisuals() - remove the 3D visual of an equipment slot
-- @category: the equipment category
--
-- Return: nothing.
function InventoryManager:RemoveCharacterVisuals(category)
	local char = self.Player.Character
	if not char then
		return
	end

	-- Welded visuals, such as the Lantern, are in the VisualEquipment folder.
	local visFolder = char:FindFirstChild("VisualEquipment")
	if visFolder then
		local existingVisual = visFolder:FindFirstChild(category)
		if existingVisual then
			existingVisual:Destroy()
		end
	end

	-- An accessory item can have several pieces, so remove every one for the slot.
	local safeName = "EquipSlot_" .. category
	for _, child in ipairs(char:GetChildren()) do
		if child.Name == safeName and child:IsA("Accessory") then
			child:Destroy()
		end
	end
end

-- InventoryManager:ApplyCharacterVisuals() - show the 3D visual of an equipped item
-- @itemName: the item name
-- @category: the equipment category
--
-- An item under ServerStorage.Equipments/<category> is added as accessories. Any other
-- item is welded to the torso.
--
-- Return: nothing.
function InventoryManager:ApplyCharacterVisuals(itemName, category)
	self:RemoveCharacterVisuals(category)

	local char = self.Player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")
	if not char or not humanoid then
		return
	end

	-- Any slot with a matching folder under ServerStorage.Equipments works this way.
	local equipmentsFolder = ServerStorage:FindFirstChild("Equipments")
	local categoryFolder = equipmentsFolder and equipmentsFolder:FindFirstChild(category)
	local itemPrefab = categoryFolder and categoryFolder:FindFirstChild(itemName)

	if itemPrefab then
		local slotName = "EquipSlot_" .. category
		if itemPrefab:IsA("Folder") then
			-- A multi-piece item, such as Black Trench Coat with 3 accessories.
			for _, piece in ipairs(itemPrefab:GetChildren()) do
				if piece:IsA("Accessory") then
					local clone = piece:Clone()
					clone.Name = slotName
					humanoid:AddAccessory(clone)
				end
			end
		elseif itemPrefab:IsA("Accessory") then
			-- A single-piece item, such as Prayer Beads.
			local clone = itemPrefab:Clone()
			clone.Name = slotName
			humanoid:AddAccessory(clone)
		end
		return
	end

	-- Items that are not accessories, such as Back items and lanterns, are welded.
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

-- InventoryManager:LoadAllVisuals() - show the visuals of every equipped item
--
-- Call this on spawn.
--
-- Return: nothing.
function InventoryManager:LoadAllVisuals()
	for category, itemData in pairs(self.Equipment) do
		if itemData then
			self:ApplyCharacterVisuals(itemData.Name, category)
		end
	end
end

-- Returns the ItemType of an equipment item (Head, Torso, Legs, or Back), or nil for
-- a weapon. The client UI uses it for tooltips and click-to-equip.
local function GetItemCategory(itemName)
	local equipmentFolder = ServerStorage:FindFirstChild("Equipment")
	local prefab = equipmentFolder and equipmentFolder:FindFirstChild(itemName)
	if prefab then
		return prefab:GetAttribute("ItemType")
	end
	return nil
end

-- Copies an item and adds its Category, without changing the stored data.
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

-- InventoryManager:Sync() - send the inventory to the client UI
--
-- Return: nothing.
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
