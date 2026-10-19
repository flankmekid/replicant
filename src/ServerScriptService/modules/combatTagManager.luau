local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatManager = {}
local ActiveTags = {}
local TAG_DURATION = 30

-- Create Remote for Visuals
local Events = ReplicatedStorage:FindFirstChild("remotes")
if not Events then
	Events = Instance.new("Folder")
	Events.Name = "remotes"
	Events.Parent = ReplicatedStorage
end
local CombatEvent = Events:FindFirstChild("CombatTagUpdate")
if not CombatEvent then
	CombatEvent = Instance.new("RemoteEvent")
	CombatEvent.Name = "CombatTagUpdate"
	CombatEvent.Parent = Events
end

-- Fully clears a victim's tag (internal table, attribute, visuals, character flag)
local function clearTag(victim)
	ActiveTags[victim] = nil
	if victim then
		CombatEvent:FireClient(victim, false)
		victim:SetAttribute("CombatLogExpiry", nil)
		if victim.Character then
			victim.Character:SetAttribute("InCombat", nil)
		end
	end
end

function CombatManager.TagPlayer(victim, attacker)
	if not victim or not victim:IsA("Player") then
		return
	end

	local expiryTime = os.clock() + TAG_DURATION
	local currentTag = ActiveTags[victim]

	if currentTag then
		-- Already tagged: refresh expiry, add this attacker to the set
		currentTag.Expiry = expiryTime
		if attacker and attacker:IsA("Player") and attacker ~= victim then
			currentTag.Attackers[attacker] = true
		end
	else
		local attackers = {}
		if attacker and attacker:IsA("Player") and attacker ~= victim then
			attackers[attacker] = true
		end
		ActiveTags[victim] = {
			Expiry = expiryTime,
			Attackers = attackers,
		}
	end

	-- Attribute so DataManager can check combat status without this module
	victim:SetAttribute("CombatLogExpiry", expiryTime)

	-- Visuals
	CombatEvent:FireClient(victim, true, TAG_DURATION)

	-- Character Attribute (for other scripts/NPCs)
	if victim.Character then
		victim.Character:SetAttribute("InCombat", true)
	end
end

function CombatManager.SetTagDuration(player, duration)
	local currentTag = ActiveTags[player]
	if currentTag then
		local newExpiry = os.clock() + duration
		-- Only reduce the tag, never accidentally extend it
		if newExpiry < currentTag.Expiry then
			currentTag.Expiry = newExpiry
			player:SetAttribute("CombatLogExpiry", newExpiry)
			CombatEvent:FireClient(player, true, duration)
		end
	end
end

-- Removes a single attacker from every victim's set.
-- Fully untags a victim only if that leaves the set empty.
local function removeAttackerFromAll(attacker)
	for victim, data in pairs(ActiveTags) do
		if data.Attackers[attacker] then
			data.Attackers[attacker] = nil
			if next(data.Attackers) == nil then
				clearTag(victim)
			end
		end
	end
end

-- Kept the original name for compatibility; now respects the multi-attacker set
function CombatManager.UntagIfAttackerDied(deadPlayer)
	removeAttackerFromAll(deadPlayer)
end

-- Fully clears a single player's OWN tag (used on death, so dying ends your
-- combat state immediately: stops combat music, clears InCombat, drops aggro, etc).
function CombatManager.ClearPlayerTag(player)
	-- clearTag also resets the visual/attribute flags even if there's no table entry.
	clearTag(player)
end

-- Call this from DataManager's leave handling (PlayerRemoving lives there
-- to avoid the race condition). Removes the leaver as an attacker everywhere,
-- and also clears their own tag entry if they had one.
function CombatManager.HandlePlayerLeft(player)
	removeAttackerFromAll(player)
	if ActiveTags[player] then
		-- They left; no point keeping their own tag table around
		ActiveTags[player] = nil
	end
end

-- Called when a player types "mb" in chat. Removes every tag THEY handed out.
-- Does not touch their own tag.
function CombatManager.ClearMyTags(player)
	removeAttackerFromAll(player)
end

-- Check loop to remove tags naturally on expiry
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, data in pairs(ActiveTags) do
			if now >= data.Expiry then
				clearTag(player)
			end
		end
	end
end)

return CombatManager
