-- SPDX-License-Identifier: MIT
--
-- Owns character states (Stunned, Downed, CantAnything, and others) with optional
-- timers. Each state is a Lua table entry and a character attribute, written together.
-- The table is local to each VM, so client code must read the attributes. The design is
-- in docs/combat-design.md.

local module = {}

local states = {}
-- The timer of every timed state, so a new timer can cancel the old one.
local activeTimers = {}

local animationHandler = require(script.Parent.animationHandler)
local StatScaling = require(script.Parent.StatScaling)

-- The stun speed pin runs only on the server, and SpeedService is a server module. Load
-- it lazily and only on the server, so a client require never reaches into
-- ServerScriptService.
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

-- Cancels a stored timer. The timer callback itself calls clearKey, and task.cancel
-- throws on the running thread, so take the thread out of the table first and skip
-- the cancel when it is the running thread or already dead.
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

-- The only way a state key is removed. It clears the table entry and the attribute
-- together, so they never disagree, and it never drops the whole table.
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

-- stateHandler.ReturnStates() - get the state table of a character
-- @char: the character
--
-- Return: the state table of this VM, or nil.
function module.ReturnStates(char)
	return states[char]
end

-- stateHandler.CanAct() - check whether a character may act
-- @char: the character
--
-- Use this instead of checking attributes at each call site.
--
-- Return: false while Stunned, Downed, CantAnything, Ragdolled, Carried, or
-- BeingExecuted, true otherwise.
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

-- stateHandler.GetStateAttr() - read a state from the character attribute
-- @char: the character
-- @stateKey: the state name
--
-- Use this on the client. Server states never reach the client's state table, but
-- attributes replicate.
--
-- Return: the state value, or nil.
function module.GetStateAttr(char, stateKey: string)
	if not char then
		return nil
	end
	return char:GetAttribute(stateKey)
end

-- The states in which another system owns the HumanoidRootPart.
local rootOwnedStates = {
	"Downed",
	"Ragdolled",
	"Carried",
	"Carrying",
	"BeingExecuted",
	"Executing",
}

-- stateHandler.IsRootOwned() - check whether another system owns the character's root
-- @char: the character
-- @ignoreRagdoll: true to ignore a plain knockdown ragdoll
--
-- A downed ragdoll, a carry, an execution, or a Messatsu weld owns the root. Code that
-- writes HRP.CFrame every frame, such as the lock-on, must stop while this is true.
-- LockOn passes ignoreRagdoll when it asks whether it may keep a lock, because a
-- ragdoll owns the root but is no reason to drop the lock. Reads attributes, so it
-- works on the server and the client.
--
-- Return: true if another system owns the root.
function module.IsRootOwned(char, ignoreRagdoll)
	if not char then
		return false
	end
	for _, key in ipairs(rootOwnedStates) do
		if ignoreRagdoll and key == "Ragdolled" then
			continue
		end
		if char:GetAttribute(key) then
			return true
		end
	end
	-- A Messatsu grab welds two roots together, with the weld in the attacker's
	-- character. If both clients wrote CFrame to the joined bodies, the solver would fail
	-- with NaN. Check for a weld we own and for a weld that binds our root from outside.
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	-- The carry constraints are on the victim's root.
	if root:FindFirstChild("CarryPos") or root:FindFirstChild("CarryOri") then
		return true
	end

	-- A weld we own: we are the grabber.
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("WeldConstraint") and v.Enabled and (v.Part0 == root or v.Part1 == root) then
			return true
		end
	end

	-- A weld someone else owns: we are grabbed.
	for _, v in ipairs(root:GetJoints()) do
		if v:IsA("WeldConstraint") and v.Enabled then
			local other = (v.Part0 == root) and v.Part1 or v.Part0
			-- Ignore the character's own welds, such as accessories and tools.
			if other and not other:IsDescendantOf(char) then
				return true
			end
		end
	end

	return false
end

-- stateHandler.IsValidTarget() - check whether a character can be locked on to
-- @char: the character
--
-- Reads attributes, so it works on the client.
--
-- Return: true if the character is alive and not downed, carried, or executed.
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

-- stateHandler.GetState() - read a state from this VM's state table
-- @char: the character
-- @stateKey: the state name
--
-- On the client this does not see server states. Use GetStateAttr there.
--
-- Return: the state value, or nil.
function module.GetState(char, stateKey: string)
	if states[char] then
		return states[char][stateKey]
	end
	return nil
end

-- stateHandler.IsInterrupted() - check whether an attack in progress must cancel
-- @char: the character
--
-- Every weapon uses this one check.
--
-- Return: true while Stunned or Downed.
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

-- stateHandler.WatchInterrupt() - call a function when the character is interrupted
-- @char: the character
-- @window: seconds after which the watcher removes itself
-- @onInterrupt: called once when the character becomes Stunned or Downed
--
-- Use this to cancel dash movers and animations the moment a hit lands, instead of
-- after the windup.
--
-- Return: a stop function. Call it when the swing ends normally, so a later stun does
-- not trigger the watcher.
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

		-- The timeout thread itself calls disconnectAll, so never cancel the running thread.
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
			warn(`[stateHandler] WatchInterrupt callback failed: {err}.`)
		end
	end

	-- Already interrupted: fire on the next frame, so the caller has assigned its mover
	-- references before they are cancelled.
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

	return disconnectAll
end

-- stateHandler.SetState() - set a state on a character
-- @char: the character
-- @stateKey: the state name
-- @value: the state value
-- @duration: seconds until the state clears, or nil for no timer
--
-- Setting a state again replaces its old timer.
--
-- Return: nothing.
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

-- stateHandler.SetStun() - stun a character or end the stun
-- @char: the character
-- @value: true to stun, false to end the stun
-- @duration: seconds until the stun ends, or nil for no timer
-- @stunSpeed: the WalkSpeed during the stun, or nil to leave the speed alone
--
-- A stun stops the animations, locks jumping, and pins the speed through SpeedService.
-- A character with the HyperArmor attribute ignores the stun but still takes damage.
--
-- Return: nothing.
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

	if value then
		-- Hyper armor: the attacker keeps their move. Damage still applies, so this is
		-- armor, not immunity.
		if char:GetAttribute("HyperArmor") then
			return
		end

		animationHandler.StopAnim(char, "ALL")

		cancelTimer(char, "Stunned")

		-- The stun pin is a STUN-priority modifier. When it pops, SpeedService settles
		-- the speed to whatever is still active, such as a block.
		local SpeedService = getSpeedService()
		if stunSpeed and stunSpeed > 0 and SpeedService then
			SpeedService.Push(char, "Stun", stunSpeed, SpeedService.Priority.STUN)
		end

		-- Disable the Jumping state instead of zeroing JumpPower: it works from the server,
		-- cancels a queued jump, and needs no saved value.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

		states[char]["Stunned"] = true
		char:SetAttribute("Stunned", true)

		if duration and type(duration) == "number" and duration > 0 then
			activeTimers[char]["Stunned"] = task.delay(duration, function()
				if not states[char] then
					return
				end

				-- A Downed character keeps the jump lock, because the downed system re-enables it.
				local SpeedService = getSpeedService()
				if SpeedService then
					SpeedService.Pop(char, "Stun")
				end
				if char:FindFirstChild("Humanoid") and not states[char]["Downed"] then
					char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end

				clearKey(char, "Stunned")

				-- Lock dashes for a moment after the stun. The Dash LocalScript buffers a Q press
				-- and retries it every frame, so without this it would slip out of a true combo in
				-- the gap before the next hitbox. Downed characters are already locked.
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
	else
		cancelTimer(char, "Stunned")

		if states[char] then
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

-- stateHandler.RemoveStates() - clear one state, or every state, of a character
-- @char: the character
-- @stateKey: the state name, or nil for every state
--
-- Stunned is cleared through SetStun, so the speed and jump are restored.
--
-- Return: nothing.
function module.RemoveStates(char, stateKey: string)
	if not states[char] then
		return
	end

	if stateKey then
		if stateKey == "Stunned" then
			module.SetStun(char, false)
			return
		end

		clearKey(char, stateKey)
	else
		-- Copy the keys first, because clearKey changes the table.
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

game.Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then
		local char = plr.Character

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
