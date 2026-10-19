-- inventory controller script

-- // StarterPlayerScripts.InventoryController
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local InventoryGui = PlayerGui:WaitForChild("BackpackUI")

-- UI References
local Grid = InventoryGui:WaitForChild("MainPanel"):WaitForChild("Grid")
local HotbarFrame = InventoryGui:WaitForChild("Hotbar")
local EquipPanel = InventoryGui:WaitForChild("EquipmentPanel")
local DragLayer = InventoryGui:WaitForChild("DragLayer")

-- Asset References
local HotbarTemplate = ReplicatedStorage:WaitForChild("assets"):WaitForChild("hotbarFrame")

-- Remotes
local InventoryRemotes = ReplicatedStorage:WaitForChild("remotes")
local UpdateUIEvent = InventoryRemotes:WaitForChild("UpdateUI")
local MoveItemRemote = InventoryRemotes:WaitForChild("MoveItem") 
local UseHotbarRemote = InventoryRemotes:WaitForChild("UseHotbar") 
local RequestSyncRemote = InventoryRemotes:WaitForChild("RequestSync")

-- Disable Default Backpack
local StarterGui = game:GetService("StarterGui")
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local DragState = { IsDragging = false, ItemData = nil, SourceType = nil, SourceIndex = nil, VisualClone = nil }

-- Tracks a pending press that hasn't yet decided between "click" and "drag".
local PendingPress = nil
local DRAG_THRESHOLD = 8 -- pixels of movement before a press becomes a drag

-- [[ TOOLTIP ]] --
-- One reusable tooltip frame. Weapons show just the name; equipment shows the
-- name as a title plus the slot it fits (Category comes from the server sync).
local Tooltip = Instance.new("Frame")
Tooltip.Name = "ItemTooltip"
Tooltip.AnchorPoint = Vector2.new(0, 0)
Tooltip.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
Tooltip.BackgroundTransparency = 0.15
Tooltip.BorderSizePixel = 0
Tooltip.Size = UDim2.fromOffset(160, 44)
Tooltip.Visible = false
Tooltip.ZIndex = 50
Tooltip.Parent = InventoryGui
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = Tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(243, 243, 243)
	stroke.Thickness = 2
	stroke.Transparency = 0.8
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = Tooltip

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = Tooltip

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = Tooltip
end

local TooltipTitle = Instance.new("TextLabel")
TooltipTitle.Name = "Title"
TooltipTitle.BackgroundTransparency = 1
TooltipTitle.Size = UDim2.new(1, 0, 0, 18)
TooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
TooltipTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
TooltipTitle.TextStrokeTransparency = 0
TooltipTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
TooltipTitle.TextSize = 16
TooltipTitle.FontFace = ReplicatedStorage.assets.TextLabel.FontFace
TooltipTitle.ZIndex = 51
TooltipTitle.LayoutOrder = 1
TooltipTitle.Parent = Tooltip

local TooltipSub = Instance.new("TextLabel")
TooltipSub.Name = "Sub"
TooltipSub.BackgroundTransparency = 1
TooltipSub.Size = UDim2.new(1, 0, 0, 14)
TooltipSub.TextXAlignment = Enum.TextXAlignment.Left
TooltipSub.TextColor3 = Color3.fromRGB(190, 190, 190)
TooltipSub.TextStrokeTransparency = 0.4
TooltipSub.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
TooltipSub.TextSize = 13
TooltipSub.FontFace = ReplicatedStorage.assets.TextLabel.FontFace
TooltipSub.ZIndex = 51
TooltipSub.LayoutOrder = 2
TooltipSub.Parent = Tooltip

local function ShowTooltip(itemData)
	if not itemData or not itemData.Name then return end
	TooltipTitle.Text = itemData.Name
	if itemData.Category then
		-- Equipment: title + slot line
		TooltipSub.Visible = true
		TooltipSub.Text = "Slot: " .. tostring(itemData.Category)
		Tooltip.Size = UDim2.fromOffset(160, 44)
	else
		-- Weapon (or anything uncategorized): name only
		TooltipSub.Visible = false
		TooltipSub.Text = ""
		Tooltip.Size = UDim2.fromOffset(160, 28)
	end
	Tooltip.Visible = true
end

local function HideTooltip()
	Tooltip.Visible = false
end

UserInputService.InputChanged:Connect(function(input)
	if Tooltip.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Float the tooltip just above-right of the cursor
		Tooltip.Position = UDim2.fromOffset(input.Position.X + 16, input.Position.Y + 22)
	end
end)

-- Wire hover behaviour onto a slot for a given item.
local function BindTooltip(slot, itemData)
	if not itemData then return end
	slot.MouseEnter:Connect(function()
		ShowTooltip(itemData)
	end)
	slot.MouseLeave:Connect(function()
		HideTooltip()
	end)
end

-- [[ 1. UI INFO GENERATION ]] --
local function CreateSlotInfo(itemData, parentFrame)
	if not itemData then return end


--[[
	-- 1. The Icon
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromScale(0.7, 0.7)
	icon.Position = UDim2.fromScale(0.5, 0.4)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = itemData.IsSpell and "rbxassetid://0" or "rbxassetid://0" -- Replace with real IDs
	icon.Parent = parentFrame
]]

	-- 2. The Item Name (Sleek text at the bottom)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName" -- Explicitly named so we can read it later for selection
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = itemData.Name
	nameLabel.FontFace = game:GetService("ReplicatedStorage").assets.TextLabel.FontFace
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextWrapped = true
	nameLabel.Parent = parentFrame

	-- 3. Quantity (If applicable)
	if itemData.Amount and itemData.Amount > 1 then
		local qtyLabel = Instance.new("TextLabel")
		qtyLabel.Size = UDim2.fromScale(0.3, 0.3)
		qtyLabel.Position = UDim2.fromScale(1, 0)
		qtyLabel.AnchorPoint = Vector2.new(1, 0)
		qtyLabel.BackgroundTransparency = 1
		qtyLabel.Text = "x" .. tostring(itemData.Amount)
		qtyLabel.TextColor3 = Color3.new(1, 1, 1)
		qtyLabel.TextStrokeTransparency = 0
		qtyLabel.Parent = parentFrame
	end
end

-- [[ NEW: TWEENED SELECTION VISUALS ]] --
local selectionTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

local function UpdateSelectionVisuals()
	local char = player.Character
	local equippedTool = char and char:FindFirstChildOfClass("Tool")
	local equippedName = equippedTool and equippedTool.Name or nil

	for _, slot in ipairs(HotbarFrame:GetChildren()) do
		if slot:IsA("GuiObject") then
			local nameLabel = slot:FindFirstChild("ItemName")
			local stroke = slot:FindFirstChild("SelectionStroke")

			-- If this slot holds the currently equipped item
			if nameLabel and nameLabel.Text == equippedName and equippedName ~= nil then
				if not stroke then
					stroke = Instance.new("UIStroke")
					stroke.Name = "SelectionStroke"
					stroke.Color = Color3.new(1, 1, 1) -- White outline
					stroke.Thickness = 3
					stroke.Transparency = 1 -- Start invisible so it can tween in
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = slot
				end

				-- Tween it to visible
				TweenService:Create(stroke, selectionTweenInfo, {Transparency = 0}):Play()
			else
				-- If it's NOT equipped but has a visible stroke, tween it out and remove it
				if stroke and stroke.Transparency < 1 then
					local tweenOut = TweenService:Create(stroke, selectionTweenInfo, {Transparency = 1})
					tweenOut:Play()

					-- Clean up the stroke entirely after it fades out
					tweenOut.Completed:Connect(function()
						if stroke and stroke.Transparency >= 0.99 then
							stroke:Destroy()
						end
					end)
				end
			end
		end
	end
end

-- [[ CHARACTER EQUIP LISTENERS ]] --
local function SetupCharacterListeners(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then UpdateSelectionVisuals() end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then UpdateSelectionVisuals() end
	end)
	UpdateSelectionVisuals()
end

player.CharacterAdded:Connect(SetupCharacterListeners)
if player.Character then SetupCharacterListeners(player.Character) end

-- Is the player currently holding (as an equipped Tool) the item with this name?
local function IsHoldingItem(itemName)
	local char = player.Character
	if not char then return false end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == itemName
end

-- [[ 2. UI RENDERING ]] --
local function ClearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") then 
			child:Destroy() 
		end
	end
end

-- Arm a press on a slot. Decides click-vs-drag on release/movement.
local function ArmPress(slot, item, sourceType, sourceIndex, startPos)
	PendingPress = {
		Slot = slot,
		Item = item,
		SourceType = sourceType,
		SourceIndex = sourceIndex,
		StartPos = Vector2.new(startPos.X, startPos.Y),
		Started = false,
	}
end

UpdateUIEvent.OnClientEvent:Connect(function(syncData)
	-- Render Inventory Grid
	ClearChildren(Grid)
	for index, item in pairs(syncData.Items or {}) do
		local slot = HotbarTemplate:Clone()
		slot.Name = "InvSlot_" .. tostring(index)
		slot.Active = true -- Ensures clicking works even if the template is a Frame instead of a TextButton

		CreateSlotInfo(item, slot)
		BindTooltip(slot, item)
		slot.Parent = Grid

		slot.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and item then
				ArmPress(slot, item, "Inventory", index, input.Position)
			end
		end)
	end

	-- Render Hotbar
	ClearChildren(HotbarFrame)
	for i = 1, 9 do
		local slot = HotbarTemplate:Clone()
		slot.Name = "HotbarSlot_" .. tostring(i)
		slot.Active = true

		-- Add the number label if your template doesn't already have one built-in
		if not slot:FindFirstChild("SlotNumber") then
			local numberLabel = Instance.new("TextLabel")
			numberLabel.Name = "SlotNumber"
			numberLabel.Text = tostring(i)
			numberLabel.Size = UDim2.fromOffset(15, 15)
			numberLabel.Position = UDim2.fromOffset(5, 5)
			numberLabel.BackgroundTransparency = 1
			numberLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			numberLabel.Font = Enum.Font.RobotoMono
			numberLabel.TextStrokeTransparency = 0
			numberLabel.Parent = slot
		else
			slot.SlotNumber.Text = tostring(i)
		end

		local item = syncData.Hotbar[tostring(i)] or syncData.Hotbar[i]
		CreateSlotInfo(item, slot)
		BindTooltip(slot, item)
		slot.Parent = HotbarFrame

		slot.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and item then
				ArmPress(slot, item, "Hotbar", i, input.Position)
			end
		end)
	end

	-- [[ 3. RENDER EQUIPMENT (FIXED) ]] --
	-- Hardcode the slots so we guarantee every UI box gets checked and cleared
	local equipmentSlots = {"Head", "Torso", "Legs", "Back"}

	for _, slotName in ipairs(equipmentSlots) do
		local equipSlot = EquipPanel:FindFirstChild(slotName)
		if equipSlot then
			-- Always clear the slot first, just in case the item was removed (nil)
			for _, child in ipairs(equipSlot:GetChildren()) do
				if child.Name == "ItemName" or child:IsA("ImageLabel") then 
					child:Destroy() 
				end
			end

			if equipSlot:FindFirstChild("DragConnection") then
				equipSlot.DragConnection:Fire() -- Triggers the disconnect event we made
				equipSlot.DragConnection:Destroy()
			end

			-- Now check if the server sent data for this specific slot
			local item = syncData.Equipment and syncData.Equipment[slotName]

			if item then
				CreateSlotInfo(item, equipSlot)
				BindTooltip(equipSlot, item)

				local connectionVal = Instance.new("BindableEvent")
				connectionVal.Name = "DragConnection"
				connectionVal.Parent = equipSlot

				local conn = equipSlot.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						ArmPress(equipSlot, item, "Equipment", slotName, input.Position)
					end
				end)

				connectionVal.Event:Connect(function() conn:Disconnect() end)
			end
		end
	end

	-- Refresh selection visuals after UI rebuilds
	UpdateSelectionVisuals()
end)

-- [[ 3. DRAG LOGIC ]] --
function StartDrag(uiSlot, itemData, sourceType, sourceIndex, mousePos)
	if DragState.IsDragging then return end
	if not itemData or not itemData.Name then return end

	DragState.IsDragging = true
	DragState.ItemData = itemData
	DragState.SourceType = sourceType
	DragState.SourceIndex = sourceIndex

	DragState.VisualClone = uiSlot:Clone()
	-- Make the dragged clone slightly smaller or keep it the same size
	DragState.VisualClone.Size = UDim2.fromOffset(60, 60)
	DragState.VisualClone.AnchorPoint = Vector2.new(0.5, 0.5)
	DragState.VisualClone.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)

	-- Strip the selection stroke from the dragging clone if it was equipped
	local cloneStroke = DragState.VisualClone:FindFirstChild("SelectionStroke")
	if cloneStroke then cloneStroke:Destroy() end

	-- The tooltip shouldn't follow a dragged clone around
	HideTooltip()

	DragState.VisualClone.Parent = DragLayer
end

-- A click (no drag) on an equipment item we're currently holding equips it.
local function TryClickEquip(press)
	local item = press.Item
	if not item or not item.Category then return false end -- not equipment
	if not IsHoldingItem(item.Name) then return false end   -- not holding it

	MoveItemRemote:FireServer(item.Id, press.SourceType, press.SourceIndex, "Equipment", item.Category)
	return true
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

	-- Promote a pending press to a real drag once it moves far enough
	if PendingPress and not PendingPress.Started and not DragState.IsDragging then
		local delta = (Vector2.new(input.Position.X, input.Position.Y) - PendingPress.StartPos).Magnitude
		if delta >= DRAG_THRESHOLD then
			PendingPress.Started = true
			StartDrag(PendingPress.Slot, PendingPress.Item, PendingPress.SourceType, PendingPress.SourceIndex, input.Position)
		end
	end

	-- Move the active drag clone
	if DragState.IsDragging and DragState.VisualClone then
		DragState.VisualClone.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	-- Case A: a real drag is in progress -> resolve the drop
	if DragState.IsDragging then
		local guisAtPosition = PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
		local targetType, targetIndex = nil, nil

		for _, gui in ipairs(guisAtPosition) do
			if gui.Name:match("HotbarSlot_") then
				targetType = "Hotbar"
				targetIndex = tonumber(gui.Name:match("%d+"))
				break
			elseif gui.Name:match("InvSlot_") or gui.Name == "Grid" then
				targetType = "Inventory"
				break
			elseif gui.Parent == EquipPanel then
				targetType = "Equipment"
				targetIndex = gui.Name
				break
			end
		end

		if targetType then
			MoveItemRemote:FireServer(DragState.ItemData.Id, DragState.SourceType, DragState.SourceIndex, targetType, targetIndex)
		end

		if DragState.VisualClone then DragState.VisualClone:Destroy() end
		DragState.IsDragging = false
		DragState.ItemData = nil
		PendingPress = nil
		return
	end

	-- Case B: press released without ever becoming a drag -> it's a click
	if PendingPress then
		TryClickEquip(PendingPress)
		PendingPress = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.I then
		local mainPanel = InventoryGui:FindFirstChild("MainPanel")
		local equipPanel = InventoryGui:FindFirstChild("EquipmentPanel")
		if equipPanel then equipPanel.Visible = not equipPanel.Visible end
		if mainPanel then mainPanel.Visible = not mainPanel.Visible end
	end

	if input.KeyCode.Value >= Enum.KeyCode.One.Value and input.KeyCode.Value <= Enum.KeyCode.Nine.Value then
		local slotNumber = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		UseHotbarRemote:FireServer(slotNumber)
	end
end)

-- [[ FIX FOR RESPAWNING ]] --
RequestSyncRemote:FireServer()
