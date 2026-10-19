-- Client-side cross-input gate. Shared by M1/M2/E so that once ANY attack input
-- commits, every attack input is blocked for the committed windup, immediately and
-- without waiting for the server-set state to replicate back. This closes the window
-- that let a delayed M2/E press interrupt an M1 animation while the attack still fired.
local InputGate = {}

local lockedUntil = 0

function InputGate.IsLocked()
	return os.clock() < lockedUntil
end

-- lock for `duration` seconds (the attack's committed windup)
function InputGate.Lock(duration)
	lockedUntil = os.clock() + (duration or 0)
end

-- release early (e.g. the server declined the attack, so the player is free again)
function InputGate.Unlock()
	lockedUntil = 0
end

return InputGate
