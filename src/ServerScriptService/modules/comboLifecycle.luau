-- SPDX-License-Identifier: MIT
--
-- Shared attack life cycle: a re-entry guard, a pcall around the swing, and a
-- teardown that always runs. Each weapon keeps its own busy check.

local Players = game:GetService("Players")

local Lifecycle = {}

-- Re-entry guard per player and action tag, so M1 and M2 do not block each other but
-- the same action cannot fire twice during a swing. active[plr] = { [tag] = true }.
local active = {}

local function isActive(plr, tag)
	local t = active[plr]
	return t ~= nil and t[tag] == true
end

local function setActive(plr, tag, value)
	if value then
		if not active[plr] then
			active[plr] = {}
		end
		active[plr][tag] = true
	else
		local t = active[plr]
		if t then
			t[tag] = nil
			if next(t) == nil then
				active[plr] = nil
			end
		end
	end
end

-- Lifecycle.Run() - run one swing with a re-entry guard and a guaranteed teardown
-- @plr: the attacking player
-- @opts: tag (the re-entry key, required), onSwing(ctx) (the attack, required),
--        onCleanup(ctx) (the teardown), and cleanupDelay (seconds before the
--        teardown, 0.1 by default). onSwing can call ctx.cleanup() to tear down early.
--
-- Return: true if the swing started, false if the guard rejected it.
function Lifecycle.Run(plr, opts)
	assert(opts and opts.tag, "Lifecycle.Run requires opts.tag")
	assert(opts.onSwing, "Lifecycle.Run requires opts.onSwing")

	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return false
	end

	if isActive(plr, opts.tag) then
		return false
	end
	setActive(plr, opts.tag, true)

	local ctx = { plr = plr, char = char }
	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		setActive(plr, opts.tag, false)
		if opts.onCleanup then
			local ok, err = pcall(opts.onCleanup, ctx)
			if not ok then
				warn(`[comboLifecycle] Cleanup of {opts.tag} failed for {plr.Name}: {err}.`)
			end
		end
	end
	ctx.cleanup = cleanup

	local ok, err = pcall(opts.onSwing, ctx)
	if not ok then
		warn(`[comboLifecycle] Swing {opts.tag} failed for {plr.Name}: {err}.`)
		-- Tear down at once so the player is never stuck. The swing was accepted, so no
		-- decline goes to the client.
		cleanup()
		return true
	end

	-- Tear down after the hitbox window closes.
	task.delay(opts.cleanupDelay or 0.1, cleanup)
	return true
end

Players.PlayerRemoving:Connect(function(plr)
	active[plr] = nil
end)

return Lifecycle
