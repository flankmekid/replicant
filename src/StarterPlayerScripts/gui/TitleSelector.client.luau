-- [[ TITLE SELECTOR CLIENT ]]
-- Location: StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("remotes")
local SetTitleRemote = remotes:WaitForChild("SetTitle")
local RequestTitles = remotes:WaitForChild("RequestTitles")
local TitleUpdated = remotes:WaitForChild("TitleUpdated")

-- ── COLOURS ───────────────────────────────────────────────────────────────────

local C = {
	bg = Color3.fromRGB(14, 12, 10),
	panel = Color3.fromRGB(22, 18, 14),
	border = Color3.fromRGB(70, 60, 50),
	selected = Color3.fromRGB(40, 32, 20),
	hover = Color3.fromRGB(30, 24, 16),
	muted = Color3.fromRGB(140, 128, 108),
	white = Color3.fromRGB(230, 218, 195),
}

local FADE_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ── GUI ───────────────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "TitleSelector"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

local panel = Instance.new("CanvasGroup")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.1, 0, 0.501, 0)
panel.Size = UDim2.new(0.17, 0, 0.5, 0)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = C.border
panelStroke.Thickness = 1
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = C.panel
header.BackgroundTransparency = 0.05
header.BorderSizePixel = 0
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = header

local headerMask = Instance.new("Frame")
headerMask.Size = UDim2.new(1, 0, 0, 10)
headerMask.Position = UDim2.new(0, 0, 1, -10)
headerMask.BackgroundColor3 = C.panel
headerMask.BackgroundTransparency = 0.05
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, 0, 1, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "TITLES"
titleLbl.Font = Enum.Font.Fondamento
titleLbl.TextSize = 25
titleLbl.TextXAlignment = Enum.TextXAlignment.Center
titleLbl.Parent = header
titleLbl.TextColor3 = Color3.fromRGB(167, 167, 167)

local headerDiv = Instance.new("Frame")
headerDiv.Size = UDim2.new(1, -24, 0, 1)
headerDiv.Position = UDim2.new(0, 12, 0, 48)
headerDiv.BackgroundColor3 = C.border
headerDiv.BackgroundTransparency = 0.5
headerDiv.BorderSizePixel = 0
headerDiv.Parent = panel

-- Current title display
local currentFrame = Instance.new("Frame")
currentFrame.Size = UDim2.new(1, -24, 0, 32)
currentFrame.Position = UDim2.new(0, 12, 0, 56)
currentFrame.BackgroundColor3 = C.panel
currentFrame.BackgroundTransparency = 0.3
currentFrame.BorderSizePixel = 0
currentFrame.Parent = panel

local currentCorner = Instance.new("UICorner")
currentCorner.CornerRadius = UDim.new(0, 5)
currentCorner.Parent = currentFrame

local currentLbl = Instance.new("TextLabel")
currentLbl.Name = "CurrentLabel"
currentLbl.Size = UDim2.new(1, -12, 1, 0)
currentLbl.Position = UDim2.new(0, 6, 0, 0)
currentLbl.BackgroundTransparency = 1
currentLbl.Text = "No title equipped."
currentLbl.Font = Enum.Font.Fondamento
currentLbl.TextSize = 24
currentLbl.TextColor3 = C.muted
currentLbl.TextXAlignment = Enum.TextXAlignment.Left
currentLbl.Parent = currentFrame

-- Scroll list
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "TitleList"
scroll.Size = UDim2.new(1, -24, 1, -112)
scroll.Position = UDim2.new(0, 12, 0, 96)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.border
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)
listLayout.Parent = scroll

local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 20)
listPad.PaddingBottom = UDim.new(0, 20)
listPad.Parent = scroll

-- Empty label
local emptyLbl = Instance.new("TextLabel")
emptyLbl.Name = "EmptyLabel"
emptyLbl.Size = UDim2.new(1, 0, 0, 40)
emptyLbl.BackgroundTransparency = 1
emptyLbl.Text = "No titles unlocked yet."
emptyLbl.Font = Enum.Font.Fondamento
emptyLbl.TextSize = 24
emptyLbl.TextColor3 = C.muted
emptyLbl.TextXAlignment = Enum.TextXAlignment.Center
emptyLbl.Visible = false
emptyLbl.Parent = scroll

-- ── STATE ─────────────────────────────────────────────────────────────────────

local isOpen = false
local currentTitle = ""
local titleButtons = {}

-- ── HELPERS ───────────────────────────────────────────────────────────────────

local function getSoulColor()
	return player:GetAttribute("SoulColor") or Color3.fromRGB(212, 175, 55)
end

local function updateCurrentLabel()
	if currentTitle and currentTitle ~= "" then
		currentLbl.Text = "Equipped:  " .. currentTitle
		currentLbl.TextColor3 = getSoulColor()
	else
		currentLbl.Text = "No title equipped."
		currentLbl.TextColor3 = C.muted
	end
end

local function refreshButtonVisuals()
	for title, btn in pairs(titleButtons) do
		local isSelected = title == currentTitle
		btn.BackgroundColor3 = isSelected and C.selected or C.panel

		local pip = btn:FindFirstChild("Pip")
		if pip then
			pip.BackgroundColor3 = isSelected and getSoulColor() or C.border
		end

		local lbl = btn:FindFirstChild("TitleLabel")
		if lbl then
			lbl.TextColor3 = isSelected and getSoulColor() or C.white
		end
	end
end

local function buildList(unlocked)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	titleButtons = {}

	emptyLbl.Visible = #unlocked == 0

	-- "No title" option always at top
	local clearBtn = Instance.new("TextButton")
	clearBtn.Name = "ClearTitle"
	clearBtn.Size = UDim2.new(1, 0, 0, 40)
	clearBtn.BackgroundColor3 = currentTitle == "" and C.selected or C.panel
	clearBtn.BorderSizePixel = 0
	clearBtn.Text = ""
	clearBtn.AutoButtonColor = false
	clearBtn.LayoutOrder = 0
	clearBtn.Parent = scroll

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 5)
	clearCorner.Parent = clearBtn

	local clearPip = Instance.new("Frame")
	clearPip.Name = "Pip"
	clearPip.Size = UDim2.new(0, 5, 0, 5)
	clearPip.Position = UDim2.new(0, 12, 0.5, -2.5)
	clearPip.BackgroundColor3 = currentTitle == "" and getSoulColor() or C.border
	clearPip.BorderSizePixel = 0
	clearPip.Parent = clearBtn

	local clearPipCorner = Instance.new("UICorner")
	clearPipCorner.CornerRadius = UDim.new(1, 0)
	clearPipCorner.Parent = clearPip

	local clearLbl = Instance.new("TextLabel")
	clearLbl.Name = "TitleLabel"
	clearLbl.Size = UDim2.new(1, -30, 1, 0)
	clearLbl.Position = UDim2.new(0, 26, 0, 0)
	clearLbl.BackgroundTransparency = 1
	clearLbl.Text = "None"
	clearLbl.Font = Enum.Font.Fondamento
	clearLbl.TextSize = 24
	clearLbl.TextColor3 = currentTitle == "" and getSoulColor() or C.muted
	clearLbl.TextXAlignment = Enum.TextXAlignment.Left
	clearLbl.Parent = clearBtn

	titleButtons[""] = clearBtn

	clearBtn.MouseButton1Click:Connect(function()
		currentTitle = ""
		SetTitleRemote:FireServer("")
		updateCurrentLabel()
		refreshButtonVisuals()
	end)

	clearBtn.MouseEnter:Connect(function()
		if currentTitle ~= "" then
			clearBtn.BackgroundColor3 = C.hover
		end
	end)
	clearBtn.MouseLeave:Connect(function()
		if currentTitle ~= "" then
			clearBtn.BackgroundColor3 = C.panel
		end
	end)

	for i, title in ipairs(unlocked) do
		local btn = Instance.new("TextButton")
		btn.Name = title
		btn.Size = UDim2.new(1, 0, 0, 40)
		btn.BackgroundColor3 = title == currentTitle and C.selected or C.panel
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.Parent = scroll

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		local pip = Instance.new("Frame")
		pip.Name = "Pip"
		pip.Size = UDim2.new(0, 5, 0, 5)
		pip.Position = UDim2.new(0, 12, 0.5, -2.5)
		pip.BackgroundColor3 = title == currentTitle and getSoulColor() or C.border
		pip.BorderSizePixel = 0
		pip.Parent = btn

		local pipCorner = Instance.new("UICorner")
		pipCorner.CornerRadius = UDim.new(1, 0)
		pipCorner.Parent = pip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "TitleLabel"
		lbl.Size = UDim2.new(1, -30, 1, 0)
		lbl.Position = UDim2.new(0, 26, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = title
		lbl.Font = Enum.Font.Fondamento
		lbl.TextSize = 24
		lbl.TextColor3 = title == currentTitle and getSoulColor() or C.white
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = btn

		titleButtons[title] = btn

		btn.MouseButton1Click:Connect(function()
			currentTitle = title
			SetTitleRemote:FireServer(title)
			updateCurrentLabel()
			refreshButtonVisuals()
		end)

		btn.MouseEnter:Connect(function()
			if title ~= currentTitle then
				btn.BackgroundColor3 = C.hover
			end
		end)
		btn.MouseLeave:Connect(function()
			if title ~= currentTitle then
				btn.BackgroundColor3 = C.panel
			end
		end)
	end
end

-- ── OPEN / CLOSE ──────────────────────────────────────────────────────────────

local function openPanel()
	isOpen = true

	local data = RequestTitles:InvokeServer()
	if data then
		currentTitle = data.Current or ""
		buildList(data.Unlocked or {})
		updateCurrentLabel()
	end

	panel.GroupTransparency = 1
	panel.Visible = true
	TweenService:Create(panel, FADE_IN, { GroupTransparency = 0 }):Play()
end

local function closePanel()
	isOpen = false
	local out = TweenService:Create(panel, FADE_OUT, { GroupTransparency = 1 })
	out:Play()
	out.Completed:Connect(function()
		panel.Visible = false
	end)
end

-- The journal's X button closes this panel too, via a shared bindable.
local CloseTitlePanel = remotes:WaitForChild("CloseTitlePanel")
CloseTitlePanel.Event:Connect(function()
	if isOpen then
		closePanel()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.J then
		if isOpen then
			closePanel()
		else
			openPanel()
		end
	end
end)

task.spawn(function()
	local masteryGui = PlayerGui:WaitForChild("LiturgyDisplay", 20)
	if masteryGui then
		local displayBtn = masteryGui:WaitForChild("ImageButton", 20)
		if displayBtn then
			displayBtn.MouseButton1Click:Connect(function()
				if isOpen then
					closePanel()
				else
					openPanel()
				end
			end)
		end
	end
end)

-- ── LISTEN FOR TITLE UNLOCK (so panel refreshes if open) ─────────────────────
-- fired from server when a new title is granted mid-session
local TitleUnlocked = remotes:WaitForChild("TitleUnlocked", 5)
if TitleUnlocked then
	TitleUnlocked.OnClientEvent:Connect(function(title)
		if isOpen then
			local data = RequestTitles:InvokeServer()
			if data then
				currentTitle = data.Current or ""
				buildList(data.Unlocked or {})
				updateCurrentLabel()
			end
		end
	end)
end
