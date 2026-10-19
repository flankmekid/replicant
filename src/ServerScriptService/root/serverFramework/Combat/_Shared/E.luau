-- SPDX-License-Identifier: MIT
--
-- Default server E (dash attack) for weapons without their own E module. Looks up the
-- equipped weapon in WeaponConfig and runs CombatCore.RunE.

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

-- E.ServerCheck() - run the E of the equipped weapon
-- @plr: the player who pressed E
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
	CombatCore.RunE(plr, cfg.server.e)
end

return module
