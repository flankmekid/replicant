-- SPDX-License-Identifier: MIT
--
-- Server side of the two-step wall climb: faces the character to the wall, gives the
-- upward burst for each step, plays the climb animation, and cleans up after.

local animHandler = require(game.ReplicatedStorage.modules.animationHandler)
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)

-- The cleanup task of each player, so step 2 can cancel the cleanup of step 1.
local cleanupTasks = {}

script.Parent.OnServerEvent:connect(function(player, hitPos, hitNormal, stepName, x)
	local char = player.Character
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")

	if not hrp or not hum then
		return
	end

	-- Step 1 checks the state. Step 2 skips it, so the climb flows.
	if stepName == "Step1" then
		if stateHandler.GetState(char, "CantAnything") then
			return
		end
		if stateHandler.GetState(char, "Stunned") then
			return
		end
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
	hum.WalkSpeed = 0

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
		-- FIXME: This writes WalkSpeed directly, but SpeedService owns it.
		hum.WalkSpeed = 16
		cleanupTasks[player] = nil
	end)
end)
