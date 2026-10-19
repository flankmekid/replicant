-- Burst (client): universal combo-breaker on the T key. Thin client: it only
-- reads intent and shows the cooldown HUD. All authority (mana, cooldown, the
-- i-frames, the hitbox) lives server-side in BurstHandler / SkillFunctions.Burst.
--
-- T was confirmed free on all equipped weapon Tools (the live inputHandlers in
-- ServerStorage.Weapons have their T/Throw bind commented out; only leftover
-- Workspace staging rigs still bound it, and those are not in the equip path).
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local modules = ReplicatedStorage:WaitForChild("modules")
local CooldownTracker = require(modules:WaitForChild("CooldownTracker"))
local BurstRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("Burst")

local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()

-- Predictive local guard so we don't spam the server while it is on cooldown.
-- The server is still the authority; this just avoids obviously-doomed requests.
local localReadyAt = 0

local function onInput(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	local char = Player.Character
	if not char then
		return
	end
	-- Do not even attempt while Downed. Stunned is intentionally NOT blocked here:
	-- bursting out of a combo (while Stunned) is the whole purpose.
	if char:GetAttribute("Downed") then
		return
	end
	if os.clock() < localReadyAt then
		return
	end
	BurstRemote:FireServer()
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		onInput(nil, Enum.UserInputState.Begin)
	end
end)

-- Server reply: arm the cooldown HUD only when the cast was actually committed.
BurstRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.Func ~= "BurstResponse" then
		return
	end
	if payload.Decision == "Accepted" and payload.Cooldown then
		localReadyAt = os.clock() + payload.Cooldown
		CooldownTracker.Register("Burst", "Burst", payload.Cooldown)
	end
end)
