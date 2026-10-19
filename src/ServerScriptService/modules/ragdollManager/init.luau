-- SPDX-License-Identifier: MIT
--
-- The server entry point for ragdolls. NPCs are ragdolled here, and players are told
-- to ragdoll on their own client through the Ragdoll remote.
local Manager = {}
local M = require(script.RagdollModule)
-- ragdollManager.Ragdoll() - ragdoll a character
-- @self: the character, passed as the first argument
-- @Duration: seconds until the character gets up, or nil to stay down
--
-- Return: nothing.
function Manager:Ragdoll(Duration)
	-- A downed body never gets up on its own. DownedManager decides when, so the
	-- duration is ignored.
	if self:GetAttribute("Downed") then
		Duration = nil
	end

	M.Ragdoll(self, Duration)

	if not game.Players:GetPlayerFromCharacter(self) then
		local Hum = self:FindFirstChildWhichIsA("Humanoid")
		if not Hum then
			return
		end
		Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		Hum:ChangeState(Enum.HumanoidStateType.Physics)

		if Duration then
			task.delay(Duration, function()
				-- The NPC may have gone down during the ragdoll.
				if not self.Parent then
					return
				end
				if self:GetAttribute("Downed") then
					return
				end
				Hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				Hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
			end)
		end
	else
		game.ReplicatedStorage.remotes.Ragdoll:FireClient(
			game.Players:GetPlayerFromCharacter(self),
			Duration
		)
	end
end

-- ragdollManager.UnRagdoll() - end a character's ragdoll
-- @self: the character, passed as the first argument
-- @force: true for a deliberate teardown by DownedManager (revive, execute, pickup).
--         Without it, a Downed body is left alone.
--
-- Return: nothing.
function Manager:UnRagdoll(force)
	M.UnRagdoll(self, force)
end

return Manager
