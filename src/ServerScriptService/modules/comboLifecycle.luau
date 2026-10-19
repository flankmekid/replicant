-- ============================================================
-- comboLifecycle (ModuleScript) -> ServerScriptService.modules
-- Shared attack lifecycle: re-entry guard + pcall + guaranteed teardown.
-- Each weapon keeps its OWN busy check; this only owns the swing run.
-- ============================================================

local Players = game:GetService("Players")

local Lifecycle = {}

-- per-player re-entry guard, keyed by an action tag so M1 and M2 don't
-- collide with each other (one player can't double-fire the SAME action mid-swing)
local active = {} -- active[plr] = { [tag] = true }

local function isActive(plr, tag)
	local t = active[plr]
	return t ~= nil and t[tag] == true
end

local function setActive(plr, tag, value)
	if value then
		if not active[plr] then active[plr] = {} end
		active[plr][tag] = true
	else
		local t = active[plr]
		if t then
			t[tag] = nil
			if next(t) == nil then active[plr] = nil end
		end
	end
end

-- plr: Player
-- opts: {
--   tag = "M1" | "M2" | ...,        -- re-entry key, required
--   cleanupDelay = number?,          -- seconds before teardown runs (default 0.1)
--   onSwing = function(ctx),         -- the full attack body
--   onCleanup = function(ctx)?,      -- teardown (reset speed, kill trails, destroy hitbox)
-- }
-- returns true if the swing was accepted and started, false if guarded out
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
		if cleaned then return end
		cleaned = true
		setActive(plr, opts.tag, false)
		if opts.onCleanup then
			local ok, err = pcall(opts.onCleanup, ctx)
			if not ok then
				warn("[Lifecycle:" .. opts.tag .. "] cleanup failed for", plr.Name, "->", err)
			end
		end
	end
	ctx.cleanup = cleanup -- expose so onSwing can force-teardown early if it wants

	local ok, err = pcall(opts.onSwing, ctx)
	if not ok then
		warn("[Lifecycle:" .. opts.tag .. "] swing failed for", plr.Name, "->", err)
		cleanup() -- crash path: tear down immediately, never strand the player
		return true -- swing was accepted; it just blew up. caller already sent no decline.
	end

	-- success path: tear down after the hitbox window closes
	task.delay(opts.cleanupDelay or 0.1, cleanup)
	return true
end

Players.PlayerRemoving:Connect(function(plr)
	active[plr] = nil
end)

return Lifecycle