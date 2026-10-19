-- SPDX-License-Identifier: MIT
--
-- Default server M1 for weapons without their own M1 module. Looks up the equipped
-- weapon in WeaponConfig and runs CombatCore.RunM1.

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

-- M1.ServerCheck() - run the M1 of the equipped weapon
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state ("Lunge", "AirLunge",
--        "Uppercut", or nil). The server cannot read it any other way, because
--        Running and Sliding are client-set attributes and do not replicate.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	local weapon = getEquippedTool(plr)
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	CombatCore.RunM1(plr, cfg.server.m1, { subType = data and data.SubType })
end

return module
