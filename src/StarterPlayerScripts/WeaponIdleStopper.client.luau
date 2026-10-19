-- WeaponIdleStopper
-- Stops orphaned weapon idle animation tracks on demand.
-- Weapon inputHandlers load their idle as an AnimationTrack named "Idle".
-- During a server-driven weapon swap the old tool can be destroyed before
-- its Unequipped handler stops the idle, leaving a looping track with no
-- reference to stop it. The server fires StopWeaponIdle to clear them.
-- Nothing other than weapon equips names a track "Idle", so stopping by
-- name is safe here.

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

-- A single sweep races the swap: the old tool's Idle track can still be starting
-- (or restarting) on this frame, so one pass can miss it and leave it looping under
-- the new weapon's idle. Sweep across a few frames to catch a late starter. The new
-- weapon's own idle is only loaded when the player re-equips from the hotbar, which
-- happens after this window, so this cannot stop the intended new idle.
local function stopIdleTracks()
	for _ = 1, 4 do
		sweepOnce()
		task.wait()
	end
end

stopRemote.OnClientEvent:Connect(stopIdleTracks)
