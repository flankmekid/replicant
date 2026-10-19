--[[ System By @Liam 

-> Version 1.3.3

◄ If you have any questions, hit up @liam3124 on Discord. ►
 ♥ Thanks for using this!! ♥ 
¤ Subscribe: https://www.youtube.com/@Liam223?sub_confirmation=1 ¤
‼ Don't try to resell this or claim it as yours ‼

--]] 



--||Character||--
local char = script.Parent

local Torso = nil

if char:FindFirstChild("Torso") then
	Torso = char:FindFirstChild("Torso") 
elseif char:FindFirstChild("UpperTorso") then
 	Torso = char:FindFirstChild("UpperTorso")
end

local hum = char:WaitForChild("Humanoid")

------------------------------------------------------------------------------------------------------------------




--//When the player gets ragdolled / unRagdolled
char:GetAttributeChangedSignal("IsRagdoll"):Connect(function()
	local isRagdoll = char:GetAttribute("IsRagdoll")
	if isRagdoll and Torso then
		hum:ChangeState(Enum.HumanoidStateType.Ragdoll)
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		Torso:ApplyImpulse(Torso.CFrame.LookVector * 75)
	else
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)

--//this happens when the player dies
hum.Died:Connect(function()
	if not Torso then return end
	Torso:ApplyImpulse(Torso.CFrame.LookVector * 100)
end)