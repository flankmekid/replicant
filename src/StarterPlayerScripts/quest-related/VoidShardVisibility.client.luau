-- [[ VOID SHARD VISIBILITY ]]
-- Location: StarterPlayerScripts
-- Shows the shard only to players with SidurguErrand active at progress 0.
-- Controls transparency directly on the part. No BillboardGui.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player        = Players.LocalPlayer
local QuestUpdate   = ReplicatedStorage.QuestSystem:WaitForChild("QuestUpdate")
local QuestStateRequest = ReplicatedStorage.QuestSystem:WaitForChild("QuestStateRequest")
local PickupRemote  = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("ShardPickup")

local QUEST_ID        = "SidurguErrand"
local SHARD_PART_NAME = "VoidStoneShard"

local shardPart = workspace:WaitForChild(SHARD_PART_NAME, 10)
if not shardPart then
	warn("[VoidShard] Part not found: " .. SHARD_PART_NAME)
	return
end

-- Create ProximityPrompt if not already present
local prompt = shardPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText            = "Void-stone Shard"
	prompt.ActionText            = "Take"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = shardPart
end

-- ── VISIBILITY ────────────────────────────────────────────────────────────────

local glowLoop = nil

local function setVisible(visible)
	if visible then
		shardPart.Transparency = 0
		shardPart.DarkFlame.Enabled = true
		shardPart.Dark.Enabled = true
		prompt.Enabled = true
	else
		shardPart.Transparency = 1
		shardPart.DarkFlame.Enabled = false
		shardPart.Dark.Enabled = false
		prompt.Enabled = false
	end
end

-- ── QUEST STATE CHECK ─────────────────────────────────────────────────────────

local function checkState()
	local success, state = pcall(function()
		return QuestStateRequest:InvokeServer(QUEST_ID)
	end)
	if not success or not state then return end
	setVisible(state.active and state.progress == 0)
end

-- ── PICKUP ────────────────────────────────────────────────────────────────────

prompt.Triggered:Connect(function()
	setVisible(false)
	PickupRemote:FireServer(QUEST_ID)
end)

-- ── REMOTE LISTENER ───────────────────────────────────────────────────────────

QuestUpdate.OnClientEvent:Connect(function(action, payload)
	if action == "New" and payload and payload.Id == QUEST_ID then
		checkState()
	elseif action == "Update" and payload and payload.Id == QUEST_ID then
		checkState()
	elseif action == "Complete" and payload and payload.Id == QUEST_ID then
		setVisible(false)
	elseif action == "ListUpdate" then
		checkState()
	end
end)

-- ── INIT ──────────────────────────────────────────────────────────────────────
setVisible(false)
task.spawn(function()
	player:WaitForChild("PlayerStats", 15)
	task.wait(0.5)
	checkState()
end)