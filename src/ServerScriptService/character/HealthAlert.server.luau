local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Ensure the Remote exists
local AlertRemote = ReplicatedStorage:FindFirstChild("HealthAlertEvent") 
if not AlertRemote then
	AlertRemote = Instance.new("RemoteEvent")
	AlertRemote.Name = "HealthAlertEvent"
	AlertRemote.Parent = ReplicatedStorage
end

-- [[ RACE CONFIGURATION ]] --
local RaceAlertConfig = {
	-- [[ COMMON ]] --
	["Human"] = { 
		Threshold = 0.2, 
		Messages = {
			"My resolve... is not yet broken.",
			"Just a scratch... keep fighting!",
			"I will not be another forgotten name.",
			"Push through the pain!"
		} 
	},
	["Elezen"] = { 
		Threshold = 0.3,
		Messages = {
			"The pages are tearing...",
			"My concentration wavers!",
			"Return me to the earth...",
			"Nature cannot protect me forever."
		} 
	},
	["Grob"] = { 
		Threshold = 0.35,
		Messages = {
			"No! My loot! Mine!",
			"Too broken... run away! Hide!",
			"Fix it! Someone fix me!",
			"Not worth the shiny things... retreat!"
		} 
	},

	-- [[ UNCOMMON ]] --
	["Verdis"] = { 
		Threshold = 0.25, 
		Messages = {
			"My roots are bleeding...",
			"The experiment... is failing.",
			"I must regrow... retreat...",
			"The forest mourns my weakness."
		} 
	},
	["Arach"] = { 
		Threshold = 0.2, 
		Messages = {
			"The web snaps...",
			"My venom runs dry.",
			"Scuttle away... into the shadows...",
			"Too many eyes... all closing..."
		} 
	},

	-- [[ RARE ]] --
	["Cruor"] = { 
		Threshold = 0.15, 
		Messages = {
			"Need... more... meat...",
			"The stitches are coming loose.",
			"This vessel is failing.",
			"Blood... I need blood..."
		} 
	},
	["Karu"] = { 
		Threshold = 0.15, -- Very sturdy, so warning feels significant
		Messages = {
			"Even the mountain crumbles...",
			"Cracks in the foundation...",
			"I can still stand... I must stand.",
			"My horns remain unbroken!"
		} 
	},
	["Meskar"] = { 
		Threshold = 0.3, -- Very fragile
		Messages = {
			"Bones shatter so easily...",
			"This form is too weak...",
			"The ritual is interrupted.",
			"I fade... like dust."
		} 
	},

	-- [[ EPIC ]] --
	["Marasi"] = { 
		Threshold = 0.2, 
		Messages = {
			"Blood in the water... my blood...",
			"The tide turns against me.",
			"Keep swimming... or sink.",
			"I smell my own fear."
		} 
	},
	["Seer"] = { 
		Threshold = 0.25, 
		Messages = {
			"The vision blurs...",
			"I did not foresee this pain.",
			"The Eye closes...",
			"My future... is dark."
		} 
	},

	-- [[ LEGENDARY ]] --
	["Maw"] = { 
		Threshold = 0.2, -- Berserker
		Messages = {
			"THE VOID LEAKS OUT.",
			"CONSUME... OR FADE AWAY.",
			"EMPTY... SO EMPTY...",
			"THE HUNGER... IT HURTS..."
		} 
	},
	["Ancestor"] = { 
		Threshold = 0.2, 
		Messages = {
			"Does my lineage end here?",
			"The halo dims...",
			"Forgive my weakness...",
			"Grace has left me."
		} 
	},
	["Aegir"] = { 
		Threshold = 0.25, 
		Messages = {
			"My scales are cracking.",
			"Drowning... on dry land...",
			"The depths call me back.",
			"My glory fades..."
		} 
	},

	-- [[ FALLBACK ]] --
	["Default"] = { 
		Threshold = 0.2, 
		Messages = {
			"CRITICAL CONDITION.",
			"SYSTEM FAILURE IMMINENT.",
			"VITAL SIGNS FAILING."
		} 
	}
}

-- Track state so we don't spam the remote
local panicState = {} -- [Player] = boolean

local function MonitorCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local stats = player:WaitForChild("PlayerStats", 10)

	-- Resolve the panic config LIVE, every evaluation. Capturing it once at spawn
	-- meant a mid-game race switch (no death/respawn, so no CharacterAdded, so no
	-- re-init) kept firing the PREVIOUS race's messages and threshold. Reading
	-- Race.Value here makes a race change take effect immediately with no re-init.
	local function currentConfig()
		local raceName = "Human"
		if stats and stats:FindFirstChild("Race") then
			raceName = stats.Race.Value
		end
		return RaceAlertConfig[raceName] or RaceAlertConfig["Default"]
	end

	panicState[player] = false

	-- Single debounced evaluator. Both MaxHealth and Health changes schedule one
	-- deferred re-check against SETTLED values and cancel any pending one. This
	-- removes the old dependency on signal-fire ordering: the transient mid-write
	-- frame (a Vitality point raises MaxHealth first, Health a line later in
	-- mainGameHandler) is never evaluated on its own, only the final state is.
	-- Kills the phantom low-HP text on level-up.
	local pending = false

	local function evaluate()
		local maxHealth = humanoid.MaxHealth
		if maxHealth <= 0 then return end

		local health = humanoid.Health
		local percentage = health / maxHealth
		local config = currentConfig()

		-- [[ STATE LOGIC ]] --
		if percentage <= config.Threshold and percentage > 0 then
			-- Enter Panic Mode
			if not panicState[player] then
				panicState[player] = true
				-- Send "Start" and the list of messages for the client to use
				AlertRemote:FireClient(player, "Start", config.Messages)
			end

		elseif percentage > config.Threshold then
			-- Exit Panic Mode
			if panicState[player] then
				panicState[player] = false
				AlertRemote:FireClient(player, "Stop")
			end
		end
	end

	local function scheduleEvaluate()
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if not character.Parent or not humanoid.Parent then return end
			evaluate()
		end)
	end

	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(scheduleEvaluate)
	humanoid.HealthChanged:Connect(scheduleEvaluate)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		panicState[player] = false -- Reset on death/respawn
		MonitorCharacter(player, char)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	panicState[player] = nil
end)