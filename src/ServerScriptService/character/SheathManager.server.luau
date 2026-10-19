-- SPDX-License-Identifier: MIT
--
-- Shows the sheath of the equipped weapon on the character. Only tools in
-- ServerStorage.Weapons count, so equipping a spell or a quest item keeps the current
-- sheath. To give a weapon a sheath, add it to sheathMap.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local assets = game:GetService("ReplicatedStorage"):WaitForChild("assets")

-- Tool name to sheath model name in ReplicatedStorage.assets. Equipping a weapon
-- without an entry removes the sheath and adds nothing.
local sheathMap = {
	["Katana"] = "Sheath",
	["Vermillion"] = "SheathKensei",
}

-- Every weapon name in ServerStorage.Weapons.
local weaponNames = {}
local weaponsFolder = ServerStorage:WaitForChild("Weapons")
for _, tool in ipairs(weaponsFolder:GetChildren()) do
	weaponNames[tool.Name] = true
end

-- Every sheath model name, for cleanup.
local allSheathNames = {}
for _, assetName in pairs(sheathMap) do
	allSheathNames[assetName] = true
end

local function removeSheath(char)
	for _, child in ipairs(char:GetChildren()) do
		if allSheathNames[child.Name] then
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
	local assetName = sheathMap[tool.Name]
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
		if not weaponNames[child.Name] then
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
