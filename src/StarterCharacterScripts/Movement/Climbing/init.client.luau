-- SPDX-License-Identifier: MIT
--
-- Client side of climbing: ledge grabs, the two-step wall climb, the jump input buffer,
-- and hold-to-catch. The arming rules are in docs/systems-design.md.

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")

local ClientCameraShake =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("ClientCameraShake"))
local CooldownTracker =
	require(game.ReplicatedStorage:WaitForChild("modules"):WaitForChild("CooldownTracker"))

local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = { character }
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local canVault = true
local vaultConnection = nil
local ledgePart = nil
local climbDebounce = false

-- A climb needs the player airborne and armed. A press in the air arms, a wall run
-- arms, and touching the ground disarms, so a single ground press is only a jump.
local armed = false

-- Uses up the arm that a wall run gives (WallRanRecently). Returns true if it armed.
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

-- The climb cooldown in seconds, for the HUD. It matches the task.wait in the climb.
local climbCooldown = 1.25

-- The thinnest part side that can be a ledge, in studs. Rejects railings and blades.
local minLedgeThickness = 0.5
-- A more transparent part cannot be a ledge.
local maxLedgeTransparency = 0.5

local grabAnim = humanoid:LoadAnimation(script:WaitForChild("Grab"))
grabAnim.Priority = Enum.AnimationPriority.Action4

local grabSounds = script:WaitForChild("Sounds"):GetChildren()

local function playSound()
	local sound = grabSounds[math.random(1, #grabSounds)]:Clone()
	sound.Parent = rootPart
	sound.Volume = 0.35
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Returns whether the player may hang on a part. Characters, NPCs, and their gear
-- (including weapons, which are Tools in the character), see-through or non-collidable
-- parts, and very thin parts are not ledges.
local function isValidLedgeSurface(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	-- Anything under a model with a Humanoid is a creature or its gear.
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then
			return false
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end

	-- Loose tools in the world are gear too.
	if part:FindFirstAncestorWhichIsA("Tool") then
		return false
	end

	if part.Transparency > maxLedgeTransparency then
		return false
	end
	if not part.CanCollide then
		return false
	end

	-- Check the smallest side. A thin wall is still tall and wide, so it passes.
	local sz = part.Size
	if math.min(sz.X, sz.Y, sz.Z) < minLedgeThickness then
		return false
	end

	return true
end

-- Returns true if nothing blocks the space above the ledge.
local function partCheck(ledge)
	local vaultPartCheck =
		workspace:Raycast(ledge.Position + ledge.LookVector * 1, ledge.UpVector * 3, raycastParams)
	return vaultPartCheck == nil
end

-- Grabs a ledge in front of the head, or lets go when already hanging. bypassChecks
-- allows a grab during the wall climb, when the server sets CantAnything.
local function detectLedge(bypassChecks)
	-- Already hanging: let go.
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

		-- Cast at head height and 1 stud above and below, so a ledge near the head still
		-- counts. The first valid surface wins, and an invalid hit tries the next height.
		local ledgeVerticalLeeway = 1
		local vaultCheck = nil
		for _, yOff in ipairs({ 0, ledgeVerticalLeeway, -ledgeVerticalLeeway }) do
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

local function checkWall()
	local rayOrigin = head.Position
	local rayDirection = rootPart.CFrame.lookVector * 3
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

-- A press that cannot act now is buffered and retried for bufferWindow seconds, like
-- the dash. handleJumpAction yields through the climb, so actionRunning keeps a second
-- attempt from starting during the first.
local bufferWindow = 0.5
local bufferedAt = nil
local actionRunning = false

-- Returns true if a climb or ledge action started, false if it was rejected.
local function handleJumpAction()
	if actionRunning then
		return false
	end

	-- Letting go of a ledge is not a climb, so it comes before the armed check: while
	-- hanging the player is Seated, not airborne.
	if not canVault then
		detectLedge(false)
		return true
	end

	-- Without the arm, the press is only the normal jump.
	if not isAirborne() then
		return false
	end
	consumeWallRunArm()
	if not armed then
		return false
	end

	actionRunning = true

	local fired = false

	local ledgeFound = detectLedge(false)
	if ledgeFound then
		actionRunning = false
		return true
	end

	-- No ledge: try the wall climb.
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

			local wallCheck1 = checkWall()

			local x = math.random(1, 2)

			if wallCheck1 and wallCheck1.Instance.CanCollide then
				climbDebounce = true
				fired = true
				-- The HUD only shows the cooldown. climbDebounce is the real gate.
				CooldownTracker.Register("Climb", "Wall Jump", climbCooldown)

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

				-- Look for a ledge during the rise, for about 0.3 seconds.
				local grabbedLedge = false
				for i = 1, 6 do
					task.wait(0.05)

					-- Bypass the CantAnything check, because the server sets it during the climb.
					if detectLedge(true) then
						grabbedLedge = true
						break
					end
				end

				-- A ledge grab ends the climb before step 2.
				if grabbedLedge then
					climbDebounce = false
					actionRunning = false
					return true
				end

				-- Check the wall again: the player may have moved or the wall may have ended.
				local wallCheck2 = checkWall()

				if wallCheck2 and wallCheck2.Instance.CanCollide then
					playSound()
					script.RemoteEvent:FireServer(
						wallCheck2.Position,
						wallCheck2.Normal,
						"Step2",
						x
					)

					-- One more ledge check during the step 2 rise.
					task.delay(0.1, function()
						detectLedge(true)
					end)
				end

				task.wait(1.25)
				climbDebounce = false
			end
		end
	end

	actionRunning = false
	return fired
end

-- Buffers a press that could not act.
local function bufferJumpAction()
	if not handleJumpAction() then
		bufferedAt = os.clock()
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space then
		-- A fresh press in the air arms the climb. A press on the ground stays a jump.
		if isAirborne() then
			armed = true
		end
		bufferJumpAction()
	end
end)

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

-- Touching the ground disarms.
RunService.Heartbeat:Connect(function()
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		armed = false
	end
end)

-- Retry a buffered press while no attempt is running, until the window ends.
RunService.Heartbeat:Connect(function()
	if not bufferedAt then
		return
	end
	if os.clock() - bufferedAt > bufferWindow then
		bufferedAt = nil
		return
	end
	if actionRunning then
		return
	end
	if handleJumpAction() then
		bufferedAt = nil
	end
end)

-- Hold-to-catch: while the jump key is held and the player is armed, try to grab a
-- ledge every frame, so the timing is forgiving. It never runs while hanging, because
-- detectLedge would let go, and it stays out of the wall climb.
local holdKeys = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true }

local function isHoldingCatch()
	for key in pairs(holdKeys) do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function()
	if not canVault then
		return
	end
	if actionRunning or climbDebounce then
		return
	end
	if not isHoldingCatch() then
		return
	end

	if not isAirborne() then
		return
	end

	consumeWallRunArm()
	if not armed then
		return
	end

	-- The same checks are in detectLedge, but stopping here avoids a call every frame.
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

	-- Here canVault is true, so detectLedge can only grab, never let go.
	detectLedge(false)
end)
