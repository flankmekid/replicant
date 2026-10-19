--[[

> TopbarPlus was developed by ForeverHD and is actively maintained
thanks to HD Admin.

> You can get in touch with me on Discord via the social link here:
https://create.roblox.com/store/asset/92368439343389/TopbarPlus

> READ_ME is Script with RunContext set to 'Client' meaning you can
store it in ReplicatedStorage and Workspace and it will still run 
like a normal LocalScript. DO NOT PLACE place in StarterPlayerScripts
(because this is a Script with RunContext). You need to create a separate
LocalScript for anything under StarterPlayerScripts. 

> You're welcome to move `Icon` and require it yourself. You can
then delete this folder and READ_ME.

> Icon is a Package for when Roblox (hopefully soon) release
public packages. This for example will enable you to receive
automatic updates, and to compare code easily between changes

> Have feedback? Post it to devforum.roblox.com/t/topbarplus/1017485
which I actively monitor. Enjoy! ~ForeverHD June 2025

--]]

local container  = script.Parent
local Icon = require(container.Icon)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local weapon_switch = game:GetService("ReplicatedStorage").remotes:WaitForChild("ChangeWeapon")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Animation Settings
local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Variable to track the current animation so we can cancel it if clicked fast
local currentTween = nil

local db = false

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("TutorialGui")
local api = gui:WaitForChild("TutorialState") -- BindableFunction from the controller

local controlIcon = Icon.new()
controlIcon:setLabel("Controls")
controlIcon:align("Left")

controlIcon.selected:Connect(function()
	local isOpen = api:Invoke("toggle")
	-- keep the icon visual state in sync with the panel
	if not isOpen then
		controlIcon:deselect()
	end
end)

controlIcon.deselected:Connect(function()
	api:Invoke("close")
end)

-- the in-panel X button (TutorialTrigger) fires RequestClose. deselecting the
-- icon here triggers the deselected handler above, which closes the panel, and
-- leaves the topbar icon in the correct (deselected) visual state. without this
-- the X closed the panel directly and the icon stayed stuck "open".
local requestClose = gui:WaitForChild("RequestClose")
requestClose.Event:Connect(function()
	controlIcon:deselect() -- safe no-op if already deselected
end)


local function actionCheck(char)
	
	if char:FindFirstChildWhichIsA("Tool") then return end
	if char:GetAttribute("CantAnything") then return false end
	if char:GetAttribute("Stunned") then return false end
	if char:GetAttribute("Sliding") then return false end
	if char:GetAttribute("Blocking") then return false end
	if char:GetAttribute("Parrying") then return false end
	if char:GetAttribute("Dodging") then return false end
	if char:GetAttribute("M1") then return  false end
	if char:GetAttribute("M2") then return false end
	
	return true
end

local function playSound(char : Model, soundName : string)
	local folder = ReplicatedStorage:WaitForChild("assets"):WaitForChild("sounds"):WaitForChild("interactions")
	
	if char and folder:FindFirstChild(soundName) then
		local sound = folder[soundName]:Clone()
		sound.Parent = char:WaitForChild("Torso")
		sound:Play()
		game.Debris:AddItem(sound, sound.TimeLength + 1)
	end
end

--[[
Icon.new()
	:setLabel("Weapons")
	:modifyTheme({"Dropdown", "MaxIcons", 3})
	:modifyChildTheme({"Widget", "MinimumWidth", 158})
	:setDropdown({
		Icon.new()
		:setLabel("Fists")
		:bindEvent("selected", function()
			if db == false and actionCheck(player.Character) then
				db = true
				weapon_switch:FireServer("Fists")
				playSound(player.Character, "Accepted")
				task.wait(5)
				db = false
			else
				playSound(player.Character, "Cooldown")
			end
		end)
		:oneClick(true)
		,
		Icon.new()
		:setLabel("Dagger")
		:bindEvent("selected", function()
			if db == false and actionCheck(player.Character) then
				db = true
				weapon_switch:FireServer("Dagger")
				playSound(player.Character, "Accepted")
				task.wait(5)
				db = false
			else
				playSound(player.Character, "Cooldown")
			end
		end)
		:oneClick(true)
		,
		Icon.new()
		:setLabel("Katana")
		:bindEvent("selected", function()
			if db == false and actionCheck(player.Character) then
				db = true
				weapon_switch:FireServer("Katana")
				playSound(player.Character, "Accepted")
				task.wait(5)
				db = false
			else
				playSound(player.Character, "Cooldown")
			end
		end)
		:oneClick(true)
		,
		Icon.new()
		:setLabel("Greatsword")
		:bindEvent("selected", function()
			if db == false and actionCheck(player.Character) then
				db = true
				weapon_switch:FireServer("Greatsword")
				playSound(player.Character, "Accepted")
				task.wait(5)
				db = false
			else
				playSound(player.Character, "Cooldown")
			end
		end)
		:oneClick(true)
		,
		Icon.new()
		:setLabel("Sword")
		:bindEvent("selected", function()
			if db == false and actionCheck(player.Character) then
				db = true
				weapon_switch:FireServer("Sword")
				playSound(player.Character, "Accepted")
				task.wait(5)
				db = false
			else
				playSound(player.Character, "Cooldown")
			end
		end)
		:oneClick(true)
		,
	})
]]

--[[
Icon.new()
	:setLabel("Controls")
	:bindEvent("selected", function()
		local controlUI = playerGui:WaitForChild("GameControlsUI"):WaitForChild("ControlsContainer")
		if currentTween then
			currentTween:Cancel()
		end
		
		controlUI.Visible = true

		currentTween = TweenService:Create(controlUI, TWEEN_INFO, {GroupTransparency = 0})
		currentTween:Play()
	end)
	:bindEvent("deselected", function()
		local controlUI = playerGui:WaitForChild("GameControlsUI"):WaitForChild("ControlsContainer")
		if currentTween then
			currentTween:Cancel()
		end
		
		currentTween = TweenService:Create(controlUI, TWEEN_INFO, {GroupTransparency = 1})
		currentTween:Play()

		currentTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				controlUI.Visible = false
			end
		end)
	end)

Icon.new()
	:setLabel("Invite friend")
	:bindEvent("selected", function()
		pcall(function()
			if SocialService:CanSendCallInviteAsync(player) then
				SocialService:PromptGameInvite(player)
			end
		end)
	end)
	:oneClick(true)
	:align("Right")
]]
