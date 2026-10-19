-- SPDX-License-Identifier: MIT
--
-- Routes every client action from the server remote to a handler module. The payload names
-- the module by Type, folder, and Action, and the handler function by Func.

local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server
local Players = game:GetService("Players")

local loadedModules = {}

local typeToStringValue = {
	Ability = "Plr_SkillSet",
	Misc = "Misc",
}

ServerRemote.OnServerEvent:Connect(function(plr, data, ...)
	local actionType = data.Type
	local moduleName = data.Action
	local funcName = data.Func

	local root = script:FindFirstChild(actionType)
	local folderName

	if actionType == "Combat" then
		local combatTypeName = data.CombatType
		if not combatTypeName then
			warn(`[serverFramework] Combat action from {plr.Name} has no CombatType.`)
			return
		end
		folderName = combatTypeName

		local char = plr.Character

		if not char then
			warn(`[serverFramework] Character of {plr.Name} not found.`)

			return
		end
	else
		local stringValueName = typeToStringValue[actionType]
		local folderNameValue = plr:FindFirstChild(stringValueName)
		if not folderNameValue then
			warn(`[serverFramework] {plr.Name} has no StringValue for {actionType}.`)
			return
		end
		folderName = folderNameValue.Value
	end

	local actionFolder = root:FindFirstChild(folderName)
	local module = actionFolder and actionFolder:FindFirstChild(moduleName)

	-- Most weapons have no module of their own for an action and use the shared one.
	if (not module or not module:IsA("ModuleScript")) and actionType == "Combat" then
		local sharedFolder = root:FindFirstChild("_Shared")
		local sharedModule = sharedFolder and sharedFolder:FindFirstChild(moduleName)
		if sharedModule and sharedModule:IsA("ModuleScript") then
			module = sharedModule
			folderName = "_Shared"
		end
	end

	if not module or not module:IsA("ModuleScript") then
		warn(`[serverFramework] No module {actionType}/{folderName}/{moduleName} ({plr.Name}).`)
		return
	end

	loadedModules[plr] = loadedModules[plr] or {}
	loadedModules[plr][actionType] = loadedModules[plr][actionType] or {}
	loadedModules[plr][actionType][folderName] = loadedModules[plr][actionType][folderName] or {}
	loadedModules[plr][actionType][folderName][moduleName] = loadedModules[plr][actionType][folderName][moduleName]
		or require(module)

	local moduleTable = loadedModules[plr][actionType][folderName][moduleName]

	if typeof(moduleTable[funcName]) == "function" then
		-- Handlers get the payload because it is the only way the server learns the client's
		-- movement state. Running and Sliding are client-set attributes and do not replicate.
		moduleTable[funcName](plr, data, ...)
	else
		warn(`[serverFramework] Function {moduleName}.{funcName} not found ({plr.Name}).`)
	end
end)

game.Players.PlayerRemoving:Connect(function(plr)
	loadedModules[plr] = nil
end)
