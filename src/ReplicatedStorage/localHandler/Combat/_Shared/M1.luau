-- SPDX-License-Identifier: MIT
--
-- Client side of the M1 for every weapon, driven by WeaponConfig: the combo, the
-- running lunge, the air attack, and the uppercut. The server owns the combo counter
-- through the Combo attribute.

local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TS = game:GetService("TweenService")
local ServerRemote = RP.remotes.server
local Sounds = RP.assets.sounds

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local WeaponConfig = require(RP.modules.WeaponConfig)
local InputGate = require(script.Parent:WaitForChild("InputGate"))
local DashConfig = require(RP.modules.DashConfig)

-- The same for every weapon.
local comboResetTime = 5
local uppercutVelocity = 15

-- Raises the HRP to targetPos and holds it for window seconds, then lets it fall.
-- AlignPosition works through physics, so it does not fight the character's own
-- simulation the way a CFrame tween would.
local function juggleFloat(hrp, targetPos, window, responsiveness)
	if not hrp then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "UppercutApex"
	att.Parent = hrp
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = targetPos
	ap.MaxForce = math.huge
	ap.Responsiveness = responsiveness
	ap.RigidityEnabled = false
	ap.ApplyAtCenterOfMass = true
	ap.Parent = hrp
	Debris:AddItem(ap, window)
	Debris:AddItem(att, window)
end

-- Attack state is shared, because only one weapon is equipped at a time.
local combo = 0
local comboResetTask = nil
local canAttack = true
local lungeDB = false
local airDB = false
local uppercutDB = false

local function resetCombo()
	combo = 0
	canAttack = true
	comboResetTask = nil
end

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

-- Resolves a dotted path under assets.sounds, such as "katana.katanaSwing".
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

-- Returns the weapon of any character. The replicated FX handlers also run for other
-- players, not only the local player.
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

-- M1.OnM1Activated() - use the M1
--
-- Picks the uppercut, the running lunge, the air attack, or the next combo hit from the
-- movement state.
--
-- Return: nothing. Yields until the attack can repeat.
function module.OnM1Activated()
	local char = plr.Character or plr.CharacterAdded:Wait()

	local weapon = getEquippedTool()
	if not weapon then
		return
	end
	local cfg = WeaponConfig[weapon]
	if not cfg then
		return
	end
	local m1 = cfg.client.m1
	local comboMax = cfg.server.m1.maxCombo
	local cooldown = m1.cooldown
	local spd = m1.animSpeed

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
	InputGate.Lock(cfg.server.m1.windup + 0.2)

	-- During the uppercut hang (Launched) the character is in Freefall, but the M1 must be
	-- the ground combo, not the air attack. The server applies the same rule.
	local launched = char:GetAttribute("Launched")

	-- SubType tells the server the movement state, because Running and Sliding are
	-- client-set attributes that do not replicate.

	-- Uppercut: slide + M1, or Ctrl + M1 on the ground. The Ctrl path needs the ground, so
	-- it cannot take over the air attack. UserInputService is fetched here, because
	-- GetService("UserInputService") throws if the server loads this module.
	local UIS = game:GetService("UserInputService")
	local ctrlHeld = UIS:IsKeyDown(Enum.KeyCode.LeftControl)
		or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local grounded = char.Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	local wantsUppercut = char:GetAttribute("Sliding") or (ctrlHeld and grounded)

	if (not launched) and wantsUppercut and uppercutDB == false then
		uppercutDB = true
		canAttack = false

		-- End the slide first, so its velocity does not fight the launch.
		local usEv = RP:FindFirstChild("UppercutStopSlide")
		if usEv then
			usEv:Fire()
		end

		animationHndlr.StopAnim(char, "Sliding", "rbxassetid://136848049831912")
		char.Humanoid.HipHeight = 0

		local animID = m1.uppercutAnim
		if animID then
			animationHndlr.StopAnim(char, "ALL")
			animationHndlr.LoadAnim(char, "M1", animID, nil, false, spd)
		end

		-- The attacker rises only when the server confirms the hit (UppercutRise), so
		-- attacker and victim leave the ground together.
		ServerRemote:FireServer({
			Type = "Combat",
			Action = "M1",
			Func = "ServerCheck",
			CombatType = weapon,
			SubType = "Uppercut",
		})

		task.wait(m1.uppercutWait)

		dashEff()

		canAttack = true

		task.delay(3, function()
			uppercutDB = false
		end)
	elseif
		not launched
		and char:GetAttribute("Running")
		and lungeDB == false
		and (char.Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall)
	then
		lungeDB = true
		canAttack = false
		local animID = m1.lungeAnim
		if animID then
			animationHndlr.StopAnim(char, "ALL")
			animationHndlr.LoadAnim(char, "M1", animID, nil, false, spd)
		end

		-- LungeService makes the lunge on the server, and a client mover here would fight
		-- it. Send the request first, so the server starts the lunge at the top of the
		-- attack.
		ServerRemote:FireServer({
			Type = "Combat",
			Action = "M1",
			Func = "ServerCheck",
			CombatType = weapon,
			SubType = "Lunge",
		})

		task.wait(m1.lungeWait)

		dashEff()

		canAttack = true

		task.delay(3, function()
			lungeDB = false
		end)
	elseif
		not launched
		and (char.Humanoid:GetState() == Enum.HumanoidStateType.Freefall)
		and airDB == false
	then
		airDB = true
		canAttack = false
		local animID = m1.airAnim
		if animID then
			animationHndlr.StopAnim(char, "ALL")
			animationHndlr.LoadAnim(char, "M1", animID, nil, false, spd)
		end

		-- MaxForce.Y holds the vertical velocity at 0, which hangs the character in the air
		-- during an air M1.
		local airSpeed, airLife = DashConfig.Get("M1Air", weapon)
		if airSpeed then
			local BV = Instance.new("BodyVelocity", plr.Character.HumanoidRootPart)
			BV.MaxForce = Vector3.new(25000, 9999, 25000)
			BV.Velocity = plr.Character.HumanoidRootPart.CFrame.lookVector * airSpeed
			game.Debris:AddItem(BV, airLife)
		end

		ServerRemote:FireServer({
			Type = "Combat",
			Action = "M1",
			Func = "ServerCheck",
			CombatType = weapon,
			SubType = "AirLunge",
		})

		task.wait(m1.airWait)
		dashEff()

		canAttack = true

		task.delay(3, function()
			airDB = false
		end)
	else
		if char:GetAttribute("Combo") then
			combo = (char:GetAttribute("Combo") % comboMax) + 1
		else
			combo = (combo % comboMax) + 1
		end
		local animID = m1.comboAnims[combo]
		if animID then
			animationHndlr.StopAnim(char, "ALL")
			animationHndlr.LoadAnim(char, "M1", animID, nil, false, spd)
		end

		if comboResetTask then
			task.cancel(comboResetTask)
			comboResetTask = nil
		end
		comboResetTask = task.delay(comboResetTime, resetCombo)
		ServerRemote:FireServer({
			Type = "Combat",
			Action = "M1",
			Func = "ServerCheck",
			CombatType = weapon,
		})

		if combo == comboMax then
			task.delay(0.25, function()
				-- The finisher always gets the dash effect. DashConfig decides if it moves.
				dashEff()
				local finSpeed, finLife = DashConfig.Get("M1Finisher", weapon)
				if finSpeed then
					local BV = Instance.new("BodyVelocity", plr.Character.HumanoidRootPart)
					BV.MaxForce = Vector3.new(25000, 9999, 25000)
					BV.Velocity = plr.Character.HumanoidRootPart.CFrame.lookVector * finSpeed
					game.Debris:AddItem(BV, finLife)
				end
			end)
			task.wait(cooldown + m1.finisherExtraWait)
		else
			task.wait(cooldown)
		end
		canAttack = true
	end
end

-- M1.ServerResponse() - handle the server's reply to an attack request
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
		local anim = cfg and cfg.client.m1.comboAnims[combo]
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

-- M1.UppercutRise() - lift the attacker after a confirmed uppercut hit
--
-- CombatCore fires this only when the uppercut connects, so the attacker rises together
-- with the victim. On a whiff it never fires.
--
-- Return: nothing.
function module.UppercutRise()
	local char = plr.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local UC = WeaponConfig.Uppercut
	juggleFloat(
		hrp,
		hrp.Position + Vector3.new(0, UC.RiseHeight, 0),
		UC.HangWindow,
		UC.Responsiveness
	)
end

-- M1.Hitstop() - freeze the animations of both fighters on impact
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

-- M1.Swing() - play the swing sound
-- @ochar: the attacking character
--
-- The server replicates this to every client.
--
-- Return: nothing.
module.Swing = function(ochar)
	local sc = soundsFor(ochar)
	local snd = sc and resolveSound(sc.m1Swing)
	if snd then
		local s = snd:Clone()
		s.Parent = ochar.Torso
		s:Play()
		game.Debris:AddItem(s, 5)
	end
end

-- M1.Hit() - play the hit sound and FX
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

-- M1.Blocked() - play the block sound and FX
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

-- M1.Parry() - play the parry sound and FX
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

-- M1.GB() - play the guard-break sound and FX
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

return module
