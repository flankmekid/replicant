-- [[ LEVEL UP INDICATOR ]]
-- Location: StarterPlayerScripts
-- Watches PlayerStats.WeaponData.[Weapon].Level for changes
-- and fires an FFXIV-inspired level up effect on the local client.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local character = player.Character or player.CharacterAdded:Wait()

-- ── CONFIGURATION ─────────────────────────────────────────────────────────────
local CFG = {
	-- Ring
	RING_DURATION = 1, -- seconds the ring expands
	RING_MAX_SIZE = 18, -- studs diameter at peak
	RING_THICKNESS = 0.18, -- ring wall thickness
	RING_COLOR = Color3.fromRGB(255, 220, 100),
	RING_EMISSION = 2, -- surface light emission

	-- Inner flash
	FLASH_DURATION = 0.2,
	FLASH_COLOR = Color3.fromRGB(255, 245, 180),

	-- UI toast
	TOAST_HOLD = 3.5, -- seconds the toast stays fully visible
	TOAST_FADE = 0.5, -- fade in/out duration
	TOAST_BG = Color3.fromRGB(20, 14, 8),
	TOAST_BORDER = Color3.fromRGB(200, 160, 50),
	TOAST_LABEL_COLOR = Color3.fromRGB(255, 220, 100),
	TOAST_SUB_COLOR = Color3.fromRGB(220, 200, 160),

	-- Milestone labels (matches your spreadsheet milestones)
	MILESTONES = {
		[10] = "You are ready to specialise. Seek out a trainer to further your knowledge.",
		[15] = "A new technique has awakened. Return to your trainer.",
		[20] = "Your style is your own now. Return to your trainer.",
		[25] = "Mastery achieved. Return to your trainer.",
	},

	-- Sound (replace with your own asset IDs if you have them)
	SOUND_ID = "rbxassetid://108161825312558", -- bright chime, swap freely
	SOUND_VOLUME = 1,
	SOUND_PITCH = 1.0,
}

local WEAPON_TYPES = { "Fists", "Katana", "Sword", "Dagger", "Greatsword" }

-- ── WAIT FOR DATA ──────────────────────────────────────────────────────────────
local function waitForStats()
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		return stats
	end
	-- PlayerStats is created server-side in dataManager shortly after spawn
	return player:WaitForChild("PlayerStats", 15)
end

-- ── SOUND ──────────────────────────────────────────────────────────────────────
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

-- ── WORLD EFFECT: EXPANDING RING ───────────────────────────────────────────────
--
-- A flat torus-like ring made from a scaled cylinder shell.
-- We fake the ring by using a very short, hollow-looking cylinder:
-- outer cylinder slightly larger than inner, clipped by CFrame.
-- Roblox doesn't have a torus primitive, so we use a SpecialMesh (ring shape).
--
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

-- ── WORLD EFFECT: CHARACTER FLASH ─────────────────────────────────────────────
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

-- ── UI TOAST ───────────────────────────────────────────────────────────────────
--
-- FFXIV-style: dark bordered panel slides down from top-center,
-- holds, then fades out. Shows weapon name, new level, and
-- milestone text if applicable.
--
local function buildToastGui()
	-- Reuse existing ScreenGui if present (prevents stacking on rapid level-ups)
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

	-- Outer container — centred top
	local container = Instance.new("CanvasGroup")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0.08, 0)
	container.Size = UDim2.new(0, 380, 0, 90)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = gui

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	-- "LEVEL UP" eyebrow label
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

	-- Main label: "[Weapon] · Level [N]"
	local mainLabel = Instance.new("TextLabel")
	mainLabel.Name = "MainLabel"
	mainLabel.Size = UDim2.new(1, -20, 0, 30)
	mainLabel.Position = UDim2.new(0, 10, 0, 28)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Text = "" -- filled in at call time
	mainLabel.TextColor3 = CFG.TOAST_LABEL_COLOR
	mainLabel.TextSize = 22
	mainLabel.Font = Enum.Font.Fondamento
	mainLabel.TextXAlignment = Enum.TextXAlignment.Center
	mainLabel.Parent = container

	-- Sub label: milestone text or blank
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

	-- Start fully transparent
	container.GroupTransparency = 1
	container.Position = UDim2.new(0.5, 0, 0.08, 0)

	-- Fade in over 0.5s
	TweenService:Create(
		container,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	):Play()

	-- Hold for 2s, then fade out over 0.5s
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

-- ── MASTER LEVEL-UP HANDLER ────────────────────────────────────────────────────
local function onLevelUp(weaponName, newLevel)
	-- Guard: don't fire on initial data load (level starts at 1)
	if newLevel <= 1 then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- World effects (run in parallel, non-blocking)
	task.spawn(playLevelUpSound, root)
	task.spawn(spawnFX, root)
	--task.spawn(spawnFlash, root)

	-- UI toast
	showToast(weaponName, newLevel)
end

-- ── WATCHER ───────────────────────────────────────────────────────────────────
--
-- Connects to each weapon's Level IntValue.
-- Uses the previous value to confirm an actual increase
-- (guards against data reconciliation setting level to 1 on first load).
--
local function watchWeaponLevels(stats)
	local weaponDataFolder = stats:WaitForChild("WeaponData", 10)
	if not weaponDataFolder then
		warn("[LevelUp] WeaponData folder not found in PlayerStats.")
		return
	end

	for _, weaponName in ipairs(WEAPON_TYPES) do
		local weaponFolder = weaponDataFolder:WaitForChild(weaponName, 10)
		if weaponFolder then
			local levelValue = weaponFolder:WaitForChild("Level", 10)
			if levelValue then
				local previousLevel = levelValue.Value

				levelValue.Changed:Connect(function(newLevel)
					-- Only fire if the level genuinely increased
					if newLevel > previousLevel then
						onLevelUp(weaponName, newLevel)
					end
					previousLevel = newLevel
				end)
			end
		end
	end
end

-- ── INIT ──────────────────────────────────────────────────────────────────────
task.spawn(function()
	local stats = waitForStats()
	if stats then
		watchWeaponLevels(stats)
	else
		warn("[LevelUp] PlayerStats did not load in time.")
	end
end)

-- Handle character respawns — root part reference needs refreshing
player.CharacterAdded:Connect(function(newChar)
	character = newChar
end)
