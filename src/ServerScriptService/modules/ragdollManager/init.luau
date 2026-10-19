local Manager = {}
local M = require(script.RagdollModule) 
--local stun = require(game.ServerStorage.Modules.StunHandlerV2)

--- Call this module directely if u wanna ragdoll from server
function Manager:Ragdoll(Duration)
	-- A Downed body never auto-recovers. DownedManager owns when they get up
	-- (revive timer / execute / pickup). Any duration passed in is ignored, so
	-- neither the server NPC timer below nor the client timer in RagOnDeath gets
	-- scheduled. Previously a 2s ragdoll landing on a downed player would fire
	-- ChangeState(GettingUp) two seconds later and stand them back up mid-downed.
	if self:GetAttribute("Downed") then
		Duration = nil
	end

	M.Ragdoll(self,Duration)

	if not game.Players:GetPlayerFromCharacter(self) then
		local Hum = self:FindFirstChildWhichIsA("Humanoid")
		if not Hum then return end
		Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp,false)
		Hum:ChangeState(Enum.HumanoidStateType.Physics)
		--stun.Stun(Hum, Duration)

		if Duration then
			task.delay(Duration,function()
				-- re-check: they may have been knocked down inside the window
				if not self.Parent then return end
				if self:GetAttribute("Downed") then return end
				Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp,true)
				Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				Hum:SetStateEnabled(Enum.HumanoidStateType.Physics,false)

			end)
		end
	else
		game.ReplicatedStorage.remotes.Ragdoll:FireClient(game.Players:GetPlayerFromCharacter(self),Duration)
	end
end

-- force = true means a deliberate teardown by DownedManager (revive / execute /
-- pickup). Without force, UnRagdoll will not disturb a Downed body.
function Manager:UnRagdoll(force)
	M.UnRagdoll(self, force)
	--[[
	local h = highlight:Clone()
	h.Parent = self
	game.TweenService:Create(h, .5, {FillTransparency = 0.35}):Play()
	task.wait(0.5)
	game.TweenService:Create(h, .5, {FillTransparency = 1}):Play()
	game.Debris:AddItem(h, 0.5)
	]]
end

return Manager