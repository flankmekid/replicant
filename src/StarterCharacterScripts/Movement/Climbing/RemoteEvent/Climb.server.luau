local animHandler = require(game.ReplicatedStorage.modules.animationHandler)
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)

-- Track cleanup tasks per player so Step 2 can cancel Step 1's cleanup
local cleanupTasks = {}

script.Parent.OnServerEvent:connect(function(player, hitPos, hitNormal, stepName, x)
	local char = player.Character
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")

	if not hrp or not hum then return end

	-- If it's Step 1, we do fresh checks. If Step 2, we bypass stun checks to ensure flowiness
	if stepName == "Step1" then
		if stateHandler.GetState(char, "CantAnything") then return end
		if stateHandler.GetState(char, "Stunned") then return end
	end

	-- Cancel any pending cleanup from a previous step (so we don't fall mid-climb)
	if cleanupTasks[player] then
		task.cancel(cleanupTasks[player])
		cleanupTasks[player] = nil
	end

	-- Remove old movers immediately to apply new forces
	for _, child in pairs(hrp:GetChildren()) do
		if child.Name == "ClimbVelocity" or child.Name == "ClimbGyro" then
			child:Destroy()
		end
	end

	-- 1. SETUP STATE
	stateHandler.SetState(char, "CantAnything", true, 0.5)
	hum.AutoRotate = false
	hum.WalkSpeed = 0 

	-- 2. SNAP ORIENTATION
	local bg = Instance.new("BodyGyro")
	bg.Name = "ClimbGyro"
	bg.P = 50000 
	bg.MaxTorque = Vector3.new(400000, 400000, 400000)
	bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position - hitNormal)
	bg.Parent = hrp

	-- 3. APPLY VELOCITY & ANIMATION BASED ON STEP
	local bv = Instance.new("BodyVelocity")
	bv.Name = "ClimbVelocity"
	bv.MaxForce = Vector3.new(100000, 100000, 100000) 
	bv.Parent = hrp

	if stepName == "Step1" then
		-- == STEP 1 LOGIC ==
		-- Strong initial burst
		bv.Velocity = Vector3.new(0, 50, 0) 

		-- REPLACE WITH YOUR ANIMATION ID FOR STEP 1
		if x == 1 then
			animHandler.LoadAnim(char, "ClimbStep1", "rbxassetid://118025182512218", nil, false)
		else
			animHandler.LoadAnim(char, "ClimbStep2", "rbxassetid://91901047304475", nil, false)
		end

		-- Physics decay for Step 1
		task.spawn(function()
			for i = 1, 5 do
				if not bv.Parent then break end
				task.wait(0.05)
				bv.Velocity = bv.Velocity * 0.8 
			end
		end)

	elseif stepName == "Step2" then
		-- == STEP 2 LOGIC ==
		-- Secondary burst (maybe slightly higher or same as step 1)
		bv.Velocity = Vector3.new(0, 45, 0) 
		
		animHandler.StopAnim(char, "ALL")

		-- REPLACE WITH YOUR ANIMATION ID FOR STEP 2
		if x == 1 then
			animHandler.LoadAnim(char, "ClimbStep2", "rbxassetid://91901047304475", nil, false)
		else
			animHandler.LoadAnim(char, "ClimbStep1", "rbxassetid://118025182512218", nil, false)
		end


		-- Physics decay for Step 2
		task.spawn(function()
			for i = 1, 5 do
				if not bv.Parent then break end
				task.wait(0.05)
				bv.Velocity = bv.Velocity * 0.75
			end
			if bv.Parent then bv.Velocity = Vector3.zero end
		end)
	end

	-- 4. CLEANUP (Scheduled)
	-- We store this task so if Step 2 fires quickly, we can cancel Step 1's cleanup
	cleanupTasks[player] = task.delay(0.25, function()
		if bg then bg:Destroy() end
		if bv then bv:Destroy() end
		hum.AutoRotate = true
		hum.WalkSpeed = 16 -- Reset to default (or handle getting original speed)
		cleanupTasks[player] = nil
	end)
end)