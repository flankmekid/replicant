local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local RaceConfig = require(ReplicatedStorage.modules.RaceConfig)
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

-- Logic Modules
local SkillFunctions = require(ServerScriptService.modules.SkillFunctions)
local BuffService = require(ServerScriptService.modules.BuffService)
local RacialSkills = require(ServerScriptService.modules.RacialSkills) -- [NEW] Require the racial module

local CastSkillRemote = ReplicatedStorage.remotes.CastSkill
local serverCooldowns = {}

-- [[ CLIENT COOLDOWN IS SERVER-CONFIRMED ]] --
-- The client no longer arms its own cooldown (and the HUD swipe) optimistically the
-- instant it fires the cast. It waits for this reply. That way a cast the server
-- REJECTS (state check, ownership desync, resource desync, or the server-cooldown
-- guard firing when the client thought it was ready) never puts the skill on cooldown
-- on the client. Pressing the button at the wrong time costs nothing; only a cast the
-- server actually spends resources on arms the cooldown. We reuse the CastSkill remote
-- for the reply: "Accepted" carries the authoritative cooldown the client should show;
-- "Declined" lets the client drop its predictive guard immediately instead of eating it.
local function reply(player, skillName, decision, cooldown)
	CastSkillRemote:FireClient(player, {
		Func = "CastResponse",
		Skill = skillName,
		Decision = decision,
		Cooldown = cooldown, -- present only on Accepted
	})
end

CastSkillRemote.OnServerEvent:Connect(function(player, skillName, mouseHit)
	-- Guard against the client receiving its own reply table echoed back up. The client
	-- only ever fires (skillName: string, mouseHit). A table here is not a cast request.
	if type(skillName) ~= "string" then
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
		reply(player, skillName, "Declined")
		return
	end

	-- 0. State Check (Prevent casting if stunned/etc on server side too for safety)
	if
		char:GetAttribute("Stunned")
		or char:GetAttribute("CantAnything")
		or char:GetAttribute("Downed")
	then
		reply(player, skillName, "Declined")
		return
	end

	-- 1. Get Config
	local skillInfo = SkillConfig.Skills[skillName]
	if not skillInfo then
		reply(player, skillName, "Declined")
		return
	end

	-- 2. Verify Ownership (Hybrid Check)
	local isVerified = false

	-- A: Check if it's a Racial Skill
	local playerRace = player:FindFirstChild("PlayerStats")
		and player.PlayerStats:FindFirstChild("Race")
		and player.PlayerStats.Race.Value
	if playerRace and SkillConfig.RaceSkills[playerRace] == skillName then
		isVerified = true
	else
		-- B: Check if it's an Unlocked Spell
		-- We use the new HasSpell function since skills/spells are saved separately from tools now
		if DataManager.HasSpell(player, skillName) then
			isVerified = true
		end
	end

	if not isVerified then
		warn(player.Name .. " attempted to cast unowned skill: " .. skillName)
		reply(player, skillName, "Declined")
		return
	end

	-- 3. Check Server Cooldown
	if not serverCooldowns[player] then
		serverCooldowns[player] = {}
	end
	local lastUse = serverCooldowns[player][skillName] or 0
	if os.time() < lastUse then
		reply(player, skillName, "Declined")
		return
	end

	-- 4. Resource Check
	local manaCost = skillInfo.Mana or 0
	local hpCost = skillInfo.HPCost or 0

	local stats = player:FindFirstChild("PlayerStats")
	local mana = stats and stats:FindFirstChild("Mana")

	if not mana or mana.Value < manaCost then
		reply(player, skillName, "Declined")
		return
	end
	if char.Humanoid.Health <= hpCost then
		reply(player, skillName, "Declined")
		return
	end

	-- 5. CONSUME
	mana.Value -= manaCost
	char.Humanoid.Health -= hpCost

	-- 6. SET COOLDOWN
	local cooldown = skillInfo.Cooldown or 1
	serverCooldowns[player][skillName] = os.time() + cooldown

	-- 6b. CONFIRM TO CLIENT
	-- Cast is committed; tell the client to arm its cooldown + HUD now (and only now).
	reply(player, skillName, "Accepted", cooldown)

	-- 7. EXECUTE LOGIC
	-- Remove spaces (e.g., "Solar Flare" -> "SolarFlare")
	local funcName = string.gsub(skillName, "%s+", "")

	print(funcName)

	-- Buff skills: activate the centralized, weapon-independent buff. BuffService
	-- only knows weapon buffs (Monastic Stance / Mystic Eyes / Berserker Armor);
	-- unknown names (e.g. racial buffs) no-op here and are handled elsewhere.
	if skillInfo.Type == "Buff" then
		BuffService.Activate(player, skillName)
	end

	-- HYPERARMOR (skills, "armor only"): give offensive casts armor for their cast
	-- window so an incoming hit deals damage but does not stop the animation or stun
	-- the caster out of the skill. Buffs are instant activations with no committed
	-- cast to protect, so they are skipped. Any skill can opt out with HyperArmor=false
	-- or set a custom window with HyperArmorDuration in SkillConfig. Damage still lands
	-- (see damageCalculator + stateHandler.SetStun); this only stops the interrupt.
	-- Note: a PARRY beats armor. The parry branches inside SkillFunctions clear the
	-- HyperArmor attribute before they stun the caster, so a parried skill still punishes.
	local armorSkill = (skillInfo.Type ~= "Buff") and (skillInfo.HyperArmor ~= false)
	if armorSkill then
		char:SetAttribute("HyperArmor", true)
		local armorWindow = skillInfo.HyperArmorDuration or 1.0
		task.delay(armorWindow, function()
			if char then
				char:SetAttribute("HyperArmor", nil)
			end
		end)
	end

	-- Check Racial Skills Module First
	if SkillFunctions[funcName] then
		task.spawn(function()
			print(funcName)
			SkillFunctions[funcName](player)
		end)
	elseif RacialSkills[funcName] or RacialSkills[playerRace] then
		task.spawn(function()
			RacialSkills[playerRace](player, char, mouseHit)
		end)
	else
		warn("No function found for skill: " .. funcName)
	end
end)
