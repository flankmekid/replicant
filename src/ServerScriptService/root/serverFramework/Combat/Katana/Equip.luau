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

function module.Equip(plr)
	local char = plr.Character

	if StateHandler.GetState(char, "Equip") then
		StateHandler.SetState(char, "Equip", false, 999999999)
		print("unequipped")
	else
		StateHandler.SetState(char, "Equip", true, 999999999)
		print("equipped")
	end
end

return module
