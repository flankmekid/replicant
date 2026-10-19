-- SPDX-License-Identifier: MIT
--
-- Replaces the body parts of every player's avatar with the default R6 parts, so all
-- characters share one body shape.
local Appearanceconnections = {}

function overWriteCharacter(chr)
	local hDescription = chr:WaitForChild("Humanoid"):GetAppliedDescription()
	hDescription.Head = 0
	hDescription.Torso = 0
	hDescription.LeftArm = 0
	hDescription.RightArm = 0
	hDescription.LeftLeg = 0
	hDescription.RightLeg = 0
	chr.Humanoid:ApplyDescription(hDescription)
end

game.Players.PlayerAdded:Connect(function(player)
	Appearanceconnections[player.UserId] =
		player.CharacterAppearanceLoaded:Connect(overWriteCharacter)
end)
game.Players.PlayerRemoving:Connect(function(player)
	Appearanceconnections[player.UserId]:Disconnect()
end)
