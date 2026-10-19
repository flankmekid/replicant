-- LungeService: server-authoritative lunge for the running attack.
--
-- [[ THE RULE ]] --
--
-- The BOOST always fires. It is the move: a forward burst, then the animation plays,
-- then the swing lands. Unconditional, no target needed, works into empty air.
--
-- The CHASE only engages when the target is RUNNING AWAY. If they are facing you and
-- holding ground, you get the plain step-in and you have to actually reach them. If
-- they turn tail, the lunge sticks to them so the running attack does what a running
-- attack is for.
--
-- That split matters. A chase that engages against someone standing their ground is
-- just magnetism: it drags you onto a target who never tried to escape, and it makes
-- spacing meaningless. Fleeing is the only case that needs the correction.
--
-- [[ WHY THE OLD ONE FAILED ]] --
--
-- Not the impulse. The setSpeed slow was eating it:
--   * Boost closes ~15 studs (50 * 0.3s).
--   * Then setSpeed pinned the attacker at walkspeed 4 for the whole windup.
--   * A sprinting target does ~28.
--   * Over the ~0.6s from boost-end to hitbox they took back 13-15 studs.
-- Net displacement against a runner: about zero. Every stud the lunge bought was
-- handed straight back. (Fixed in CombatCore: the running attack skips setSpeed.)
--
-- [[ TARGETING ]] --
-- Mirrors StarterCharacterScripts.LockOn:
--   * Locked on -> that target. The client publishes it as the LockTarget attribute;
--     we RE-VALIDATE here, so a forged attribute buys nothing.
--   * Not locked -> the same nearest-valid-target-in-a-cone search the lock-on runs.
--
-- The runner can still win. Steering is rate-limited (MAX_TURN_RATE_DEG), so cutting
-- hard across the attacker's facing breaks the track. And a dodge or parry at the
-- right time beats it outright, because the lunge only closes DISTANCE. The hitbox
-- still has to land.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashConfig = require(ReplicatedStorage.modules.DashConfig)

local LungeService = {}

local TARGET_FOLDER = Workspace:WaitForChild("plrManager"):WaitForChild("alive")

-- [[ TUNING ]] --
local MAX_ACQUIRE_DIST = 60 -- lock-on allows 100, but a lunge across 100 studs is
-- a teleport
local ACQUIRE_CONE_DEG = 60 -- how far off your facing a target can sit and still
-- be picked up when NOT locked on

-- The burst length: the step-in, which fires whether or not anyone is there. It lives
-- in DashConfig with every other weapon dash. Passing no weapon returns the M1Lunge
-- default, and the life is uniform across weapons anyway.
--
-- The old BURST_MULT of 1.35 is gone. DashConfig holds the final lunge speeds now, so
-- there is nothing left to scale here. Tune M1Lunge in that table instead.
local _, BOOST_TIME = DashConfig.Get("M1Lunge")
BOOST_TIME = BOOST_TIME or 0.3 -- only reachable if M1Lunge is ever disabled outright,
-- in which case CombatCore never calls Start anyway

-- [[ WHAT COUNTS AS "RUNNING AWAY" ]] --
-- Two independent tests, either one is enough:
--   1. FACING: they are turned away from us (their look vector points away).
--   2. MOVING: they are physically travelling away from us.
-- A player backpedalling while facing us is NOT fleeing (they are spacing, which is
-- legitimate defence). A player sprinting away with their back turned is.
local FLEE_FACING_DOT = -0.15 -- their lookVector vs the direction from them to us.
-- Below this they are turned away from us.
local FLEE_SPEED_MIN = 8 -- studs/sec of AWAY-from-us velocity before we call
-- it fleeing. Filters out strafing and jitter.

-- [[ THE CHASE ]] --
local SPRINT_MULT = 1.75 -- mirrors Movement.Running: sprint = walkspeed * this
local BASE_SPRINT = 16 * SPRINT_MULT
local CHASE_SPRINT_MULT = 1.35 -- how much faster than THEIR sprint we close. Keyed
-- to the target, not to the boost speed: the 35-speed
-- weapons would otherwise "chase" at 19 against a
-- 28 sprint, i.e. slower than running away. Raised from
-- 1.15 so the follow actually welds to a fleeing target
-- (author: "stuck behind the one running away") instead
-- of trailing a step behind. Still capped by the boost
-- velocity below, so it cannot exceed the weapon's reach.
local MAX_TURN_RATE_DEG = 280 -- deg/sec of steering. THE SKILL DIAL: high = homing
-- missile, low = trivially juked. Raised from 220 so a
-- runner cutting angles is tracked harder; a HARD cut
-- across the attacker's facing still breaks it.
local STOP_DIST = 5 -- stop driving inside this, so you land NEXT to them
-- rather than clipping through
local MIN_FLAT_DIST = 1.5 -- below this the XZ vector is degenerate and .Unit
-- returns NaN (the trap the lock-on camera hit)

-- [[ VALIDITY (mirrors LockOn.isValidTarget) ]] --
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
	if mag < MIN_FLAT_DIST then
		return nil, nil
	end
	local u = d.Unit
	if not isFiniteVector(u) then
		return nil, nil
	end
	return u, mag
end

-- [[ IS THIS TARGET RUNNING AWAY FROM US? ]] --
-- This is the gate on the whole chase. Returns false for someone facing us, someone
-- standing still, and someone backpedalling to make space while still facing us.
local function isFleeing(target, myRoot)
	local tRoot = target:FindFirstChild("HumanoidRootPart")
	if not tRoot then
		return false
	end

	-- Direction from THEM to US, flattened.
	local toUs =
		Vector3.new(myRoot.Position.X - tRoot.Position.X, 0, myRoot.Position.Z - tRoot.Position.Z)
	if toUs.Magnitude < MIN_FLAT_DIST then
		return false
	end
	toUs = toUs.Unit
	if not isFiniteVector(toUs) then
		return false
	end

	-- 1. FACING: is their back to us?
	local look = tRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.01 then
		flatLook = flatLook.Unit
		-- Dot of their facing with the direction TO us. Near +1 = looking straight at
		-- us. Negative = turned away.
		if flatLook:Dot(toUs) < FLEE_FACING_DOT then
			return true
		end
	end

	-- 2. MOVING: are they physically travelling away from us, fast enough to count?
	-- We project their velocity onto the AWAY-from-us axis. Strafing contributes
	-- nothing; only genuine retreat does.
	local vel = tRoot.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local awaySpeed = flatVel:Dot(-toUs) -- positive = moving away from us
	if awaySpeed >= FLEE_SPEED_MIN then
		return true
	end

	return false
end

-- [[ ACQUISITION ]] --
local function getLockedTarget(char)
	local name = char:GetAttribute("LockTarget")
	if type(name) ~= "string" then
		return nil
	end

	local enemy = TARGET_FOLDER:FindFirstChild(name)
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

	-- Range gate. A forged attribute naming someone across the map gets nothing.
	if (enemy.HumanoidRootPart.Position - myRoot.Position).Magnitude > MAX_ACQUIRE_DIST then
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

	local cosLimit = math.cos(math.rad(ACQUIRE_CONE_DEG))
	local best, bestDist = nil, math.huge

	for _, enemy in ipairs(TARGET_FOLDER:GetChildren()) do
		if enemy:IsA("Model") and isValidTarget(enemy, char) then
			local dir, dist = flatDir(myPos, enemy.HumanoidRootPart.Position)
			if dir and dist and dist <= MAX_ACQUIRE_DIST then
				if flatFacing:Dot(dir) >= cosLimit and dist < bestDist then
					bestDist = dist
					best = enemy
				end
			end
		end
	end

	return best
end

function LungeService.AcquireTarget(char)
	if not char then
		return nil
	end
	return getLockedTarget(char) or getConeTarget(char)
end

-- Rotate `current` toward `desired` by at most `maxStep` radians, in the XZ plane.
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

-- [[ THE LUNGE ]] --
--
--   speed      : boost velocity, already resolved from DashConfig by the caller
--   chaseUntil : how long the drive MAY last, if a chase engages. Pass
--                windupDelay + lungeWait so the follow covers the whole animation.
--                With no chase, the drive always ends at BOOST_TIME.
--   token      : CombatCore's attack token. A parry or stun kills the lunge instead
--                of dragging the attacker onward.
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

	-- THE BOOST ALWAYS FIRES. No target required, no conditions. This is the move.
	local BV = Instance.new("BodyVelocity")
	BV.Name = "LungeVelocity"
	BV.MaxForce = Vector3.new(25000, 0, 25000)
	BV.Velocity = currentDir * speed
	BV.Parent = root

	-- The chase is a separate question, re-asked every frame.
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

			-- A target that dies, goes down, or gets carried mid-lunge stops being one.
			if target and not isValidTarget(target, char) then
				target = nil
				chasing = false
			end

			-- Re-evaluate the chase every frame. Someone who turns to FACE us mid-lunge
			-- stops being chased: the tracking drops and we coast on our current
			-- heading. Someone who turns to RUN mid-lunge starts being chased.
			-- Standing your ground beats the magnet; only fleeing invites it.
			if target then
				chasing = isFleeing(target, root)
			end

			-- Drive ends at BOOST_TIME unless a chase is actively engaged.
			local limit = chasing and math.max(BOOST_TIME, chaseUntil) or BOOST_TIME
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
						-- Close enough: stop driving. Overshooting is what makes a
						-- lunge feel like it clips THROUGH someone instead of landing
						-- on them. This is the "almost welded to their back" moment.
						if dist <= STOP_DIST then
							stop()
							return
						end

						currentDir = steer(currentDir, desired, math.rad(MAX_TURN_RATE_DEG) * dt)
					end

					-- After the burst, hold a follow speed keyed to THEIR sprint, so it
					-- works identically on a 35-velocity Dagger and a 50-velocity
					-- Katana, and auto-adapts to a target whose Stamina makes them fast.
					if elapsed > BOOST_TIME then
						local tHum = target:FindFirstChild("Humanoid")
						local theirSprint = BASE_SPRINT
						if tHum and tHum.WalkSpeed > 0 then
							theirSprint = tHum.WalkSpeed * SPRINT_MULT
						end
						spd = math.min(speed, theirSprint * CHASE_SPRINT_MULT)
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

function LungeService.Stop(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local BV = root and root:FindFirstChild("LungeVelocity")
	if BV then
		BV:Destroy()
	end
end

return LungeService
