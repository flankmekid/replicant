-- SPDX-License-Identifier: MIT
--
-- Freezes and unfreezes the local player's movement input.

local PlayerMovement = {}

-- PlayerMovement:Movement() - freeze or unfreeze movement input
-- @Player: not used
-- @move: false to freeze, true to unfreeze
--
-- Return: nothing.
function PlayerMovement:Movement(Player, move)
	local ContextActionService = game:GetService("ContextActionService")
	local FREEZE_ACTION = "freezeMovement"

	if move == false then
		ContextActionService:BindAction(FREEZE_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, unpack(Enum.PlayerActions:GetEnumItems()))
	elseif move == true then
		ContextActionService:UnbindAction(FREEZE_ACTION)
	end
end

return PlayerMovement
