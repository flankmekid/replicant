-- Caestus server E (thin). Live fist particle FX (fistsWhite) on the leg, mana gain
-- on hit, and half XP. Dash flow + resolution come from CombatCore.RunE.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local WINDUP = WeaponConfig.Caestus.server.e.windup

local function FX(char, bodypart)
	local part = char:FindFirstChild(bodypart)
	if not part then return end
	local effect1 = RP.assets.FX.fistsWhite.partic:Clone()
	local effect2 = RP.assets.FX.fistsWhite.paricle:Clone()
	effect1.Parent = part
	effect2.Parent = part
	effect1.Enabled = true
	effect2.Enabled = true
	task.delay(WINDUP - 0.2, function()
		game.Debris:AddItem(effect1, 0.2)
		game.Debris:AddItem(effect2, 0.2)
	end)
end

local function onWindupStart(char)
	FX(char, "Left Leg")
end

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	damageCalculator.CalculateDamage(char, targetChar, dmg, extraDmg, false, "Weapon")
	local mana = plr:FindFirstChild("PlayerStats") and plr.PlayerStats:FindFirstChild("Mana")
	if mana and mana.Value < 90 then mana.Value += 10 end
end

function module.ServerCheck(plr)
	CombatCore.RunE(plr, WeaponConfig.Caestus.server.e, {
		onWindupStart = onWindupStart,
		onDamage = onDamage,
		xpMultiplier = 0.5,
	})
end

return module
