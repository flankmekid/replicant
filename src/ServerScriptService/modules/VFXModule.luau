local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local module = {}

-- Ensure you have the asset or use a placeholder
local wingAsset = game.ReplicatedStorage:FindFirstChild("assets")
	and game.ReplicatedStorage.assets.FX.aegir:FindFirstChild("DragonWings")

function module.Wings(rootPart)
	local wing1 = wingAsset:Clone()
	wing1.Parent = rootPart.Parent
	wing1.WeldPart.Part0 = wing1
	wing1.WeldPart.Part1 = rootPart
	game.Debris:AddItem(wing1, 1)

	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal1 = {
		Transparency = 0.6,
		--Orientation = wing1.Orientation + Vector3.new(0, -65, 0),
		Position = wing1.Position - (rootPart.CFrame.LookVector * 5),
	}
	local tw = TweenService:Create(wing1, tweenInfo, goal1)
	tw:Play()
	task.spawn(function()
		tw.Completed:Wait()
		TweenService:Create(wing1, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end)
end

return module
