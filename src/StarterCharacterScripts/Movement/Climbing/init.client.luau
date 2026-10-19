-- client sided climbing script

-- services
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")

-- variables
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")

-- modules
-- shared single-owner camera shaker (replaces this script's old private CameraShaker
-- instance, so we don't run two render-step binds fighting over camera.CFrame)
local ClientCameraShake =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("ClientCameraShake"))
local CooldownTracker =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("CooldownTracker"))

-- vaulting/climbing variables
local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = { character }
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local canVault = true
local vaultConnection = nil
local ledgePart = nil
local climbDebounce = false

-- [[ CLIMB ARMING STATE ]]
-- A climb (ledge grab OR wall jump) is only allowed when airborne AND "armed". Arming is
-- what stops a single ground press from launching you up a wall:
--   * A space press while GROUNDED is just a jump -- it does NOT arm.
--   * A separate space press while AIRBORNE arms you (and that same press attempts the
--     climb). So a ground-start climb costs two distinct taps: tap 1 jumps, tap 2 (in
--     the air) climbs. InputBegan only fires on a fresh key-down, never on hold, so you
--     can't satisfy the second tap by holding jump -- it must be a real second press.
--   * A wall run re-arms you (WallRun sets the WallRanRecently attribute on the
--     character), so after a wall run a SINGLE mid-air press climbs.
--   * Touching the ground DISARMS.
-- While armed and airborne you may climb repeatedly without re-arming.
local armed = false

-- Pull (and consume) a wall-run re-arm if WallRun flagged one. Returns true if it armed.
local function consumeWallRunArm()
	if character:GetAttribute("WallRanRecently") then
		character:SetAttribute("WallRanRecently", false)
		armed = true
		return true
	end
	return false
end

local function isAirborne()
	local s = humanoid:GetState()
	return s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping
end

local CLIMB_COOLDOWN = 1.25 -- matches the task.wait below; surfaced on the cooldown UI

-- [[ LEDGE SURFACE VALIDATION ]]
-- Tunables for what counts as a grabbable ledge surface.
local MIN_LEDGE_THICKNESS = 0.5 -- smallest part dimension (studs) allowed; rejects railings, decals-on-thin-parts, blades
local MAX_LEDGE_TRANSPARENCY = 0.5 -- anything more see-through than this is treated as non-grabbable

-- ANIMATIONS
local grabAnim = humanoid:LoadAnimation(script:WaitForChild("Grab"))
grabAnim.Priority = Enum.AnimationPriority.Action4

-- Audio
local grabSounds = script:WaitForChild("Sounds"):GetChildren()

-- play vault sounds
local function playSound()
	local sound = grabSounds[math.random(1, #grabSounds)]:Clone()
	sound.Parent = rootPart
	sound.Volume = 0.35
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Gate for whether a raycast-hit part is something the player is allowed to hang on.
-- Rejects: non-BaseParts, characters/NPCs and (since weapons are Tools parented to the
-- character) their held weapons via the Humanoid-ancestor test, transparent/ghost parts,
-- non-collidable parts, and surfaces thinner than MIN_LEDGE_THICKNESS (railings, blades,
-- decal-thin geometry).
local function isValidLedgeSurface(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	-- Anything under a model that has a Humanoid is a creature (player/NPC) or its gear.
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then
			return false
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end

	-- Loose tools sitting in the world (not parented to a character) are still gear.
	if part:FindFirstAncestorWhichIsA("Tool") then
		return false
	end

	-- Visibility / solidity.
	if part.Transparency > MAX_LEDGE_TRANSPARENCY then
		return false
	end
	if not part.CanCollide then
		return false
	end

	-- Thickness: reject if the SMALLEST dimension is below the threshold. A thin wall is
	-- fine (it's only thin on one axis but tall/wide on others) -- this targets parts that
	-- are thin enough to be a railing bar, blade, or sliver of geometry on their grab face.
	local sz = part.Size
	if math.min(sz.X, sz.Y, sz.Z) < MIN_LEDGE_THICKNESS then
		return false
	end

	return true
end

-- check if part is above when tryin to vault or move
local function partCheck(ledge)
	local vaultPartCheck =
		workspace:Raycast(ledge.Position + ledge.LookVector * 1, ledge.UpVector * 3, raycastParams)
	return vaultPartCheck == nil
end

-- ledge detection logic
-- Added 'bypassChecks' parameter to allow detection while mid-climb
local function detectLedge(bypassChecks)
	-- If already hanging, let go
	if not canVault then
		canVault = true
		humanoid.AutoRotate = true
		rootPart.Anchored = false
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		grabAnim:Stop()
		game:GetService("ReplicatedStorage").remotes.stateRepl:FireServer("VaultOff")
		if vaultConnection then
			vaultConnection:Disconnect()
		end
		if ledgePart then
			ledgePart:Destroy()
		end
		return true
	end

	if
		canVault
		and (
			bypassChecks
			or humanoid:GetState() == Enum.HumanoidStateType.Freefall
			or humanoid:GetState() == Enum.HumanoidStateType.Jumping
		)
	then
		if character:GetAttribute("Stunned") then
			return
		end
		if character:GetAttribute("Carried") then
			return
		end
		if character:GetAttribute("Downed") then
			return
		end
		if character:GetAttribute("Carrying") then
			return
		end
		if not bypassChecks and character:GetAttribute("CantAnything") then
			return
		end

		-- Cast forward at three heights -- head level plus/minus 1 stud of leeway -- so a
		-- ledge slightly above or below your head still registers. First ray that hits a
		-- VALID surface wins; if a ray hits an invalid surface (player, thin part, etc.)
		-- we just try the next height rather than bailing outright.
		local LEDGE_VERTICAL_LEEWAY = 1 -- studs of up/down slack around head height
		local vaultCheck = nil
		for _, yOff in ipairs({ 0, LEDGE_VERTICAL_LEEWAY, -LEDGE_VERTICAL_LEEWAY }) do
			local origin = head.CFrame.Position + Vector3.new(0, yOff, 0)
			local result = workspace:Raycast(origin, head.CFrame.LookVector * 5, raycastParams)
			if result and result.Instance and isValidLedgeSurface(result.Instance) then
				vaultCheck = result
				break
			end
		end

		if vaultCheck and vaultCheck.Instance then
			local hit = vaultCheck.Instance

			local localPos = vaultCheck.Instance.CFrame:PointToObjectSpace(vaultCheck.Position)
			local localLedgePos =
				Vector3.new(localPos.X, vaultCheck.Instance.Size.Y / 2, localPos.Z)
			local ledgePos = vaultCheck.Instance.CFrame:PointToWorldSpace(localLedgePos)

			local flatNormal = Vector3.new(vaultCheck.Normal.X, 0, vaultCheck.Normal.Z)
			local lookDir = -flatNormal

			if lookDir:Dot(head.CFrame.LookVector) < 0 or lookDir.Magnitude < 0.001 then
				lookDir = head.CFrame.LookVector * Vector3.new(1, 0, 1)
			end

			local ledgeOffset = CFrame.lookAt(ledgePos, ledgePos + lookDir.Unit)
			local magnitude = (ledgePos - head.Position).Magnitude

			if magnitude < 3 and partCheck(ledgeOffset) then
				canVault = false
				-- grab jolt, via the shared shaker
				ClientCameraShake.ShakeOnce(4, 0, 0, 0.3)

				ledgePart = Instance.new("Part")
				ledgePart.Name = "LedgeAnchor"
				ledgePart.Parent = workspace
				ledgePart.Anchored = true
				ledgePart.CFrame = ledgeOffset
					+ Vector3.new(0, -2, 0)
					+ (ledgeOffset.LookVector * -1)
				ledgePart.Transparency = 1
				ledgePart.CanQuery, ledgePart.CanCollide, ledgePart.CanTouch = false, false, false

				local animM = require(game:GetService("ReplicatedStorage").modules.animationHandler)
				animM.StopAnim(character, "ALL")

				grabAnim:Play()
				playSound()
				game:GetService("ReplicatedStorage").remotes.stateRepl:FireServer("VaultOn")

				vaultConnection = RunService.RenderStepped:Connect(function()
					rootPart.Anchored = true
					humanoid.AutoRotate = false
					local lookTarget = (ledgePart.CFrame * CFrame.new(0, 0, -5)).Position
					rootPart.CFrame =
						rootPart.CFrame:Lerp(CFrame.lookAt(ledgePart.Position, lookTarget), 0.25)
					humanoid:ChangeState(Enum.HumanoidStateType.Seated)
				end)
				return true
			end
		end
	end
	return false
end

-- check for wall (Reusable)
local function checkWall()
	local rayOrigin = head.Position
	local rayDirection = rootPart.CFrame.lookVector * 3
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

-- [[ INPUT BUFFER ]]
-- The jump/climb input is buffered exactly like the dash: a press that can't act right
-- now (mid-cooldown via climbDebounce, or a transient CantAnything/state block) is
-- stashed with a timestamp, and a Heartbeat loop retries handleJumpAction within the
-- window. Because handleJumpAction YIELDS (it task.waits through the climb sequence),
-- a naive per-frame retry would stack overlapping climb attempts -- so an
-- `actionRunning` guard ensures only one attempt is ever in flight, and the buffer
-- only retries while nothing is running.
local BUFFER_WINDOW = 0.5
local bufferedAt = nil
local actionRunning = false

-- Returns true if a climb/ledge action actually started, false if rejected. The body is
-- unchanged from the original handleJumpAction; the actionRunning guard, the boolean
-- returns, and the ARMED gate are the only additions. The armed gate is what makes a
-- ground press a pure jump instead of a wall launch -- no climb of any kind fires unless
-- you're airborne and armed.
local function handleJumpAction()
	-- Only one climb attempt in flight at a time (this function yields).
	if actionRunning then
		return false
	end

	-- RELEASE CASE FIRST: if we're currently hanging, a press just lets go (with the
	-- script's built-in up/forward hop). Letting go is NOT a climb, so it must run
	-- BEFORE the airborne/armed gate -- while hanging you're in the Seated state (not
	-- airborne) and not armed, so the gate below would otherwise trap you on the ledge.
	if not canVault then
		detectLedge(false) -- toggles the hang off
		return true
	end

	-- ARMED GATE: a climb requires being airborne AND armed. A wall run can supply the
	-- arm on demand (consume it here). If not armed, this press does nothing climb-wise
	-- (the default jump still happens via the Humanoid as normal).
	if not isAirborne() then
		return false
	end
	consumeWallRunArm()
	if not armed then
		return false
	end

	actionRunning = true

	local fired = false

	-- 1. Try Ledge Logic (Manual input check)
	local ledgeFound = detectLedge(false)
	if ledgeFound then
		actionRunning = false
		return true
	end

	-- 2. If no ledge, try Wall Climb Sequence
	if not ledgeFound and canVault then
		if
			humanoid:GetState() == Enum.HumanoidStateType.Freefall
			or humanoid:GetState() == Enum.HumanoidStateType.Jumping
		then
			if climbDebounce then
				actionRunning = false
				return false
			end

			if character:GetAttribute("Stunned") then
				actionRunning = false
				return false
			end
			if character:GetAttribute("Carried") then
				actionRunning = false
				return false
			end
			if character:GetAttribute("Downed") then
				actionRunning = false
				return false
			end
			if character:GetAttribute("Carrying") then
				actionRunning = false
				return false
			end

			-- === STEP 1 CHECK ===
			local wallCheck1 = checkWall()

			local x = math.random(1, 2)

			if wallCheck1 and wallCheck1.Instance.CanCollide then
				climbDebounce = true
				fired = true
				-- show the climb cooldown (display only; climbDebounce is the real gate)
				CooldownTracker.Register("Climb", "Wall Jump", CLIMB_COOLDOWN)

				-- Fire Step 1
				script.RemoteEvent:FireServer(wallCheck1.Position, wallCheck1.Normal, "Step1", x)

				playSound()
				if script:FindFirstChild("Effect") then
					script.Effect:FireServer()
				end

				local dashEffect2 = game.ReplicatedStorage.assets.dashEff2:Clone()

				local eff = dashEffect2:Clone()
				for _, effect in pairs(eff:GetChildren()) do
					if effect:IsA("ParticleEmitter") then
						effect.Parent = character.Torso
						effect.EmissionDirection = Enum.NormalId.Bottom
						effect:Emit(9)
					elseif effect:IsA("Attachment") then
						effect.Parent = character.Torso
						effect:FindFirstChildWhichIsA("ParticleEmitter").EmissionDirection =
							Enum.NormalId.Bottom
						effect:FindFirstChildWhichIsA("ParticleEmitter"):Emit(9)
					end
				end

				-- === AUTOMATIC LEDGE DETECTION LOOP ===
				-- Instead of a flat wait, we loop and check for a ledge as the player rises
				local grabbedLedge = false
				for i = 1, 6 do -- Runs for approx 0.3 seconds (6 * 0.05)
					task.wait(0.05)

					-- Check for ledge with 'true' to bypass the "CantAnything" check
					-- because the server sets that attribute during the climb
					if detectLedge(true) then
						grabbedLedge = true
						break
					end
				end

				-- If we grabbed a ledge during the rise, we stop here.
				-- We do NOT proceed to Step 2.
				if grabbedLedge then
					climbDebounce = false
					actionRunning = false
					return true
				end

				-- === STEP 2 CHECK ===
				-- We check again because the player might have moved or the wall might have ended
				local wallCheck2 = checkWall()

				if wallCheck2 and wallCheck2.Instance.CanCollide then
					-- Fire Step 2
					playSound()
					script.RemoteEvent:FireServer(
						wallCheck2.Position,
						wallCheck2.Normal,
						"Step2",
						x
					)

					-- Optional: Check for ledge one last time during Step 2 rise
					task.delay(0.1, function()
						detectLedge(true)
					end)
				end

				task.wait(1.25) -- Cooldown before they can climb again
				climbDebounce = false
			end
		end
	end

	actionRunning = false
	return fired
end

-- Buffer a press that couldn't act. Skipped if one already succeeded inline.
local function bufferJumpAction()
	if not handleJumpAction() then
		bufferedAt = os.clock()
	end
end

-- PC/Console Support
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space then
		-- ARM ON AIRBORNE PRESS: if this fresh press happens while airborne, it's the
		-- "second tap" (or the post-wall-run tap) -- arm so the climb attempt can fire.
		-- A grounded press leaves armed false, so it stays a pure jump. (Releasing a
		-- ledge hang doesn't need arming -- handleJumpAction checks that case first.)
		if isAirborne() then
			armed = true
		end
		bufferJumpAction()
	end
end)

-- Mobile Support
if UserInputService.TouchEnabled then
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local touchGui = playerGui:WaitForChild("TouchGui")
		local jumpButton = touchGui:WaitForChild("TouchControlFrame"):WaitForChild("JumpButton")
		jumpButton.Activated:Connect(function()
			if isAirborne() then
				armed = true
			end
			bufferJumpAction()
		end)
	end)
end

-- Disarm on landing: touching the ground clears the arm so the next climb again needs a
-- fresh airborne press (or a wall run).
RunService.Heartbeat:Connect(function()
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		armed = false
	end
end)

-- Buffer retry: while a press is fresh AND no climb attempt is mid-flight, retry it.
-- Consume the buffer the instant one starts an action, or drop it when the window expires.
RunService.Heartbeat:Connect(function()
	if not bufferedAt then
		return
	end
	if os.clock() - bufferedAt > BUFFER_WINDOW then
		bufferedAt = nil
		return
	end
	if actionRunning then
		return
	end -- don't stack attempts while one is yielding
	if handleJumpAction() then
		bufferedAt = nil
	end
end)

-- [[ HOLD-TO-CATCH LEDGE GRAB ]]
-- Per-frame ledge catching, but ONLY while the jump key is actively held AND you're armed.
-- This makes the grab timing forgiving (you don't have to frame-perfectly tap at the
-- ledge) without the auto-grab problem where you snap onto a ledge you were trying to
-- fall past, and without a ground press leaking into a grab (armed is false on the ground).
--
-- It deliberately only acts when canVault is true (not already hanging) -- calling
-- detectLedge while hanging would RELEASE the hang, so the hold loop must never run then.
-- It also stays out of the way during the wall-climb sequence (climbDebounce / actionRunning).
local HOLD_KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true }

local function isHoldingCatch()
	for key in pairs(HOLD_KEYS) do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function()
	-- Not while hanging (would toggle release), not mid wall-climb, not on cooldown.
	if not canVault then
		return
	end
	if actionRunning or climbDebounce then
		return
	end
	if not isHoldingCatch() then
		return
	end

	-- Same airborne gate the manual grab uses.
	if not isAirborne() then
		return
	end

	-- A wall run can arm us; pull that in. Then require armed -- no catch off a ground hold.
	consumeWallRunArm()
	if not armed then
		return
	end

	-- Transient blocks: don't try to catch while disabled. detectLedge re-checks these too,
	-- but bailing here avoids spamming it every frame.
	if character:GetAttribute("Stunned") then
		return
	end
	if character:GetAttribute("Carried") then
		return
	end
	if character:GetAttribute("Downed") then
		return
	end
	if character:GetAttribute("Carrying") then
		return
	end
	if character:GetAttribute("CantAnything") then
		return
	end

	-- detectLedge does all the surface validation + grab. canVault is here true, so this
	-- can only ever GRAB, never release.
	detectLedge(false)
end)
