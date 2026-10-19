-- SPDX-License-Identifier: MIT
--
-- Regenerates the character's HP when it has taken no damage for waitTime seconds,
-- scaled by the race RegenMultiplier. A downed character does not regenerate.

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

-- HP per tick.
local regenRate = 1
-- Seconds between ticks.
local regenFrequency = 0.25
-- Seconds without damage before regeneration starts.
local waitTime = 30

-- The os.time() of the last hit.
local lastDamageTime = 0
local currentHealth = humanoid.Health

-- A drop in HP counts as damage.
humanoid.HealthChanged:Connect(function(newHealth)
	if newHealth < currentHealth then
		lastDamageTime = os.time()
	end

	currentHealth = newHealth
end)

while true do
	task.wait(regenFrequency)

	if humanoid.Health <= 0 then
		continue
	end

	if humanoid.Health >= humanoid.MaxHealth then
		continue
	end

	if (os.time() - lastDamageTime) >= waitTime and not character:GetAttribute("Downed") then
		local mult = character:GetAttribute("RegenMultiplier") or 1

		local finalHeal = regenRate * mult

		humanoid.Health = math.min(humanoid.Health + finalHeal, humanoid.MaxHealth)

		-- Update the tracked HP, so the heal does not look like damage or healing to the
		-- damage check.
		currentHealth = humanoid.Health
	end
end
