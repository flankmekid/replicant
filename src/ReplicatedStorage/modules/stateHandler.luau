local module = {}

local states = {}
local activeTimers = {} -- Universally tracks all state timers to prevent overlapping

local animationHandler = require(script.Parent.animationHandler)
local StatScaling = require(script.Parent.StatScaling)

-- stateHandler is shared (ReplicatedStorage), but the stun WALKSPEED pin is
-- server-authoritative and SpeedService lives server-side. Require it lazily and only
-- on the server so a client require of stateHandler never reaches into ServerScriptService.
local RunService = game:GetService("RunService")
local _SpeedService
local function getSpeedService()
	if not RunService:IsServer() then
		return nil
	end
	if _SpeedService == nil then
		_SpeedService = require(game:GetService("ServerScriptService").modules.SpeedService)
	end
	return _SpeedService
end

-- Cancel a stored timer thread safely.
--
-- A task.delay callback calls clearKey() from INSIDE the very thread that is
-- stored in activeTimers[char][key]. task.cancel() errors ("cannot cancel
-- thread") when handed the thread that is currently running. So: pull the
-- thread out of the table first, then only cancel it if it is not us, and
-- only if it is not already dead.
local function cancelTimer(char, key)
	local bucket = activeTimers[char]
	if not bucket then
		return
	end

	local thread = bucket[key]
	if not thread then
		return
	end

	bucket[key] = nil

	if thread == coroutine.running() then
		return
	end
	if coroutine.status(thread) == "dead" then
		return
	end

	pcall(task.cancel, thread)
end

-- Single removal path for every state key. Writes the Lua table entry AND the
-- Instance attribute together so the two can never disagree.
--
-- The old code did `if next(states[char]) == nil then states[char] = nil end` in
-- several places. That dropped the WHOLE table when one key happened to be last,
-- while leaving the other keys' attributes still set on the Instance. Callers
-- reading GetState() then saw a clean character while callers reading
-- GetAttribute() still saw Downed/CantAnything. That desync is what let downed
-- players act. The table is now kept alive; only individual keys are cleared.
local function clearKey(char, key)
	if not char then
		return
	end

	cancelTimer(char, key)

	if states[char] then
		states[char][key] = nil
	end

	char:SetAttribute(key, nil)
end

function module.ReturnStates(char)
	return states[char]
end

-- Canonical "is this character allowed to act" check. Read this instead of
-- hand-rolling attribute checks per call site.
function module.CanAct(char)
	if not char then
		return false
	end
	local t = states[char]
	if not t then
		return true
	end
	if
		t["Stunned"]
		or t["Downed"]
		or t["CantAnything"]
		or t["Ragdolled"]
		or t["Carried"]
		or t["BeingExecuted"]
	then
		return false
	end
	return true
end

-- ATTRIBUTE-BASED READS (use these from the CLIENT).
--
-- `states` is a plain Lua table local to whichever VM required this module. The
-- server's states table and the client's states table are SEPARATE. A state set
-- by the server (Downed, Carried, BeingExecuted) never appears in the client's
-- table, so GetState() called from a LocalScript returns nil for all of them.
-- SetAttribute DOES replicate, so attributes are the only cross-boundary read.
-- Client code must use these, not GetState.
function module.GetStateAttr(char, stateKey: string)
	if not char then
		return nil
	end
	return char:GetAttribute(stateKey)
end

-- True while some other system owns this character's HumanoidRootPart (downed
-- ragdoll, carry constraints, execution anchor, Messatsu weld). Anything that
-- writes HRP.CFrame every frame (lock-on) must stand down while this is true.
-- Reads attributes, so it is correct on both server and client.
local ROOT_OWNED_STATES = {
	"Downed",
	"Ragdolled",
	"Carried",
	"Carrying",
	"BeingExecuted",
	"Executing",
}

-- ignoreRagdoll = true asks the weaker question: "is something OTHER than a plain
-- knockdown ragdoll holding this root?" A ragdoll still owns the root (never drive
-- CFrame through one), but it is not a reason to DROP a lock-on. LockOn passes true
-- when it asks "may I keep this lock" and nothing when it asks "may I drive the root".
function module.IsRootOwned(char, ignoreRagdoll)
	if not char then
		return false
	end
	for _, key in ipairs(ROOT_OWNED_STATES) do
		if ignoreRagdoll and key == "Ragdolled" then
			continue
		end
		if char:GetAttribute(key) then
			return true
		end
	end
	-- A Messatsu grab welds two HumanoidRootParts together (the WeldConstraint is
	-- parented to the ATTACKER's character, Part0 = attacker HRP, Part1 = victim
	-- HRP). Neither party may drive CFrame while that weld exists, or two clients
	-- both writing CFrame on rigidly-joined bodies blow the solver up into NaN.
	-- Scan our own character for a weld we own, and check whether anything is
	-- welded TO our root from the other side.
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	-- carry constraints live directly on the victim's root
	if root:FindFirstChild("CarryPos") or root:FindFirstChild("CarryOri") then
		return true
	end

	-- a weld we own (we are the grabber)
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("WeldConstraint") and v.Enabled and (v.Part0 == root or v.Part1 == root) then
			return true
		end
	end

	-- a weld someone else owns that binds our root (we are the grabbed)
	for _, v in ipairs(root:GetJoints()) do
		if v:IsA("WeldConstraint") and v.Enabled then
			local other = (v.Part0 == root) and v.Part1 or v.Part0
			-- ignore the character's own internal welds (accessories, tools)
			if other and not other:IsDescendantOf(char) then
				return true
			end
		end
	end

	return false
end

-- Is this character a legal lock-on target? Attribute-based; safe on the client.
function module.IsValidTarget(char)
	if not char then
		return false
	end
	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	if char:GetAttribute("Downed") then
		return false
	end
	if char:GetAttribute("Carried") then
		return false
	end
	if char:GetAttribute("BeingExecuted") then
		return false
	end
	return true
end

function module.GetState(char, stateKey: string)
	if states[char] then
		return states[char][stateKey]
	end
	return nil
end

-- Returns true if the character is in a state that should cancel any
-- in-progress attack swing (windup or pending hitbox). Centralized here so
-- every weapon checks the same interrupt condition and it can be expanded
-- in one place. Currently: Stunned (covers hits, parries, guard-break) or Downed.
function module.IsInterrupted(char)
	if not char then
		return false
	end
	if states[char] then
		if states[char]["Stunned"] then
			return true
		end
		if states[char]["Downed"] then
			return true
		end
	end
	return false
end

-- Reactive interrupt watcher. Fires onInterrupt() the instant the character
-- becomes Stunned or Downed (via the attributes SetStun/SetState write), then
-- self-disconnects so it only fires once. Auto-tears down after `window` seconds
-- as a safety net. Returns a stop() function the caller invokes on normal swing
-- completion so a finished swing's watcher can't fire against a later, unrelated stun.
-- Use this to cancel in-flight dash movers / animations the moment a hit lands,
-- rather than waiting for the windup to finish.
function module.WatchInterrupt(char, window, onInterrupt)
	if not char or type(onInterrupt) ~= "function" then
		return function() end
	end

	local fired = false
	local conns = {}
	local timeoutTask

	local function disconnectAll()
		for _, c in ipairs(conns) do
			if c.Connected then
				c:Disconnect()
			end
		end
		table.clear(conns)

		-- Same self-cancel hazard as the state timers: the timeout thread itself
		-- calls disconnectAll. Never hand task.cancel the running thread.
		local t = timeoutTask
		timeoutTask = nil
		if t and t ~= coroutine.running() and coroutine.status(t) ~= "dead" then
			pcall(task.cancel, t)
		end
	end

	local function trigger()
		if fired then
			return
		end
		fired = true
		disconnectAll()
		local ok, err = pcall(onInterrupt)
		if not ok then
			warn("[WatchInterrupt] onInterrupt failed ->", err)
		end
	end

	-- If already interrupted at registration time, fire on the next frame so the
	-- caller's local mover references are assigned before we try to cancel them.
	if module.IsInterrupted(char) then
		task.defer(trigger)
		return disconnectAll
	end

	table.insert(
		conns,
		char:GetAttributeChangedSignal("Stunned"):Connect(function()
			if char:GetAttribute("Stunned") then
				trigger()
			end
		end)
	)
	table.insert(
		conns,
		char:GetAttributeChangedSignal("Downed"):Connect(function()
			if char:GetAttribute("Downed") then
				trigger()
			end
		end)
	)

	if window and type(window) == "number" and window > 0 then
		timeoutTask = task.delay(window, disconnectAll)
	end

	-- caller stops the watcher on normal completion
	return disconnectAll
end

function module.SetState(char, stateKey: string, value, duration: number)
	if not states[char] then
		states[char] = {}
	end
	if not activeTimers[char] then
		activeTimers[char] = {}
	end

	cancelTimer(char, stateKey)

	states[char][stateKey] = value
	if char then
		char:SetAttribute(stateKey, value)
	end

	if duration and type(duration) == "number" and duration > 0 then
		activeTimers[char][stateKey] = task.delay(duration, function()
			clearKey(char, stateKey)
		end)
	end
end

function module.SetStun(char, value: boolean, duration: number, stunSpeed: number)
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end
	local humanoid = char.Humanoid
	if not states[char] then
		states[char] = {}
	end
	if not activeTimers[char] then
		activeTimers[char] = {}
	end

	if value then -- STUNNING
		-- HYPERARMOR: an armored attacker/caster absorbs the hit without losing their
		-- move. We skip the anim-stop, the Stunned state, and the speed pin, so the
		-- swing/cast rides through to its hitbox. Damage is still dealt by
		-- damageCalculator (which runs independently of this call), so this is
		-- "armor only", never damage immunity. Set/cleared by the move that owns the
		-- armor window (CombatCore guardbreak swings; SkillFunctions casts).
		if char:GetAttribute("HyperArmor") then
			return
		end

		animationHandler.StopAnim(char, "ALL")

		-- Cancel any existing stun timer
		cancelTimer(char, "Stunned")

		-- Handle stun speed. Push a STUN-priority modifier through SpeedService instead
		-- of stashing OriginalWalkSpeed. The old stash restored to a single remembered
		-- value and ignored other live modifiers, so a player hit mid-block came back at
		-- base speed instead of block speed. Now the pin just overrides while it's live
		-- and, when popped, the stack recomputes (block/skill slow still applies if held).
		local SpeedService = getSpeedService()
		if stunSpeed and stunSpeed > 0 and SpeedService then
			SpeedService.Push(char, "Stun", stunSpeed, SpeedService.Priority.STUN)
		end

		-- Lock jump for the duration. Disabling the Jumping humanoid state (rather
		-- than zeroing JumpPower) is server-authoritative, cancels an already-queued
		-- jump, and needs no value snapshot. Restored on both stun-clear paths below.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

		-- Set Stun State
		states[char]["Stunned"] = true
		char:SetAttribute("Stunned", true)

		-- Start the new timer
		if duration and type(duration) == "number" and duration > 0 then
			activeTimers[char]["Stunned"] = task.delay(duration, function()
				if not states[char] then
					return
				end

				-- Restore speed. Pop the stun modifier and let SpeedService recompute:
				-- a Downed character keeps their PIN, a still-blocking one settles to block,
				-- otherwise full base. The Downed guard on the jump-restore is kept so a
				-- downed player's jump stays disabled (the downed system re-enables it).
				local SpeedService = getSpeedService()
				if SpeedService then
					SpeedService.Pop(char, "Stun")
				end
				if char:FindFirstChild("Humanoid") and not states[char]["Downed"] then
					char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end

				clearKey(char, "Stunned")

				-- Post-stun dash lockout. The victim's hitstun is tuned so an M1 string
				-- is a true combo, but the dash client buffers a Q press and retries it
				-- every frame; without this it would fire on the very first frame the
				-- stun clears, slipping out in the sliver before the next hitbox. Hold a
				-- brief DashLocked flag (read by the Dash LocalScript) to close that gap.
				-- Skipped for Downed (already fully locked by the downed system).
				if not states[char]["Downed"] then
					char:SetAttribute("DashLocked", true)
					task.delay(0.15, function()
						if char and char.Parent then
							char:SetAttribute("DashLocked", nil)
						end
					end)
				end
			end)
		end
	else -- UN-STUNNING (Clearing Stun manually)
		-- Cancel any pending timer
		cancelTimer(char, "Stunned")

		if states[char] then
			-- Restore speed via SpeedService pop (see the timer path above for why).
			local SpeedService = getSpeedService()
			if SpeedService then
				SpeedService.Pop(char, "Stun")
			end
			if char:FindFirstChild("Humanoid") and not states[char]["Downed"] then
				char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end

			clearKey(char, "Stunned")
		end
	end
end

function module.RemoveStates(char, stateKey: string)
	if not states[char] then
		return
	end

	if stateKey then
		-- SPECIAL CASE: Stunned goes through SetStun so walkspeed is restored.
		-- SetStun(false) clears ONLY the Stunned key; it no longer drops the table.
		if stateKey == "Stunned" then
			module.SetStun(char, false)
			return
		end

		clearKey(char, stateKey)
	else
		-- Clearing ALL states. Snapshot the keys first: clearKey mutates the table.
		local keys = {}
		for key in pairs(states[char]) do
			table.insert(keys, key)
		end

		for _, key in ipairs(keys) do
			if key == "Stunned" then
				module.SetStun(char, false)
			elseif key ~= "OriginalWalkSpeed" then
				clearKey(char, key)
			end
		end

		states[char] = nil
		activeTimers[char] = nil
	end
end

-- Cleanup on player disconnect
game.Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then
		local char = plr.Character

		-- Cancel all active timers for this character
		if activeTimers[char] then
			for key in pairs(activeTimers[char]) do
				cancelTimer(char, key)
			end
			activeTimers[char] = nil
		end

		if states[char] then
			for key in pairs(states[char]) do
				plr.Character:SetAttribute(key, nil)
			end
			states[char] = nil
		end
	end
end)

return module
