-- SPDX-License-Identifier: MIT
--
-- The inventory UI: the item grid, the hotbar, and the equipment slots, with tooltips,
-- click-to-equip, and drag and drop. The server owns the inventory and syncs it through
-- UpdateUI. This replaces the default Backpack.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local InventoryGui = PlayerGui:WaitForChild("BackpackUI")

local Grid = InventoryGui:WaitForChild("MainPanel"):WaitForChild("Grid")
local HotbarFrame = InventoryGui:WaitForChild("Hotbar")
local EquipPanel = InventoryGui:WaitForChild("EquipmentPanel")
local DragLayer = InventoryGui:WaitForChild("DragLayer")

local HotbarTemplate = ReplicatedStorage:WaitForChild("assets"):WaitForChild("hotbarFrame")

local InventoryRemotes = ReplicatedStorage:WaitForChild("remotes")
local UpdateUIEvent = InventoryRemotes:WaitForChild("UpdateUI")
local MoveItemRemote = InventoryRemotes:WaitForChild("MoveItem")
local UseHotbarRemote = InventoryRemotes:WaitForChild("UseHotbar")
local RequestSyncRemote = InventoryRemotes:WaitForChild("RequestSync")

local StarterGui = game:GetService("StarterGui")
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local DragState =
	{ IsDragging = false, ItemData = nil, SourceType = nil, SourceIndex = nil, VisualClone = nil }

-- A press that has not yet become a click or a drag.
local PendingPress = nil
-- Pixels of movement before a press becomes a drag.
local dragThreshold = 8

-- One shared tooltip. A weapon shows its name. Equipment shows the name and the slot
-- it fits, from the Category the server sends.
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
	if not itemData or not itemData.Name then
		return
	end
	TooltipTitle.Text = itemData.Name
	if itemData.Category then
		TooltipSub.Visible = true
		TooltipSub.Text = "Slot: " .. tostring(itemData.Category)
		Tooltip.Size = UDim2.fromOffset(160, 44)
	else
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
		-- Place the tooltip just above and right of the cursor.
		Tooltip.Position = UDim2.fromOffset(input.Position.X + 16, input.Position.Y + 22)
	end
end)

-- Shows the tooltip of an item while its slot is hovered.
local function BindTooltip(slot, itemData)
	if not itemData then
		return
	end
	slot.MouseEnter:Connect(function()
		ShowTooltip(itemData)
	end)
	slot.MouseLeave:Connect(function()
		HideTooltip()
	end)
end

-- Adds the name and amount labels of an item to a slot.
local function CreateSlotInfo(itemData, parentFrame)
	if not itemData then
		return
	end

	local nameLabel = Instance.new("TextLabel")
	-- The selection code finds the equipped item by this label.
	nameLabel.Name = "ItemName"
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

local selectionTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

local function UpdateSelectionVisuals()
	local char = player.Character
	local equippedTool = char and char:FindFirstChildOfClass("Tool")
	local equippedName = equippedTool and equippedTool.Name or nil

	for _, slot in ipairs(HotbarFrame:GetChildren()) do
		if slot:IsA("GuiObject") then
			local nameLabel = slot:FindFirstChild("ItemName")
			local stroke = slot:FindFirstChild("SelectionStroke")

			-- Outline the slot of the equipped item.
			if nameLabel and nameLabel.Text == equippedName and equippedName ~= nil then
				if not stroke then
					stroke = Instance.new("UIStroke")
					stroke.Name = "SelectionStroke"
					stroke.Color = Color3.new(1, 1, 1)
					stroke.Thickness = 3
					-- Start invisible, so the outline fades in.
					stroke.Transparency = 1
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = slot
				end

				TweenService:Create(stroke, selectionTweenInfo, { Transparency = 0 }):Play()
			else
				-- Not equipped: fade the outline out and remove it.
				if stroke and stroke.Transparency < 1 then
					local tweenOut =
						TweenService:Create(stroke, selectionTweenInfo, { Transparency = 1 })
					tweenOut:Play()

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

local function SetupCharacterListeners(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			UpdateSelectionVisuals()
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			UpdateSelectionVisuals()
		end
	end)
	UpdateSelectionVisuals()
end

player.CharacterAdded:Connect(SetupCharacterListeners)
if player.Character then
	SetupCharacterListeners(player.Character)
end

-- Returns true if the player holds the named item as an equipped Tool.
local function IsHoldingItem(itemName)
	local char = player.Character
	if not char then
		return false
	end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == itemName
end

local function ClearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if
			child:IsA("GuiObject")
			and not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
		then
			child:Destroy()
		end
	end
end

-- Starts a press on a slot. Release or movement decides between click and drag.
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
	ClearChildren(Grid)
	for index, item in pairs(syncData.Items or {}) do
		local slot = HotbarTemplate:Clone()
		slot.Name = "InvSlot_" .. tostring(index)
		-- Active, so the click works when the template is a Frame and not a TextButton.
		slot.Active = true

		CreateSlotInfo(item, slot)
		BindTooltip(slot, item)
		slot.Parent = Grid

		slot.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and item then
				ArmPress(slot, item, "Inventory", index, input.Position)
			end
		end)
	end

	ClearChildren(HotbarFrame)
	for i = 1, 9 do
		local slot = HotbarTemplate:Clone()
		slot.Name = "HotbarSlot_" .. tostring(i)
		slot.Active = true

		-- Add the slot number unless the template has one.
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

	-- Visit every equipment slot, so each one is cleared or filled.
	local equipmentSlots = { "Head", "Torso", "Legs", "Back" }

	for _, slotName in ipairs(equipmentSlots) do
		local equipSlot = EquipPanel:FindFirstChild(slotName)
		if equipSlot then
			-- Clear the slot first, because the item may have been removed.
			for _, child in ipairs(equipSlot:GetChildren()) do
				if child.Name == "ItemName" or child:IsA("ImageLabel") then
					child:Destroy()
				end
			end

			if equipSlot:FindFirstChild("DragConnection") then
				-- Disconnects the old drag handler.
				equipSlot.DragConnection:Fire()
				equipSlot.DragConnection:Destroy()
			end

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

				connectionVal.Event:Connect(function()
					conn:Disconnect()
				end)
			end
		end
	end

	UpdateSelectionVisuals()
end)

function StartDrag(uiSlot, itemData, sourceType, sourceIndex, mousePos)
	if DragState.IsDragging then
		return
	end
	if not itemData or not itemData.Name then
		return
	end

	DragState.IsDragging = true
	DragState.ItemData = itemData
	DragState.SourceType = sourceType
	DragState.SourceIndex = sourceIndex

	DragState.VisualClone = uiSlot:Clone()
	DragState.VisualClone.Size = UDim2.fromOffset(60, 60)
	DragState.VisualClone.AnchorPoint = Vector2.new(0.5, 0.5)
	DragState.VisualClone.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)

	-- The dragged copy has no selection outline.
	local cloneStroke = DragState.VisualClone:FindFirstChild("SelectionStroke")
	if cloneStroke then
		cloneStroke:Destroy()
	end

	-- The tooltip does not follow a dragged copy.
	HideTooltip()

	DragState.VisualClone.Parent = DragLayer
end

-- A click on an equipment item the player holds equips it. Returns true if it did.
local function TryClickEquip(press)
	local item = press.Item
	if not item or not item.Category then
		return false
	end
	if not IsHoldingItem(item.Name) then
		return false
	end

	MoveItemRemote:FireServer(
		item.Id,
		press.SourceType,
		press.SourceIndex,
		"Equipment",
		item.Category
	)
	return true
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	-- A press that moves far enough becomes a drag.
	if PendingPress and not PendingPress.Started and not DragState.IsDragging then
		local delta = (Vector2.new(input.Position.X, input.Position.Y) - PendingPress.StartPos).Magnitude
		if delta >= dragThreshold then
			PendingPress.Started = true
			StartDrag(
				PendingPress.Slot,
				PendingPress.Item,
				PendingPress.SourceType,
				PendingPress.SourceIndex,
				input.Position
			)
		end
	end

	if DragState.IsDragging and DragState.VisualClone then
		DragState.VisualClone.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	-- A drag ends with a drop.
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
			MoveItemRemote:FireServer(
				DragState.ItemData.Id,
				DragState.SourceType,
				DragState.SourceIndex,
				targetType,
				targetIndex
			)
		end

		if DragState.VisualClone then
			DragState.VisualClone:Destroy()
		end
		DragState.IsDragging = false
		DragState.ItemData = nil
		PendingPress = nil
		return
	end

	-- A press released without a drag is a click.
	if PendingPress then
		TryClickEquip(PendingPress)
		PendingPress = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.I then
		local mainPanel = InventoryGui:FindFirstChild("MainPanel")
		local equipPanel = InventoryGui:FindFirstChild("EquipmentPanel")
		if equipPanel then
			equipPanel.Visible = not equipPanel.Visible
		end
		if mainPanel then
			mainPanel.Visible = not mainPanel.Visible
		end
	end

	if
		input.KeyCode.Value >= Enum.KeyCode.One.Value
		and input.KeyCode.Value <= Enum.KeyCode.Nine.Value
	then
		local slotNumber = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		UseHotbarRemote:FireServer(slotNumber)
	end
end)

-- Ask for a sync, so a respawned UI shows the inventory.
RequestSyncRemote:FireServer()
