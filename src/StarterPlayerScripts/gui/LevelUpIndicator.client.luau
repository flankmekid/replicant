-- SPDX-License-Identifier: MIT
--
-- Plays the level-up effect, a ring, a sound, and a toast, when one of the local
-- player's weapon levels in PlayerStats.WeaponData rises.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local character = player.Character or player.CharacterAdded:Wait()

local CFG = {
	RING_DURATION = 1, -- Seconds.
	RING_MAX_SIZE = 18, -- Diameter in studs.
	RING_THICKNESS = 0.18,
	RING_COLOR = Color3.fromRGB(255, 220, 100),
	RING_EMISSION = 2,

	FLASH_DURATION = 0.2,
	FLASH_COLOR = Color3.fromRGB(255, 245, 180),

	TOAST_HOLD = 3.5, -- Seconds fully visible.
	TOAST_FADE = 0.5, -- Seconds per fade.
	TOAST_BG = Color3.fromRGB(20, 14, 8),
	TOAST_BORDER = Color3.fromRGB(200, 160, 50),
	TOAST_LABEL_COLOR = Color3.fromRGB(255, 220, 100),
	TOAST_SUB_COLOR = Color3.fromRGB(220, 200, 160),

	-- Weapon levels that unlock trainer steps.
	MILESTONES = {
		[10] = "You are ready to specialise. Seek out a trainer to further your knowledge.",
		[15] = "A new technique has awakened. Return to your trainer.",
		[20] = "Your style is your own now. Return to your trainer.",
		[25] = "Mastery achieved. Return to your trainer.",
	},

	SOUND_ID = "rbxassetid://108161825312558",
	SOUND_VOLUME = 1,
	SOUND_PITCH = 1.0,
}

local weaponTypes = { "Fists", "Katana", "Sword", "Dagger", "Greatsword" }

local function waitForStats()
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		return stats
	end
	-- The server creates PlayerStats shortly after spawn.
	return player:WaitForChild("PlayerStats", 15)
end

local function playLevelUpSound(root)
	local s = Instance.new("Sound")
	s.SoundId = CFG.SOUND_ID
	s.Volume = CFG.SOUND_VOLUME
	s.PlaybackSpeed = CFG.SOUND_PITCH
	s.RollOffMaxDistance = 100000
	s.Parent = workspace
	s:Play()
	game:GetService("Debris"):AddItem(s, 4)
end

-- Plays the level-up particles at the root part.
local function spawnFX(root)
	local spawnFXTemplate =
		game.ReplicatedStorage.assets.FX:FindFirstChild("LevelUpParticle").Main.partic
	if spawnFXTemplate then
		local emitter = spawnFXTemplate:Clone()
		emitter.Parent = root
		emitter:Emit(30)
		game.Debris:AddItem(emitter, 4)
	end
end

local function spawnFlash(root)
	local flashPart = Instance.new("Part")
	flashPart.Anchored = true
	flashPart.CanCollide = false
	flashPart.CastShadow = false
	flashPart.Material = Enum.Material.Neon
	flashPart.Color = CFG.FLASH_COLOR
	flashPart.Transparency = 0.55
	flashPart.Size = Vector3.new(3, 5, 3)
	flashPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0))
	flashPart.Shape = Enum.PartType.Ball
	flashPart.Parent = workspace

	TweenService:Create(
		flashPart,
		TweenInfo.new(CFG.FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(6, 9, 6), Transparency = 1 }
	):Play()

	game:GetService("Debris"):AddItem(flashPart, CFG.FLASH_DURATION + 0.1)
end

-- Shows the level-up toast at the top center: the weapon, the new level, and any
-- milestone text.
local function buildToastGui()
	-- Reuse the toast GUI, so rapid level-ups do not stack.
	local existing = playerGui:FindFirstChild("LevelUpToast")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LevelUpToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local container = Instance.new("CanvasGroup")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0.08, 0)
	container.Size = UDim2.new(0, 380, 0, 90)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.Size = UDim2.new(1, -20, 0, 18)
	eyebrow.Position = UDim2.new(0, 10, 0, 10)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Text = "WEAPON LEVEL UP"
	eyebrow.TextColor3 = CFG.TOAST_BORDER
	eyebrow.TextSize = 11
	eyebrow.Font = Enum.Font.Fondamento
	eyebrow.TextXAlignment = Enum.TextXAlignment.Center
	eyebrow.Parent = container

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Name = "MainLabel"
	mainLabel.Size = UDim2.new(1, -20, 0, 30)
	mainLabel.Position = UDim2.new(0, 10, 0, 28)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Text = ""
	mainLabel.TextColor3 = CFG.TOAST_LABEL_COLOR
	mainLabel.TextSize = 22
	mainLabel.Font = Enum.Font.Fondamento
	mainLabel.TextXAlignment = Enum.TextXAlignment.Center
	mainLabel.Parent = container

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Size = UDim2.new(1, -20, 0, 18)
	subLabel.Position = UDim2.new(0, 10, 0, 62)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = ""
	subLabel.TextColor3 = CFG.TOAST_SUB_COLOR
	subLabel.TextSize = 12
	subLabel.Font = Enum.Font.Fondamento
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.TextTransparency = 0.2
	subLabel.Parent = container

	return gui, container, mainLabel, subLabel
end

local function showToast(weaponName, newLevel)
	local gui, container, mainLabel, subLabel = buildToastGui()

	mainLabel.Text = string.upper(weaponName) .. "  <->  LEVEL " .. newLevel
	subLabel.Text = CFG.MILESTONES[newLevel] or ""

	container.GroupTransparency = 1
	container.Position = UDim2.new(0.5, 0, 0.08, 0)

	TweenService:Create(
		container,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	):Play()

	task.delay(0.5 + 2.0, function()
		if not gui.Parent then
			return
		end
		local fadeOut = TweenService:Create(
			container,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if gui.Parent then
				gui:Destroy()
			end
		end)
	end)
end

local function onLevelUp(weaponName, newLevel)
	-- Skip level 1, which the first data load sets.
	if newLevel <= 1 then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	task.spawn(playLevelUpSound, root)
	task.spawn(spawnFX, root)

	showToast(weaponName, newLevel)
end

-- Watches each weapon's Level value and fires only on a real increase, so the first
-- data load does not count.
local function watchWeaponLevels(stats)
	local weaponDataFolder = stats:WaitForChild("WeaponData", 10)
	if not weaponDataFolder then
		warn("[LevelUpIndicator] WeaponData not found in PlayerStats.")
		return
	end

	for _, weaponName in ipairs(weaponTypes) do
		local weaponFolder = weaponDataFolder:WaitForChild(weaponName, 10)
		if weaponFolder then
			local levelValue = weaponFolder:WaitForChild("Level", 10)
			if levelValue then
				local previousLevel = levelValue.Value

				levelValue.Changed:Connect(function(newLevel)
					if newLevel > previousLevel then
						onLevelUp(weaponName, newLevel)
					end
					previousLevel = newLevel
				end)
			end
		end
	end
end

task.spawn(function()
	local stats = waitForStats()
	if stats then
		watchWeaponLevels(stats)
	else
		warn(`[LevelUpIndicator] PlayerStats did not load for {player.Name}.`)
	end
end)

-- Keep the current character, for its root part.
player.CharacterAdded:Connect(function(newChar)
	character = newChar
end)
