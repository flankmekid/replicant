-- SheathManager
-- Centralised sheath logic. Only reacts to tools that exist in ServerStorage.Weapons.
-- Equipping anything else (spells, quest items, etc.) leaves the current sheath untouched.
-- To give a weapon a sheath, add its name to SHEATH_MAP below.

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local assets        = game:GetService("ReplicatedStorage"):WaitForChild("assets")

-- ── Configuration ─────────────────────────────────────────────────────────────
-- Key: exact Tool name. Value: Model name inside ReplicatedStorage.assets.
-- Weapons with no entry get their sheath removed on equip, but nothing is added.
local SHEATH_MAP = {
	["Katana"]     = "Sheath",
	["Vermillion"] = "SheathKensei",
}
-- ──────────────────────────────────────────────────────────────────────────────

-- Build a lookup set of every weapon name from ServerStorage.Weapons at startup
local WEAPON_NAMES = {}
local weaponsFolder = ServerStorage:WaitForChild("Weapons")
for _, tool in ipairs(weaponsFolder:GetChildren()) do
	WEAPON_NAMES[tool.Name] = true
end

-- Also keep a set of all sheath asset names for reliable cleanup
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
	if char:FindFirstChild(assetName) then return end

	local template = assets:FindFirstChild(assetName)
	if not template then
		warn("[SheathManager] Asset not found:", assetName)
		return
	end

	local sheath = template:Clone()
	sheath.Parent = char

	local innerPart = sheath:FindFirstChild("Sheath")
	local weld = innerPart and innerPart:FindFirstChild("Torso")
	if weld then
		weld.Part1 = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	else
		warn("[SheathManager] Torso weld not found inside:", assetName)
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
		-- Ignore anything that isn't a registered weapon
		if not child:IsA("Tool") then return end
		if not WEAPON_NAMES[child.Name] then return end
		onWeaponEquipped(char, child)
	end)

	-- No unequip handler: sheath persists until the next weapon is equipped
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
