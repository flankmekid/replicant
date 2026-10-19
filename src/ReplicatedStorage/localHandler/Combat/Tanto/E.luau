local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ServerRemote = RP.remotes.server
local Sounds = RP.assets.sounds

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)
local CooldownTracker = require(RP.modules.CooldownTracker)
local ParryCooldownClient = require(RP.modules.ParryCooldownClient)

-- Animation IDs
local ANIM_THROW = "rbxassetid://115237120299356" -- Replace with Dagger Throw Anim

local ATTACK_COOLDOWN = 3 -- Client side debounce
local debounce = false

-- Helper to get tool name
local function getEquippedToolName()
	local char = plr.Character
	if not char then return nil end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool and tool.Name
end

function module.OnEActivated()
	local char = plr.Character
	if not char then return end

	if debounce then return end

	-- Standard Client-Side State Checks
	if char:GetAttribute("CantAnything") or 
		char:GetAttribute("Stunned") or 
		char:GetAttribute("Dodging") or
		char:GetAttribute("Sliding") or
		char:GetAttribute("M1") or
		char:GetAttribute("M2") then 
		return 
	end

	local toolName = getEquippedToolName()
	if not toolName then return end

	debounce = true
	
	CooldownTracker.Register("Dagger_E", "E", ATTACK_COOLDOWN)
	
	local s = RP.assets.sounds.dagger.daggerLunge:Clone()
	s.Parent = char.HumanoidRootPart
	s:Play()
	game:GetService("Debris"):AddItem(s, 1)

	-- Fire request to server
	ServerRemote:FireServer({
		Type = "Combat", 
		Action = "E", 
		Func = "ServerCheck",
		CombatType = toolName
	})

	-- Play initial throw animation immediately for responsiveness
	animationHndlr.StopAnim(char, "ALL")
	animationHndlr.LoadAnim(char, "E", ANIM_THROW, nil, false)

	-- Reset client debounce
	task.delay(ATTACK_COOLDOWN, function()
		debounce = false
	end)
end

function module.ServerResponse(plr, response)
	local char = plr.Character or plr.CharacterAdded:Wait()

	if response == "Declined" then
		animationHndlr.StopAnim(char, "E", ANIM_THROW)
		print(response)
	end
end

module.Swing = function(ochar)
	local s = Sounds.dagger.daggerSwing:Clone()
	s.Parent = ochar.Torso
	s:Play()
end

module.Hit = function(ochar, echar)
	local s = Sounds.dagger.daggerHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, .5)
end

module.Blocked = function(ochar, echar)
	local s = Sounds.BlockingHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.BlockFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, .5)
end

module.Parry = function(ochar, echar)
	local s = Sounds.ParrySound:Clone()
	s.Parent = ochar.Torso
	s:Play()
	local hitFX = RP.assets.FX.ParryFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, .5)
end

module.GB = function(ochar, echar)
	local s = Sounds.dagger.daggerHit:Clone()
	s.Parent = echar.Torso
	s:Play()
	local hitFX = RP.assets.FX.HitFX.Attachment:Clone()
	hitFX.Parent = echar:FindFirstChild("Torso")
	Debris:AddItem(hitFX, .5)
end

plr.CharacterAdded:Connect(function()
	debounce = false
end)


return module