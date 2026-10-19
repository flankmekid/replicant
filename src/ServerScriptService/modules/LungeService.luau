-- SPDX-License-Identifier: MIT
--
-- Runs the running-attack lunge on the server: a forward boost that always fires, and
-- a chase that follows the target only while they run away. The design is in
-- docs/combat-design.md.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashConfig = require(ReplicatedStorage.modules.DashConfig)

local LungeService = {}

local targetFolder = Workspace:WaitForChild("plrManager"):WaitForChild("alive")

-- The lock-on reaches 100 studs, but a lunge across 100 studs is a teleport.
local maxAcquireDist = 60
-- How far off the attacker's facing, in degrees, a target can be without a lock-on.
local acquireConeDeg = 60

-- The boost length comes from the M1Lunge entry in DashConfig. The fallback matters only
-- if M1Lunge is disabled, and then CombatCore never calls Start.
local _, boostTime = DashConfig.Get("M1Lunge")
boostTime = boostTime or 0.3

-- The target's lookVector dotted with the direction to the attacker. Below this, they
-- are turned away.
local fleeFacingDot = -0.15
-- Speed away from the attacker, in studs per second, that counts as fleeing. Filters
-- out strafing and jitter.
local fleeSpeedMin = 8

-- The same multiplier as Movement.Running: sprint = WalkSpeed * sprintMult.
local sprintMult = 1.75
local baseSprint = 16 * sprintMult
-- How much faster than the target's sprint the chase closes.
local chaseSprintMult = 1.35
-- Steering in degrees per second. High makes a homing missile, low is easy to juke.
local maxTurnRateDeg = 280
-- Stop driving inside this distance, so the attacker lands next to the target.
local stopDist = 5
-- Below this distance the flat vector is degenerate and .Unit returns NaN.
local minFlatDist = 1.5

-- The same rules as LockOn.isValidTarget.
local function isValidTarget(enemy, attacker)
	if not enemy or not enemy.Parent then
		return false
	end
	if enemy == attacker then
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
		and math.abs(v.X) ~= math.huge
		and math.abs(v.Y) ~= math.huge
		and math.abs(v.Z) ~= math.huge
end

local function flatDir(fromPos, toPos)
	local d = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	local mag = d.Magnitude
	if mag < minFlatDist then
		return nil, nil
	end
	local u = d.Unit
	if not isFiniteVector(u) then
		return nil, nil
	end
	return u, mag
end

-- The gate on the chase. False for a target who faces us, stands still, or backs up
-- while facing us.
local function isFleeing(target, myRoot)
	local tRoot = target:FindFirstChild("HumanoidRootPart")
	if not tRoot then
		return false
	end

	local toUs =
		Vector3.new(myRoot.Position.X - tRoot.Position.X, 0, myRoot.Position.Z - tRoot.Position.Z)
	if toUs.Magnitude < minFlatDist then
		return false
	end
	toUs = toUs.Unit
	if not isFiniteVector(toUs) then
		return false
	end

	local look = tRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.01 then
		flatLook = flatLook.Unit
		-- Near +1 means looking straight at us. Negative means turned away.
		if flatLook:Dot(toUs) < fleeFacingDot then
			return true
		end
	end

	-- Project their velocity on the axis away from us. Strafing adds nothing.
	local vel = tRoot.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local awaySpeed = flatVel:Dot(-toUs)
	if awaySpeed >= fleeSpeedMin then
		return true
	end

	return false
end

local function getLockedTarget(char)
	local name = char:GetAttribute("LockTarget")
	if type(name) ~= "string" then
		return nil
	end

	local enemy = targetFolder:FindFirstChild(name)
	if not enemy or not enemy:IsA("Model") then
		return nil
	end
	if not isValidTarget(enemy, char) then
		return nil
	end

	local myRoot = char:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return nil
	end

	-- A forged attribute that names someone across the map gets nothing.
	if (enemy.HumanoidRootPart.Position - myRoot.Position).Magnitude > maxAcquireDist then
		return nil
	end

	return enemy
end

local function getConeTarget(char)
	local myRoot = char:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return nil
	end

	local myPos = myRoot.Position
	local facing = myRoot.CFrame.LookVector
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 0.01 then
		return nil
	end
	flatFacing = flatFacing.Unit

	local cosLimit = math.cos(math.rad(acquireConeDeg))
	local best, bestDist = nil, math.huge

	for _, enemy in ipairs(targetFolder:GetChildren()) do
		if enemy:IsA("Model") and isValidTarget(enemy, char) then
			local dir, dist = flatDir(myPos, enemy.HumanoidRootPart.Position)
			if dir and dist and dist <= maxAcquireDist then
				if flatFacing:Dot(dir) >= cosLimit and dist < bestDist then
					bestDist = dist
					best = enemy
				end
			end
		end
	end

	return best
end

-- LungeService.AcquireTarget() - pick the lunge target for a character
-- @char: the attacking character
--
-- Return: the locked target if it is valid and in range, otherwise the nearest valid
-- target in the cone, or nil.
function LungeService.AcquireTarget(char)
	if not char then
		return nil
	end
	return getLockedTarget(char) or getConeTarget(char)
end

-- Rotates current toward desired by at most maxStep radians in the XZ plane.
local function steer(current, desired, maxStep)
	local dot = math.clamp(current:Dot(desired), -1, 1)
	local angle = math.acos(dot)

	if angle <= maxStep or angle < 1e-4 then
		return desired
	end

	local cross = current:Cross(desired)
	local sign = (cross.Y >= 0) and 1 or -1
	local rotated = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), sign * maxStep) * current
	local flat = Vector3.new(rotated.X, 0, rotated.Z)
	if flat.Magnitude > 0.01 then
		local u = flat.Unit
		if isFiniteVector(u) then
			return u
		end
	end
	return current
end

-- LungeService.Start() - start a lunge
-- @char: the attacking character
-- @speed: the boost velocity, from DashConfig
-- @chaseUntil: how long the drive may last if a chase engages. Pass windupDelay plus
--              lungeWait so the chase covers the whole animation. Without a chase, the
--              drive ends at boostTime.
-- @token: CombatCore's attack token. A parry or a stun ends the lunge.
--
-- Return: nothing.
function LungeService.Start(char, speed, chaseUntil, token)
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local old = root:FindFirstChild("LungeVelocity")
	if old then
		old:Destroy()
	end

	local facing = root.CFrame.LookVector
	local currentDir = Vector3.new(facing.X, 0, facing.Z)
	if currentDir.Magnitude < 0.01 then
		return
	end
	currentDir = currentDir.Unit

	-- The boost always fires, with or without a target.
	local BV = Instance.new("BodyVelocity")
	BV.Name = "LungeVelocity"
	BV.MaxForce = Vector3.new(25000, 0, 25000)
	BV.Velocity = currentDir * speed
	BV.Parent = root

	local target = LungeService.AcquireTarget(char)
	local chasing = false

	task.spawn(function()
		local elapsed = 0
		local conn

		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt

			local function stop()
				if conn then
					conn:Disconnect()
				end
				if BV.Parent then
					BV:Destroy()
				end
			end

			if
				(token and token.cancelled)
				or not char.Parent
				or not root.Parent
				or not BV.Parent
			then
				stop()
				return
			end

			-- A target that dies, goes down, or is carried during the lunge stops being one.
			if target and not isValidTarget(target, char) then
				target = nil
				chasing = false
			end

			-- Check the chase every frame. A target who turns to face us stops being chased,
			-- and one who turns to run starts being chased.
			if target then
				chasing = isFleeing(target, root)
			end

			-- The drive ends at boostTime unless a chase is engaged.
			local limit = chasing and math.max(boostTime, chaseUntil) or boostTime
			if elapsed >= limit then
				stop()
				return
			end

			local spd = speed

			if chasing and target then
				local tRoot = target:FindFirstChild("HumanoidRootPart")
				if tRoot then
					local desired, dist = flatDir(root.Position, tRoot.Position)
					if desired and dist then
						-- Stop when close, so the lunge lands on the target, not through them.
						if dist <= stopDist then
							stop()
							return
						end

						currentDir = steer(currentDir, desired, math.rad(maxTurnRateDeg) * dt)
					end

					-- After the burst, follow at a speed based on the target's sprint, so it works
					-- the same for every weapon and adapts to a fast target.
					if elapsed > boostTime then
						local tHum = target:FindFirstChild("Humanoid")
						local theirSprint = baseSprint
						if tHum and tHum.WalkSpeed > 0 then
							theirSprint = tHum.WalkSpeed * sprintMult
						end
						spd = math.min(speed, theirSprint * chaseSprintMult)
					end
				end
			end

			local vel = currentDir * spd
			if isFiniteVector(vel) then
				BV.Velocity = vel
			end
		end)
	end)
end

-- LungeService.Stop() - end a character's lunge
-- @char: the character
--
-- Return: nothing.
function LungeService.Stop(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local BV = root and root:FindFirstChild("LungeVelocity")
	if BV then
		BV:Destroy()
	end
end

return LungeService
