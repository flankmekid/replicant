-- [[ TITLE EARNED NOTIFICATION CLIENT ]]
-- Location: StarterPlayerScripts
-- Listens for TitleEarned remote and shows the QuestCompleteFrame
-- with the title name and Liturgy reward, same as quest completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local TitleEarned = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("TitleEarned")

local SLIDE_UP = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local queue = {}
local playing = false

local function playNotification(titleName, liturgyReward)
	-- Reuse QuestCompleteFrame from QuestGUI
	local questGui = PlayerGui:FindFirstChild("QuestGUI")
	if not questGui then
		return
	end

	local frame = questGui:FindFirstChild("QuestCompleteFrame")
	if not frame then
		return
	end

	local nameLbl = frame:FindFirstChild("CompleteName")
	local rewardLbl = frame:FindFirstChild("CompleteReward")
	local sound = frame:FindFirstChild("CompleteSound")

	if not nameLbl or not rewardLbl then
		return
	end

	nameLbl.Text = titleName
	rewardLbl.Text = liturgyReward > 0 and "Title Unlocked  ·  +" .. liturgyReward .. " Liturgy"
		or "Title Unlocked"

	frame.Position = UDim2.new(0.5, 0, 1.1, 0)
	frame.GroupTransparency = 0
	frame.Visible = true

	if sound then
		sound:Play()
	end

	TweenService:Create(frame, SLIDE_UP, {
		Position = UDim2.new(0.5, 0, 0.88, 0),
	}):Play()

	task.wait(0.4 + 2.5)

	if not frame.Parent then
		return
	end

	local out = TweenService:Create(frame, FADE_OUT, {
		GroupTransparency = 1,
	})
	out:Play()
	out.Completed:Wait()
	frame.Visible = false
end

TitleEarned.OnClientEvent:Connect(function(titleName, liturgyReward)
	table.insert(queue, { title = titleName, liturgy = liturgyReward or 0 })
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		while #queue > 0 do
			local next = table.remove(queue, 1)
			playNotification(next.title, next.liturgy)
			task.wait(0.3)
		end
		playing = false
	end)
end)
