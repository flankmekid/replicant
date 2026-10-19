-- Caestus server M1 (thin). Monastic-stance buff (aura + buffed hits deal +dmg/2
-- and restore mana), live fist particle FX per combo, and half XP credit. Slashes
-- come from the generic path (corrected comboMap); everything shared from CombatCore.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local BuffService = require(SSS.modules.BuffService)
local WINDUP = WeaponConfig.Caestus.server.m1.windup
local FX_PARTS = {
	"Left Arm",
	"Right Arm",
	"Left Arm",
	"Left Leg",
	"Left Arm",
	"Right Arm",
	"Right Leg",
	"Right Arm",
}
-- Buff (Monastic Stance) is now centralized in BuffService and activated from
-- SkillHandler on cast; state + aura FX live there, not here.

local function FX(char, bodypart)
	local part = char:FindFirstChild(bodypart)
	if not part then
		return
	end
	local effect1 = RP.assets.FX.fists.partic:Clone()
	local effect2 = RP.assets.FX.fists.paricle:Clone()
	effect1.Parent = part
	effect2.Parent = part
	effect1.Enabled = true
	effect2.Enabled = true
	task.delay(WINDUP - 0.2, function()
		game.Debris:AddItem(effect1, 0.2)
		game.Debris:AddItem(effect2, 0.2)
	end)
end

local function onWindupStart(char, movePattern)
	local bp = FX_PARTS[movePattern]
	if bp then
		FX(char, bp)
	end
end

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	BuffService.ApplyDamage(plr, char, targetChar, dmg, extraDmg, "Weapon")
end

function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Caestus.server.m1, {
		onWindupStart = onWindupStart,
		onDamage = onDamage,
		xpMultiplier = 0.5,
		subType = data and data.SubType,
	})
end

return module
