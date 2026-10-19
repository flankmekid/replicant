-- SPDX-License-Identifier: MIT
--
-- Blocks every attack input for the committed windup once any attack (M1, M2, or E)
-- starts, without waiting for the server state to replicate. Otherwise a late M2 or E
-- press could cancel an M1 animation while the M1 still fired.

local InputGate = {}

local lockedUntil = 0

-- InputGate.IsLocked() - check whether attack input is locked
--
-- Return: true while locked.
function InputGate.IsLocked()
	return os.clock() < lockedUntil
end

-- InputGate.Lock() - lock attack input
-- @duration: the committed windup in seconds
--
-- Return: nothing.
function InputGate.Lock(duration)
	lockedUntil = os.clock() + (duration or 0)
end

-- InputGate.Unlock() - release the lock early, for example when the server declined
--
-- Return: nothing.
function InputGate.Unlock()
	lockedUntil = 0
end

return InputGate
