-- SPDX-License-Identifier: MIT
--
-- Plays a copy of a sound and removes it after a set time.

local module = {}

local Debris = game:GetService("Debris")

-- SoundsModule.PlaySound() - play a copy of a sound
-- @Sound: the sound to copy
-- @Parent: where to play it
-- @DestroyTime: seconds until the copy is removed
--
-- Return: nothing.
function module.PlaySound(Sound: Sound, Parent, DestroyTime: number)
	local sound = Sound:Clone()
	sound.Parent = Parent
	sound:Play()

	Debris:AddItem(sound, DestroyTime)
end

return module
