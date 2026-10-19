task.wait(1)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui
local character = player.Character or player.CharacterAdded:Wait()

local WEAPON_REGISTRY = {
	Sword = "Sword",
	Excalibur = "Sword",
	Guandao = "Sword",
	Scythe = "Sword",
	Katana = "Katana",
	Vermillion = "Katana",
	Dagger = "Dagger",
	Tanto = "Dagger",
	Greatsword = "Greatsword",
	Deathbringer = "Greatsword",
	["Dragon Slayer"] = "Greatsword",
	Fists = "Fists",
	Caestus = "Fists",
	Shackles = "Fists",
}

local ABBREVIATIONS = {
	Sword = "SWD",
	Katana = "KTN",
	Dagger = "DGR",
	Greatsword = "GSW",
	Fists = "FIS",
}

local GUI = PlayerGui:WaitForChild("WeaponXPBar")
local Container = GUI:WaitForChild("Container")
local BarTrack = Container:WaitForChild("BarTrack")
local BarFill = BarTrack:WaitForChild("Fill")
local BarGlow = BarTrack:WaitForChild("Glow")
local InfoLeft = Container:WaitForChild("InfoLeft")
local InfoRight = Container:WaitForChild("InfoRight")

local XP_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local activeConnections = {}

local function getStats()
	return player:FindFirstChild("PlayerStats")
end

local function clearConnections()
	for _, c in ipairs(activeConnections) do
		c:Disconnect()
	end
	activeConnections = {}
end

local function updateDisplay(category, weaponFolder, animate)
	local levelVal = weaponFolder:FindFirstChild("Level")
	local curXPVal = weaponFolder:FindFirstChild("CurrentXP")
	local maxXPVal = weaponFolder:FindFirstChild("MaxXP")
	if not levelVal or not curXPVal or not maxXPVal then
		return
	end

	local lvl = levelVal.Value
	local cur = curXPVal.Value
	local max = maxXPVal.Value
	local ratio = (max > 0) and math.clamp(cur / max, 0, 1) or 1
	local abbr = ABBREVIATIONS[category] or category:sub(1, 3):upper()

	if lvl >= 25 then
		InfoLeft.Text = abbr .. "  Lv.MAX"
		InfoRight.Text = "MASTERED"
	else
		InfoLeft.Text = abbr .. "  Lv." .. lvl
		InfoRight.Text = "EXP  " .. tostring(cur) .. " / " .. tostring(max)
	end

	local targetSize = UDim2.new(ratio, 0, 1, 0)
	if animate then
		TweenService:Create(BarFill, XP_TWEEN, { Size = targetSize }):Play()
		TweenService:Create(BarGlow, XP_TWEEN, { Size = targetSize }):Play()
	else
		BarFill.Size = targetSize
		BarGlow.Size = targetSize
	end
end

local function watchWeapon(category, weaponFolder)
	clearConnections()
	if not weaponFolder then
		Container.Visible = false
		return
	end

	Container.Visible = true
	updateDisplay(category, weaponFolder, false)

	local curXP = weaponFolder:FindFirstChild("CurrentXP")
	local level = weaponFolder:FindFirstChild("Level")

	if curXP then
		table.insert(
			activeConnections,
			curXP.Changed:Connect(function()
				updateDisplay(category, weaponFolder, true)
			end)
		)
	end
	if level then
		table.insert(
			activeConnections,
			level.Changed:Connect(function()
				updateDisplay(category, weaponFolder, true)
			end)
		)
	end
end

local function resolveWeapon()
	local equipped = character:FindFirstChildWhichIsA("Tool")
	if equipped and WEAPON_REGISTRY[equipped.Name] then
		return WEAPON_REGISTRY[equipped.Name]
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and WEAPON_REGISTRY[tool.Name] then
				return WEAPON_REGISTRY[tool.Name]
			end
		end
	end
	return nil
end

local function refresh()
	local stats = getStats()
	if not stats then
		return
	end
	local weaponData = stats:FindFirstChild("WeaponData")
	if not weaponData then
		return
	end

	local category = resolveWeapon()
	if not category then
		clearConnections()
		Container.Visible = false
		return
	end

	watchWeapon(category, weaponData:FindFirstChild(category))
end

local function connectCharacter(char)
	character = char
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.wait()
			refresh()
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.wait()
			refresh()
		end
	end)
end

local function init()
	local stats = player:WaitForChild("PlayerStats", 15)
	if not stats then
		warn("[WeaponXP] PlayerStats not found.")
		return
	end
	stats:WaitForChild("WeaponData", 10)

	refresh()
	connectCharacter(character)

	player.CharacterAdded:Connect(function(newChar)
		character = newChar
		connectCharacter(newChar)
		task.spawn(function()
			local s = player:WaitForChild("PlayerStats", 15)
			if not s then
				return
			end
			s:WaitForChild("WeaponData", 10)
			refresh()
		end)
	end)

	local backpack = player:WaitForChild("Backpack", 10)
	if backpack then
		backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and WEAPON_REGISTRY[child.Name] then
				refresh()
			end
		end)
	end
end

task.spawn(init)
