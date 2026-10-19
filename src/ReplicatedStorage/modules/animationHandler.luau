local module = {}

local preloaded = {}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

module.Anims = {}

local function getAnimator(char)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "Animator"
		animator.Parent = humanoid
	end

	return animator
end

-- [UPDATED] Added 'speed' parameter (defaults to 1 if nil)
function module.LoadAnim(
	char,
	_type: string,
	animID: string,
	keyframeCallback: number,
	isLooped: boolean,
	speed: number
)
	if not char or not _type or not animID then
		return
	end

	local animator = getAnimator(char)
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animID
	local track = animator:LoadAnimation(animation)

	module.Anims[char] = module.Anims[char] or {}
	module.Anims[char][_type] = module.Anims[char][_type] or {}

	local connections = {}

	if keyframeCallback then
		table.insert(
			connections,
			track.KeyframeReached:Connect(function(markerName)
				keyframeCallback(markerName)
			end)
		)
	end

	table.insert(
		connections,
		track.Stopped:Connect(function()
			module.RemoveAnim(char, _type, animID)
		end)
	)

	module.Anims[char][_type][animID] = {
		Track = track,
		Connections = connections,
	}

	-- Apply the speed
	track:Play()
	if speed then
		track:AdjustSpeed(speed)
	end

	if not isLooped then
		-- Calculate cleanup time based on speed to avoid deleting too early or too late
		local adjustedLength = track.Length / (speed or 1)
		Debris:AddItem(track, adjustedLength + 1)
	end

	return track
end

function module.GetAnims(char, animType)
	if not module.Anims[char] then
		return {}
	end
	if animType then
		return module.Anims[char][animType] or {}
	end
	return module.Anims[char]
end

function module.GetTrack(char, _type: string, animID: string)
	local entry = module.Anims[char]
		and module.Anims[char][_type]
		and module.Anims[char][_type][animID]
	return entry and entry.Track or nil
end

function module.ConnectKeyframeReached(char, _type: string, animID: string, callback)
	local entry = module.Anims[char]
		and module.Anims[char][_type]
		and module.Anims[char][_type][animID]

	if entry and entry.Track then
		local connection = entry.Track.KeyframeReached:Connect(callback)
		table.insert(entry.Connections, connection)
		return connection
	end

	warn("Could not find animation to connect KeyframeReached:", animID)
	return nil
end

-- Hitstop: freeze every currently-playing track for `char` to speed 0, then
-- restore each track's prior speed after `duration`. Re-entrant: overlapping
-- hitstops share one restore window keyed per track, so a second hit during a
-- freeze extends rather than double-restores. Purely cosmetic (animation only);
-- movement locking is handled separately by the caller.
module._hitstopState = module._hitstopState or setmetatable({}, { __mode = "k" })

function module.Hitstop(char: Model, duration: number)
	if not char then
		return
	end
	duration = duration or 0.12
	local charAnims = module.Anims[char]
	if not charAnims then
		return
	end

	local frozen = module._hitstopState[char]
	if not frozen then
		frozen = {}
		module._hitstopState[char] = frozen
	end

	for _, byType in pairs(charAnims) do
		for _, entry in pairs(byType) do
			local track = entry and entry.Track
			if track and track.IsPlaying and track.Speed > 0 then
				-- remember the speed we came from, but only the first time we freeze
				-- this track (so re-freezing mid-hitstop doesn't record 0)
				if frozen[track] == nil then
					frozen[track] = track.Speed
				end
				track:AdjustSpeed(0)
			end
		end
	end

	task.delay(duration, function()
		local state = module._hitstopState[char]
		if not state then
			return
		end
		for track, prevSpeed in pairs(state) do
			if track and track.IsPlaying and track.Speed == 0 then
				track:AdjustSpeed(prevSpeed or 1)
			end
		end
		module._hitstopState[char] = nil
	end)
end

-- NEW FUNCTION: Pauses animation(s)
-- @param duration (optional): If provided, the animation will resume automatically after this time (Hitstop)
function module.PauseAnim(char: Model, _type: string, animID: string, duration: number)
	module.Anims[char] = module.Anims[char] or {}
	module.Anims[char][_type] = module.Anims[char][_type] or {}

	local function modifyTrack(entry)
		if entry and entry.Track and entry.Track.IsPlaying then
			entry.Track:AdjustSpeed(0.25) -- Freeze

			-- Handle automatic resuming (Hitstop logic)
			if duration and duration > 0 then
				task.delay(duration, function()
					-- Ensure track still exists and hasn't been removed/stopped manually
					if entry.Track and entry.Track.IsPlaying and entry.Track.Speed == 0 then
						entry.Track:AdjustSpeed(1)
					end
				end)
			end
		end
	end

	if _type == "ALL" then
		for _, entry in pairs(module.Anims[char]) do
			modifyTrack(entry)
			print("paused all anims")
		end
	else
		if animID then
			-- Pause specific animation
			modifyTrack(module.Anims[char][_type][animID])
			print("paused anim")
		else
			-- Pause ALL animations in this category (e.g. Pause all "Attacks")
			for _, entry in pairs(module.Anims[char]) do
				modifyTrack(entry)
				print("paused all anims")
			end
		end
	end
end

-- NEW FUNCTION: Resumes animation(s) manually
function module.ResumeAnim(char, _type: string, animID: string)
	module.Anims[char] = module.Anims[char] or {}
	module.Anims[char][_type] = module.Anims[char][_type] or {}

	local function modifyTrack(entry)
		if entry and entry.Track and entry.Track.IsPlaying then
			entry.Track:AdjustSpeed(1)
		end
	end

	if _type == "ALL" then
		for _, entry in pairs(module.Anims[char]) do
			modifyTrack(entry)
			print("paused all anims")
		end
	else
		if animID then
			-- Pause specific animation
			modifyTrack(module.Anims[char][_type][animID])
			print("paused anim")
		else
			-- Pause ALL animations in this category (e.g. Pause all "Attacks")
			for _, entry in pairs(module.Anims[char]) do
				modifyTrack(entry)
				print("paused all anims")
			end
		end
	end
end

function module.IsAnim(char, _type: string, animID: string)
	local entry = module.Anims[char]
		and module.Anims[char][_type]
		and module.Anims[char][_type][animID]
	return entry and entry.Track and entry.Track.IsPlaying or false
end

function module.RemoveAnim(char, _type: string, animID: string)
	local animData = module.Anims[char]
		and module.Anims[char][_type]
		and module.Anims[char][_type][animID]
	if animData then
		if animData.Track then
			animData.Track:Stop()
			animData.Track:Destroy()
		end

		if animData.Connections then
			for _, conn in ipairs(animData.Connections) do
				if conn.Connected then
					conn:Disconnect()
				end
			end
		end

		module.Anims[char][_type][animID] = nil

		if next(module.Anims[char][_type]) == nil then
			module.Anims[char][_type] = nil
		end
		if next(module.Anims[char]) == nil then
			module.Anims[char] = nil
		end
	end
end

function module.StopAnim(char: Player, _type: string, animID: string)
	if not module.Anims[char] then
		return
	end

	if _type == "ALL" then
		for typeKey, anims in pairs(module.Anims[char]) do
			for id in pairs(anims) do
				module.RemoveAnim(char, typeKey, id)
			end
		end
	else
		if animID then
			module.RemoveAnim(char, _type, animID)
		else
			for id in pairs(module.Anims[char][_type] or {}) do
				module.RemoveAnim(char, _type, id)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	local char = player.Character or player:FindFirstChild("Character")
	if module.Anims[char] then
		module.StopAnim(char, "ALL")
		module.Anims[char] = nil
	end
end)

function module.PreloadAnimations(char, animList)
	local animator = getAnimator(char)
	if not animator then
		return
	end
	for _, animID in ipairs(animList) do
		if not preloaded[animID] then
			local animation = Instance.new("Animation")
			animation.AnimationId = animID
			animation.Parent = char

			game:GetService("ContentProvider"):PreloadAsync({ animation })

			local track = animator:LoadAnimation(animation)
			track:AdjustSpeed(0)
			track:Play()
			track:Stop()

			animation:Destroy()
			preloaded[animID] = true
		end
	end
end

local AnimationIdsToPreload = {
	--fists (bandages)
	"rbxassetid://131646776816840", --Lunge [Atk6]
	"rbxassetid://120719298691152", --M2

	--fists (shackles)
	"rbxassetid://91594781717410", --Atk1 --old: 118036252209789
	"rbxassetid://85174374982448", --Atk2 --old: 75826573172649
	"rbxassetid://126029733860542", --Atk3 --old: 87550115195472
	"rbxassetid://83421056516300", --Atk4 --old: 135048698912271
	"rbxassetid://127652739314319", --Atk5 --old: 12084982971
	"rbxassetid://112488887193091", --M2
	"rbxassetid://110592013279586", --Aerial M2
	"rbxassetid://129341879780968", --EAtk
	"rbxassetid://90274625983274", --Block
	"rbxassetid://12075933616", --Parry
	"rbxassetid://101513335589823", -- ULT (attacker)
	"rbxassetid://73915210544765", -- ULT (defender)

	--dagger
	"rbxassetid://113064652209163", --Atk1 --old: 107844876090586
	"rbxassetid://139414553077908", --Atk2 --old: 97402296978242
	"rbxassetid://129665787591050", --Atk3 --old:107844876090586
	"rbxassetid://132164060511681", --Atk4 --old: 77033380901540
	"rbxassetid://135589429108202", --Atk5 --old: 128783724078586
	"rbxassetid://116928872151839", --Lunge [Atk6]
	"rbxassetid://131630220640395", --Air [Atk7]
	"rbxassetid://105653775477364", --M2
	"rbxassetid://72037949342562", --EAtk
	"rbxassetid://88771475533388", --Block
	"rbxassetid://12075933616", --Parry

	--tanto
	"rbxassetid://116490680994705", --daggerThrow
	"rbxassetid://115237120299356", --EAtk
	"rbxassetid://115983114799315", --SpAtk2

	--scythe
	"rbxassetid://85617413780831", --Atk1 --old: 74535696665387
	"rbxassetid://100835881970712", --Atk2 --old: 71402041930858
	"rbxassetid://85617413780831", --Atk3 --old: 92572967396962
	"rbxassetid://91201840746245", --Atk4 --old: 107276012652729
	"rbxassetid://124209719397794", --Atk5 --old: 87262517685983
	"rbxassetid://104237193184444", --Lunge [Atk6]
	"rbxassetid://125596523289062", --Air [Atk7]
	"rbxassetid://128904437387172", --E

	--guandao
	"rbxassetid://124210375406879", --s1
	"rbxassetid://100711039492817", --s2
	"rbxassetid://72337130586284", --s3

	--katana
	"rbxassetid://114445073328189", --Atk1 --old: 74535696665387
	"rbxassetid://133004135285326", --Atk2 --old: 71402041930858
	"rbxassetid://80789854734263", --Atk3 --old: 92572967396962
	"rbxassetid://104365254449720", --Atk4 --old: 107276012652729
	"rbxassetid://133831562453891", --Atk5 --old: 87262517685983
	"rbxassetid://106820530333875", --Lunge [Atk6]
	"rbxassetid://133184595696252", --Air [Atk7]
	"rbxassetid://99454982620637", --M2
	"rbxassetid://105034588643859", --EAtk
	"rbxassetid://108301561470863", --Block
	"rbxassetid://85755994980927", --Parry

	--greatsword
	"rbxassetid://12074816470", --Atk1
	"rbxassetid://12074817864", --Atk2
	"rbxassetid://12074838957", --Atk3
	"rbxassetid://12074836890", --Atk4
	"rbxassetid://12074819641", --Atk5
	"rbxassetid://12074847009", --Lunge [Atk6]
	"rbxassetid://120024992814931", --Air [Atk7]
	"rbxassetid://113982059903937", --Uppercut [Atk8]
	"rbxassetid://12074867177", --M2
	"rbxassetid://89138660171326", --E
	"rbxassetid://75746825553579", --Block
	"rbxassetid://12075933616", --Parry

	--dragonslayer
	"rbxassetid://90438398769518", --M2
	"rbxassetid://129202616365258", --Whirlwind
	"rbxassetid://81314710758281", --Abyssal Scream
	"rbxassetid://81970199114583", --Berserker Armor

	--sword and shield
	"rbxassetid://95741265754072", --Atk1 --old: 74535696665387
	"rbxassetid://137684081723536", --Atk2 --old: 71402041930858
	"rbxassetid://95741265754072", --Atk3 --old: 92572967396962
	"rbxassetid://137684081723536", --Atk4 --old: 107276012652729
	"rbxassetid://109278941983106", --Lunge [Atk6]
	"rbxassetid://85616104803022", --Air [Atk7]
	"rbxassetid://113982059903937", --Uppercut [Atk8]
	"rbxassetid://137977683268052", --M2
	"rbxassetid://98445666179570", --Block
	"rbxassetid://128724578433172", --Parry

	--caestus
	"rbxassetid://120522365139110", --Atk1
	"rbxassetid://118388583927592", --Atk2
	"rbxassetid://134477588734123", --Atk3
	"rbxassetid://131646776816840", --Lunge [Atk6]
	"rbxassetid://89409612525164", --Air [Atk7]
	"rbxassetid://89428867846129", --M2
	"rbxassetid://78626426378686", --Block

	--vermillion
	"rbxassetid://121694381561946", --M2

	--excalibur
	"rbxassetid://117555274895512", --Atk1 --old: 74535696665387
	"rbxassetid://81811424657955", --Atk2 --old: 71402041930858
	"rbxassetid://132064005321533", --Atk3 --old: 92572967396962
	"rbxassetid://127657179139040", --Atk4 --old: 107276012652729
	"rbxassetid://127322241276345", --Lunge [Atk5]
	"rbxassetid://90007274513754", --Air [Atk6]
	"rbxassetid://113982059903937", --Uppercut [Atk7]
	"rbxassetid://105579656851449", -- Elfin Dance
	"rbxassetid://128012851889140", -- Air Wave

	"rbxassetid://133000376160967", --M2
	"rbxassetid://106055406798496", --E

	"rbxassetid://86099520309760", --Block
	"rbxassetid://116806359529444", --Parry

	-- dark knight
	"rbxassetid://78646471226698", --Idle (torso)
	"rbxassetid://126116554289996", --Idle (legs)

	--extras
	"rbxassetid://113982059903937", --Uppercut
	"rbxassetid://96311777205911",
	"rbxassetid://111089735892609", -- hits
	"rbxassetid://118025182512218",
	"rbxassetid://91901047304475", --climbing anims
	"rbxassetid://71959991904098", -- rise
	"rbxassetid://89337388294441", -- fist dash
	"rbxassetid://108425878268854", -- fist ult windup
	"rbxassetid://97964685841149", -- monastic stance
	"rbxassetid://122781628053647", -- rising dragon
	"rbxassetid://98387922517299", -- judgementcut start
	"rbxassetid://89034380090419", -- judgementcut end
	"rbxassetid://139345216330283", -- katana dash1
	"rbxassetid://77971444416399", -- katana dash2

	--parried anims
	"rbxassetid://12075943075", --old
	"rbxassetid://74891530644094", --katana/fists
	"rbxassetid://125236478541602", --gs
	"rbxassetid://116383775729821", --dagger
	"rbxassetid://83649127182166", --sword

	--skill anims
	"rbxassetid://130627090034596", --meskari
	"rbxassetid://70984351311195", --arach grapple
	"rbxassetid://84861768973112", --vamp grab
	"rbxassetid://108023368315027", --vamp bite
	"rbxassetid://98864333664089", --bomb throw
	"rbxassetid://126568014162974", --human buff
	"rbxassetid://117886434655481", --elezen mana regen
	"rbxassetid://84818556494893", --rooted
	"rbxassetid://110763167362898", --maw bite
}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
		task.wait(0.1)
		module.PreloadAnimations(char, AnimationIdsToPreload)
	end)
	player.CharacterRemoving:Connect(function(oldChar)
		if module.Anims[oldChar] then
			module.StopAnim(oldChar, "ALL")
			module.Anims[oldChar] = nil
		end
	end)
end)

return module
