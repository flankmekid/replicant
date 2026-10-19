-- Shackles server E (thin). Mana gain on hit and half XP (no live FX). Dash flow
-- and resolution come from CombatCore.RunE.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	damageCalculator.CalculateDamage(char, targetChar, dmg, extraDmg, false, "Weapon")
	local mana = plr:FindFirstChild("PlayerStats") and plr.PlayerStats:FindFirstChild("Mana")
	if mana and mana.Value < 90 then mana.Value += 10 end
end

function module.ServerCheck(plr)
	CombatCore.RunE(plr, WeaponConfig.Shackles.server.e, {
		onDamage = onDamage,
		xpMultiplier = 0.5,
	})
end

return module
