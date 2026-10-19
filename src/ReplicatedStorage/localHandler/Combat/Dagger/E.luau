-- SPDX-License-Identifier: MIT
--
-- Client side of the E for the dagger family (Dagger, Tanto): sends the request, plays
-- the animation and sound at once, and plays the effects that the server replicates.
local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ServerRemote = RP.remotes.server
local Sounds = RP.assets.sounds

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local CooldownTracker = require(RP.modules.CooldownTracker)
local ParryCooldownClient = require(RP.modules.ParryCooldownClient)

local ANIM_THROW = "rbxassetid://72037949342562"

-- A client-side debounce. The server has its own checks.
local ATTACK_COOLDOWN = 3
local debounce = false

local function getEquippedToolName()
	local char = plr.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool and tool.Name
end

-- E.OnEActivated() - use the E
--
-- Return: nothing.
function module.OnEActivated()
	local char = plr.Character
	if not char then
		return
	end

	if debounce then
		return
	end

	-- Skip the request when the character cannot act.
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

	local toolName = getEquippedToolName()
	if not toolName then
		return
	end

	debounce = true

	CooldownTracker.Register("Dagger_E", "E", ATTACK_COOLDOWN)

	local s = RP.assets.sounds.dagger.daggerLunge:Clone()
	s.Parent = char.HumanoidRootPart
	s:Play()
	game:GetService("Debris"):AddItem(s, 1)

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "E",
		Func = "ServerCheck",
		CombatType = toolName,
	})

	-- Play the throw animation now, for responsiveness.
	animationHndlr.StopAnim(char, "ALL")
	animationHndlr.LoadAnim(char, "E", ANIM_THROW, nil, false)

	task.delay(ATTACK_COOLDOWN, function()
		debounce = false
	end)
end

-- E.ServerResponse() - handle the server's reply to an attack request
-- @plr: the local player
-- @response: "Declined" when the server rejected the attack
--
-- Return: nothing.
function module.ServerResponse(plr, response)
	local char = plr.Character or plr.CharacterAdded:Wait()

	if response == "Declined" then
		animationHndlr.StopAnim(char, "E", ANIM_THROW)
	end
end

-- E.Swing() - play the swing sound
-- @ochar: the attacking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Swing = function(ochar)
	local s = Sounds.dagger.daggerSwing:Clone()
	s.Parent = ochar.Torso
	s:Play()
end

-- E.Hit() - play the hit sound and FX
-- @ochar: the attacking character
-- @echar: the character that was hit
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Hit = function(ochar, echar)
	local s = Sounds.dagger.daggerHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

-- E.Blocked() - play the block sound and FX
-- @ochar: the attacking character
-- @echar: the blocking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Blocked = function(ochar, echar)
	local s = Sounds.BlockingHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.BlockFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

-- E.Parry() - play the parry sound and FX
-- @ochar: the parried attacker
-- @echar: the parrying character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Parry = function(ochar, echar)
	local s = Sounds.ParrySound:Clone()
	s.Parent = ochar.Torso
	s:Play()
	local hitFX = RP.assets.FX.ParryFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

-- E.GB() - play the guard-break sound and FX
-- @ochar: the attacking character
-- @echar: the guard-broken character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.GB = function(ochar, echar)
	local s = Sounds.dagger.daggerHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

plr.CharacterAdded:Connect(function()
	debounce = false
end)

return module
