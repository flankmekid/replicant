-- SPDX-License-Identifier: MIT
--
-- Client side of the Shackles M2: checks the state, plays the ground or air
-- animation and the air dash at once, and plays the effects that the server
-- replicates.
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
local DashConfig = require(RP.modules.DashConfig)

local comboResetTime = 1.5
local comboMax = 5

local animID = "rbxassetid://112488887193091"
local aerialAnimID = "rbxassetid://110592013279586"

local combo = 0
local cooldown = 4
local comboResetTask = nil
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

-- M2.OnM2Activated() - use the M2
--
-- Return: nothing. Yields for the cooldown.
function module.OnM2Activated()
	local char = plr.Character or plr.CharacterAdded:Wait()

	if getEquippedTool() ~= script.Parent.Name then
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
	CooldownTracker.Register("Shackles_M2", "Critical", 4)

	animationHndlr.StopAnim(char, "ALL")

	if char.Humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		animationHndlr.LoadAnim(char, "M2", aerialAnimID, nil, false)

		local airSpeed, airLife = DashConfig.Get("ShacklesM2Air")
		if airSpeed then
			local BV = Instance.new("BodyVelocity", plr.Character.HumanoidRootPart)
			BV.MaxForce = Vector3.new(25000, 9999, 25000)
			BV.Velocity = plr.Character.HumanoidRootPart.CFrame.lookVector * airSpeed
			game.Debris:AddItem(BV, airLife)
		end

		task.delay(0.2, function()
			dashEff()
		end)
	else
		animationHndlr.LoadAnim(char, "M2", animID, nil, false)
	end

	ServerRemote:FireServer({
		Type = "Combat",
		Action = "M2",
		Func = "ServerCheck",
		CombatType = getEquippedTool(),
	})

	task.wait(cooldown)

	canAttack = true
end

-- M2.ServerResponse() - handle the server's reply to an attack request
-- @plr: the local player
-- @response: "Declined" when the server rejected the attack
--
-- Return: nothing.
function module.ServerResponse(plr, response)
	if not plr then
		return
	end
	local char = plr.Character or plr.CharacterAdded:Wait()

	if response == "Declined" then
		animationHndlr.StopAnim(char, "M2", animID)
	end
end

-- M2.PunchSound() - play the punch sound
-- @ochar: the attacking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.PunchSound = function(ochar)
	local s = Sounds.PunchSound:Clone()
	s.Parent = ochar.Torso
	s:Play()
end

-- M2.Hit() - play the hit sound and FX
-- @ochar: the attacking character
-- @echar: the character that was hit
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Hit = function(ochar, echar)
	local s = Sounds.PunchHit:Clone()
	s.Parent = echar.Torso
	s:Play()
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
	local s = Sounds.PunchHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

plr.CharacterAdded:Connect(function()
	canAttack = true
end)

return module
