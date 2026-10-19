-- SPDX-License-Identifier: MIT
--
-- Server side of equipping and unequipping the weapon. Toggles the Equip state.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicateRemote = RP.remotes.replicate

local Helper = require(SSS.modules.helperModule)
local StateHandler = require(RP.modules.stateHandler)
local ParryService = require(SSS.modules.parryService)
local AnimationHandler = require(RP.modules.animationHandler)

-- Equip.Equip() - toggle the Equip state of a player
-- @plr: the player who equipped or unequipped the weapon
--
-- Return: nothing.
function module.Equip(plr)
	local char = plr.Character

	if StateHandler.GetState(char, "Equip") then
		StateHandler.SetState(char, "Equip", false, 999999999)
	else
		StateHandler.SetState(char, "Equip", true, 999999999)
	end
end

return module
