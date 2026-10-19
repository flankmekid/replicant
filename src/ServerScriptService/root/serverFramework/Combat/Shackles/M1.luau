-- Shackles server M1 (thin). Live fist particle FX (per-combo body part) via the
-- onWindupStart hook; slashes come from the generic path (corrected comboMap). No buff.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local WINDUP = WeaponConfig.Shackles.server.m1.windup
local FX_PARTS = {
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
	local bp = FX_PARTS[movePattern]
	if bp then
		FX(char, bp)
	end
end

function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Shackles.server.m1, {
		onWindupStart = onWindupStart,
		subType = data and data.SubType,
	})
end

return module
