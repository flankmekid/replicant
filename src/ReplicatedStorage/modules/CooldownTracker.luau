-- SPDX-License-Identifier: MIT
--
-- Records started cooldowns so the HUD can show them. Display only: it never decides
-- whether an ability can fire. Each ability's own debounce does that.

local CooldownTracker = {}

-- Layout: active[id] = { label, startTime, duration }.
local active = {}
-- Ids from oldest to newest.
local order = {}

-- CooldownTracker.Register() - show a cooldown on the client HUD
-- @id: a unique key for the cooldown
-- @label: the text on the HUD entry
-- @duration: the length in seconds
--
-- Registering an active id again restarts it in place.
--
-- Return: nothing.
function CooldownTracker.Register(id, label, duration)
	if type(id) ~= "string" or type(duration) ~= "number" or duration <= 0 then
		return
	end

	if active[id] then
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
	table.insert(order, id)
end

-- CooldownTracker.GetActive() - list the active cooldowns, oldest first
--
-- Also removes the finished ones.
--
-- Return: an array of { id, label, remaining, fraction }. fraction goes from 1 at the
-- start to 0 when ready.
function CooldownTracker.GetActive()
	local now = os.clock()

	-- Iterate backwards so table.remove is safe.
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
			fraction = remaining / cd.duration,
		})
	end
	return result
end

-- CooldownTracker.Remove() - remove a cooldown early, such as when a dash charge returns
-- @id: the key used in Register
--
-- Return: nothing.
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

-- CooldownTracker.Clear() - remove every cooldown
--
-- Return: nothing.
function CooldownTracker.Clear()
	active = {}
	order = {}
end

return CooldownTracker
