-- SPDX-License-Identifier: MIT
--
-- Applies fall damage that the client reports. A roll reduces it, and a fall that
-- would kill knocks the player down instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage").remotes

local fallEvent = ReplicatedStorage:WaitForChild("FallDmg")

local MIN_FALL_DAMAGE_HEIGHT = 30
local FATAL_FALL_HEIGHT = 200
local ROLL_DAMAGE_REDUCTION = 0.75

local ragdoll = require(game.ServerScriptService.modules.ragdollManager)
local stateHandler = require(game.ReplicatedStorage.modules.stateHandler)
local DownedManager = require(game.ServerScriptService.modules.DownedManager)

local function calculateDamage(height)
	if height < MIN_FALL_DAMAGE_HEIGHT then
		return 0
	end

	local damageRatio = (height - MIN_FALL_DAMAGE_HEIGHT)
		/ (FATAL_FALL_HEIGHT - MIN_FALL_DAMAGE_HEIGHT)
	local damage = damageRatio * 100

	return math.clamp(damage, 0, 1000)
end

fallEvent.OnServerEvent:Connect(function(player, clientCalculatedDistance, isRolling)
	local character = player.Character
	if not character then
		return
	end

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

	local baseDamage = calculateDamage(clientCalculatedDistance)

	if baseDamage > 5 then
		if isRolling then
			local reducedDamage = baseDamage * (1 - ROLL_DAMAGE_REDUCTION)

			if reducedDamage > 10 then
				humanoid:TakeDamage(reducedDamage)
			end

			local eff = game.ReplicatedStorage.assets.FX.DUST:Clone()
			eff.Parent = character["Right Leg"]
			eff:Emit(10)
			local eff2 = game.ReplicatedStorage.assets.FX.DUST:Clone()
			eff2.Parent = character["Left Leg"]
			eff2:Emit(10)
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
			sound.Parent = character.HumanoidRootPart
			sound:Play()
			game.Debris:AddItem(sound, sound.TimeLength + 1)

			local eff = game.ReplicatedStorage.assets.FX.DUST:Clone()
			eff.Parent = character["Right Leg"]
			eff:Emit(10)
			local eff2 = game.ReplicatedStorage.assets.FX.DUST:Clone()
			eff2.Parent = character["Left Leg"]
			eff2:Emit(10)

			if not willDown then
				ragdoll.Ragdoll(character, 1)
				stateHandler.SetStun(character, true, 1)
			end
		end
	end
end)
