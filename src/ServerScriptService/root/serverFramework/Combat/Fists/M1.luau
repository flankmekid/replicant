-- Fists server M1 (thin). Its particle FX is dead code and it has no buff, so it's
-- a plain config-driven weapon: CombatCore runs the whole thing, generic swing FX
-- comes from the (now-corrected) comboMap.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Fists.server.m1, { subType = data and data.SubType })
end

return module
