-- SPDX-License-Identifier: MIT
--
-- Typing "mb" in chat removes every combat tag the player handed out.
local Players = game:GetService("Players")

local CombatManager = require(game.ServerScriptService.modules.combatTagManager)

local function onMessage(player, message)
	local msg = message:lower():gsub("^%s+", ""):gsub("%s+$", "")
	-- Match "mb" as its own word at the start ("mb", "mb sorry"), not "maybe" or "mbappe".
	if msg == "mb" or msg:match("^mb%s") then
		CombatManager.ClearMyTags(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		onMessage(player, message)
	end)
end)

-- Also connect players who joined before this script ran.
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(message)
		onMessage(player, message)
	end)
end
