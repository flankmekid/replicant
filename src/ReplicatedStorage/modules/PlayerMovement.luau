local PlayerMovement = {}

function PlayerMovement:Movement(Player, move)

	local ContextActionService = game:GetService("ContextActionService")
	local FREEZE_ACTION = "freezeMovement"

	if move == false then

		ContextActionService:BindAction(
			FREEZE_ACTION,
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			unpack(Enum.PlayerActions:GetEnumItems())
		)

	elseif move == true then

		ContextActionService:UnbindAction(FREEZE_ACTION)

	end

end

return PlayerMovement