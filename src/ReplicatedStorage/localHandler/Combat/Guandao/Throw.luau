-- SPDX-License-Identifier: MIT
--
-- Client side of the weapon throw: sends the request, plays the grab animation at once,
-- and plays the hit or whiff effects that the server replicates.

local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)

-- TODO: Replace the placeholder grab and whiff animations.
local ANIM = "rbxassetid://117582907989700"
local ANIM_WHIFF = "rbxassetid://96311777205911"

-- A client-side debounce, for responsiveness. The server has its own cooldown.
local THROW_COOLDOWN = 5
local isThrowing = false

local function getEquippedToolName()
	local char = plr.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool and tool.Name
end

-- Throw.OnThrowActivated() - try a throw
--
-- Return: nothing.
function module.OnThrowActivated()
	local char = plr.Character
	if not char then
		return
	end

	if isThrowing then
		return
	end

	-- Predict the server's state checks, so a throw it would reject does not play.
	if
		char:GetAttribute("CantAnything")
		or char:GetAttribute("Stunned")
		or char:GetAttribute("Dodging")
		or char:GetAttribute("Sliding")
		or char:GetAttribute("M1")
		or char:GetAttribute("M2")
	then
		return
	end

	isThrowing = true

	local toolName = getEquippedToolName()
	if not toolName then
		isThrowing = false
		return
	end

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "Throw",
		Func = "ServerCheck",
		CombatType = toolName,
	})

	-- Play the grab animation now, for responsiveness. The server's hit or whiff
	-- effect replaces it.
	animationHndlr.LoadAnim(char, "ThrowStart", ANIM, nil, false)

	task.delay(THROW_COOLDOWN, function()
		isThrowing = false
	end)
end

-- Throw.ExecuteEffect() - play the hit or whiff effect of a throw
-- @char: the throwing character
-- @effectType: "Hit" or "Whiff"
--
-- The server replicates this to every client.
--
-- Return: nothing.
function module.ExecuteEffect(char, effectType)
	if effectType == "Whiff" then
		local s = RP.assets.sounds.PunchSound:Clone()
		s.Parent = char.Torso
		s:Play()
		game.Debris:AddItem(s, 2)

		animationHndlr.StopAnim(char, "ThrowStart", ANIM)
		animationHndlr.LoadAnim(char, "Whiff", ANIM_WHIFF, nil, false)
	elseif effectType == "Hit" then
		local s = RP.assets.sounds.PunchHit:Clone()
		s.Parent = char.Torso
		s:Play()
		game.Debris:AddItem(s, 2)
		-- TODO: Add an impact particle.
	end
end

return module
