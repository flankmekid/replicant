-- SPDX-License-Identifier: MIT
--
-- Shows floating damage numbers for the hits that the server reports.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DamageNumberRemote = ReplicatedStorage.remotes:WaitForChild("DamageNumber")

DamageNumberRemote.OnClientEvent:Connect(function(anchorPart, damage)
	if not anchorPart or not anchorPart.Parent then
		return
	end
	if type(damage) ~= "number" then
		return
	end

	local big = damage > 20
	local text = big and (tostring(damage) .. "!") or tostring(damage)

	local bb = Instance.new("BillboardGui")
	bb.Name = "DamageNumber"
	bb.Size = UDim2.fromScale(3, 1)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	-- Scatter sideways, so stacked hits do not overlap exactly.
	bb.StudsOffsetWorldSpace = Vector3.new(math.random(-15, 15) / 10, 2, 0)
	bb.Adornee = anchorPart
	bb.Parent = anchorPart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Garamond
	label.Text = text
	label.TextColor3 = big and Color3.fromRGB(255, 80, 60) or Color3.fromRGB(153, 153, 153)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.TextTransparency = 0
	label.Parent = bb

	label.TextSize = 1
	local popIn = TweenService:Create(
		bb,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(big and 5 or 4, big and 2 or 1.5) }
	)
	popIn:Play()

	local floatUp = TweenService:Create(
		bb,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0) }
	)
	floatUp:Play()

	task.delay(0.45, function()
		local fade = TweenService:Create(
			label,
			TweenInfo.new(0.45, Enum.EasingStyle.Linear),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fade:Play()
	end)

	game.Debris:AddItem(bb, 1)
end)
