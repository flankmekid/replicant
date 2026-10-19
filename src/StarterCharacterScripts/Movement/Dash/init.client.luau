--// Services
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

--// Modules & Remotes
local modules = ReplicatedStorage:WaitForChild("modules")
local stateHandler = require(modules:WaitForChild("stateHandler"))
local CooldownTracker = require(modules:WaitForChild("CooldownTracker"))
local StatScaling = require(modules:WaitForChild("StatScaling"))
local remotes = ReplicatedStorage:WaitForChild("remotes")
local stateRemote = remotes:WaitForChild("stateRepl")

--// Player Variables
local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local HumRP = Char:WaitForChild("HumanoidRootPart")
local Hum = Char:WaitForChild("Humanoid")

--// Assets & UI
local assets = ReplicatedStorage:WaitForChild("assets")
local dashEff = assets:WaitForChild("Dash"):WaitForChild("Attachment")
local dashEffect2 = assets:WaitForChild("dashEff2")
local Remote = script:WaitForChild("Remote")
Remote:FireServer()

--// Animations Loading Helper
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
	Cancel = loadAnim("CancelAnim")
}

--// Configuration (Tweak your dash settings here!)
local DASH_CONFIG = {
	Cooldown = 2.5,          -- per-charge cooldown for a SINGLE-charge build
	MultiCooldown = 3.5,     -- per-charge cooldown when the player has 2 charges
	                         -- (slightly longer: the "bit higher total cooldown" tradeoff)
	Duration = 0.3,          -- How long the dash lasts in seconds
	BaseSpeed = 60,          -- Standardized speed for all directions
	HealthThreshold = 0.3,   -- Kicks in at 30% HP
	HealthMultiplier = 0.65, -- Speed drops to 75%
}

local isDashing = false

-- [[ DASH CHARGE SYSTEM (Stamina stat) ]]
-- Charges are modeled as fixed SLOTS (1..maxCharges). Each slot recovers on its own
-- timer. maxCharges is read live from the Stamina stat so respec/level-up takes effect
-- immediately.
--
-- Cooldown UI rule: there is NO persistent bar. When the player consumes a slot, that
-- exact slot gets its own cooldown entry ("Dash 1", "Dash 2", ...) which the GUI counts
-- down and auto-prunes when it expires. No slots on cooldown = no bars = you can dash.
-- Slots are consumed lowest-ready-first so the labels stay stable.

-- slots[i] = false when ready, or an os.clock() "returnAt" timestamp while on cooldown.
local slots = nil             -- lazy-init to a table of `maxCharges` ready slots
local lastDashDir = nil       -- direction (Enum.NormalId) of the previous dash while chaining;
                              -- a consecutive dash may NOT reuse it. Cleared when ALL slots are ready.

local function getMaxCharges()
	local stam = 0
	local stats = Player:FindFirstChild("PlayerStats")
	if stats then
		local sf = stats:FindFirstChild("Stats")
		if sf and sf:FindFirstChild("Stamina") then stam = sf.Stamina.Value end
	end
	return StatScaling.HasSecondDash(stam) and 2 or 1
end

local function perChargeCooldown()
	return (getMaxCharges() >= 2) and DASH_CONFIG.MultiCooldown or DASH_CONFIG.Cooldown
end

-- Build the slot table on first use, sized to the current max.
local function ensureSlots()
	if slots == nil then
		slots = {}
		for i = 1, getMaxCharges() do
			slots[i] = false -- ready
		end
	end
	return slots
end

-- True if every slot is currently ready (used to clear the no-repeat-direction rule).
local function allSlotsReady()
	for i = 1, #slots do
		if slots[i] ~= false then return false end
	end
	return true
end

-- Lowest-numbered ready slot index, or nil if none.
local function firstReadySlot()
	ensureSlots()
	for i = 1, #slots do
		if slots[i] == false then return i end
	end
	return nil
end

-- Consume the given slot, register its cooldown UI entry, and schedule its refill.
local function consumeSlot(slotIndex)
	local cd = perChargeCooldown()
	local returnAt = os.clock() + cd
	slots[slotIndex] = returnAt

	-- With a single dash charge, show just "Dash" (no "1" suffix). The internal
	-- cooldown ID stays unique per slot so slot bookkeeping/Remove are unaffected.
	local dashLabel = (getMaxCharges() <= 1) and "Dash" or ("Dash " .. slotIndex)
	CooldownTracker.Register("Dash" .. slotIndex, dashLabel, cd)

	task.delay(cd, function()
		-- Only free the slot if this exact cooldown is still the active one (guards
		-- against a respec rebuilding the table mid-cooldown).
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

-- When Stamina changes (level-up / respec), resize the slot table to the new max.
-- Gaining the 2nd-dash threshold grants the extra slot immediately as READY. Lowering
-- max drops the highest slots; any in-flight cooldown on a removed slot is cleared from
-- the UI so no orphan bar lingers.
local function syncChargesToMax()
	ensureSlots()
	local maxC = getMaxCharges()
	local cur = #slots

	if maxC > cur then
		for i = cur + 1, maxC do
			slots[i] = false -- newly unlocked slot is ready right away
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
	-- The Stats folder may not exist yet at script start; retry until it does.
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

-- Calculates which animation and particle direction to use based on where the player is moving relative to their camera
local function GetDashData(moveDir)
	local relativeDir = HumRP.CFrame:VectorToObjectSpace(moveDir)
	local absX = math.abs(relativeDir.X)
	local absZ = math.abs(relativeDir.Z)

	-- Check if the player is moving more horizontally (X) or vertically (Z) relative to their character
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
		local targetParticle = effect:IsA("Attachment") and effect:FindFirstChildWhichIsA("ParticleEmitter") or effect

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
	if left:FindFirstChild("Trail") then left.Trail.Attachment1 = left.Parent:FindFirstChild("LeftGripAttachment") end

	local right = dashEff:Clone()
	right.Parent = Char:FindFirstChild("Right Arm")
	right.Position = Vector3.new(0.5, -1, 0)
	if right:FindFirstChild("Trail") then right.Trail.Attachment1 = right.Parent:FindFirstChild("RightGripAttachment") end

	task.delay(0.5, function()
		if left then left:Destroy() end
		if right then right:Destroy() end
	end)
end

-- [[ INPUT BUFFER ]]
-- A Q press that fails the state check (CantAnything, Stunned, M1/M2, no ready slot,
-- etc.) is stashed with a timestamp instead of being dropped. A Heartbeat loop retries
-- the real action every frame while the press is still fresh; the first frame the gates
-- clear, the dash fires and the buffer is consumed. Validation is NOT forked -- the
-- retry runs the exact same tryDash() as the live press, so you can never buffer your
-- way out of a ragdoll or skip the no-repeat-direction rule.
local BUFFER_WINDOW = 0.2
local bufferedAt = nil

-- Runs the full dash validate-and-execute. Returns true if a dash actually fired,
-- false if any gate rejected it. Has no knowledge of buffering -- it just answers
-- "can I dash right this instant, and if so, do it."
local function tryDash()
	if not canDashNow() or isDashing then return false end

	-- 1. Validate State
	if HumRP.Anchored or Hum.Health <= 0 or Hum.MoveDirection.Magnitude <= 0 then return false end
	if Char:GetAttribute("CantAnything") and not Char:GetAttribute("Carrying") then return false end
	if Char:FindFirstChild("Disabled") then return false end

	-- "DashLocked" is a short-lived server-set flag with two writers:
	--   1. stateHandler.SetStun: set for a brief window AFTER a stun clears, so a
	--      frame-perfect buffered dash can't slip out in the gap before the next M1
	--      hitbox (keeps an M1 string a true combo end to end).
	--   2. the Null Gaze slow (RacialSkills): held for the slow's duration, because a
	--      dash uses a LinearVelocity that ignores WalkSpeed, so a WalkSpeed slow alone
	--      does nothing to a dash. This is what actually stops a slowed target dashing.
	local blockedStates = {"Blocking", "Stunned", "DashLocked", "Ragdolled", "M1", "M2", "Carried", "Downed", "Sliding"}
	for _, state in ipairs(blockedStates) do
		if Char:GetAttribute(state) then return false end
	end

	-- Ragdoll guard: the "Ragdolled" attribute can lag behind (it replicates
	-- server->client), but the humanoid being in the Physics state is local and
	-- immediate. Block the dash on either, which closes the replication-gap window
	-- where you could dash out of a ragdoll.
	if Hum:GetState() == Enum.HumanoidStateType.Physics then return false end

	-- Get Animation & Direction Data (computed BEFORE consuming a charge so we
	-- can reject a repeated direction without spending the dash).
	local moveDir = Hum.MoveDirection
	local anim, particleDir, soundToPlay = GetDashData(moveDir)
	local isAirborne = Hum:GetState() == Enum.HumanoidStateType.Freefall

	-- NO-REPEAT-DIRECTION RULE: a consecutive dash (while below max charges)
	-- may not reuse the previous dash's direction bucket.
	if lastDashDir ~= nil and particleDir == lastDashDir then
		return false
	end

	-- Claim the lowest ready slot. (canDashNow already confirmed one exists, but
	-- re-check to be safe against any state change between the guard and here.)
	local slotIndex = firstReadySlot()
	if not slotIndex then return false end

	-- 2. Setup Dash
	isDashing = true
	lastDashDir = particleDir -- remember this dash's direction for the next consecutive one
	consumeSlot(slotIndex) -- consumes the slot, schedules its refill, and drives that slot's cooldown UI
	stateRemote:FireServer("Dodge")

	-- Health Penalty Logic
	local hpPercentage = Hum.Health / Hum.MaxHealth
	local speedMultiplier = (hpPercentage <= DASH_CONFIG.HealthThreshold) and DASH_CONFIG.HealthMultiplier or 1

	-- 3. Execute Visuals & Audio
	anim:Play()
	soundToPlay:Play()

	if isAirborne then
		SpawnAirEffects(particleDir)
	else
		script.Effect:FireServer()
	end

	-- 4. Execute Movement (Modern Physics)
	local attachment = Instance.new("Attachment", HumRP)

	local linearVelocity = Instance.new("LinearVelocity", HumRP)
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = 100000 -- High force to override gravity and friction instantly
	linearVelocity.VectorVelocity = moveDir * (DASH_CONFIG.BaseSpeed * speedMultiplier)

	-- [[ THE FIX: Prevent stumbling by locking orientation ]] --
	local alignOrientation = Instance.new("AlignOrientation", HumRP)
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	-- Lock the orientation to exactly how they are facing when the dash starts
	alignOrientation.CFrame = HumRP.CFrame 
	alignOrientation.RigidityEnabled = true
	-- ======================================================== --

	-- 5. Cleanup & Reset
	task.delay(DASH_CONFIG.Duration, function()
		linearVelocity:Destroy()
		alignOrientation:Destroy() -- Clean up the orientation lock!
		attachment:Destroy()
		isDashing = false
		stateHandler.SetState(Char, "Dodging", false)
	end)

	return true
end

--// Main Input Handling
UserInputService.InputBegan:Connect(function(Input, IsTyping)
	if IsTyping then return end
	if Input.KeyCode ~= Enum.KeyCode.Q then return end

	-- Fire immediately if possible; otherwise open a buffer window so the press
	-- isn't wasted if the gates clear in the next half second.
	if not tryDash() then
		bufferedAt = os.clock()
	end
end)

-- Buffer retry: while a press is still within its window, keep attempting the dash.
-- Consume the buffer the instant one succeeds, or drop it when the window expires.
RunService.Heartbeat:Connect(function()
	if not bufferedAt then return end
	if os.clock() - bufferedAt > BUFFER_WINDOW then
		bufferedAt = nil
		return
	end
	if tryDash() then
		bufferedAt = nil
	end
end)
