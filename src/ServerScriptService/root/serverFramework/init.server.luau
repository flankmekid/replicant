-- SPDX-License-Identifier: MIT
--
-- Routes every client action from the server remote to a handler module. The payload names
-- the module by Type, folder, and Action, and the handler function by Func.

local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server

-- Every payload field comes from the client, so the handler checks its shape first.
local allowedTypes = {
	Combat = true,
}

ServerRemote.OnServerEvent:Connect(function(plr, data, ...)
	if typeof(data) ~= "table" or not allowedTypes[data.Type] then
		warn(`[serverFramework] {plr.Name} sent a payload with no valid Type.`)
		return
	end
	if
		typeof(data.CombatType) ~= "string"
		or typeof(data.Action) ~= "string"
		or typeof(data.Func) ~= "string"
	then
		warn(`[serverFramework] {plr.Name} sent a payload without CombatType, Action, or Func.`)
		return
	end

	local actionType = data.Type
	local moduleName = data.Action
	local funcName = data.Func
	local folderName = data.CombatType

	if not plr.Character then
		warn(`[serverFramework] Character of {plr.Name} not found.`)
		return
	end

	local root = script:FindFirstChild(actionType)
	local actionFolder = root:FindFirstChild(folderName)
	local module = actionFolder and actionFolder:FindFirstChild(moduleName)

	-- Most weapons have no module of their own for an action and use the shared one.
	if not module or not module:IsA("ModuleScript") then
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

	local moduleTable = require(module)

	if typeof(moduleTable[funcName]) == "function" then
		-- Handlers get the payload because it is the only way the server learns the client's
		-- movement state. Running and Sliding are client-set attributes and do not replicate.
		moduleTable[funcName](plr, data, ...)
	else
		warn(`[serverFramework] Function {moduleName}.{funcName} not found ({plr.Name}).`)
	end
end)
