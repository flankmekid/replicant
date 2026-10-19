-- SPDX-License-Identifier: MIT
--
-- Client side of parry and block for every weapon. Parry (RMB tap) and block (hold F)
-- are separate inputs. This module plays the animations and sends the intent. The
-- server Block module owns the Parrying and Blocking states, and ParryService owns the
-- parry cooldown.

local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local ParryCooldownClient = require(RP.modules.ParryCooldownClient)
local WeaponConfig = require(RP.modules.WeaponConfig)

-- The delay before the next block, in seconds, so block is not spammable.
local BLOCK_COOLDOWN = 0.35

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

-- The shared gate for parry and block presses.
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

-- Block.Parry() - parry (RMB tap)
--
-- A pure 0.2-second parry that never becomes a block. A stunned player may parry,
-- because it is the only escape from an M1 combo.
--
-- Return: nothing.
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

	-- The cooldown starts on the press, per weapon.
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

-- Block.Hold() - start blocking (hold F)
--
-- A pure block with no parry window. Not allowed while stunned, because a stunned
-- player gets only the parry. The block cooldown applies.
--
-- Return: nothing.
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

	-- Guard-broken: block is locked out for the 5-second recovery. Flash the bar instead of
	-- ignoring the press.
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

-- Block.Release() - stop blocking (release F)
--
-- Return: nothing.
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

-- Block.GB() - drop the block after a guard break
-- @ochar: the attacking character
-- @echar: the guard-broken character
--
-- The server fires this on a guard break or a block break.
--
-- Return: nothing.
module.GB = function(ochar, echar)
	module.Release()
end

-- The old names, kept for callers that may still use them.
module.Block = module.Hold
module.Unblock = module.Release

return module
