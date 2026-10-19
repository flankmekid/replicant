-- SPDX-License-Identifier: MIT
--
-- Stops leftover weapon idle animations when the server fires StopWeaponIdle. During a
-- weapon swap the old tool can be destroyed before it stops its "Idle" track, which
-- then loops with no reference. Only weapon idles use that track name, so stopping by
-- name is safe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local stopRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("StopWeaponIdle")

local function sweepOnce()
	local char = plr.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Name == "Idle" then
			track:Stop()
		end
	end
end

-- The old idle can still be starting on this frame, so sweep for a few frames. The new
-- weapon's idle loads only when the player equips it from the hotbar, after this window.
local function stopIdleTracks()
	for _ = 1, 4 do
		sweepOnce()
		task.wait()
	end
end

stopRemote.OnClientEvent:Connect(stopIdleTracks)
