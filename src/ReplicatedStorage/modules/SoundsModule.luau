local module = {}

--||Services||--
local Debris = game:GetService("Debris")

------------------------------------------------------------------------------------------------------------------


--[[
the paramters are: the sound instance, the parent of the sound and the time it takes to destroy the sound instance

so as an example if you have a part in workspace and a Sound under this script you can just do:

module.PlaySound(script.Sound, workspace.Part, 5) 
]]


--//
function module.PlaySound(Sound: Sound, Parent, DestroyTime: number) 
	local sound = Sound:Clone()
	sound.Parent = Parent
	sound:Play()
	
	Debris:AddItem(sound,DestroyTime)
end


return module
