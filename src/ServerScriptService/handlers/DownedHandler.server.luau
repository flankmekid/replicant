-- SPDX-License-Identifier: MIT
--
-- Handles the client requests to execute, carry, or drop a downed body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DownedManager = require(ServerScriptService.modules.DownedManager)
local StateHandler = require(ReplicatedStorage.modules.stateHandler)

local Remotes = ReplicatedStorage:FindFirstChild("remotes")
local InteractionRemote = Remotes:FindFirstChild("DownedInteraction")

InteractionRemote.OnServerEvent:Connect(function(player, action, targetChar)
	local myChar = player.Character
	if not myChar then
		return
	end

	if action == "Execute" then
		-- A second Execute cancels the running execution.
		if StateHandler.GetState(myChar, "Executing") then
			DownedManager.StopExecution(myChar)
		elseif targetChar then
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
			DownedManager.AttemptCarry(myChar, targetChar)
		else
			-- No target means drop.
			DownedManager.DropIfCarrying(myChar)
		end
	end
end)
