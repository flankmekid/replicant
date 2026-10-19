local module = {}

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local ServerRemote = RP.remotes.server

local plr = Players.LocalPlayer
local animationHndlr = require(RP.modules.animationHandler)

-- Placeholder Animation IDs (REPLACE THESE)
local ANIM = "rbxassetid://117582907989700" -- Attacker misses grab
local ANIM_WHIFF = "rbxassetid://96311777205911" -- Attacker misses grab

local THROW_COOLDOWN = 5 -- Client side debounce for responsiveness
local isThrowing = false

-- Helper to get tool name for the server request
local function getEquippedToolName()
	local char = plr.Character
	if not char then return nil end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool and tool.Name
end

function module.OnThrowActivated()
	local char = plr.Character
	if not char then return end

	if isThrowing then return end

	-- Standard Client-Side State Checks (Predictive)
	if char:GetAttribute("CantAnything") or 
		char:GetAttribute("Stunned") or 
		char:GetAttribute("Dodging") or
		char:GetAttribute("Sliding") or
		char:GetAttribute("M1") or
		char:GetAttribute("M2") then 
		return 
	end

	isThrowing = true

	local toolName = getEquippedToolName()
	if not toolName then 
		isThrowing = false
		return 
	end

	-- Fire request to server
	ServerRemote:FireServer({
		Type = "Combat", 
		Action = "Throw", 
		Func = "ServerCheck",
		CombatType = toolName
	})

	-- Play initial grab attempt animation immediately for responsiveness
	-- The server will override this with a success/punish animation later
	animationHndlr.LoadAnim(char, "ThrowStart", ANIM, nil, false)

	-- Reset client debounce
	task.delay(THROW_COOLDOWN, function()
		isThrowing = false
	end)
end

-- Called by server to play sounds/effects
function module.ExecuteEffect(char, effectType)
	if effectType == "Whiff" then
		local s = RP.assets.sounds.PunchSound:Clone()
		s.Parent = char.Torso
		s:Play()
		game.Debris:AddItem(s, 2)
		
		animationHndlr.StopAnim(char, "ThrowStart", ANIM)
		animationHndlr.LoadAnim(char, "Whiff", ANIM_WHIFF, nil, false)
		
	elseif effectType == "Hit" then
		local s = RP.assets.sounds.PunchHit:Clone()
		s.Parent = char.Torso
		s:Play()
		game.Debris:AddItem(s, 2)
		-- Create an impact particle
	end
end


return module