-- SPDX-License-Identifier: MIT
--
-- Shackles M1. Adds fist particle FX on each combo hit to CombatCore.RunM1.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local WINDUP = WeaponConfig.Shackles.server.m1.windup
-- The limb that glows for each move pattern: combo hits 1 to 5, then the running
-- attack (6), the air attack (7), and the uppercut (8).
local fxParts = {
	"Right Arm",
	"Left Arm",
	"Right Leg",
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
	local bp = fxParts[movePattern]
	if bp then
		FX(char, bp)
	end
end

-- M1.ServerCheck() - run the Shackles M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Shackles.server.m1, {
		onWindupStart = onWindupStart,
		subType = data and data.SubType,
	})
end

return module
