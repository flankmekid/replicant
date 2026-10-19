-- SPDX-License-Identifier: MIT
--
-- Client side of equipping the weapon. Tells the server so it can toggle the Equip
-- state.
local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TS = game:GetService("TweenService")
local ServerRemote = RP.remotes.server
local Sounds = RP.assets.sounds

local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()

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

-- Equip.Equip() - report an equip or unequip to the server
--
-- Return: nothing.
function module.Equip()
	ServerRemote:FireServer({
		Type = "Combat",
		Action = "Equip",
		Func = "Equip",
		CombatType = getEquippedTool(),
	})
end

return module
