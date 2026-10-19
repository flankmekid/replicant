local Players = game:GetService("Players")

-- adjust this path to where CombatManager actually is
local CombatManager = require(game.ServerScriptService.modules.combatTagManager)

local function onMessage(player, message)
	-- normalize: trim and lowercase
	local msg = message:lower():gsub("^%s+", ""):gsub("%s+$", "")
	-- match "mb" as its own word at the start: "mb", "mb all", "mb sorry"
	-- but NOT "maybe", "mbappe", "mbtiles", etc.
	if msg == "mb" or msg:match("^mb%s") then
		CombatManager.ClearMyTags(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		onMessage(player, message)
	end)
end)

-- catch anyone already in-game when this script runs
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(message)
		onMessage(player, message)
	end)
end
