-- SPDX-License-Identifier: MIT
--
-- Server side of the two-step wall climb: faces the character to the wall, gives the
-- upward burst for each step, plays the climb animation, and cleans up after.

local animHandler = require(game.ReplicatedStorage.modules.animationHandler)
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local SpeedService = require(game.ServerScriptService.modules.SpeedService)

-- The cleanup task of each player, so step 2 can cancel the cleanup of step 1.
local cleanupTasks = {}

-- Every step is a burst upward, so the server checks what the client claims. The climb
-- client waits climbCooldown (1.25 s) between climbs and sends step 2 about 0.3 s after
-- step 1. The windows below add latency slack.
local stepOneInterval = 1.1
local stepTwoWindow = 1
-- The client finds the wall 3 studs ahead of the head.
local wallReach = 6

-- Layout: lastStepOne[player] = os.clock() of the last accepted step 1.
local lastStepOne = {}
-- The players whose accepted step 1 still allows one step 2.
local stepTwoOpen = {}

-- Every character has its own copy of this script and its remote, so a copy serves only
-- the player of its own character.
local ownerChar = script:FindFirstAncestorOfClass("Model")

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude

-- Returns true if a collidable wall is within reach behind hitNormal.
local function hasWall(char, origin, hitNormal)
	wallParams.FilterDescendantsInstances = { char }
	local result = workspace:Raycast(origin, -hitNormal.Unit * wallReach, wallParams)
	return result ~= nil and result.Instance.CanCollide
end

script.Parent.OnServerEvent:Connect(function(player, hitPos, hitNormal, stepName, x)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChild("Humanoid")

	if not hrp or not hum or char ~= ownerChar then
		return
	end
	if stepName ~= "Step1" and stepName ~= "Step2" then
		return
	end
	if typeof(hitNormal) ~= "Vector3" or hitNormal.Magnitude < 0.5 then
		return
	end

	local now = os.clock()
	if stepName == "Step1" then
		if stateHandler.GetState(char, "CantAnything") then
			return
		end
		if stateHandler.GetState(char, "Stunned") then
			return
		end
		if lastStepOne[player] and now - lastStepOne[player] < stepOneInterval then
			return
		end
	else
		-- Step 2 skips the state checks, because step 1 set CantAnything, but it needs a
		-- fresh step 1.
		if not stepTwoOpen[player] or now - lastStepOne[player] > stepTwoWindow then
			return
		end
	end

	local head = char:FindFirstChild("Head")
	if not hasWall(char, head and head.Position or hrp.Position, hitNormal) then
		return
	end

	if stepName == "Step1" then
		lastStepOne[player] = now
		stepTwoOpen[player] = true
	else
		stepTwoOpen[player] = nil
	end

	-- Cancel the cleanup of the previous step, so the player does not fall mid-climb.
	if cleanupTasks[player] then
		task.cancel(cleanupTasks[player])
		cleanupTasks[player] = nil
	end

	for _, child in pairs(hrp:GetChildren()) do
		if child.Name == "ClimbVelocity" or child.Name == "ClimbGyro" then
			child:Destroy()
		end
	end

	stateHandler.SetState(char, "CantAnything", true, 0.5)
	hum.AutoRotate = false
	SpeedService.Push(char, "Climb", 0, SpeedService.Priority.SKILL)

	local bg = Instance.new("BodyGyro")
	bg.Name = "ClimbGyro"
	bg.P = 50000
	bg.MaxTorque = Vector3.new(400000, 400000, 400000)
	bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position - hitNormal)
	bg.Parent = hrp

	local bv = Instance.new("BodyVelocity")
	bv.Name = "ClimbVelocity"
	bv.MaxForce = Vector3.new(100000, 100000, 100000)
	bv.Parent = hrp

	if stepName == "Step1" then
		bv.Velocity = Vector3.new(0, 50, 0)

		if x == 1 then
			animHandler.LoadAnim(char, "ClimbStep1", "rbxassetid://118025182512218", nil, false)
		else
			animHandler.LoadAnim(char, "ClimbStep2", "rbxassetid://91901047304475", nil, false)
		end

		-- The burst decays over 0.25 seconds.
		task.spawn(function()
			for i = 1, 5 do
				if not bv.Parent then
					break
				end
				task.wait(0.05)
				bv.Velocity = bv.Velocity * 0.8
			end
		end)
	elseif stepName == "Step2" then
		bv.Velocity = Vector3.new(0, 45, 0)

		animHandler.StopAnim(char, "ALL")

		if x == 1 then
			animHandler.LoadAnim(char, "ClimbStep2", "rbxassetid://91901047304475", nil, false)
		else
			animHandler.LoadAnim(char, "ClimbStep1", "rbxassetid://118025182512218", nil, false)
		end

		-- The burst decays over 0.25 seconds and then stops.
		task.spawn(function()
			for i = 1, 5 do
				if not bv.Parent then
					break
				end
				task.wait(0.05)
				bv.Velocity = bv.Velocity * 0.75
			end
			if bv.Parent then
				bv.Velocity = Vector3.zero
			end
		end)
	end

	cleanupTasks[player] = task.delay(0.25, function()
		if bg then
			bg:Destroy()
		end
		if bv then
			bv:Destroy()
		end
		hum.AutoRotate = true
		SpeedService.Pop(char, "Climb")
		cleanupTasks[player] = nil
	end)
end)

game.Players.PlayerRemoving:Connect(function(player)
	lastStepOne[player] = nil
	stepTwoOpen[player] = nil
end)
