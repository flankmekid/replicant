-- SPDX-License-Identifier: MIT
--
-- Shows the sheath of the equipped weapon on the character. Only tools in
-- ServerStorage.Weapons count, so equipping a spell or a quest item keeps the current
-- sheath. To give a weapon a sheath, add it to SHEATH_MAP.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local assets = game:GetService("ReplicatedStorage"):WaitForChild("assets")

-- Tool name to sheath model name in ReplicatedStorage.assets. Equipping a weapon
-- without an entry removes the sheath and adds nothing.
local SHEATH_MAP = {
	["Katana"] = "Sheath",
	["Vermillion"] = "SheathKensei",
}

-- Every weapon name in ServerStorage.Weapons.
local WEAPON_NAMES = {}
local weaponsFolder = ServerStorage:WaitForChild("Weapons")
for _, tool in ipairs(weaponsFolder:GetChildren()) do
	WEAPON_NAMES[tool.Name] = true
end

-- Every sheath model name, for cleanup.
local ALL_SHEATH_NAMES = {}
for _, assetName in pairs(SHEATH_MAP) do
	ALL_SHEATH_NAMES[assetName] = true
end

local function removeSheath(char)
	for _, child in ipairs(char:GetChildren()) do
		if ALL_SHEATH_NAMES[child.Name] then
			child:Destroy()
		end
	end
end

local function attachSheath(char, assetName)
	if char:FindFirstChild(assetName) then
		return
	end

	local template = assets:FindFirstChild(assetName)
	if not template then
		warn(`[SheathManager] Sheath model {assetName} not found in ReplicatedStorage.assets.`)
		return
	end

	local sheath = template:Clone()
	sheath.Parent = char

	local innerPart = sheath:FindFirstChild("Sheath")
	local weld = innerPart and innerPart:FindFirstChild("Torso")
	if weld then
		weld.Part1 = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	else
		warn(`[SheathManager] Sheath model {assetName} has no Sheath.Torso weld.`)
	end
end

local function onWeaponEquipped(char, tool)
	removeSheath(char)
	local assetName = SHEATH_MAP[tool.Name]
	if assetName then
		attachSheath(char, assetName)
	end
end

local function watchCharacter(char)
	char:WaitForChild("HumanoidRootPart")

	char.ChildAdded:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		if not WEAPON_NAMES[child.Name] then
			return
		end
		onWeaponEquipped(char, child)
	end)

	-- No unequip handler: the sheath stays until the next weapon is equipped.
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(char)
		watchCharacter(char)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
