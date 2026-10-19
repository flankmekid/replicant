local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BackTools = ReplicatedStorage:WaitForChild("WeldTools")

local Character = script.Parent
local Player = game.Players:GetPlayerFromCharacter(Character)
local Torso = Character:FindFirstChild('Torso')

local weaponModel = nil

function Weld(weldMe, toThis)
	local weld = Instance.new("Weld")
	weld.Part0 = weldMe
	weld.Part1 = toThis
	weld.C0 = weldMe.CFrame:ToObjectSpace(toThis.CFrame)
	weld.Parent = toThis
end

Character.ChildAdded:Connect(function(child)
	if weaponModel and BackTools:FindFirstChild(child.Name) then
		weaponModel:Destroy()
	end
end)

Character.ChildRemoved:Connect(function(child)
	local Model = BackTools:FindFirstChild(child.Name)
	if weaponModel and Model then
		weaponModel:Destroy()
	end
	if child:IsA('Tool') and Model then
		if weaponModel then
			weaponModel:Destroy()
		end
		weaponModel = Model:Clone()
		weaponModel:SetPrimaryPartCFrame(Torso.CFrame)
		weaponModel.Parent = workspace
		Weld(weaponModel.PrimaryPart, Torso)
	end
end)

for _, weap in pairs(Player.StarterGear:GetChildren()) do
	if BackTools:FindFirstChild(weap.Name) then
		local Model = BackTools:FindFirstChild(weap.Name)
		weaponModel = Model:Clone()
		weaponModel:SetPrimaryPartCFrame(Torso.CFrame)
		weaponModel.Parent = workspace
		Weld(weaponModel.PrimaryPart, Torso)
	end
end