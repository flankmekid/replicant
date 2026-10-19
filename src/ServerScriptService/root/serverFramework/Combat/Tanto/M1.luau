-- SPDX-License-Identifier: MIT
--
-- Tanto M1. Sends hits through BuffService, so the Mystic Eyes buff applies, and
-- otherwise runs CombatCore.RunM1.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local BuffService = require(SSS.modules.BuffService)

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	BuffService.ApplyDamage(plr, char, targetChar, dmg, extraDmg, "Weapon")
end

-- M1.ServerCheck() - run the Tanto M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Tanto.server.m1, {
		onDamage = onDamage,
		subType = data and data.SubType,
	})
end

return module
