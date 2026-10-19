-- SPDX-License-Identifier: MIT
--
-- Moves Yuna into view, and hides the lantern blocker, for a player whose Lantern quest
-- is at step 0 or 1, and handles her prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local QuestUpdate = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
local QuestStateRequest = ReplicatedStorage.QuestSystem:WaitForChild("QuestStateRequest")
local PickupRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("YunaInteraction", 10)

local quest_id = "Lantern"
local characterModel = workspace:WaitForChild("Yuna", 10)

local prompt = characterModel.Torso:FindFirstChildWhichIsA("ProximityPrompt")

local glowLoop = nil

local function setVisible(visible)
	if visible then
		characterModel:PivotTo(CFrame.new(2503.724, 121.087, -3260.104))
		local model = workspace:WaitForChild("lanternvis2")
		for _, p in pairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = 1
				p.CanCollide = false
			end
		end
	else
		characterModel:PivotTo(CFrame.new(2503.724, 106.087, -3260.104))
		local model = workspace:WaitForChild("lanternvis2")
		for _, p in pairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = 0
				p.CanCollide = true
			end
		end
	end
end

local function checkState()
	local success, state = pcall(function()
		return QuestStateRequest:InvokeServer(quest_id)
	end)
	if not success or not state then
		return
	end
	setVisible(state.active and state.progress == 0 or state.progress == 1)
end

prompt.Triggered:Connect(function()
	PickupRemote:FireServer(quest_id)
end)

QuestUpdate.OnClientEvent:Connect(function(action, payload)
	if action == "New" and payload and payload.Id == quest_id then
		checkState()
	elseif action == "Update" and payload and payload.Id == quest_id then
		checkState()
	elseif action == "Complete" and payload and payload.Id == quest_id then
		setVisible(false)
	elseif action == "ListUpdate" then
		checkState()
	end
end)

setVisible(false)
task.spawn(function()
	player:WaitForChild("PlayerStats", 15)
	task.wait(0.5)
	checkState()
end)
