-- Thin standard server M2. Resolves the equipped weapon's config and hands off to
-- CombatCore.RunM2. Serves every standard M2 weapon via the dispatcher fallback.
-- Fist weapons with the aerial variant keep their own M2 that passes opts.swingM2.
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

function module.ServerCheck(plr)
	local weapon = getEquippedTool(plr)
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	CombatCore.RunM2(plr, cfg.server.m2)
end

return module
