-- SPDX-License-Identifier: MIT
--
-- The lock-on (G): locks onto the closest visible target, switches left or right with
-- strafe + G, turns the character to face the target, and moves the camera over the
-- shoulder. Holding G unlocks. The design is in docs/combat-design.md.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local toggleShiftLockEvent = ReplicatedStorage.remotes:WaitForChild("ToggleShiftLock")
local StateHandler = require(ReplicatedStorage.modules.stateHandler)

local CONFIG = {
	Keybind = Enum.KeyCode.G,
	MaxDistance = 100,
	TargetFolder = Workspace:WaitForChild("plrManager"):WaitForChild("alive"),

	CameraSmoothness = 0.15, -- 0.05 is slow and heavy, 0.3 is snappy.
	LockOnOffset = Vector3.new(0, 1, 0), -- Aim at the chest.

	-- The camera position relative to the player: X is right, Y is up, Z is back.
	ShoulderOffset = Vector3.new(-5, 8, 7),

	HoldToUnlockTime = 0.35, -- Seconds to hold G to unlock.

	-- Below this horizontal distance the look vectors are degenerate, and .Unit
	-- returns NaN, which breaks the camera.
	MinFlatDistance = 2.5,
}

local isLockedOn = false
local currentTarget = nil
local keyPressTime = 0
local isHoldingKey = false

local reticleGui = Instance.new("BillboardGui")
reticleGui.Name = "LockOnReticle"
reticleGui.Size = UDim2.new(0, 40, 0, 40)
reticleGui.AlwaysOnTop = true
reticleGui.Enabled = false

local reticleImage = Instance.new("ImageLabel")
reticleImage.Parent = reticleGui
reticleImage.BackgroundTransparency = 1
reticleImage.Size = UDim2.new(1, 0, 1, 0)
reticleImage.Image = "rbxassetid://12389946814"
reticleImage.ImageColor3 = Color3.fromRGB(255, 50, 50)

reticleGui.Parent = player:WaitForChild("PlayerGui")

-- These checks read attributes, not StateHandler.GetState, because server states never
-- reach the client's state table.

-- Returns whether the local player may hold a lock right now.
local function canSelfLock()
	local char = player.Character
	if not char then
		return false
	end

	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end

	if char:GetAttribute("Downed") then
		return false
	end

	-- No lock while another system owns our root (carry, execution, Messatsu weld). A
	-- plain knockdown ragdoll is ignored: the lock survives it, and the update loop
	-- only stops writing the root CFrame while ragdolled.
	if StateHandler.IsRootOwned(char, true) then
		return false
	end

	return true
end

-- Returns whether a character can be locked onto.
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
				-- Only visible targets count, or targets closer than 10 studs.
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

-- Returns the nearest target on the given side of the current one on screen
-- (-1 is left, 1 is right).
local function getDirectionalTarget(direction)
	if not currentTarget then
		return getClosestTarget()
	end

	local targets = getAllValidTargets()
	local bestCandidate = nil
	local bestAngle = math.huge

	local camCFrame = camera.CFrame
	local currentTargetPos = currentTarget.HumanoidRootPart.Position

	for _, t in pairs(targets) do
		if t ~= currentTarget then
			local tPos = t.HumanoidRootPart.Position

			local delta = tPos - currentTargetPos
			if delta.Magnitude > 0.01 then
				local dirToCandidate = delta.Unit

				-- Its dot product with the camera's right vector is positive on the right.
				local rightDot = camCFrame.RightVector:Dot(dirToCandidate)

				local isOnCorrectSide = false
				if direction > 0 and rightDot > 0 then
					isOnCorrectSide = true
				end
				if direction < 0 and rightDot < 0 then
					isOnCorrectSide = true
				end

				if isOnCorrectSide then
					-- Prefer the closest target on that side.
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

	-- Publish the lock target for the server's running-attack lunge. The server checks
	-- range and validity again, so a forged attribute gains nothing.
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

	-- Leave AutoRotate alone while another system owns the root. The downed system
	-- restores it on revive, and setting it here would let a ragdoll spin.
	local char = player.Character
	if char and char:FindFirstChild("Humanoid") and not StateHandler.IsRootOwned(char) then
		char.Humanoid.AutoRotate = true
	end
end

RunService.RenderStepped:Connect(function()
	if not isLockedOn or not currentTarget then
		return
	end

	-- The loop writes the root CFrame every frame. While another system owns the root,
	-- that write would fight it, and with a Messatsu weld both clients writing CFrame
	-- breaks the solver with NaN.
	if not canSelfLock() then
		unlockCamera()
		return
	end

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

	-- Too close to the target: the horizontal direction would be NaN, so keep the last
	-- good frame.
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude < CONFIG.MinFlatDistance then
		return
	end

	-- Turn the character to face the target, unless another system owns the root. This
	-- is the strict check, without ignoreRagdoll, so a ragdoll is never driven. The
	-- camera still follows the target during a knockdown.
	local hum = myChar:FindFirstChild("Humanoid")
	if hum and not StateHandler.IsRootOwned(myChar) then
		hum.AutoRotate = false
		local lookPos = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
		local goalRot = CFrame.lookAt(myRoot.Position, lookPos)
		myRoot.CFrame = myRoot.CFrame:Lerp(goalRot, 0.2)
	end

	-- Put the camera behind the player, away from the target, at ShoulderOffset.
	local flatDir = -flat.Unit

	local rightVec = flatDir:Cross(Vector3.new(0, 1, 0))

	local camGoalPos = myRoot.Position
		+ (flatDir * CONFIG.ShoulderOffset.Z)
		+ (rightVec * CONFIG.ShoulderOffset.X)
		+ (Vector3.new(0, 1, 0) * CONFIG.ShoulderOffset.Y)

	local lookAtPos = targetRoot.Position + CONFIG.LockOnOffset

	-- A NaN in camera.CFrame cannot be recovered without a respawn, so check again.
	if not isFiniteVector(camGoalPos) or not isFiniteVector(lookAtPos) then
		return
	end
	if (lookAtPos - camGoalPos).Magnitude < 0.01 then
		return
	end

	local goalCFrame = CFrame.lookAt(camGoalPos, lookAtPos)

	local blended = camera.CFrame:Lerp(goalCFrame, CONFIG.CameraSmoothness)
	if isFiniteVector(blended.Position) then
		camera.CFrame = blended
	end
end)

-- Drop the lock the moment the server downs, grabs, or carries us. Ragdolled is not in
-- the list: a knockdown keeps the lock.
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == CONFIG.Keybind then
		keyPressTime = tick()
		isHoldingKey = true

		if not canSelfLock() then
			if isLockedOn then
				unlockCamera()
			end
			return
		end

		if not isLockedOn then
			local target = getClosestTarget()
			if target then
				lockCamera(target)
			end
		else
			-- Already locked: strafing left or right with G switches the target.
			local moveDir = Vector3.new(0, 0, 0)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				moveDir = player.Character.Humanoid.MoveDirection
			end

			local relativeMove = camera.CFrame:VectorToObjectSpace(moveDir)

			-- X above 0.5 is a deliberate move right, below -0.5 left.
			if relativeMove.X < -0.5 then
				local newTarget = getDirectionalTarget(-1)
				if newTarget then
					lockCamera(newTarget)
				end
			elseif relativeMove.X > 0.5 then
				local newTarget = getDirectionalTarget(1)
				if newTarget then
					lockCamera(newTarget)
				end
			else
				-- Not strafing: InputEnded decides whether this unlocks.
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CONFIG.Keybind then
		isHoldingKey = false
		local duration = tick() - keyPressTime

		-- Holding G for HoldToUnlockTime unlocks.
		if isLockedOn then
			local moveDir = Vector3.new(0, 0, 0)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				moveDir = player.Character.Humanoid.MoveDirection
			end
			local relativeMove = camera.CFrame:VectorToObjectSpace(moveDir)

			if duration > CONFIG.HoldToUnlockTime then
				unlockCamera()
			end
		end
	end
end)
