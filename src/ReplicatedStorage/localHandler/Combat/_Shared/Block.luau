-- Shared Block (config-driven). REWRITTEN: parry and block are now SEPARATE inputs.
--   module.Parry   -> RMB tap. A pure parry (0.2s window), never rolls into block.
--   module.Hold    -> hold F. A pure block, no parry pre-roll.
--   module.Release -> release F. Ends the block.
-- The old model fused them (a held parry became a block after 0.2s); that is gone.
--
-- Thin client: this only plays anims and fires intent. Server _Shared.Block owns the
-- authoritative Parrying/Blocking state (and block WalkSpeed); ParryService owns the
-- parry cooldown. GB is still fired at us by the server on a guardbreak / block-break
-- so we can run break FX through the existing localHandler path.
local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local ParryCooldownClient = require(RP.modules.ParryCooldownClient)
local WeaponConfig = require(RP.modules.WeaponConfig)

-- [[ CONFIGURATION ]] --
local BLOCK_COOLDOWN = 0.35 -- lower than the old 0.5, but still not spammable

-- [[ STATE ]] --
local isBlocking = false
local nextBlockTime = 0

local function getEquippedTool()
	local currentCharacter = plr.Character
	if not currentCharacter then
		return nil
	end
	local tool = currentCharacter:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == currentCharacter then
		return tool.Name
	end
	return nil
end

-- Shared gate for both parry and block presses.
local function canAct(char)
	if not char then
		return false
	end
	if char:GetAttribute("CantAnything") then
		return false
	end
	if char:GetAttribute("Sliding") then
		return false
	end
	if char:GetAttribute("M1") then
		return false
	end
	if char:GetAttribute("M2") then
		return false
	end
	if char:GetAttribute("Carried") then
		return false
	end
	if char:GetAttribute("Downed") then
		return false
	end
	return true
end

-- ------------------------------------------------------------------ PARRY -----
-- RMB tap. A stunned player is deliberately allowed to parry (the only escape out
-- of an M1 combo), so Stunned is NOT checked here. Block (below) still forbids it.
function module.Parry()
	local char = plr.Character
	if not char then
		return
	end
	local weapon = getEquippedTool()
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	local blk = cfg.client.block

	if not canAct(char) then
		return
	end
	if isBlocking then
		return
	end
	if not ParryCooldownClient.CanParry() then
		return
	end

	-- cooldown applied immediately on press, keyed per weapon
	ParryCooldownClient.StartCooldown(weapon .. "_Block")

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "Block",
		Func = "ParryActive",
		CombatType = weapon,
	})

	animationHndlr.StopAnim(char, "ALL")
	animationHndlr.LoadAnim(char, "Parrying", blk.parryAnim, nil, false)
	RP.assets.sounds.BlockStart:Play()
end

-- ------------------------------------------------------------------ BLOCK -----
-- Hold F. Pure block: no parry, no window. Forbidden while Stunned (a stunned
-- victim gets the parry option only) and gated by the block cooldown.
function module.Hold()
	local char = plr.Character
	if not char then
		return
	end
	local weapon = getEquippedTool()
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	local blk = cfg.client.block

	if not canAct(char) then
		return
	end
	if isBlocking then
		return
	end
	if char:GetAttribute("Stunned") then
		return
	end

	-- Guard-broken: block is locked out during the 5s recovery. Give the player
	-- feedback (bar flashes darker) instead of silently eating the press.
	if char:GetAttribute("GuardBroken") then
		RP.remotes.GuardFlash:Fire()
		return
	end

	if os.clock() < nextBlockTime then
		return
	end

	isBlocking = true
	animationHndlr.LoadAnim(char, "Blocking", blk.blockAnim, nil, false)
	ServerRemote:FireServer({
		Type = "Combat",
		Action = "Block",
		Func = "BlockActive",
		CombatType = weapon,
	})
end

function module.Release()
	local char = plr.Character
	local weapon = getEquippedTool()
	local cfg = weapon and WeaponConfig[weapon]

	if isBlocking then
		nextBlockTime = os.clock() + BLOCK_COOLDOWN
		local anim = cfg and cfg.client.block.blockAnim
		animationHndlr.StopAnim(char, "Blocking", anim)
		ServerRemote:FireServer({
			Type = "Combat",
			Action = "Block",
			Func = "Deactivated",
			CombatType = weapon,
		})
	end
	isBlocking = false
end

-- ------------------------------------------------------------ COMPAT / FX -----
-- Server still fires GB at us on a guardbreak or block-break. Drop the block and
-- let the existing break-FX path (if any) run. Kept so old call sites don't warn.
module.GB = function(ochar, echar)
	module.Release()
end

-- Back-compat shims: if anything still calls the old names, route them sanely.
module.Block = module.Hold
module.Unblock = module.Release

return module
