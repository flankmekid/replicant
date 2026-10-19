-- SPDX-License-Identifier: MIT
--
-- Owns the guard bar on the server. The value is the GuardBar character attribute
-- (0 to MAX), which clients only read. BlockResolver is the only caller that fills it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RP = game:GetService("ReplicatedStorage")

local StateHandler = require(RP.modules.stateHandler)
local AnimationHandler = require(RP.modules.animationHandler)

local GuardBarService = {}

local MAX = 100
local BLOCK_BREAK_ANIM = "rbxassetid://131056155810963"
-- The hard stun and CantAnything lockout on a break, in seconds.
local BLOCK_BREAK_DURATION = 1.0
-- WalkSpeed while guard-broken.
local BLOCK_BREAK_STUNSPEED = 2

-- After the stun ends, the bar starts full and drains to empty over this window. The
-- player cannot block until it is empty.
local GUARD_RECOVERY_DURATION = 5.0

-- Fill added to the blocker's bar per blocked hit, by attack class. M2 is 0, because
-- an M2 is a guard break and skips the bar.
local FILL = {
	M1 = 18,
	M2 = 0,
	E = 22,
	Skill = 20,
	Default = 18,
}

-- Drain when the guarding player relieves pressure: a landed parry, or landing their
-- own hit while the bar is up.
local DRAIN_ON_PARRY = 40
local DRAIN_ON_HIT = 12

-- After REGEN_DELAY seconds without a blocked hit, the bar drains at REGEN_RATE per
-- second.
local REGEN_RATE = 8
local REGEN_DELAY = 3

-- The os.clock() time of each character's last fill, for the regen delay.
local lastFillClock = {}
-- A counter per character that cancels an old break recovery.
local recoveryToken = {}

local function get(char)
	return char:GetAttribute("GuardBar") or 0
end

local function set(char, v)
	char:SetAttribute("GuardBar", math.clamp(v, 0, MAX))
end

-- The HUD reads MAX so it does not hardcode the maximum.
GuardBarService.MAX = MAX

-- GuardBarService.Init() - set up the guard bar of a new character
-- @char: the character
--
-- mainGameHandler calls this on spawn. The regen loop serves only characters that
-- have the attribute.
--
-- Return: nothing.
function GuardBarService.Init(char)
	if not char then
		return
	end
	set(char, 0)
	char:SetAttribute("GuardBroken", false)
	recoveryToken[char] = nil
end

-- GuardBarService.IsGuardBroken() - check whether a character is in break recovery
-- @char: the character
--
-- Return: true while the bar drains after a break, when blocking is disabled.
function GuardBarService.IsGuardBroken(char)
	return char and char:GetAttribute("GuardBroken") == true or false
end

-- GuardBarService.AddOnBlock() - fill the bar of a character who blocked a hit
-- @char: the blocking character
-- @attackClass: "M1", "M2", "E", or "Skill"
--
-- The block breaks the moment the fill reaches MAX. There is no grace hit.
--
-- Return: true if this hit broke the guard.
function GuardBarService.AddOnBlock(char, attackClass)
	if not char then
		return false
	end
	lastFillClock[char] = os.clock()

	-- A character in break recovery cannot block, so ignore the hit.
	if GuardBarService.IsGuardBroken(char) then
		return false
	end

	local amount = FILL[attackClass] or FILL.Default
	local cur = get(char)
	if cur + amount >= MAX then
		GuardBarService.Break(char)
		return true
	end

	set(char, cur + amount)
	return false
end

-- GuardBarService.Drain() - lower a character's guard bar
-- @char: the character
-- @amount: the amount to remove
--
-- Return: nothing.
function GuardBarService.Drain(char, amount)
	if not char then
		return
	end
	set(char, get(char) - amount)
end

-- GuardBarService.DrainOnParry() - drain the bar after a landed parry
-- @char: the character that parried
--
-- Return: nothing.
function GuardBarService.DrainOnParry(char)
	GuardBarService.Drain(char, DRAIN_ON_PARRY)
end

-- GuardBarService.DrainOnHit() - drain the bar after the character lands a hit
-- @char: the attacking character
--
-- Return: nothing.
function GuardBarService.DrainOnHit(char)
	GuardBarService.Drain(char, DRAIN_ON_HIT)
end

-- GuardBarService.Break() - break a character's guard
-- @char: the character
--
-- Used for both a full bar and a guard-break attack. Applies the hard stun and
-- lockout and the break animation, then drains the bar from full to empty over
-- GUARD_RECOVERY_DURATION. Blocking is disabled for the whole recovery.
--
-- Return: nothing.
function GuardBarService.Break(char)
	if not char then
		return
	end

	StateHandler.RemoveStates(char, "Blocking")
	StateHandler.SetStun(char, true, BLOCK_BREAK_DURATION, BLOCK_BREAK_STUNSPEED)
	StateHandler.SetState(char, "CantAnything", true, BLOCK_BREAK_DURATION)
	AnimationHandler.StopAnim(char, "ALL")
	AnimationHandler.LoadAnim(char, "GuardBreak", BLOCK_BREAK_ANIM, nil, false)

	set(char, MAX)
	char:SetAttribute("GuardBroken", true)

	-- The token stops an old recovery after a new break or a respawn.
	local token = (recoveryToken[char] or 0) + 1
	recoveryToken[char] = token
	-- The recovery owns the drain, so passive regen stays off.
	lastFillClock[char] = nil

	task.spawn(function()
		local elapsed = 0
		while elapsed < GUARD_RECOVERY_DURATION do
			local dt = task.wait()
			if recoveryToken[char] ~= token then
				return
			end
			if not char.Parent then
				recoveryToken[char] = nil
				return
			end
			elapsed += dt
			local ratio = math.clamp(1 - elapsed / GUARD_RECOVERY_DURATION, 0, 1)
			set(char, MAX * ratio)
		end
		if recoveryToken[char] ~= token then
			return
		end
		set(char, 0)
		char:SetAttribute("GuardBroken", false)
		recoveryToken[char] = nil
	end)
end

RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		-- Skip guard-broken characters, because the recovery owns their bar.
		if
			char
			and char:GetAttribute("GuardBar") ~= nil
			and not GuardBarService.IsGuardBroken(char)
		then
			local v = get(char)
			if v > 0 then
				local last = lastFillClock[char]
				if not last or (os.clock() - last) >= REGEN_DELAY then
					set(char, v - REGEN_RATE * dt)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	local char = plr.Character
	if char then
		lastFillClock[char] = nil
		recoveryToken[char] = nil
	end
end)

return GuardBarService
