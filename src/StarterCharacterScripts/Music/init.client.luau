local player = game.Players.LocalPlayer

repeat
	wait()
until player.Character:FindFirstChild("Humanoid")

local Sounds = game:GetService("ReplicatedStorage").music:GetChildren()

local localSound = script.Sound

local Sound

player.Character:WaitForChild("Humanoid").Died:connect(function()
	if Sound then
		Sound:Stop()
	end
end)

while true do
	local RandomIndex = math.random(1, #Sounds)

	Sound = Sounds[RandomIndex]

	localSound.SoundId = Sound.SoundId
	localSound.Volume = Sound.Volume
	localSound:Play()

	localSound.Ended:Wait()
end
