-- SPDX-License-Identifier: MIT
--
-- The music player: menu, zone, and combat playlists with fades, and the play/pause and
-- skip buttons. The zone comes from a downward raycast against Workspace.Locations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MusicFolder = ReplicatedStorage:WaitForChild("music")
local AmbianceFolder = MusicFolder:WaitForChild("ambiance")
local MenuFolder = MusicFolder:WaitForChild("main_menu")
local CombatFolder = MusicFolder:WaitForChild("combat")
local LocationsFolder = Workspace:WaitForChild("Locations")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local CombatRemote = Remotes:WaitForChild("CombatTagUpdate")

local currentZone = nil
local currentAudio = nil
local currentPlaylist = nil
local isPlaying = true
local inMainMenu = true
local inCombat = false

-- The running volume tween, so a new one can cancel it. Two tweens on Volume fight.
local activeVolumeTween = nil

local FADE_DURATION = 1.5
local RAYCAST_INTERVAL = 0.5
local timeSinceLastCast = 0

-- Set by BindGui, so the script works whether or not MusicUI resets on spawn.
local ControlFrame = nil
local PlayPauseBtn = nil
local SkipBtn = nil

local zoneRayParams = RaycastParams.new()
zoneRayParams.FilterType = Enum.RaycastFilterType.Include
zoneRayParams.FilterDescendantsInstances = { LocationsFolder }

local function cancelVolumeTween()
	if activeVolumeTween then
		activeVolumeTween:Cancel()
		activeVolumeTween = nil
	end
end

local function tweenVolume(audio, duration, target)
	cancelVolumeTween()
	activeVolumeTween = TweenService:Create(audio, TweenInfo.new(duration), { Volume = target })
	activeVolumeTween:Play()
	return activeVolumeTween
end

local function refreshButtonVisual()
	if PlayPauseBtn then
		PlayPauseBtn.ImageTransparency = isPlaying and 0 or 0.5
	end
end

local PlayRandomTrackFromFolder

local function PlayTrack(newAudioObject)
	if currentAudio == newAudioObject then
		currentAudio.TimePosition = 0
		if isPlaying and not currentAudio.IsPlaying then
			currentAudio:Play()
		end
		return
	end

	local oldAudio = currentAudio
	currentAudio = newAudioObject

	local baseVolume = currentAudio:GetAttribute("BaseVolume")
	if not baseVolume then
		baseVolume = currentAudio.Volume
		currentAudio:SetAttribute("BaseVolume", baseVolume)
	end

	if currentAudio then
		currentAudio.TimePosition = 0
		currentAudio.Volume = 0
		currentAudio.Looped = false

		-- The new track owns the tween now.
		cancelVolumeTween()

		if isPlaying then
			currentAudio:Play()
			tweenVolume(currentAudio, FADE_DURATION, baseVolume)
		else
			currentAudio:Play()
			currentAudio:Pause()
		end
		refreshButtonVisual()

		currentAudio.Ended:Once(function()
			if currentAudio == newAudioObject then
				if currentPlaylist then
					-- A natural skip to the next song.
					PlayRandomTrackFromFolder(currentPlaylist, true)
				end
			end
		end)
	end

	if oldAudio then
		-- The old track fades out on its own tween and stops when silent.
		local fadeOut = TweenService:Create(oldAudio, TweenInfo.new(FADE_DURATION), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			if oldAudio ~= currentAudio then
				oldAudio:Stop()
			end
		end)
	end
end

PlayRandomTrackFromFolder = function(folder, isSkip)
	-- Keep playing the same playlist unless this is a skip.
	if folder == currentPlaylist and not isSkip then
		return
	end

	local tracks = folder:GetChildren()
	if #tracks == 0 then
		return
	end

	currentPlaylist = folder

	local randomTrack
	if #tracks == 1 then
		randomTrack = tracks[1]
	else
		repeat
			randomTrack = tracks[math.random(1, #tracks)]
		until randomTrack ~= currentAudio
	end

	PlayTrack(randomTrack)
end

local function CheckZone()
	if inMainMenu or inCombat then
		return
	end

	local char = LocalPlayer.Character
	if not char then
		return
	end

	local head = char:FindFirstChild("Head")
	if not head then
		return
	end

	local raycastResult = Workspace:Raycast(head.Position, Vector3.new(0, 500, 0), zoneRayParams)
	local hitZoneName = raycastResult and raycastResult.Instance.Name or "Ambiance"

	if hitZoneName ~= currentZone then
		currentZone = hitZoneName

		local targetFolder = MusicFolder:FindFirstChild(currentZone)
		if not targetFolder then
			targetFolder = AmbianceFolder
		end

		PlayRandomTrackFromFolder(targetFolder)
	end
end

-- BindGui connects the buttons of the current MusicUI. It can run again after a reset.

local playPauseDebounce = false
local skipDebounce = false

local function BindGui()
	local musicUi = PlayerGui:WaitForChild("MusicUI", 10)
	if not musicUi then
		return
	end

	ControlFrame = musicUi:WaitForChild("Frame", 10)
	if not ControlFrame then
		return
	end

	PlayPauseBtn = ControlFrame:WaitForChild("PlayPause", 10)
	SkipBtn = ControlFrame:WaitForChild("Skip", 10)
	if not PlayPauseBtn or not SkipBtn then
		return
	end

	if not inMainMenu then
		ControlFrame.Visible = true
	end
	refreshButtonVisual()

	PlayPauseBtn.MouseButton1Click:Connect(function()
		if playPauseDebounce then
			return
		end
		if not currentAudio then
			return
		end
		playPauseDebounce = true

		-- Decide the state now, so a later click cannot change this pause during the fade.
		isPlaying = not isPlaying
		local shouldPlay = isPlaying
		refreshButtonVisual()

		if shouldPlay then
			currentAudio:Resume()
			local baseVolume = currentAudio:GetAttribute("BaseVolume") or 0.5
			tweenVolume(currentAudio, 0.5, baseVolume)
		else
			local audioAtClick = currentAudio
			local fadeOut = tweenVolume(currentAudio, 0.5, 0)
			fadeOut.Completed:Once(function(state)
				-- Pause only if the fade finished without a newer click, on the same track.
				if
					state == Enum.PlaybackState.Completed
					and not isPlaying
					and currentAudio == audioAtClick
				then
					currentAudio:Pause()
				end
			end)
		end

		task.wait(0.15)
		playPauseDebounce = false
	end)

	SkipBtn.MouseButton1Click:Connect(function()
		if currentPlaylist and not skipDebounce then
			skipDebounce = true
			PlayRandomTrackFromFolder(currentPlaylist, true)
			task.wait(0.5)
			skipDebounce = false
		end
	end)
end

local function BindMainMenuButton()
	local mainMenu = PlayerGui:WaitForChild("MainMenu", 10)
	if not mainMenu then
		return
	end

	local playBtn = mainMenu:WaitForChild("MainFrame", 10)
	if not playBtn then
		return
	end
	playBtn = playBtn:WaitForChild("Buttons"):WaitForChild("Play"):WaitForChild("TextButton")

	playBtn.MouseButton1Click:Connect(function()
		inMainMenu = false
		if ControlFrame then
			ControlFrame.Visible = true
		end
		currentZone = nil
		CheckZone()
	end)
end

CombatRemote.OnClientEvent:Connect(function(isInCombat, duration)
	if inCombat == isInCombat then
		return
	end

	inCombat = isInCombat

	if inCombat then
		PlayRandomTrackFromFolder(CombatFolder)
	else
		currentZone = nil
		CheckZone()
	end
end)

RunService.Heartbeat:Connect(function(dt)
	timeSinceLastCast += dt
	if timeSinceLastCast >= RAYCAST_INTERVAL then
		timeSinceLastCast = 0
		CheckZone()
	end
end)

local function Init()
	BindMainMenuButton()
	BindGui()

	if inMainMenu then
		PlayRandomTrackFromFolder(MenuFolder)
	end
end

Init()
