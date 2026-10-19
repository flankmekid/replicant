-- LOCAL SCRIPT (inside StarterPlayerScripts)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Ensure you still have the RemoteEvent from the previous step
local toggleShiftLockEvent = ReplicatedStorage.remotes:WaitForChild("ToggleShiftLock")
local StateHandler = require(ReplicatedStorage.modules.stateHandler)

-- CONFIGURATION
local CONFIG = {
	Keybind = Enum.KeyCode.G, -- The Master Key
	MaxDistance = 100,
	TargetFolder = Workspace:WaitForChild("plrManager"):WaitForChild("alive"),

	-- Camera "Feel" Settings
	CameraSmoothness = 0.15, -- 0.05 is very slow/heavy, 0.3 is snappy
	LockOnOffset = Vector3.new(0, 1, 0), -- Aim at chest/head

	-- Over-the-Shoulder Position relative to Player
	-- X = Right, Y = Up, Z = Back
	ShoulderOffset = Vector3.new(-5, 8, 7),

	-- Input Settings
	HoldToUnlockTime = 0.35, -- How long to hold G to force unlock

	-- Below this flat XZ separation the look/offset vectors go degenerate. See
	-- the RenderStepped comment. Standing on top of the target used to produce a
	-- zero-magnitude vector, .Unit on it returns NaN, and NaN in camera.CFrame is
	-- what made the camera spin and the world vanish.
	MinFlatDistance = 2.5,
}

-- STATE VARIABLES
local isLockedOn = false
local currentTarget = nil
local keyPressTime = 0
local isHoldingKey = false

-- VISUALS
local reticleGui = Instance.new("BillboardGui")
reticleGui.Name = "LockOnReticle"
reticleGui.Size = UDim2.new(0, 40, 0, 40)
reticleGui.AlwaysOnTop = true
reticleGui.Enabled = false

local reticleImage = Instance.new("ImageLabel")
reticleImage.Parent = reticleGui
reticleImage.BackgroundTransparency = 1
reticleImage.Size = UDim2.new(1, 0, 1, 0)
reticleImage.Image = "rbxassetid://12389946814" -- Circle
reticleImage.ImageColor3 = Color3.fromRGB(255, 50, 50) -- Red

reticleGui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- STATE GATES
--------------------------------------------------------------------------------

-- IMPORTANT: read ATTRIBUTES, not StateHandler.GetState().
--
-- stateHandler keeps its state in a plain Lua table local to whichever VM
-- required the module. The server's table and this client's table are separate
-- objects. A state the server sets (Downed, Carried, BeingExecuted) never lands
-- in the client's table, so GetState() from here returns nil for every one of
-- them. The old code called GetState(enemy, "Downed") and it silently did
-- nothing, which is why you could lock onto downed players. SetAttribute DOES
-- replicate, so attributes are the only read that works across the boundary.

-- Can the local player hold a lock at all right now?
local function canSelfLock()
	local char = player.Character
	if not char then
		return false
	end

	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end

	-- A downed player locks onto nothing.
	if char:GetAttribute("Downed") then
		return false
	end

	-- Anything that means another system owns our HumanoidRootPart: the carry
	-- AlignPosition/AlignOrientation, the execution anchor, the Messatsu weld.
	-- IsRootOwned is attribute-based and also sniffs for a weld binding our root,
	-- so it catches the grab.
	--
	-- A plain knockdown ragdoll is DELIBERATELY excluded (ignoreRagdoll = true).
	-- Getting knocked down no longer drops the lock. The lock survives the flop and
	-- the RenderStepped loop below just stops writing myRoot.CFrame while Ragdolled
	-- is set, so we still never become a second author on the part. Downed, carry,
	-- execution and the grab all still kill the lock.
	if StateHandler.IsRootOwned(char, true) then
		return false
	end

	return true
end

-- Is this character a legal thing to lock ONTO?
local function isValidTarget(enemy)
	if not enemy or not enemy.Parent then
		return false
	end

	local hum = enemy:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 3 then
		return false
	end
	if not enemy:FindFirstChild("HumanoidRootPart") then
		return false
	end

	-- No locking onto someone who is down, being carried, or being executed.
	if enemy:GetAttribute("Downed") then
		return false
	end
	if enemy:GetAttribute("Carried") then
		return false
	end
	if enemy:GetAttribute("BeingExecuted") then
		return false
	end

	return true
end

local function isFiniteVector(v)
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and v.X ~= math.huge
		and v.X ~= -math.huge
		and v.Y ~= math.huge
		and v.Y ~= -math.huge
		and v.Z ~= math.huge
		and v.Z ~= -math.huge
end

--------------------------------------------------------------------------------
-- TARGETING FUNCTIONS
--------------------------------------------------------------------------------

local function getAllValidTargets()
	local targets = {}
	local character = player.Character
	if not character then
		return targets
	end
	local myRoot = character:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return targets
	end

	for _, enemy in pairs(CONFIG.TargetFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy ~= character and isValidTarget(enemy) then
			local root = enemy.HumanoidRootPart
			local dist = (myRoot.Position - root.Position).Magnitude
			if dist < CONFIG.MaxDistance then
				-- Raycast for visibility
				local origin = camera.CFrame.Position
				local dir = (root.Position - origin)
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { character, enemy, CONFIG.TargetFolder }
				params.FilterType = Enum.RaycastFilterType.Exclude

				local result = Workspace:Raycast(origin, dir, params)
				if not result or result.Instance:IsDescendantOf(enemy) or dist < 10 then
					table.insert(targets, enemy)
				end
			end
		end
	end
	return targets
end

local function getClosestTarget()
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	local targets = getAllValidTargets()
	local closest = nil
	local minDst = math.huge
	local myPos = character.HumanoidRootPart.Position

	for _, t in pairs(targets) do
		local dst = (t.HumanoidRootPart.Position - myPos).Magnitude
		if dst < minDst then
			minDst = dst
			closest = t
		end
	end
	return closest
end

-- DIRECTIONAL SWITCHING LOGIC
-- Direction: -1 for Left, 1 for Right
local function getDirectionalTarget(direction)
	if not currentTarget then
		return getClosestTarget()
	end

	local targets = getAllValidTargets()
	local bestCandidate = nil
	local bestAngle = math.huge -- We want the smallest angle difference

	local camCFrame = camera.CFrame
	local currentTargetPos = currentTarget.HumanoidRootPart.Position

	-- We want to compare other enemies relative to the CURRENT target on screen
	for _, t in pairs(targets) do
		if t ~= currentTarget then
			local tPos = t.HumanoidRootPart.Position

			local delta = tPos - currentTargetPos
			if delta.Magnitude > 0.01 then
				-- Vector from current target to candidate target
				local dirToCandidate = delta.Unit

				-- Convert this vector to Camera Space (Right/Left)
				-- Dot product with Camera's Right Vector tells us if it's right (+) or left (-)
				local rightDot = camCFrame.RightVector:Dot(dirToCandidate)

				-- Check if the candidate is on the requested side
				local isOnCorrectSide = false
				if direction > 0 and rightDot > 0 then
					isOnCorrectSide = true
				end -- Want Right, is Right
				if direction < 0 and rightDot < 0 then
					isOnCorrectSide = true
				end -- Want Left, is Left

				if isOnCorrectSide then
					-- Calculate distance between targets to prioritize closer ones in that direction
					local distBetweenTargets = delta.Magnitude

					if distBetweenTargets < bestAngle then
						bestAngle = distBetweenTargets
						bestCandidate = t
					end
				end
			end
		end
	end

	return bestCandidate
end

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------

local function lockCamera(target)
	if not target then
		return
	end
	if not canSelfLock() then
		return
	end
	if not isValidTarget(target) then
		return
	end

	isLockedOn = true
	currentTarget = target
	reticleGui.Adornee = target:FindFirstChild("HumanoidRootPart")
	reticleGui.Enabled = true
	toggleShiftLockEvent:FireServer(false)

	-- Publish the lock so the SERVER can see it. The lock used to live entirely on
	-- this client (camera math only), so server-side combat had no idea who you were
	-- aimed at. The running-attack lunge needs it.
	--
	-- This is an ObjectValue-style attribute, so it replicates. It is a HINT, not a
	-- grant: the server re-validates range and legality before it will lunge at
	-- anything, so a forged attribute buys an exploiter nothing.
	local char = player.Character
	if char then
		char:SetAttribute("LockTarget", target.Name)
	end
end

local function unlockCamera()
	if not isLockedOn then
		return
	end

	isLockedOn = false
	currentTarget = nil
	reticleGui.Adornee = nil
	reticleGui.Enabled = false
	toggleShiftLockEvent:FireServer(true)

	local myChar = player.Character
	if myChar then
		myChar:SetAttribute("LockTarget", nil)
	end

	-- Do NOT hand AutoRotate back to a character something else is driving. A
	-- downed / carried / ragdolled body wants AutoRotate false; the downed system
	-- will restore it on revive. Setting it true here would let a ragdoll spin.
	local char = player.Character
	if char and char:FindFirstChild("Humanoid") and not StateHandler.IsRootOwned(char) then
		char.Humanoid.AutoRotate = true
	end
end

--------------------------------------------------------------------------------
-- UPDATE LOOP (CAMERA MATH)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not isLockedOn or not currentTarget then
		return
	end

	-- 0. Are WE still allowed to be locked on?
	-- This gate is the whole fix for the downed / carried / grabbed spinning. The
	-- loop below writes myRoot.CFrame every single frame. While we are ragdolled,
	-- carried (AlignPosition + AlignOrientation own the root), being executed
	-- (anchored), or welded to someone by Messatsu, that write fights whatever
	-- else owns the part, at 60Hz. In the Messatsu case both players are welded
	-- rigid AND both clients are writing CFrame, which detonates the solver and
	-- throws positions to NaN. That is why the environment "disappeared": the
	-- camera CFrame went non-finite, not a rendering bug.
	if not canSelfLock() then
		unlockCamera()
		return
	end

	-- 1. Target still valid? (dead, downed, carried, executed, despawned)
	if not isValidTarget(currentTarget) then
		unlockCamera()
		return
	end

	local myChar = player.Character
	if not myChar then
		return
	end
	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return
	end
	local targetRoot = currentTarget.HumanoidRootPart

	local toTarget = targetRoot.Position - myRoot.Position

	if toTarget.Magnitude > CONFIG.MaxDistance * 1.5 then
		unlockCamera()
		return
	end

	-- 2. DEGENERATE GEOMETRY GUARD.
	-- Every vector below is derived from the flat XZ separation between us and
	-- the target. Stand directly on top of them and that separation goes to zero.
	-- Vector3.zero.Unit is NaN, and CFrame.lookAt with a zero look direction is
	-- undefined. Both used to be fed straight into myRoot.CFrame and camera.CFrame.
	-- When we are too close, hold the last good frame instead of computing garbage.
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude < CONFIG.MinFlatDistance then
		return
	end

	-- 3. Character Movement (Strafe Face)
	-- Skipped entirely while ANOTHER system owns the root (ragdoll, carry, execution,
	-- Messatsu grab). canSelfLock now lets a ragdolled player KEEP the lock, so this
	-- check is the only thing left standing between the ragdoll physics and our
	-- per-frame CFrame write. Note it is the strict IsRootOwned (no ignoreRagdoll).
	-- The camera block below still runs, so a knocked-down player keeps the enemy
	-- framed while they flop, and the strafe-face resumes the moment they get up.
	local hum = myChar:FindFirstChild("Humanoid")
	if hum and not StateHandler.IsRootOwned(myChar) then
		hum.AutoRotate = false
		-- Face the enemy flat on Y axis
		local lookPos = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
		local goalRot = CFrame.lookAt(myRoot.Position, lookPos)
		-- Smooth character rotation
		myRoot.CFrame = myRoot.CFrame:Lerp(goalRot, 0.2)
	end

	-- 4. Camera Math (Smooth Over-The-Shoulder)

	-- Step A: Determine desired Camera Position
	-- We want the camera behind the player, but offset to the right
	-- We calculate "Behind" based on the direction from Enemy to Player.
	-- flat is guaranteed non-degenerate by the guard above.
	local flatDir = -flat.Unit

	-- Calculate Right Vector relative to that direction
	local rightVec = flatDir:Cross(Vector3.new(0, 1, 0))

	-- Assemble the target Position
	-- Position = PlayerPos + (Back * Z_Offset) + (Right * X_Offset) + (Up * Y_Offset)
	local camGoalPos = myRoot.Position
		+ (flatDir * CONFIG.ShoulderOffset.Z)
		+ (rightVec * CONFIG.ShoulderOffset.X)
		+ (Vector3.new(0, 1, 0) * CONFIG.ShoulderOffset.Y)

	-- Step B: Determine Look Position
	local lookAtPos = targetRoot.Position + CONFIG.LockOnOffset

	-- Step C: guard again before building the CFrame. Cheap insurance: if
	-- anything upstream produced a non-finite number, bail rather than write NaN
	-- into the camera, which is unrecoverable without a respawn.
	if not isFiniteVector(camGoalPos) or not isFiniteVector(lookAtPos) then
		return
	end
	if (lookAtPos - camGoalPos).Magnitude < 0.01 then
		return
	end

	local goalCFrame = CFrame.lookAt(camGoalPos, lookAtPos)

	-- Step D: Smoothly Interpolate (Lerp)
	-- This fixes the "Stiff" feeling. It blends current CFrame to Goal CFrame.
	local blended = camera.CFrame:Lerp(goalCFrame, CONFIG.CameraSmoothness)
	if isFiniteVector(blended.Position) then
		camera.CFrame = blended
	end
end)

--------------------------------------------------------------------------------
-- REACTIVE UNLOCK
--------------------------------------------------------------------------------

-- Drop the lock the instant the server downs / grabs / carries us, rather than
-- waiting for the next RenderStepped tick to notice.
-- "Ragdolled" is intentionally NOT in this list. A knockdown keeps the lock. The
-- RenderStepped loop just stops driving the root until the ragdoll ends.
local function hookCharacter(char)
	for _, key in ipairs({ "Downed", "Carried", "BeingExecuted", "Executing", "Carrying" }) do
		char:GetAttributeChangedSignal(key):Connect(function()
			if char:GetAttribute(key) and isLockedOn then
				unlockCamera()
			end
		end)
	end
end

if player.Character then
	hookCharacter(player.Character)
end
player.CharacterAdded:Connect(function(char)
	isLockedOn = false
	currentTarget = nil
	reticleGui.Adornee = nil
	reticleGui.Enabled = false
	hookCharacter(char)
end)

--------------------------------------------------------------------------------
-- INPUT HANDLING (CONTEXT SENSITIVE)
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == CONFIG.Keybind then
		keyPressTime = tick() -- Record when we pressed G
		isHoldingKey = true

		-- A downed / carried / grabbed player cannot acquire a lock at all.
		if not canSelfLock() then
			if isLockedOn then
				unlockCamera()
			end
			return
		end

		-- Determine intent based on Movement
		if not isLockedOn then
			-- Scenario 1: Not locked -> Lock onto closest
			local target = getClosestTarget()
			if target then
				lockCamera(target)
			end
		else
			-- Scenario 2: Already Locked. Check movement for switching.
			local moveDir = Vector3.new(0, 0, 0)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				moveDir = player.Character.Humanoid.MoveDirection
			end

			-- Convert MoveDirection to Camera Space to know if it's Left or Right
			local relativeMove = camera.CFrame:VectorToObjectSpace(moveDir)

			-- relativeMove.X > 0 is Right, < 0 is Left
			-- Threshold of 0.5 ensures deliberate movement
			if relativeMove.X < -0.5 then
				-- Holding Left -> Switch Left
				local newTarget = getDirectionalTarget(-1) -- -1 = Left
				if newTarget then
					lockCamera(newTarget)
				end
			elseif relativeMove.X > 0.5 then
				-- Holding Right -> Switch Right
				local newTarget = getDirectionalTarget(1) -- 1 = Right
				if newTarget then
					lockCamera(newTarget)
				end
			else
				-- Standing Still (or moving forward/back only)
				-- We wait for InputEnded to decide if this is a Tap (Unlock) or Hold (Unlock)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CONFIG.Keybind then
		isHoldingKey = false
		local duration = tick() - keyPressTime

		-- If we are locked on, and we just tapped G without moving sideways (handled in InputBegan),
		-- OR if we held it down for a long time: Unlock.
		if isLockedOn then
			-- We check Humanoid again to ensure we weren't trying to switch targets
			local moveDir = Vector3.new(0, 0, 0)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				moveDir = player.Character.Humanoid.MoveDirection
			end
			local relativeMove = camera.CFrame:VectorToObjectSpace(moveDir)

			-- Only unlock if we aren't strafing hard (which means we tried to switch targets)
			-- OR if we held the button down for safety
			--if (math.abs(relativeMove.X) < 0.5) or (duration > CONFIG.HoldToUnlockTime) then
			--	unlockCamera()
			--end

			if duration > CONFIG.HoldToUnlockTime then
				unlockCamera()
			end
		end
	end
end)
