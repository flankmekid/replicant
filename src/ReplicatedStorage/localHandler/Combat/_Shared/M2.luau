-- SPDX-License-Identifier: MIT
--
-- Client side of the standard M2, driven by WeaponConfig: plays the animation, sends
-- the request, and waits the cooldown. The server runs the M2 itself.

local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TS = game:GetService("TweenService")
local ServerRemote = RP.remotes.server
local Sounds = RP.assets.sounds

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local CooldownTracker = require(RP.modules.CooldownTracker)
local WeaponConfig = require(RP.modules.WeaponConfig)
local InputGate = require(script.Parent:WaitForChild("InputGate"))

local canAttack = true

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

local function resolveSound(path)
	if not path then
		return nil
	end
	local node = Sounds
	for part in path:gmatch("[^.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
local function weaponOf(char)
	local tool = char and char:FindFirstChildOfClass("Tool")
	return tool and tool.Name
end
local function soundsFor(char)
	local w = weaponOf(char)
	local c = w and WeaponConfig[w]
	return c and c.client.sounds
end

-- M2.ResetStats() - release the M2 lock
--
-- The blade throw E calls this after a throw resolves.
--
-- Return: nothing.
function module.ResetStats()
	if canAttack == false then
		canAttack = true
	end
end

-- M2.OnM2Activated() - use the M2
--
-- Return: nothing. Yields until the cooldown ends.
function module.OnM2Activated()
	local char = plr.Character or plr.CharacterAdded:Wait()

	local weapon = getEquippedTool()
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	local m2 = cfg.client.m2

	if InputGate.IsLocked() then
		return
	end
	if not canAttack then
		return
	end
	if char:GetAttribute("CantAnything") then
		return
	end
	if char:GetAttribute("Stunned") then
		return
	end
	if char:GetAttribute("Sliding") then
		return
	end
	if char:GetAttribute("Blocking") then
		return
	end
	if char:GetAttribute("Parrying") then
		return
	end
	if char:GetAttribute("Dodging") then
		return
	end
	if char:GetAttribute("M1") then
		return
	end
	if char:GetAttribute("M2") then
		return
	end
	if char:GetAttribute("Carried") then
		return
	end
	if char:GetAttribute("Downed") then
		return
	end
	canAttack = false
	InputGate.Lock(cfg.server.m2.windup + 0.2)
	CooldownTracker.Register(m2.cdKey, m2.cdTag, m2.cdTime)

	animationHndlr.StopAnim(char, "ALL")
	animationHndlr.LoadAnim(char, "M2", m2.animID, nil, false)

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "M2",
		Func = "ServerCheck",
		CombatType = weapon,
	})

	task.wait(m2.cooldown)

	canAttack = true
end

-- M2.ServerResponse() - handle the server's reply to an attack request
-- @plr2: the local player
-- @response: "Declined" when the server rejected the attack
--
-- Return: nothing.
function module.ServerResponse(plr2, response)
	if not plr2 then
		return
	end
	local char = plr2.Character or plr2.CharacterAdded:Wait()
	if response == "Declined" then
		InputGate.Unlock()
		local weapon = getEquippedTool()
		local cfg = weapon and WeaponConfig[weapon]
		local anim = cfg and cfg.client.m2.animID
		animationHndlr.StopAnim(char, "M2", anim)
		-- The server rejected the swing: remove any movement that already started.
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, v in ipairs(hrp:GetChildren()) do
				if v:IsA("BodyVelocity") or v:IsA("BodyMover") or v:IsA("LinearVelocity") then
					v:Destroy()
				end
			end
		end
	end
end

-- M2.Hitstop() - freeze the animations of both fighters on impact
-- @ochar: the attacking character
-- @echar: the character that was hit
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Hitstop = function(ochar, echar)
	if ochar then
		animationHndlr.Hitstop(ochar, 0.12)
	end
	if echar then
		animationHndlr.Hitstop(echar, 0.12)
	end
end

-- M2.Swing() - play the swing sound
-- @ochar: the attacking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Swing = function(ochar)
	local sc = soundsFor(ochar)
	local snd = sc and resolveSound(sc.m2Swing)
	if snd then
		local s = snd:Clone()
		s.Parent = ochar.Torso
		s:Play()
		game.Debris:AddItem(s, 2)
	end
end

-- M2.Hit() - play the hit sound and FX
-- @ochar: the attacking character
-- @echar: the character that was hit
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Hit = function(ochar, echar)
	local sc = soundsFor(ochar)
	local snd = sc and resolveSound(sc.hit)
	if snd then
		local s = snd:Clone()
		s.Parent = echar.Torso
		s:Play()
	end
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

-- M2.Blocked() - play the block sound and FX
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

-- M2.Parry() - play the parry sound and FX
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

-- M2.GB() - play the guard-break sound and FX
-- @ochar: the attacking character
-- @echar: the guard-broken character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.GB = function(ochar, echar)
	local sc = soundsFor(ochar)
	local snd = sc and resolveSound(sc.gb)
	if snd then
		local s = snd:Clone()
		s.Parent = echar.Torso
		s:Play()
	end
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

plr.CharacterAdded:Connect(function()
	canAttack = true
end)

return module
