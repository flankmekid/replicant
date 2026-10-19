-- SPDX-License-Identifier: MIT
--
-- Receives the replicate remote and calls the named effect function of a client
-- module, such as the swing sound or hit FX of a weapon. A weapon without its own
-- module uses the _Shared one. It also resets the parry cooldown after a landed parry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("remotes")
local remote = Remotes:WaitForChild("replicate")
local ReplicationFolder = ReplicatedStorage:WaitForChild("localHandler")

local plr = game.Players.LocalPlayer

local ParryCooldownClient = require(ReplicatedStorage.modules.ParryCooldownClient)
-- Requiring the shaker here starts it, and its CameraShake listener, at join.
local ClientCameraShake = require(ReplicatedStorage.modules.ClientCameraShake)

local loadedClientModules = {}

-- Action types whose folder name comes from a StringValue on the player.
local typeToStringValue = {
	Ability = "Plr_SkillSet",
}

remote.OnClientEvent:Connect(function(data, ...)
	local actionType = data.Type
	local moduleName = data.Action
	local funcName = data.Func
	local folderName

	-- The server fires a Combat "Parry" with (attacker, parrier). If the local player is the
	-- parrier, shorten their local cooldown, the same as ParryService.ResetParry.
	if actionType == "Combat" and funcName == "Parry" then
		local parrier = select(2, ...)
		if parrier == plr.Character and data.FolderName then
			ParryCooldownClient.Reset(data.FolderName .. "_Block")
			-- A short shake on the parrier's camera.
			ClientCameraShake.Bump()
		end
	end

	if actionType == "Combat" then
		-- The server sends the weapon folder name.
		folderName = data.FolderName
		if not folderName then
			warn(`[replicator] Combat replication arrived without FolderName.`)
			return
		end
	else
		-- Other types read the folder name from a StringValue.
		local stringValueName = typeToStringValue[actionType]
		local stringValue = plr:FindFirstChild(stringValueName)
		if not stringValue then
			warn(`[replicator] No StringValue for {actionType}.`)
			return
		end
		folderName = stringValue.Value
	end

	local typeFolder = ReplicationFolder:FindFirstChild(actionType)
	local actionFolder = typeFolder and typeFolder:FindFirstChild(folderName)

	local module = actionFolder and actionFolder:FindFirstChild(moduleName)

	-- A weapon without its own module uses the _Shared one.
	if not (module and module:IsA("ModuleScript")) then
		local sharedFolder = typeFolder and typeFolder:FindFirstChild("_Shared")
		module = sharedFolder and sharedFolder:FindFirstChild(moduleName)
	end

	if not module or not module:IsA("ModuleScript") then
		warn(`[replicator] Client module {moduleName} not found for {folderName}.`)
		return
	end

	loadedClientModules[actionType] = loadedClientModules[actionType] or {}
	loadedClientModules[actionType][folderName] = loadedClientModules[actionType][folderName] or {}
	loadedClientModules[actionType][folderName][moduleName] = loadedClientModules[actionType][folderName][moduleName]
		or require(module)

	local moduleTable = loadedClientModules[actionType][folderName][moduleName]

	if typeof(moduleTable[funcName]) == "function" then
		moduleTable[funcName](...)
	else
		warn(`[replicator] Function {moduleName}.{funcName} not found.`)
	end
end)
