local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

-- CONFIGURATION
local REGEN_RATE = 1          -- How much health to restore per tick
local REGEN_FREQUENCY = 0.25  -- How often to heal (in seconds)
local WAIT_TIME = 30          -- How long to wait after taking damage (in seconds)

local lastDamageTime = 0      -- Timestamp of the last hit
local currentHealth = humanoid.Health

-- Detect when health changes to determine if damage was taken
humanoid.HealthChanged:Connect(function(newHealth)
	-- If health went DOWN, it means we took damage
	if newHealth < currentHealth then
		lastDamageTime = os.time() -- Reset the timer
	end

	-- Update our tracker so we know the new baseline
	currentHealth = newHealth
end)

-- The Loop
while true do
	task.wait(REGEN_FREQUENCY)

	-- Check 1: Is the player alive?
	if humanoid.Health <= 0 then continue end

	-- Check 2: Are they missing health?
	if humanoid.Health >= humanoid.MaxHealth then continue end

	-- Check 3: Has it been long enough since the last hit?
	if (os.time() - lastDamageTime) >= WAIT_TIME and not character:GetAttribute("Downed") then

		-- [[ NEW LOGIC ]] --
		-- Get the multiplier from the Character Attribute (defaults to 1 if missing)
		local mult = character:GetAttribute("RegenMultiplier") or 1

		-- Calculate final heal amount
		local finalHeal = REGEN_RATE * mult

		-- Heal the player
		humanoid.Health = math.min(humanoid.Health + finalHeal, humanoid.MaxHealth)

		-- Update tracker immediately so the heal doesn't confuse the damage detector logic
		currentHealth = humanoid.Health 
	end
end