local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CAU = require(ReplicatedStorage.modules.ContextActionUtility)

local Character = script.Parent
local Hum = Character:WaitForChild("Humanoid")
local Head = Character:WaitForChild("Head")

Hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

local CarryButton = Enum.KeyCode.V
local GripButton = Enum.KeyCode.B

local debounce = false
local gripDB = false

-- 2. CREATE THE GUI (Bottom Middle & Horizontal)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local interactionGui = Instance.new("ScreenGui")
interactionGui.Name = "DownedInteractionGUI"
interactionGui.ResetOnSpawn = true
interactionGui.Parent = playerGui

local container = Instance.new("Frame")
container.Size = UDim2.new(0, 400, 0, 50) -- Wider container to fit both texts
container.Position = UDim2.new(0.5, 0, 0.92, 0) -- 92% down the screen
container.AnchorPoint = Vector2.new(0.5, 1) -- Anchored at the bottom-center
container.BackgroundTransparency = 1
container.Parent = interactionGui

-- UIListLayout handles the Horizontal alignment automatically
local listLayout = Instance.new("UIListLayout")
listLayout.Parent = container
listLayout.FillDirection = Enum.FillDirection.Horizontal -- Side by side
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center -- Center of frame
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, 60) -- Space between the two texts

local function createLabel(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 100, 1, 0) -- Fixed width blocks
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.RobotoMono -- Kept your font preference
	label.TextSize = 16 -- Kept your size preference
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.TextColor3 = Color3.fromRGB(150, 150, 150) -- Kept your color preference
	label.Parent = container
	return label
end

local gripLabel = createLabel("B - Grip")
local carryLabel = createLabel("V - Carry")

-- 3. FADE LOGIC
local isVisible = false
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function fadeGui(visible)
	if isVisible == visible then return end
	isVisible = visible

	local targetTransparency = visible and 0 or 1
	local strokeTransparency = visible and 0.5 or 1

	TweenService:Create(gripLabel, tweenInfo, {TextTransparency = targetTransparency, TextStrokeTransparency = strokeTransparency}):Play()
	TweenService:Create(carryLabel, tweenInfo, {TextTransparency = targetTransparency, TextStrokeTransparency = strokeTransparency}):Play()
end

-- 4. UTILITY FUNCTIONS
function GetClosestDowned(position)
	local maxDistance = 5
	local nearestDowned, nearestDistance

	local downedFolder = ReplicatedStorage:FindFirstChild("Downed")
	if not downedFolder then return nil end

	for i, v in pairs(downedFolder:GetChildren()) do
		if not v.Value or not v.Value:FindFirstChild("Head") then continue end

		if v.Value:FindFirstChild("Dead") then continue end

		local character = v.Value
		local distance = (character.Head.Position - position).Magnitude

		if not character or 
			distance > maxDistance or 
			(nearestDistance and distance >= nearestDistance) 
		then
			continue
		end

		nearestDistance = distance
		nearestDowned = character
	end
	return nearestDowned
end

-- 5. ACTIONS
local function Carry(actionName, inputState, _inputObject)
	if Character:GetAttribute("CantAnything") then return end
	if debounce == true then return end
	if inputState ~= Enum.UserInputState.Begin then return end
	debounce = true

	local victim = GetClosestDowned(Head.Position)

	if victim and victim ~= Character then
		ReplicatedStorage.remotes.CarryEvent:FireServer(victim)
		task.wait(2)
	end
	debounce = false
end

local function Grip(actionName, inputState, _inputObject)
	if Character:GetAttribute("CantAnything") then return end
	if gripDB then return end
	if inputState ~= Enum.UserInputState.Begin then return end
	gripDB = true

	local victim = GetClosestDowned(Head.Position)

	if victim and victim ~= Character then
		ReplicatedStorage.remotes.GripEvent:FireServer(victim)
		task.wait(2)
	end
	gripDB = false
end

CAU:BindAction("Carry", Carry, true, CarryButton)
CAU:SetImage("Carry", "rbxassetid://18362401517")

CAU:BindAction("Grip", Grip, true, GripButton)
CAU:SetImage("Grip", "rbxassetid://18362400331")

Hum.HealthChanged:Connect(function(health)
	if Character:GetAttribute("Stunned") == false then return end
	if (health/Hum.Health) > 0.3 and Character:GetAttribute("Carried") == false then
		ReplicatedStorage.remotes.ReviveEvent:FireServer()
	end
end)

RunService.RenderStepped:Connect(function()
	if not Head then return end

	local victim = GetClosestDowned(Head.Position)

	if victim and victim ~= Character then
		print(victim)
		fadeGui(true) -- Show GUI
	else
		fadeGui(false) -- Hide GUI
	end
end)