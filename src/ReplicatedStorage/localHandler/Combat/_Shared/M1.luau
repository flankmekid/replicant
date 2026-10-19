-- Shared M1 (config-driven). Faithful port of the per-weapon M1 template.
-- Weapon-specific values come from ReplicatedStorage.modules.WeaponConfig,
-- resolved per equipped weapon. Attack state is shared (one equipped weapon
-- at a time; the server is the combo authority via the "Combo" attribute).
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

-- uniform constants (identical across every weapon in the original modules)
local comboResetTime = 5
local UPPERCUT_VELOCITY = 15

-- Eases an HRP up to `targetPos` and HOLDS it there for `window`, then releases (it falls).
-- AlignPosition drives the position via the physics engine, so it plays nice with the
-- character's own simulation instead of fighting it the way a CFrame tween would.
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

-- shared attack state
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

-- resolve a dotted path ("katana.katanaSwing" or "PunchSound") under assets.sounds
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

-- weapon identity of an arbitrary character (used by the replicated FX callbacks,
-- where the acting character may be a remote player, not the LocalPlayer)
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

	-- [[ JUGGLE GATE ]] --
	-- Launched means we are hanging in the uppercut float. We ARE technically in
	-- Freefall during it, but a juggled M1/E/M2 should read as the normal GROUND
	-- combo performed in the air, not the aerial attack. So while Launched holds we
	-- skip the movement-special branches (Sliding / Running / Freefall) and drop
	-- straight to the combo branch. Same reasoning has to hold on the server, which
	-- also gates extraAtk on Launched (see CombatCore.RunM1).
	local launched = char:GetAttribute("Launched")

	-- SubType is the ONLY honest way the server learns our movement state. Running and
	-- Sliding are custom attributes set by LocalScripts; a client SetAttribute does not
	-- replicate up to the server, so the server's GetAttribute("Running") is always nil
	-- and its running/slide branches never fired. We stamp the state into the M1 remote
	-- and the server trusts THIS instead of the phantom attribute. (Freefall it can and
	-- still does re-check itself, since Humanoid states genuinely replicate.)

	-- [[ UPPERCUT INPUT ]] --
	-- Two ways in: the original slide + M1, or Ctrl held + M1 from the ground.
	-- The Ctrl path is grounded-only. An uppercut out of freefall launches off nothing
	-- and would swallow the aerial branch below. Slide already owns Ctrl + W while
	-- running, so a slide with Ctrl still held lands on this branch either way.
	-- UserInputService is fetched here, not at module scope: this module sits in
	-- ReplicatedStorage and GetService("UserInputService") throws if the server loads it.
	local UIS = game:GetService("UserInputService")
	local ctrlHeld = UIS:IsKeyDown(Enum.KeyCode.LeftControl)
		or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local grounded = char.Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	local wantsUppercut = char:GetAttribute("Sliding") or (ctrlHeld and grounded)

	if (not launched) and wantsUppercut and uppercutDB == false then
		uppercutDB = true
		canAttack = false

		-- End the slide cleanly FIRST: fires StopSlide (kills its Heartbeat loop and
		-- SlideVelocity) so nothing fights the AlignPosition launch we author below.
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

		-- Attacker's launch is HIT-GATED now. We do NOT rise here on input. We only fire
		-- the swing; if it connects, the server tells us to rise (module.UppercutRise
		-- below authors the exact same AlignPosition lift, timed to the confirmed hit so
		-- attacker and victim leave the ground together). On a whiff, no rise ever comes.
		-- The slide is already killed above, so we are grounded and committed until then.
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

		-- The lunge BodyVelocity is created SERVER-side (LungeService, fired from
		-- CombatCore.RunM1 when extraAtk == 6). Creating one here as well would put two
		-- authors on the same HumanoidRootPart and the constraint solver would fight
		-- itself.
		--
		-- FireServer moves FIRST: the server needs to start the lunge at the top of the
		-- attack, not lungeWait seconds into it. The animation still plays here on the
		-- same schedule, so the step-in reads identically.
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

		-- MaxForce.Y = 9999 is deliberate. It pins Y velocity at zero for the life of
		-- the mover, and that is what hangs you in the air on an air M1.
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
				-- dashEff stays regardless. The finisher keeps its visual whether or not
				-- it travels. Only the movement is table-gated.
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

function module.ServerResponse(plr2, response)
	local char = plr2.Character or plr2.CharacterAdded:Wait()
	if response == "Declined" then
		InputGate.Unlock()
		local weapon = getEquippedTool()
		local cfg = weapon and WeaponConfig[weapon]
		local anim = cfg and cfg.client.m1.comboAnims[combo]
		animationHndlr.StopAnim(char, "M1", anim)
		-- server rejected the swing: kill any optimistic movement velocity we already spawned
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, v in ipairs(hrp:GetChildren()) do
				if v:IsA("BodyVelocity") or v:IsA("BodyMover") or v:IsA("LinearVelocity") then
					v:Destroy()
				end
			end
		end
		print(response)
	end
end

-- Server-driven, HIT-GATED attacker rise. CombatCore fires this at the local player
-- ONLY when their uppercut actually connected (from inside the on-hit m1Knockback
-- closure). It authors the exact AlignPosition lift the old input path used to fire
-- immediately, but now timed to the confirmed hit so the attacker rises together with
-- the server-juggled victim. On a whiff the server never fires this, so no rise.
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

module.Hitstop = function(ochar, echar)
	-- freeze both attacker and victim animations on impact (client-side feel)
	if ochar then
		animationHndlr.Hitstop(ochar, 0.12)
	end
	if echar then
		animationHndlr.Hitstop(echar, 0.12)
	end
end

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

module.Blocked = function(ochar, echar)
	local s = Sounds.BlockingHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.BlockFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

module.Parry = function(ochar, echar)
	local s = Sounds.ParrySound:Clone()
	s.Parent = ochar.Torso
	s:Play()
	local hitFX = RP.assets.FX.ParryFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, 0.5)
end

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
