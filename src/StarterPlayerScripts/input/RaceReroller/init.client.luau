local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RollRaceFunction = Remotes:WaitForChild("RollRace")
local RaceConfig = require(ReplicatedStorage.modules:WaitForChild("RaceConfig"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local RaceUI = PlayerGui:WaitForChild("MainMenu") -- Adjusted to your UI structure
local MainFrame = RaceUI:WaitForChild("MainFrame"):WaitForChild("Popups"):WaitForChild("Races")

-- [[ FRAME REFERENCES ]] --
local LeftFrame = MainFrame:WaitForChild("LeftFrame")
local MidFrame = MainFrame:WaitForChild("MiddleFrame")
local RightFrame = MainFrame:WaitForChild("RightFrame")

-- Rolling Refs
local RollButton = MidFrame:WaitForChild("RollButton")
local RollingFrame = MidFrame:WaitForChild("RollingFrame")
-- If you have a counter, reference it here. Example:
-- local RollCounter = MidFrame:WaitForChild("RollCounter")

local Labels = {
	RollingFrame:WaitForChild("Label1"), -- Top
	RollingFrame:WaitForChild("Label2"), -- Middle
	RollingFrame:WaitForChild("Label3"), -- Bottom
}

-- Viewport Refs
local Viewport = LeftFrame:WaitForChild("Viewport")
local WorldModel = Viewport:WaitForChild("WorldModel")
local RaceNameLbl = LeftFrame:WaitForChild("RaceName")
local RarityLbl = LeftFrame:WaitForChild("Rarity")
local DescLbl = LeftFrame:WaitForChild("Description")

-- Stats Refs
local StatsList = RightFrame:WaitForChild("StatsList")

-- [[ CONFIG ]] --
local SPEED = 700
local TOTAL_ROLLS = 40
local LABEL_HEIGHT = Labels[1].Size.Y.Offset
if LABEL_HEIGHT == 0 then
	LABEL_HEIGHT = RollingFrame.AbsoluteSize.Y / 3
end -- Failsafe
local Debounce = false

-- [[ STAT NAMES MAPPING ]] --
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

-- [[ HELPER: COLOR LOOKUP ]] --
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

-- [[ VIEWPORT LOGIC ]] --
local viewportCam = Instance.new("Camera")
Viewport.CurrentCamera = viewportCam
viewportCam.Parent = Viewport

local currentRotation = 0
local isDragging = false
local lastMouseX = 0

local function UpdateViewport(character, raceName)
	-- [[ 1. RESET ROTATION ]] --
	currentRotation = 180

	WorldModel:ClearAllChildren()
	character.Archivable = true
	local clone = character:Clone()
	clone.Parent = WorldModel

	-- [[ 2. CLEANUP CLONE ]] --
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

	-- [[ 3. FORCE APPLY VISUALS ]] --
	if raceName then
		local data = RaceConfig.Races[raceName]
		if data and data.Visuals then
			local visuals = data.Visuals

			-- [[ A. FORCE SKIN COLOR ]] --
			if visuals.SkinColor then
				for _, part in ipairs(clone:GetChildren()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						part.Color = visuals.SkinColor
					end
				end
			end

			-- [[ B. FORCE HAIR COLOR ]] --
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

	-- [[ 4. CAMERA SETUP ]] --
	local root = clone:WaitForChild("HumanoidRootPart")
	root.Anchored = true
	root.CFrame = CFrame.new(Vector3.new(0, 0, 0))

	local cameraDist = 6
	viewportCam.CFrame = CFrame.new(Vector3.new(0, 1, cameraDist), root.Position)

	-- [[ 5. ROTATION BIND ]] --
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

-- [[ UI UPDATE LOGIC ]] --
local function UpdateUI(raceName)
	local data = RaceConfig.Races[raceName]
	if not data then
		return
	end

	-- Left Frame
	RaceNameLbl.Text = raceName
	RaceNameLbl.TextColor3 = GetRaceColor(raceName)
	RarityLbl.Text = data.Rarity
	RarityLbl.TextColor3 = GetRaceColor(raceName)
	DescLbl.Text = data.Description or "No description."

	-- Right Frame (Stats)
	StatsList:ClearAllChildren()
	local uiLayout = Instance.new("UIListLayout")
	uiLayout.Padding = UDim.new(0, 5)
	uiLayout.Parent = StatsList

	-- List Number/Value Stats
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

		-- Custom formatting
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

-- [[ ROLL ANIMATION ]] --
-- [[ GENERATE RACE LIST AUTOMATICALLY ]] --
local r2 = {}
for raceName, _ in pairs(RaceConfig.Races) do
	table.insert(r2, raceName)
end

local function AnimateRoll(finalRace)
	local counter = 0
	local offset = 0

	-- Hide outer labels for clean look during spin
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

		-- UI List Layout handles position, so we just logic-swap when offset hits threshold
		if offset >= LABEL_HEIGHT then
			offset = 0
			counter += 1

			-- Shift visual logic
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

			-- Final State
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

			UpdateViewport(player.Character, finalRace) -- Sync the 3D model

			Debounce = false
		end
	end)
end

-- [[ INITIALIZATION ]] --
local function Init()
	task.wait(1)
	local pStats = player:WaitForChild("PlayerStats")
	local currentRace = pStats:WaitForChild("Race").Value

	-- Setup Initial Text
	Labels[2].Text = currentRace
	Labels[2].TextColor3 = GetRaceColor(currentRace)

	-- Random fillers for hidden labels
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
		print("Buy more spins!")
		Debounce = false
	else
		AnimateRoll(result)
		if script:FindFirstChild("Roll") then
			script.Roll:Play()
		end
	end
end)

-- Update viewport when character respawns (after race change applied)
player.CharacterAdded:Connect(function(char)
	task.delay(1.5, function() -- Wait for appearance load
		UpdateViewport(char, player:WaitForChild("PlayerStats"):WaitForChild("Race").Value)
	end)
end)

Init()
