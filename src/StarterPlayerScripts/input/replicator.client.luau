local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("remotes")
local remote = Remotes:WaitForChild("replicate")
local ReplicationFolder = ReplicatedStorage:WaitForChild("localHandler")

local plr = game.Players.LocalPlayer

local ParryCooldownClient = require(ReplicatedStorage.modules.ParryCooldownClient)
-- requiring this here boots the single client shaker + its CameraShake remote listener
-- at join (persistent script), so server-driven damage shakes have a live receiver.
local ClientCameraShake = require(ReplicatedStorage.modules.ClientCameraShake)

local loadedClientModules = {}

-- ONLY keep types that still rely on StringValues
local typeToStringValue = {
	Ability = "Plr_SkillSet",
	-- REMOVED: Combat = "Plr_CombatType",
}

remote.OnClientEvent:Connect(function(data, ...)
	local actionType = data.Type
	local moduleName = data.Action
	local funcName = data.Func
	local folderName

	-- Parry cooldown reset: the server fires a Combat "Parry" event with (attacker, parrier).
	-- If the local player is the parrier, they landed a parry, so shorten their local cooldown
	-- to match the server's ParryService.ResetParry. Keeps the dance / re-parry alive on the client.
	if actionType == "Combat" and funcName == "Parry" then
		local parrier = select(2, ...)
		if parrier == plr.Character and data.FolderName then
			ParryCooldownClient.Reset(data.FolderName .. "_Block")
			-- snappy shake to make the landed parry feel intense (parrier's camera only)
			ClientCameraShake.Bump()
		end
	end

	-- *** NEW LOGIC: DETERMINE FOLDER NAME BASED ON ACTION TYPE ***
	if actionType == "Combat" then
		-- Combat actions are now defined by the folderName passed back by the server.
		folderName = data.FolderName
		if not folderName then
			warn(`[Client] Combat replication received without FolderName.`)
			return
		end
	else
		-- Logic for Ability, Misc, or other types that still rely on StringValue
		local stringValueName = typeToStringValue[actionType]
		local stringValue = plr:FindFirstChild(stringValueName)
		if not stringValue then
			warn(`[Client] Missing StringValue for {actionType}.`)
			return
		end
		folderName = stringValue.Value
	end

	local typeFolder = ReplicationFolder:FindFirstChild(actionType)
	local actionFolder = typeFolder and typeFolder:FindFirstChild(folderName)

	local module = actionFolder and actionFolder:FindFirstChild(moduleName)

	-- fallback to the shared module when this weapon has no per-weapon override
	if not (module and module:IsA("ModuleScript")) then
		local sharedFolder = typeFolder and typeFolder:FindFirstChild("_Shared")
		module = sharedFolder and sharedFolder:FindFirstChild(moduleName)
	end

	if not module or not module:IsA("ModuleScript") then
		warn(`Client module "{moduleName}" not found in "{folderName}"`)
		return
	end

	-- Load and cache the module (Cache logic remains the same)
	loadedClientModules[actionType] = loadedClientModules[actionType] or {}
	loadedClientModules[actionType][folderName] = loadedClientModules[actionType][folderName] or {}
	loadedClientModules[actionType][folderName][moduleName] = loadedClientModules[actionType][folderName][moduleName] or require(module)

	local moduleTable = loadedClientModules[actionType][folderName][moduleName]

	if typeof(moduleTable[funcName]) == "function" then
		moduleTable[funcName](...)
	else
		warn(`Function "{funcName}" not found in client module "{moduleName}"`)
	end
end)
