-- SPDX-License-Identifier: MIT
--
-- Caestus M1. Adds fist particle FX on each combo hit and half weapon XP to
-- CombatCore.RunM1. Hits during the Monastic Stance buff go through BuffService.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local BuffService = require(SSS.modules.BuffService)
local WINDUP = WeaponConfig.Caestus.server.m1.windup
-- The limb that glows for each move pattern: combo hits 1 to 5, then the running
-- attack (6), the air attack (7), and the uppercut (8).
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

-- M1.ServerCheck() - run the Caestus M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Caestus.server.m1, {
		onWindupStart = onWindupStart,
		onDamage = onDamage,
		xpMultiplier = 0.5,
		subType = data and data.SubType,
	})
end

return module
