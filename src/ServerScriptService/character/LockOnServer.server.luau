-- SPDX-License-Identifier: MIT
--
-- Turns Shift Lock on or off for a player when the lock-on asks for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local toggleEvent = ReplicatedStorage.remotes:WaitForChild("ToggleShiftLock")

toggleEvent.OnServerEvent:Connect(function(player, shouldEnable)
	if typeof(shouldEnable) ~= "boolean" then
		return
	end
	-- DevEnableMouseLock = false also forces the player out of Shift Lock.
	player.DevEnableMouseLock = shouldEnable
end)
