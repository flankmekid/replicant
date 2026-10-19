-- SPDX-License-Identifier: MIT
--
-- The dash (Q): picks the direction from the movement, spends a dash charge, and moves
-- the character with a LinearVelocity. Stamina can give a second charge. The charge,
-- direction, and buffer rules are in docs/combat-design.md.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local modules = ReplicatedStorage:WaitForChild("modules")
local stateHandler = require(modules:WaitForChild("stateHandler"))
local CooldownTracker = require(modules:WaitForChild("CooldownTracker"))
local StatScaling = require(modules:WaitForChild("StatScaling"))
local remotes = ReplicatedStorage:WaitForChild("remotes")
local stateRemote = remotes:WaitForChild("stateRepl")

local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local HumRP = Char:WaitForChild("HumanoidRootPart")
local Hum = Char:WaitForChild("Humanoid")

local assets = ReplicatedStorage:WaitForChild("assets")
local dashEff = assets:WaitForChild("Dash"):WaitForChild("Attachment")
local dashEffect2 = assets:WaitForChild("dashEff2")
local Remote = script:WaitForChild("Remote")
Remote:FireServer()

local function loadAnim(name)
	local anim = Hum:LoadAnimation(script:WaitForChild(name))
	anim.Priority = Enum.AnimationPriority.Action2
	return anim
end

local Anims = {
	ForwardGround = loadAnim("RollFrontGround"),
	ForwardAir = loadAnim("RollFrontAir"),
	Backward = loadAnim("BackRoll"),
	Right = loadAnim("LeftRoll"),
	Left = loadAnim("RightRoll"),
	Cancel = loadAnim("CancelAnim"),
}

local DASH_CONFIG = {
	Cooldown = 2.5, -- Seconds per charge with one charge.
	MultiCooldown = 3.5, -- Seconds per charge with two charges, a bit longer.
	Duration = 0.3, -- Seconds.
	BaseSpeed = 60,
	HealthThreshold = 0.3, -- Below 30% HP the dash slows down.
	HealthMultiplier = 0.65,
}

local isDashing = false

-- Each charge is a slot with its own cooldown, and the number of slots follows the
-- Stamina stat live. A used slot shows its own HUD entry until it is ready again.

-- Each slot is false when ready, or the os.clock() time when it is ready again.
local slots = nil
-- The direction of the previous dash in a chain. The next dash may not repeat it.
local lastDashDir = nil

local function getMaxCharges()
	local stam = 0
	local stats = Player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then
			stam = sf.Stamina.Value
		end
	end
	return StatScaling.HasSecondDash(stam) and 2 or 1
end

local function perChargeCooldown()
	return (getMaxCharges() >= 2) and DASH_CONFIG.MultiCooldown or DASH_CONFIG.Cooldown
end

-- Builds the slot table on first use, sized to the current maximum.
local function ensureSlots()
	if slots == nil then
		slots = {}
		for i = 1, getMaxCharges() do
			slots[i] = false
		end
	end
	return slots
end

-- Returns true if every slot is ready.
local function allSlotsReady()
	for i = 1, #slots do
		if slots[i] ~= false then
			return false
		end
	end
	return true
end

-- Returns the lowest ready slot, or nil. Using the lowest keeps the HUD labels stable.
local function firstReadySlot()
	ensureSlots()
	for i = 1, #slots do
		if slots[i] == false then
			return i
		end
	end
	return nil
end

-- Uses a slot, shows its cooldown on the HUD, and schedules its refill.
local function consumeSlot(slotIndex)
	local cd = perChargeCooldown()
	local returnAt = os.clock() + cd
	slots[slotIndex] = returnAt

	-- With one charge the HUD shows "Dash", not "Dash 1". The cooldown ID stays per slot.
	local dashLabel = (getMaxCharges() <= 1) and "Dash" or ("Dash " .. slotIndex)
	CooldownTracker.Register("Dash" .. slotIndex, dashLabel, cd)

	task.delay(cd, function()
		-- Free the slot only if this cooldown is still the active one, in case a respec
		-- rebuilt the table.
		if slots[slotIndex] == returnAt then
			slots[slotIndex] = false
			if allSlotsReady() then
				lastDashDir = nil
			end
		end
	end)
end

local function canDashNow()
	return firstReadySlot() ~= nil
end

-- Resizes the slots when Stamina changes. A new slot is ready at once. A removed slot
-- also loses its HUD entry.
local function syncChargesToMax()
	ensureSlots()
	local maxC = getMaxCharges()
	local cur = #slots

	if maxC > cur then
		for i = cur + 1, maxC do
			slots[i] = false
		end
	elseif maxC < cur then
		for i = cur, maxC + 1, -1 do
			CooldownTracker.Remove("Dash" .. i)
			slots[i] = nil
		end
	end
end

do
	local function hookStamina()
		local stats = Player:FindFirstChild("PlayerStats")
		local sf = stats and stats:FindFirstChild("Stats")
		local stam = sf and sf:FindFirstChild("Stamina")
		if stam then
			stam.Changed:Connect(syncChargesToMax)
			syncChargesToMax()
		end
	end
	-- The Stats folder may not exist yet, so retry until it does.
	task.spawn(function()
		local tries = 0
		while tries < 60 do
			local stats = Player:FindFirstChild("PlayerStats")
			local sf = stats and stats:FindFirstChild("Stats")
			if sf and sf:FindFirstChild("Stamina") then
				hookStamina()
				return
			end
			tries += 1
			task.wait(0.5)
		end
	end)
end

-- Returns the animation, particle direction, and sound for a dash in moveDir, relative
-- to the character.
local function GetDashData(moveDir)
	local relativeDir = HumRP.CFrame:VectorToObjectSpace(moveDir)
	local absX = math.abs(relativeDir.X)
	local absZ = math.abs(relativeDir.Z)

	if absX > absZ then
		if relativeDir.X > 0 then
			return Anims.Right, Enum.NormalId.Right, script.dash2
		else
			return Anims.Left, Enum.NormalId.Left, script.dash2
		end
	else
		if relativeDir.Z > 0 then
			return Anims.Backward, Enum.NormalId.Front, script.dash
		else
			local isAirborne = Hum:GetState() == Enum.HumanoidStateType.Freefall
			local anim = isAirborne and Anims.ForwardAir or Anims.ForwardGround
			return anim, Enum.NormalId.Back, script.dash
		end
	end
end

local function SpawnAirEffects(emissionDir)
	local eff = dashEffect2:Clone()
	for _, effect in pairs(eff:GetChildren()) do
		local targetParticle = effect:IsA("Attachment")
				and effect:FindFirstChildWhichIsA("ParticleEmitter")
			or effect

		if targetParticle and targetParticle:IsA("ParticleEmitter") then
			effect.Parent = Char:FindFirstChild("Torso") or Char:FindFirstChild("UpperTorso")
			targetParticle.EmissionDirection = emissionDir
			targetParticle:Emit(9)
		end
	end
	Debris:AddItem(eff, 2)

	local left = dashEff:Clone()
	left.Parent = Char:FindFirstChild("Left Arm")
	left.Position = Vector3.new(-0.5, -1, 0)
	if left:FindFirstChild("Trail") then
		left.Trail.Attachment1 = left.Parent:FindFirstChild("LeftGripAttachment")
	end

	local right = dashEff:Clone()
	right.Parent = Char:FindFirstChild("Right Arm")
	right.Position = Vector3.new(0.5, -1, 0)
	if right:FindFirstChild("Trail") then
		right.Trail.Attachment1 = right.Parent:FindFirstChild("RightGripAttachment")
	end

	task.delay(0.5, function()
		if left then
			left:Destroy()
		end
		if right then
			right:Destroy()
		end
	end)
end

-- A Q press that fails a check is buffered and retried every frame for BUFFER_WINDOW
-- seconds. The retry runs the same tryDash, so a buffer can never skip a check.
local BUFFER_WINDOW = 0.2
local bufferedAt = nil

-- Checks and runs a dash. Returns true if the dash started, false otherwise.
local function tryDash()
	if not canDashNow() or isDashing then
		return false
	end

	if HumRP.Anchored or Hum.Health <= 0 or Hum.MoveDirection.Magnitude <= 0 then
		return false
	end
	if Char:GetAttribute("CantAnything") and not Char:GetAttribute("Carrying") then
		return false
	end
	if Char:FindFirstChild("Disabled") then
		return false
	end

	-- The server sets DashLocked briefly after a stun, so a buffered dash cannot slip out
	-- of a true combo, and during the Null Gaze slow, which a dash would otherwise ignore.
	local blockedStates = {
		"Blocking",
		"Stunned",
		"DashLocked",
		"Ragdolled",
		"M1",
		"M2",
		"Carried",
		"Downed",
		"Sliding",
	}
	for _, state in ipairs(blockedStates) do
		if Char:GetAttribute(state) then
			return false
		end
	end

	-- The Ragdolled attribute replicates late, but the local Physics state is immediate,
	-- so check both.
	if Hum:GetState() == Enum.HumanoidStateType.Physics then
		return false
	end

	-- Compute the direction before using a charge, so a repeated direction costs nothing.
	local moveDir = Hum.MoveDirection
	local anim, particleDir, soundToPlay = GetDashData(moveDir)
	local isAirborne = Hum:GetState() == Enum.HumanoidStateType.Freefall

	-- A chained dash may not repeat the previous direction.
	if lastDashDir ~= nil and particleDir == lastDashDir then
		return false
	end

	-- Check the slot again, in case the state changed since canDashNow.
	local slotIndex = firstReadySlot()
	if not slotIndex then
		return false
	end

	isDashing = true
	lastDashDir = particleDir
	consumeSlot(slotIndex)
	stateRemote:FireServer("Dodge")

	local hpPercentage = Hum.Health / Hum.MaxHealth
	local speedMultiplier = (hpPercentage <= DASH_CONFIG.HealthThreshold)
			and DASH_CONFIG.HealthMultiplier
		or 1

	anim:Play()
	soundToPlay:Play()

	if isAirborne then
		SpawnAirEffects(particleDir)
	else
		script.Effect:FireServer()
	end

	local attachment = Instance.new("Attachment", HumRP)

	local linearVelocity = Instance.new("LinearVelocity", HumRP)
	linearVelocity.Attachment0 = attachment
	-- A high force overrides gravity and friction at once.
	linearVelocity.MaxForce = 100000
	linearVelocity.VectorVelocity = moveDir * (DASH_CONFIG.BaseSpeed * speedMultiplier)

	-- Lock the orientation to the facing at the start, so the character does not stumble.
	local alignOrientation = Instance.new("AlignOrientation", HumRP)
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.CFrame = HumRP.CFrame
	alignOrientation.RigidityEnabled = true

	task.delay(DASH_CONFIG.Duration, function()
		linearVelocity:Destroy()
		alignOrientation:Destroy()
		attachment:Destroy()
		isDashing = false
		stateHandler.SetState(Char, "Dodging", false)
	end)

	return true
end

UserInputService.InputBegan:Connect(function(Input, IsTyping)
	if IsTyping then
		return
	end
	if Input.KeyCode ~= Enum.KeyCode.Q then
		return
	end

	-- Dash now if possible, otherwise buffer the press.
	if not tryDash() then
		bufferedAt = os.clock()
	end
end)

-- Retry a buffered press until it succeeds or the window ends.
RunService.Heartbeat:Connect(function()
	if not bufferedAt then
		return
	end
	if os.clock() - bufferedAt > BUFFER_WINDOW then
		bufferedAt = nil
		return
	end
	if tryDash() then
		bufferedAt = nil
	end
end)
