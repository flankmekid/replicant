-- SPDX-License-Identifier: MIT
--
-- Dragon Slayer M1. Adds the greatsword swing FX, the ground slam on the running
-- attack, and the weapon buff (through BuffService) to CombatCore.RunM1.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

local BuffService = require(SSS.modules.BuffService)

local function groundSlam(tool)
	local slam = RP.assets.FX.groundSlam.Attachment:Clone()
	slam.Parent = tool.Greatsword
	slam.Position = tool.Greatsword.Top.Position
	slam.Orientation = Vector3.new(0, 0, 50)
	for _, eff in pairs(slam:GetChildren()) do
		if eff:IsA("ParticleEmitter") then
			eff:Emit(eff:GetAttribute("EmitCount"))
		end
	end
	game.Debris:AddItem(slam, 2)
end

-- Greatswords play SlashRight on odd combo hits, the opposite of the comboMap
-- convention, and a down slash on the running attack and the air attack.
local function swingDispatch(char, combo)
	local E = CombatCore.EmitSlash
	if combo == 1 or combo == 3 or combo == 5 then
		E(char, "GSSlashes", "SlashRight", "Torso")
	elseif combo == 2 or combo == 4 then
		E(char, "GSSlashes", "SlashLeft", "Torso")
	elseif combo == 6 then
		E(char, "GSSlashes", "SlashDown", "HumanoidRootPart")
		local tool = char:FindFirstChild("Dragon Slayer")
		if tool and tool:FindFirstChild("Greatsword") then
			groundSlam(tool)
		end
	elseif combo == 7 then
		E(char, "GSSlashes", "SlashDown", "HumanoidRootPart")
	elseif combo == 8 then
		E(char, "GSSlashes", "SlashUp", "HumanoidRootPart")
	end
end

local function onDamage(plr, char, targetChar, dmg, extraDmg)
	BuffService.ApplyDamage(plr, char, targetChar, dmg, extraDmg, "Weapon")
end

-- M1.ServerCheck() - run the Dragon Slayer M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig["Dragon Slayer"].server.m1, {
		swingDispatch = swingDispatch,
		onDamage = onDamage,
		subType = data and data.SubType,
	})
end

return module
