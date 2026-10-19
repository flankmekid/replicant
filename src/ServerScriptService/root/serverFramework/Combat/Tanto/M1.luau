-- Tanto server M1 (thin). Standard swing (no custom dispatch), plus its buff:
-- buffed hits deal double base damage and restore 5 mana (no heal). Shared flow
-- and generic swing FX come from CombatCore.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

-- Buff (Mystic Eyes) is centralized in BuffService (activated from SkillHandler
-- on cast). This weapon just routes its hits through it.
local BuffService = require(SSS.modules.BuffService)

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	BuffService.ApplyDamage(plr, char, targetChar, dmg, extraDmg, "Weapon")
end

function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Tanto.server.m1, {
		onDamage = onDamage,
		subType = data and data.SubType,
	})
end

return module
