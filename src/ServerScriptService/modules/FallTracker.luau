-- SPDX-License-Identifier: MIT
--
-- The server's fall tracking state for each character, shared between FallDmgServer,
-- which measures falls, and every server script that moves a character, which resets
-- the measurement so a teleport never counts as a fall.

local FallTracker = {}

-- After a reset, the client can still send a position from before the move for a
-- moment, so falls do not count for this long.
local resetGrace = 0.5

-- Layout: FallTracker.tracked[character] = { airborne, startY, lastPos, resetUntil }.
FallTracker.tracked = setmetatable({}, { __mode = "k" })

-- FallTracker.Reset() - forget a character's fall in progress
-- @character: the character the caller moved
--
-- Call it right before or after writing the character's CFrame. The measurement starts
-- again from wherever the character is resetGrace seconds later.
--
-- Return: nothing.
function FallTracker.Reset(character)
	if not character then
		return
	end
	FallTracker.tracked[character] = { resetUntil = os.clock() + resetGrace }
end

return FallTracker
