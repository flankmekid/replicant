-- Thin standard server M1. Resolves the equipped weapon's config and hands off to
-- CombatCore. Serves every standard weapon via the dispatcher fallback. Weapons
-- with special mechanics (buffs, downSwing, fist FX) keep their own server M1 that
-- calls CombatCore.RunM1 with the appropriate hooks.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local function getEquippedTool(plr)
	local c = plr.Character
	if not c then
		return nil
	end
	local tool = c:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == c then
		return tool.Name
	end
	return nil
end

-- data.SubType carries the client's movement state ("Lunge" / "Uppercut" / "AirLunge"
-- / nil). It is the only honest signal the server gets: Running and Sliding are
-- client-set attributes that never replicate up, so CombatCore reads this instead.
function module.ServerCheck(plr, data)
	local weapon = getEquippedTool(plr)
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	CombatCore.RunM1(plr, cfg.server.m1, { subType = data and data.SubType })
end

return module
