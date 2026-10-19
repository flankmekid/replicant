-- SPDX-License-Identifier: MIT
--
-- Default server M2 for weapons without their own M2 module. Looks up the equipped
-- weapon in WeaponConfig and runs CombatCore.RunM2.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local function getEquippedTool(plr)
	local c = plr.Character
	if not c then
		return nil
	end
	local tool = c:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == c then
		return tool.Name
	end
	return nil
end

-- M2.ServerCheck() - run the M2 of the equipped weapon
-- @plr: the player who pressed M2
--
-- Return: nothing.
function module.ServerCheck(plr)
	local weapon = getEquippedTool(plr)
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	CombatCore.RunM2(plr, cfg.server.m2)
end

return module
