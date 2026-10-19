-- SERVER SCRIPT (inside ServerScriptService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local toggleEvent = ReplicatedStorage.remotes:WaitForChild("ToggleShiftLock")

toggleEvent.OnServerEvent:Connect(function(player, shouldEnable)
	-- This property determines if the player is ALLOWED to use Shift Lock.
	-- Setting it to false forces them out of Shift Lock if they are in it.
	player.DevEnableMouseLock = shouldEnable
end)
