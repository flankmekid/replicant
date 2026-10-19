-- Thin standard server E. Resolves the equipped weapon's config and hands off to
-- CombatCore.RunE. Serves every standard E (dash attack) via the dispatcher fallback.
-- Fist weapons keep their own E (particle FX / mana), and Dagger/Tanto keep their
-- custom throw/heavy E.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.root.serverFramework.Combat._Shared.CombatCore)
local WeaponConfig = require(RP.modules.WeaponConfig)

local function getEquippedTool(plr)
	local c = plr.Character
	if not c then return nil end
	local tool = c:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == c then return tool.Name end
	return nil
end

function module.ServerCheck(plr)
	local weapon = getEquippedTool(plr)
	if not weapon then return end
	local cfg = WeaponConfig[weapon]
	if not cfg then return end
	CombatCore.RunE(plr, cfg.server.e)
end

return module
