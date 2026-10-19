-- SPDX-License-Identifier: MIT
--
-- Greatsword M1. Adds the greatsword swing FX and the ground slam on the running attack
-- to CombatCore.RunM1.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local function groundSlam(char)
	local tool = char:FindFirstChild("Greatsword")
	if not tool then
		return
	end
	local gs = RP.assets.FX.groundSlam.Attachment:Clone()
	gs.Parent = tool.Greatsword
	gs.Position = tool.Greatsword.Top.Position
	gs.Orientation = Vector3.new(0, 0, 50)
	for _, eff in pairs(gs:GetChildren()) do
		if eff:IsA("ParticleEmitter") then
			eff:Emit(eff:GetAttribute("EmitCount"))
		end
	end
	game.Debris:AddItem(gs, 2)
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
		groundSlam(char)
	elseif combo == 7 then
		E(char, "GSSlashes", "SlashDown", "HumanoidRootPart")
	elseif combo == 8 then
		E(char, "GSSlashes", "SlashUp", "HumanoidRootPart")
	end
end

-- M1.ServerCheck() - run the Greatsword M1
-- @plr: the player who pressed M1
-- @data: the client payload. data.SubType is the movement state.
--
-- Return: nothing.
function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Greatsword.server.m1, {
		swingDispatch = swingDispatch,
		subType = data and data.SubType,
	})
end

return module
