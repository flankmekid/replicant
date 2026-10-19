-- Deathbringer server M1 (thin). Unique bits only: the buff (monastic stance)
-- functions, the inverted GS swing dispatch with downSwing, and the onDamage hook
-- that applies the buff. Shared flow + resolution come from CombatCore.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)
local damageCalculator = require(SSS.modules.damageCalculator)

-- Buff (Berserker Armor) centralized in BuffService (activated from SkillHandler).
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

-- inverted convention (rightSwing -> SlashRight), downSwing on 6/7
local function swingDispatch(char, combo)
	local E = CombatCore.EmitSlash
	if combo == 1 or combo == 3 or combo == 5 then
		E(char, "GSSlashes", "SlashRight", "Torso")
	elseif combo == 2 or combo == 4 then
		E(char, "GSSlashes", "SlashLeft", "Torso")
	elseif combo == 6 then
		E(char, "GSSlashes", "SlashDown", "HumanoidRootPart")
		-- original references the "Dragon Slayer" tool (clone artifact); guarded no-op on Deathbringer
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

function module.ServerCheck(plr, data)
	CombatCore.RunM1(plr, WeaponConfig.Deathbringer.server.m1, {
		swingDispatch = swingDispatch,
		onDamage = onDamage,
		subType = data and data.SubType,
	})
end

return module
