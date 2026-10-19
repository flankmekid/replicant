-- 0xdawid (discord) | flankmekid (github & roblox)

local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local MobConfig = require(script.Parent.MobConfig)
local MobAI = require(script.Parent.MobAI)
local BossAI = require(script.Parent.BossAI)

-- mob setups

pcall(function()
	PhysicsService:RegisterCollisionGroup("Mobs")
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("Mobs", "Mobs", false)
end)

local SpawnersFolder = workspace:FindFirstChild("Spawners")
if not SpawnersFolder then
	warn("[MobServer] No 'Spawners' folder found in Workspace.")
	return
end

local ActiveMobs = {} -- array of mob objects

local function randomPositionInPart(part)
	local sx = part.Size.X / 2
	local sz = part.Size.Z / 2
	local offset =
		Vector3.new(math.random(-sx * 10, sx * 10) / 10, 0, math.random(-sz * 10, sz * 10) / 10)
	local worldPos = part.CFrame * CFrame.new(offset)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { part }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result =
		workspace:Raycast(worldPos.Position + Vector3.new(0, 5, 0), Vector3.new(0, -50, 0), params)
	if result then
		return CFrame.new(result.Position + Vector3.new(0, 2, 0))
			* CFrame.fromEulerAnglesXYZ(0, math.random(0, 628) / 100, 0)
	end
	return worldPos * CFrame.new(0, 2, 0)
end

local function spawnFromZone(mobName, zone)
	local cfg = MobConfig.Mobs[mobName]
	if not cfg then
		return
	end

	local quantity = zone:FindFirstChild("Quantity") and zone.Quantity.Value or 1

	for i = 1, quantity do
		local spawnCFrame = randomPositionInPart(zone)
		local mob

		if cfg.IsBoss then
			mob = BossAI.Spawn(mobName, spawnCFrame)
		else
			mob = MobAI.Spawn(mobName, spawnCFrame)
		end

		if mob then
			mob.Respawn = function(self)
				task.wait(1)

				local newSpawnCFrame = randomPositionInPart(zone)
				local newMob

				if cfg.IsBoss then
					newMob = BossAI.Spawn(mobName, newSpawnCFrame)
				else
					newMob = MobAI.Spawn(mobName, newSpawnCFrame)
				end

				if newMob then
					newMob.Respawn = self.Respawn
					table.insert(ActiveMobs, newMob)
				else
					warn("[MobServer] Respawn failed for: " .. mobName)
				end

				for idx, m in ipairs(ActiveMobs) do
					if m == self then
						table.remove(ActiveMobs, idx)
						break
					end
				end
			end

			table.insert(ActiveMobs, mob)
		end
	end
end

for _, categoryFolder in ipairs(SpawnersFolder:GetChildren()) do
	if not categoryFolder:IsA("Folder") then
		continue
	end
	local mobName = categoryFolder.Name
	if not MobConfig.Mobs[mobName] then
		warn("[MobServer] No config entry for spawner: " .. mobName)
		continue
	end
	for _, zone in ipairs(categoryFolder:GetChildren()) do
		if zone:IsA("BasePart") then
			spawnFromZone(mobName, zone)
		end
	end
end

local function applyPlayerCollision(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				PhysicsService:SetPartCollisionGroup(part, "Players")
			end)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait()
		applyPlayerCollision(character)
	end)
	if player.Character then
		task.wait()
		applyPlayerCollision(player.Character)
	end
end)

RunService.Heartbeat:Connect(function()
	for _, mob in ipairs(ActiveMobs) do
		if not mob.Dead then
			local cfg = MobConfig.Mobs[mob.Name]
			if cfg and cfg.IsBoss then
				BossAI.Update(mob)
			else
				MobAI.Update(mob)
			end
		end
	end
end)

print("[MobServer] Initialised. " .. #ActiveMobs .. " mobs spawned.")
