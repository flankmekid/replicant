-- SPDX-License-Identifier: MIT
--
-- Checks and runs every skill cast: state, ownership, server cooldown, and mana and HP
-- cost. Then it activates buffs, gives offensive casts hyper armor, and runs the skill
-- in SkillFunctions or RacialSkills. The design is in docs/combat-design.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.modules.dataManager)
local RaceConfig = require(ReplicatedStorage.modules.RaceConfig)
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

local SkillFunctions = require(ServerScriptService.modules.SkillFunctions)
local BuffService = require(ServerScriptService.modules.BuffService)
local RacialSkills = require(ServerScriptService.modules.RacialSkills)

local CastSkillRemote = ReplicatedStorage.remotes.CastSkill
local serverCooldowns = {}

-- The client arms its cooldown only when this reply says "Accepted", so a rejected
-- cast never puts the skill on cooldown.
local function reply(player, skillName, decision, cooldown)
	CastSkillRemote:FireClient(player, {
		Func = "CastResponse",
		Skill = skillName,
		Decision = decision,
		Cooldown = cooldown, -- Only on Accepted.
	})
end

CastSkillRemote.OnServerEvent:Connect(function(player, skillName, mouseHit)
	-- The reply uses the same remote, so ignore a table echoed back by the client.
	if type(skillName) ~= "string" then
		return
	end
	-- The racial skills aim with mouseHit.Position, so anything but a CFrame is dropped.
	if typeof(mouseHit) ~= "CFrame" then
		mouseHit = nil
	end

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
		reply(player, skillName, "Declined")
		return
	end

	if
		char:GetAttribute("Stunned")
		or char:GetAttribute("CantAnything")
		or char:GetAttribute("Downed")
	then
		reply(player, skillName, "Declined")
		return
	end

	local skillInfo = SkillConfig.Skills[skillName]
	if not skillInfo then
		reply(player, skillName, "Declined")
		return
	end

	-- The player owns the skill if it is their racial skill or an unlocked spell.
	local isVerified = false

	local playerRace = player:FindFirstChild("PlayerStats")
		and player.PlayerStats:FindFirstChild("Race")
		and player.PlayerStats.Race.Value
	if playerRace and SkillConfig.RaceSkills[playerRace] == skillName then
		isVerified = true
	else
		if DataManager.HasSpell(player, skillName) then
			isVerified = true
		end
	end

	if not isVerified then
		warn(`[SkillHandler] {player.Name} tried to cast unowned skill {skillName}.`)
		reply(player, skillName, "Declined")
		return
	end

	if not serverCooldowns[player] then
		serverCooldowns[player] = {}
	end
	local lastUse = serverCooldowns[player][skillName] or 0
	if os.time() < lastUse then
		reply(player, skillName, "Declined")
		return
	end

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

	mana.Value -= manaCost
	char.Humanoid.Health -= hpCost

	local cooldown = skillInfo.Cooldown or 1
	serverCooldowns[player][skillName] = os.time() + cooldown

	reply(player, skillName, "Accepted", cooldown)

	-- The function name is the skill name without spaces: "Solar Flare" is SolarFlare.
	local funcName = string.gsub(skillName, "%s+", "")

	-- BuffService knows only the weapon buffs. Other buff names do nothing there.
	if skillInfo.Type == "Buff" then
		BuffService.Activate(player, skillName)
	end

	-- Offensive casts get hyper armor for their cast window. SkillConfig can turn it off
	-- with HyperArmor = false or set the window with HyperArmorDuration.
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

	if SkillFunctions[funcName] then
		task.spawn(function()
			SkillFunctions[funcName](player)
		end)
	elseif RacialSkills[funcName] or RacialSkills[playerRace] then
		task.spawn(function()
			RacialSkills[playerRace](player, char, mouseHit)
		end)
	else
		warn(`[SkillHandler] No function {funcName} in SkillFunctions or RacialSkills.`)
	end
end)
