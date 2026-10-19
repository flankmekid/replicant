-- SPDX-License-Identifier: MIT
--
-- Applies fall damage. The server finds each landing itself with a ground ray and
-- measures the fall from the takeoff height, so a client cannot skip the damage. The
-- client report only adds the roll and the falls the server cannot measure, such as a
-- drop from a climb. A roll reduces the damage, and a fall that would kill knocks the
-- player down instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage").remotes

local fallEvent = ReplicatedStorage:WaitForChild("FallDmg")

local minFallDamageHeight = 30
local fatalFallHeight = 200
local rollDamageReduction = 0.75

-- An R6 root part rests about 3 studs above the floor.
local groundRayLength = 4.5
-- A larger height change in one step is a teleport, not a fall.
local teleportStep = 50
-- The client reports its landing about when the server sees it. A report counts this many
-- seconds around the server landing, and the server waits this long for it.
local reportWindow = 0.75
local reportWait = 0.3

local ragdoll = require(game.ServerScriptService.modules.ragdollManager)
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local DownedManager = require(game.ServerScriptService.modules.DownedManager)

local function calculateDamage(height)
	if height < minFallDamageHeight then
		return 0
	end

	local damageRatio = (height - minFallDamageHeight) / (fatalFallHeight - minFallDamageHeight)
	local damage = damageRatio * 100

	return math.clamp(damage, 0, 1000)
end

-- Puffs dust from both legs. A rig without R6 legs gets no dust.
local function emitDust(character)
	for _, legName in ipairs({ "Right Leg", "Left Leg" }) do
		local leg = character:FindFirstChild(legName)
		if leg then
			local eff = game.ReplicatedStorage.assets.FX.DUST:Clone()
			eff.Parent = leg
			eff:Emit(10)
		end
	end
end

local function applyFall(character, fallDistance, isRolling)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if stateHandler.GetState(character, "Sliding") == true then
		return
	end

	-- A downed player is not hit again.
	if stateHandler.GetState(character, "Downed") then
		return
	end

	local baseDamage = calculateDamage(fallDistance)

	if baseDamage > 5 then
		if isRolling then
			local reducedDamage = baseDamage * (1 - rollDamageReduction)

			if reducedDamage > 10 then
				humanoid:TakeDamage(reducedDamage)
			end

			emitDust(character)
		else
			local willDown = (baseDamage > (0.9 * humanoid.MaxHealth))
				or (humanoid.Health - baseDamage <= 0)

			if willDown then
				humanoid.Health = math.max(5, humanoid.MaxHealth * 0.1)
				DownedManager.KnockDown(character)
			else
				humanoid:TakeDamage(baseDamage)
			end

			DownedManager.DropIfCarrying(character)

			local sound = game.ReplicatedStorage.assets.sounds.Bonebreak:Clone()
			sound.Parent = character:FindFirstChild("HumanoidRootPart") or character
			sound:Play()
			game.Debris:AddItem(sound, sound.TimeLength + 1)

			emitDust(character)

			if not willDown then
				ragdoll.Ragdoll(character, 1)
				stateHandler.SetStun(character, true, 1)
			end
		end
	end
end

-- The last landing each client reported.
local reports = {}

fallEvent.OnServerEvent:Connect(function(player, clientDistance, isRolling)
	if typeof(clientDistance) ~= "number" or clientDistance ~= clientDistance then
		return
	end
	reports[player] = {
		time = os.clock(),
		distance = clientDistance,
		rolling = isRolling == true,
	}
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Returns whether the root part is over a floor, and whether that floor is water.
local function probeGround(character, root)
	rayParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -groundRayLength, 0), rayParams)
	if not result then
		return false, false
	end
	return true, result.Material == Enum.Material.Water
end

local function onLanded(player, character, serverDistance)
	local landedAt = os.clock()
	task.wait(reportWait)
	if player.Character ~= character then
		return
	end

	-- The client measures from its own Freefall start, which can be higher than the
	-- server takeoff, for example after a climb. A report never lowers the distance.
	local distance = serverDistance
	local isRolling = false
	local report = reports[player]
	if report and math.abs(report.time - landedAt) <= reportWindow then
		distance = math.max(distance, report.distance)
		isRolling = report.rolling
		reports[player] = nil
	end

	applyFall(character, distance, isRolling)
end

-- Layout: tracked[character] = { airborne, startY, lastY }.
local tracked = setmetatable({}, { __mode = "k" })

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end

		local y = root.Position.Y
		local t = tracked[character]
		if not t then
			t = { airborne = false, startY = y, lastY = y }
			tracked[character] = t
		end

		local teleported = math.abs(y - t.lastY) > teleportStep
		t.lastY = y
		local grounded, inWater = probeGround(character, root)

		-- No fall counts in the menu, in a ragdoll, or across a teleport.
		if
			teleported
			or not player:GetAttribute("HasPressedPlay")
			or stateHandler.GetState(character, "Ragdolled")
		then
			t.startY = y
			t.airborne = not grounded
		elseif not grounded then
			if not t.airborne then
				t.airborne = true
				t.startY = y
			end
		elseif t.airborne then
			t.airborne = false
			if not inWater then
				task.spawn(onLanded, player, character, t.startY - y)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	reports[player] = nil
end)
