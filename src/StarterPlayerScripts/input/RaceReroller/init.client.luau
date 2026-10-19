-- SPDX-License-Identifier: MIT
--
-- The race spin menu: rolls a race on the server, plays the spin animation, and shows
-- the rolled race in a rotatable viewport with its rarity, description, and stats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RollRaceFunction = Remotes:WaitForChild("RollRace")
local RaceConfig = require(ReplicatedStorage.modules:WaitForChild("RaceConfig"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local RaceUI = PlayerGui:WaitForChild("MainMenu")
local MainFrame = RaceUI:WaitForChild("MainFrame"):WaitForChild("Popups"):WaitForChild("Races")

local LeftFrame = MainFrame:WaitForChild("LeftFrame")
local MidFrame = MainFrame:WaitForChild("MiddleFrame")
local RightFrame = MainFrame:WaitForChild("RightFrame")

local RollButton = MidFrame:WaitForChild("RollButton")
local RollingFrame = MidFrame:WaitForChild("RollingFrame")

local Labels = {
	RollingFrame:WaitForChild("Label1"), -- Top.
	RollingFrame:WaitForChild("Label2"), -- Middle.
	RollingFrame:WaitForChild("Label3"), -- Bottom.
}

local Viewport = LeftFrame:WaitForChild("Viewport")
local WorldModel = Viewport:WaitForChild("WorldModel")
local RaceNameLbl = LeftFrame:WaitForChild("RaceName")
local RarityLbl = LeftFrame:WaitForChild("Rarity")
local DescLbl = LeftFrame:WaitForChild("Description")

local StatsList = RightFrame:WaitForChild("StatsList")

local SPEED = 700
local TOTAL_ROLLS = 40
local LABEL_HEIGHT = Labels[1].Size.Y.Offset
-- The label may have no pixel height yet, so fall back to a third of the frame.
if LABEL_HEIGHT == 0 then
	LABEL_HEIGHT = RollingFrame.AbsoluteSize.Y / 3
end
local Debounce = false

-- Display names of the race stats.
local StatNames = {
	HPBoost = "Health Boost",
	ManaBoost = "Max Mana Boost",
	LiturgyMultiplier = "Liturgy Gain Multiplier",
	RegenMultiplier = "Regen Multiplier",
	DefenseBoost = "Defense Boost",
	DashDuration = "Dash I-Frame Duration",
	SlideDuration = "Slide Duration",
	ESP = "ESP",
	Hyperarmor = "Hyperarmor",
	Lifesteal = "Lifesteal",
	ManaWhenHit = "Regenerate Mana When Hit",
}

local function GetRaceColor(raceName)
	local raceData = RaceConfig.Races[raceName]
	if not raceData then
		return Color3.fromRGB(255, 255, 255)
	end
	for _, rarityInfo in ipairs(RaceConfig.Rarities) do
		if rarityInfo.Name == raceData.Rarity then
			return rarityInfo.Color
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

local viewportCam = Instance.new("Camera")
Viewport.CurrentCamera = viewportCam
viewportCam.Parent = Viewport

local currentRotation = 0
local isDragging = false
local lastMouseX = 0

-- Shows a copy of the character in the viewport with the visuals of the race.
local function UpdateViewport(character, raceName)
	currentRotation = 180

	WorldModel:ClearAllChildren()
	character.Archivable = true
	local clone = character:Clone()
	clone.Parent = WorldModel

	for _, v in pairs(clone:GetDescendants()) do
		if
			v:IsA("Script")
			or v:IsA("LocalScript")
			or v:IsA("ForceField")
			or v:IsA("BillboardGui")
			or v:IsA("BodyColors")
		then
			v:Destroy()
		end
	end

	-- Apply the race skin and hair colors to the copy, because the character may still
	-- show the old race.
	if raceName then
		local data = RaceConfig.Races[raceName]
		if data and data.Visuals then
			local visuals = data.Visuals

			if visuals.SkinColor then
				for _, part in ipairs(clone:GetChildren()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						part.Color = visuals.SkinColor
					end
				end
			end

			if visuals.HairColor then
				for _, acc in ipairs(clone:GetChildren()) do
					if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hair then
						local handle = acc:FindFirstChild("Handle")
						if handle then
							handle.Color = visuals.HairColor
							if handle:IsA("MeshPart") then
								handle.TextureID = ""
							end
							local mesh = handle:FindFirstChildOfClass("SpecialMesh")
							if mesh then
								mesh.TextureId = ""
							end
						end
					end
				end
			end
		end
	end

	local root = clone:WaitForChild("HumanoidRootPart")
	root.Anchored = true
	root.CFrame = CFrame.new(Vector3.new(0, 0, 0))

	local cameraDist = 6
	viewportCam.CFrame = CFrame.new(Vector3.new(0, 1, cameraDist), root.Position)

	-- Dragging rotates the copy.
	RunService:UnbindFromRenderStep("RaceViewportRot")
	RunService:BindToRenderStep("RaceViewportRot", Enum.RenderPriority.Camera.Value, function()
		if clone and clone.Parent then
			root.CFrame = CFrame.Angles(0, math.rad(currentRotation), 0)
		end
	end)
end

Viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isDragging = true
		lastMouseX = input.Position.X
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position.X - lastMouseX
		lastMouseX = input.Position.X
		currentRotation = currentRotation + delta
	end
end)

local function UpdateUI(raceName)
	local data = RaceConfig.Races[raceName]
	if not data then
		return
	end

	RaceNameLbl.Text = raceName
	RaceNameLbl.TextColor3 = GetRaceColor(raceName)
	RarityLbl.Text = data.Rarity
	RarityLbl.TextColor3 = GetRaceColor(raceName)
	DescLbl.Text = data.Description or "No description."

	StatsList:ClearAllChildren()
	local uiLayout = Instance.new("UIListLayout")
	uiLayout.Padding = UDim.new(0, 5)
	uiLayout.Parent = StatsList

	for statKey, val in pairs(data.Stats) do
		local displayVal = val
		local displayName = StatNames[statKey] or statKey

		if val == true then
			displayVal = "Active"
		end

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 25)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.new(0.741176, 0.741176, 0.741176)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Font = Enum.Font.RobotoMono
		lbl.TextSize = 20

		if
			type(val) == "number"
			and (string.find(statKey, "Boost") or string.find(statKey, "Multiplier"))
			and not (string.find(statKey, "HPBoost"))
		then
			if val == 1 then
				continue
			end
			lbl.Text = string.format("%s: x%.2f", displayName, val)
		elseif type(val) == "boolean" and val == true then
			lbl.Text = displayName
			lbl.TextColor3 = Color3.fromRGB(255, 51, 54)
		else
			lbl.Text = string.format("%s: %s", displayName, tostring(val))
		end

		lbl.Parent = StatsList
	end
end

-- Every race name, for the spin.
local r2 = {}
for raceName, _ in pairs(RaceConfig.Races) do
	table.insert(r2, raceName)
end

local function AnimateRoll(finalRace)
	local counter = 0
	local offset = 0

	-- Hide the outer labels during the spin.
	Labels[1].TextTransparency = 1
	Labels[3].TextTransparency = 1
	Labels[2].TextTransparency = 0

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local move = SPEED * dt

		if counter > TOTAL_ROLLS * 0.7 then
			move = move
				* (1 - ((counter - (TOTAL_ROLLS * 0.7)) / (TOTAL_ROLLS - (TOTAL_ROLLS * 0.7))))
			if move < 5 then
				move = 5
			end
		end

		offset += move

		-- The UIListLayout positions the labels, so only swap the names when the offset passes
		-- a label height.
		if offset >= LABEL_HEIGHT then
			offset = 0
			counter += 1

			Labels[3].Text = Labels[2].Text
			Labels[3].TextColor3 = Labels[2].TextColor3

			Labels[2].Text = Labels[1].Text
			Labels[2].TextColor3 = Labels[1].TextColor3

			if counter < TOTAL_ROLLS then
				local newName = r2[math.random(1, #r2)]
				Labels[1].Text = newName
				Labels[1].TextColor3 = GetRaceColor(newName)
			else
				Labels[1].Text = finalRace
				Labels[1].TextColor3 = GetRaceColor(finalRace)
			end
		end

		if counter >= TOTAL_ROLLS + 2 then
			conn:Disconnect()

			Labels[1].TextTransparency = 1
			Labels[3].TextTransparency = 1
			Labels[2].Text = finalRace
			Labels[2].TextColor3 = GetRaceColor(finalRace)

			if RaceConfig.Races[finalRace].Rarity == "Legendary" then
				if script:FindFirstChild("Win") then
					script.Win:Play()
				end
			end

			UpdateUI(finalRace)

			UpdateViewport(player.Character, finalRace)

			Debounce = false
		end
	end)
end

local function Init()
	task.wait(1)
	local pStats = player:WaitForChild("PlayerStats")
	local currentRace = pStats:WaitForChild("Race").Value

	Labels[2].Text = currentRace
	Labels[2].TextColor3 = GetRaceColor(currentRace)

	-- Fill the hidden labels with random races.
	Labels[1].Text = r2[math.random(1, #r2)]
	Labels[1].TextColor3 = GetRaceColor(Labels[1].Text)
	Labels[3].Text = r2[math.random(1, #r2)]
	Labels[3].TextColor3 = GetRaceColor(Labels[3].Text)

	Labels[1].TextTransparency = 1
	Labels[3].TextTransparency = 1

	UpdateUI(currentRace)

	if player.Character then
		UpdateViewport(player.Character, currentRace)
	end
end

RollButton.MouseButton1Click:Connect(function()
	if Debounce then
		return
	end
	Debounce = true

	local result = RollRaceFunction:InvokeServer()
	if result == "NoSpins" then
		Debounce = false
	else
		AnimateRoll(result)
		if script:FindFirstChild("Roll") then
			script.Roll:Play()
		end
	end
end)

-- After a respawn, show the new race once the appearance has loaded.
player.CharacterAdded:Connect(function(char)
	task.delay(1.5, function()
		UpdateViewport(char, player:WaitForChild("PlayerStats"):WaitForChild("Race").Value)
	end)
end)

Init()
