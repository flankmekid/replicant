local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DownedManager = require(ServerScriptService.modules.DownedManager)
local StateHandler = require(ReplicatedStorage.modules.stateHandler)

-- Ensure Remotes folder/event exists
local Remotes = ReplicatedStorage:FindFirstChild("remotes")
local InteractionRemote = Remotes:FindFirstChild("DownedInteraction")

InteractionRemote.OnServerEvent:Connect(function(player, action, targetChar)
	local myChar = player.Character
	if not myChar then
		return
	end

	if action == "Execute" then
		-- Check if the player is ALREADY executing someone
		if StateHandler.GetState(myChar, "Executing") then
			DownedManager.StopExecution(myChar)
		elseif targetChar then
			-- Start a new execution
			DownedManager.AttemptExecute(myChar, targetChar)
		end
	elseif action == "Carry" then
		if targetChar then
			if
				StateHandler.GetState(myChar, "CantAnything")
				or StateHandler.GetState(myChar, "Stunned")
			then
				return
			end
			-- Pick up specific target
			-- (Note: AttemptCarry already calls DropIfCarrying internally if they are holding someone else)
			DownedManager.AttemptCarry(myChar, targetChar)
		else
			-- Drop (Client sent nil target)
			-- The module now handles finding the victim and cleaning up all the AlignConstraints automatically
			DownedManager.DropIfCarrying(myChar)
		end
	end
end)
