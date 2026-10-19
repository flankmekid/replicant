-- SPDX-License-Identifier: MIT
--
-- Sets server-side movement states (Dodging, Sliding, and the vault and wall-run
-- locks) when the client reports them through the stateRepl remote. The client
-- decides when it moves, so the server repeats the client's dash and slide checks and
-- never lets a client clear a lock that another system set.

local Players = game:GetService("Players")
local RP = game:GetService("ReplicatedStorage")
local stateRemote = RP.remotes.stateRepl
local stateHandler = require(RP.modules.stateHandler)
local StatScaling = require(RP.modules.StatScaling)

-- Must match DASH_CONFIG in the Dash client: seconds per charge with one charge and
-- with two.
local dashCooldown = 2.5
local dashMultiCooldown = 3.5
-- Latency slack for a charge that the client already sees as ready.
local dashSlack = 0.25
-- The states in which the Dash client refuses to dash. The server sets all of them.
local dashBlockedStates = { "Blocking", "Stunned", "DashLocked", "Ragdolled", "Carried", "Downed" }

-- The Slide client starts a slide only within 5 studs of the floor. The extra length
-- covers latency.
local slideRayLength = 7

-- Layout: dashCharges[player] = { readyAt, ... }, one entry per charge.
local dashCharges = {}
-- The characters whose CantAnything lock this script set for a vault or a wall run.
local movementLocks = setmetatable({}, { __mode = "k" })

local function getStamina(plr)
	local stats = plr:FindFirstChild("PlayerStats")
	local statFolder = stats and stats:FindFirstChild("Stats")
	local stamina = statFolder and statFolder:FindFirstChild("Stamina")
	return stamina and stamina.Value or 0
end

-- Uses a dash charge if one is ready. Returns true if it did.
local function takeDashCharge(plr)
	local twoCharges = StatScaling.HasSecondDash(getStamina(plr))
	local count = twoCharges and 2 or 1
	local cooldown = twoCharges and dashMultiCooldown or dashCooldown

	local charges = dashCharges[plr] or {}
	dashCharges[plr] = charges
	for i = count + 1, #charges do
		charges[i] = nil
	end

	local now = os.clock()
	for i = 1, count do
		if (charges[i] or 0) <= now + dashSlack then
			charges[i] = now + cooldown
			return true
		end
	end
	return false
end

local function canDash(char)
	if char:GetAttribute("CantAnything") and not char:GetAttribute("Carrying") then
		return false
	end
	for _, state in ipairs(dashBlockedStates) do
		if char:GetAttribute(state) then
			return false
		end
	end
	return true
end

local slideParams = RaycastParams.new()
slideParams.FilterType = Enum.RaycastFilterType.Exclude

local function isOnGround(char)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	slideParams.FilterDescendantsInstances = { char }
	return workspace:Raycast(root.Position, Vector3.new(0, -slideRayLength, 0), slideParams) ~= nil
end

-- Sets CantAnything for a vault or a wall run, unless another system holds it.
local function lockMovement(char)
	if stateHandler.GetState(char, "CantAnything") and not movementLocks[char] then
		return
	end
	movementLocks[char] = true
	stateHandler.SetState(char, "CantAnything", true, 99999)
end

-- Clears CantAnything only if lockMovement set it.
local function unlockMovement(char)
	if not movementLocks[char] then
		return
	end
	movementLocks[char] = nil
	stateHandler.RemoveStates(char, "CantAnything")
end

stateRemote.OnServerEvent:Connect(function(plr, args)
	local char = plr.Character
	if not char then
		return
	end

	if args == "Dodge" then
		local stats = plr:FindFirstChild("PlayerStats")
		local dashDuration = stats and stats:FindFirstChild("DashDuration")
		if not dashDuration or not canDash(char) then
			return
		end
		if not takeDashCharge(plr) then
			warn(`[stateReplicator] {plr.Name} dodged with no dash charge ready.`)
			return
		end
		stateHandler.SetState(char, "Dodging", true, dashDuration.Value)
	elseif args == "SlideOn" then
		if not isOnGround(char) then
			return
		end
		stateHandler.SetState(char, "Sliding", true, 99999)
	elseif args == "SlideOff" then
		stateHandler.RemoveStates(char, "Sliding")
	elseif args == "VaultOn" or args == "StartWallR" then
		lockMovement(char)
	elseif args == "VaultOff" or args == "StopWallR" then
		unlockMovement(char)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	dashCharges[plr] = nil
end)
