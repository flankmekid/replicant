-- SPDX-License-Identifier: MIT
--
-- The tutorial panel: shows a yes/no prompt when the player first touches the tutorial
-- trigger, and gives the topbar script a TutorialState BindableFunction to open and
-- close the panel. It uses the prebuilt TutorialGui.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("TutorialGui")
local backdrop = gui:WaitForChild("Backdrop")
local prompt = backdrop:WaitForChild("Prompt")
local panel = backdrop:WaitForChild("Panel")

local yesButton = prompt:WaitForChild("Buttons"):WaitForChild("Yes")
local noButton = prompt:WaitForChild("Buttons"):WaitForChild("No")
local closeButton = panel:WaitForChild("Close")

local bgTransparency = 0.35

local function wireHover(button)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = 0.1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService
			:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = bgTransparency })
			:Play()
	end)
end
wireHover(yesButton)
wireHover(noButton)
wireHover(closeButton)

local function showPrompt()
	gui.Enabled = true
	prompt.Visible = true
	panel.Visible = false
end

local function showPanel()
	gui.Enabled = true
	prompt.Visible = false
	panel.Visible = true
end

local function close()
	gui.Enabled = false
	prompt.Visible = false
	panel.Visible = false
end

-- The topbar script controls the panel through this function.
local api = Instance.new("BindableFunction")
api.Name = "TutorialState"
api.OnInvoke = function(action)
	if action == "toggle" then
		-- Toggle only the panel, not the yes/no prompt.
		if gui.Enabled and panel.Visible then
			close()
			return false
		else
			showPanel()
			return true
		end
	elseif action == "isOpen" then
		return gui.Enabled
	elseif action == "close" then
		close()
		return false
	end
	return nil
end
api.Parent = gui

-- The close button fires this so the topbar script deselects its icon. The button also
-- closes the panel itself, because the panel can open from the touch prompt with the
-- icon never selected.
local requestClose = Instance.new("BindableEvent")
requestClose.Name = "RequestClose"
requestClose.Parent = gui

yesButton.MouseButton1Click:Connect(showPanel)
noButton.MouseButton1Click:Connect(close)
closeButton.MouseButton1Click:Connect(function()
	close()
	requestClose:Fire()
end)

-- The trigger shows the prompt once per session.
local triggers = workspace:WaitForChild("triggers")
local trigger = triggers:WaitForChild("tutorialControlTrigger")

local fired = false
trigger.Touched:Connect(function(hit)
	if fired then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if not hit:IsDescendantOf(character) then
		return
	end
	fired = true
	showPrompt()
	trigger:Destroy()
end)
