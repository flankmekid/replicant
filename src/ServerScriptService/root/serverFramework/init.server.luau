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
			warn(`[Server] Combat action received without CombatType.`)
			return
		end
		folderName = combatTypeName

		local char = plr.Character

		if not char then
			warn(`[Server] Player character not found.`)

			return
		end
	else
		local stringValueName = typeToStringValue[actionType]
		local folderNameValue = plr:FindFirstChild(stringValueName)
		if not folderNameValue then
			warn(`[Server] Missing StringValue for {actionType}.`)
			return
		end
		folderName = folderNameValue.Value
	end

	local actionFolder = root:FindFirstChild(folderName)
	local module = actionFolder and actionFolder:FindFirstChild(moduleName)

	-- Combat fallback: weapons without a per-weapon override route to Combat._Shared
	if (not module or not module:IsA("ModuleScript")) and actionType == "Combat" then
		local sharedFolder = root:FindFirstChild("_Shared")
		local sharedModule = sharedFolder and sharedFolder:FindFirstChild(moduleName)
		if sharedModule and sharedModule:IsA("ModuleScript") then
			module = sharedModule
			folderName = "_Shared"
		end
	end

	if not module or not module:IsA("ModuleScript") then
		warn(`[Server] Module {actionType}/{folderName}/{moduleName} not found.`)
		return
	end

	loadedModules[plr] = loadedModules[plr] or {}
	loadedModules[plr][actionType] = loadedModules[plr][actionType] or {}
	loadedModules[plr][actionType][folderName] = loadedModules[plr][actionType][folderName] or {}
	loadedModules[plr][actionType][folderName][moduleName] = loadedModules[plr][actionType][folderName][moduleName]
		or require(module)

	local moduleTable = loadedModules[plr][actionType][folderName][moduleName]

	if typeof(moduleTable[funcName]) == "function" then
		-- Pass the payload table (data) as arg 2. The client fires a single table, so
		-- the trailing ... is always empty; handlers that ignore data are unaffected,
		-- and the ones that need the client's movement state (M1 ServerCheck reads
		-- data.SubType) can get at it. This is the honest channel for Running/Sliding,
		-- which as client-set attributes never replicate up to the server.
		moduleTable[funcName](plr, data, ...)
	else
		warn(`Function "{funcName}" not found in module "{moduleName}"`)
	end
end)

game.Players.PlayerRemoving:Connect(function(plr)
	loadedModules[plr] = nil
end)
