--[[
	CooldownTracker
	DISPLAY ONLY. This module never gates whether an ability fires. It only records that
	a cooldown has started so the GUI can show it. Existing debounces remain the source of truth.

	API:
		CooldownTracker.Register(id, label, duration)
		CooldownTracker.GetActive() -> ordered list for the GUI (also prunes completed entries)
]]

local CooldownTracker = {}

-- active[id] = { label = string, startTime = number, duration = number }
local active = {}
-- order = { id1, id2, ... }  FIFO: index 1 = oldest still-active, last = newest
local order = {}

-- Register (or refresh) a cooldown.
-- id:       unique key per ability instance, e.g. "Greatsword_E".
--           If already active, refresh in place (no duplicate entry, no reorder).
-- label:    display text, e.g. "Critical". The "(2.4)" countdown is appended by the GUI.
-- duration: FULL seconds until the ability is actually usable again (windup + lockout).
function CooldownTracker.Register(id, label, duration)
	if type(id) ~= "string" or type(duration) ~= "number" or duration <= 0 then
		return
	end

	if active[id] then
		-- refresh in place
		active[id].startTime = os.clock()
		active[id].duration = duration
		active[id].label = label or active[id].label
		return
	end

	active[id] = {
		label = label or id,
		startTime = os.clock(),
		duration = duration,
	}
	table.insert(order, id) -- new entries go to the END (newest)
end

-- Returns the ordered list of active cooldowns. Prunes completed ones as a side effect.
-- Each entry: { id, label, remaining (>=0), fraction (1 at start -> 0 at end) }
function CooldownTracker.GetActive()
	local now = os.clock()

	-- prune completed (iterate backwards so table.remove is safe)
	for i = #order, 1, -1 do
		local id = order[i]
		local cd = active[id]
		if not cd then
			table.remove(order, i)
		else
			local remaining = cd.duration - (now - cd.startTime)
			if remaining <= 0 then
				active[id] = nil
				table.remove(order, i)
			end
		end
	end

	local result = {}
	for _, id in ipairs(order) do
		local cd = active[id]
		local remaining = math.max(cd.duration - (now - cd.startTime), 0)
		table.insert(result, {
			id = id,
			label = cd.label,
			remaining = remaining,
			fraction = remaining / cd.duration, -- 1 at start, 0 when ready
		})
	end
	return result
end

-- Remove a single active cooldown by id (e.g. when an ability becomes usable
-- again early, like a dash charge returning). Safe no-op if not present.
function CooldownTracker.Remove(id)
	if active[id] then
		active[id] = nil
		for i = #order, 1, -1 do
			if order[i] == id then
				table.remove(order, i)
				break
			end
		end
	end
end

-- Optional helper for testing/cleanup.
function CooldownTracker.Clear()
	active = {}
	order = {}
end

return CooldownTracker
