-- SPDX-License-Identifier: MIT
--
-- Fists M1. Runs CombatCore.RunM1 with the Fists config and no extra hooks.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

-- M1.ServerCheck() - run the Fists M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Fists.server.m1, { subType = data and data.SubType })
end

return module
