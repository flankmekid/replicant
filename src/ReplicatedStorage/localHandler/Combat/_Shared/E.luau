-- SPDX-License-Identifier: MIT
--
-- Client side of the standard E (a forward dash) for every weapon, driven by
-- WeaponConfig. A weapon with a custom E (e.custom) uses its own module.

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
local DashConfig = require(RP.modules.DashConfig)

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

local function dashEff()
	for _, v in pairs(plr.Character:GetChildren()) do
		if v:IsA("BasePart") then
			if v.Transparency ~= 1 then
				local part = Instance.new("Part")
				part.Anchored = true
				part.Transparency = 0.1
				part.CanCollide = false
				part.Parent = workspace
				part.BrickColor = BrickColor.new("Really black")
				part.Material = Enum.Material.Neon
				part.Size = v.Size
				part.CFrame = v.CFrame
				if v:FindFirstChildOfClass("SpecialMesh") then
					v:FindFirstChildOfClass("SpecialMesh"):Clone().Parent = part
				end
				local tweenservice = game:GetService("TweenService")
				local goal = {}
				goal.Transparency = 1
				local tweeninfo = TweenInfo.new(0.6)
				local tween = tweenservice:Create(part, tweeninfo, goal)
				tween:Play()
				game.Debris:AddItem(part, 0.5)
			end
		end
	end
end

-- E.OnEActivated() - use the E
--
-- Return: nothing. Yields until the cooldown ends.
function module.OnEActivated()
	local char = plr.Character or plr.CharacterAdded:Wait()

	local weapon = getEquippedTool()
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	local e = cfg.client.e
	-- A weapon with a custom E runs its own module.
	if e.custom then
		return
	end

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
	InputGate.Lock(cfg.server.e.windup + 0.2)
	CooldownTracker.Register(e.cdKey, e.cdTag, e.cdTime)

	animationHndlr.StopAnim(char, "ALL")
	animationHndlr.LoadAnim(char, "M1", e.animID, nil, false, e.eAnimSpeed)

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "E",
		Func = "ServerCheck",
		CombatType = weapon,
	})

	task.wait(e.eWindupWait)

	local eSpeed, eLife = DashConfig.Get("E", weapon)
	if eSpeed then
		local BV = Instance.new("BodyVelocity", plr.Character.HumanoidRootPart)
		BV.MaxForce = Vector3.new(25000, 0, 25000)
		BV.Velocity = plr.Character.HumanoidRootPart.CFrame.lookVector * eSpeed
		game.Debris:AddItem(BV, eLife)
	end

	dashEff()

	task.wait(e.cooldown)

	canAttack = true
end

-- E.ServerResponse() - handle the server's reply to an attack request
-- @plr2: the local player
-- @response: "Declined" when the server rejected the attack
--
-- Return: nothing.
function module.ServerResponse(plr2, response)
	local char = plr2.Character or plr2.CharacterAdded:Wait()
	if response == "Declined" then
		InputGate.Unlock()
		local weapon = getEquippedTool()
		local cfg = weapon and WeaponConfig[weapon]
		local anim = cfg and cfg.client.e and cfg.client.e.animID
		animationHndlr.StopAnim(char, "M1", anim)
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

-- E.Hitstop() - freeze the animations of both fighters on impact
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

-- E.Swing() - play the swing sound
-- @ochar: the attacking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Swing = function(ochar)
	local sc = soundsFor(ochar)
	local snd = sc and resolveSound(sc.eSwing)
	if snd then
		local s = snd:Clone()
		s.Parent = ochar.Torso
		s:Play()
		game.Debris:AddItem(s, 5)
	end
end

-- E.Hit() - play the hit sound and FX
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
