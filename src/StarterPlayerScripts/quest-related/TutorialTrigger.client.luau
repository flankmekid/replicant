-- ============================================================
-- TutorialController (LocalScript) -> StarterPlayerScripts
-- Uses the prebuilt TutorialGui in PlayerGui. No UI building here.
-- Handles: trigger touch (session-only yes/no) and shared open/close.
-- ============================================================

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

local BG_TRANSPARENCY = 0.35

-- ===== hover tweens wired at runtime =====
local function wireHover(button)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = 0.1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = BG_TRANSPARENCY }):Play()
	end)
end
wireHover(yesButton)
wireHover(noButton)
wireHover(closeButton)

-- ===== shared open/close API (exposed via BindableEvents for the topbar script) =====
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

-- expose controls to the topbar script through a shared folder
local api = Instance.new("BindableFunction")
api.Name = "TutorialState"
api.OnInvoke = function(action)
	if action == "toggle" then
		-- toggle the panel only; ignores the yes/no prompt
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

-- the X syncs the topbar icon's visual state. READ_ME listens and deselects
-- the icon. note the X closes the panel directly below (not via this event),
-- because the panel can be opened from the touch prompt without the icon ever
-- being selected, in which case deselect() would be a no-op and never close it.
local requestClose = Instance.new("BindableEvent")
requestClose.Name = "RequestClose"
requestClose.Parent = gui

yesButton.MouseButton1Click:Connect(showPanel)
noButton.MouseButton1Click:Connect(close)
closeButton.MouseButton1Click:Connect(function()
	close()              -- always close the panel, regardless of how it opened
	requestClose:Fire()  -- sync the topbar icon (no-op if it wasn't selected)
end)

-- ===== trigger touch (client-side, session-only) =====
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
