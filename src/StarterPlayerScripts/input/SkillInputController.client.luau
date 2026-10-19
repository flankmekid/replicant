-- SPDX-License-Identifier: MIT
--
-- Skill input on Z, X, C (the weapon skills in the spellbook loadout) and V (the racial
-- skill). It checks the unlock, cooldown, and mana locally, sends the cast, and arms the
-- cooldown only when the server accepts it. The design is in docs/combat-design.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

local CastSkillRemote = ReplicatedStorage.remotes:WaitForChild("CastSkill")
local serverRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("server")
local TriggerCooldownEvent = ReplicatedStorage.remotes:WaitForChild("TriggerCooldown")

local mouse = player:GetMouse()

-- Key to slot: 1 = Z, 2 = X, 3 = C, 4 = V (the racial skill).
local KEYS = {
	[Enum.KeyCode.Z] = 1,
	[Enum.KeyCode.X] = 2,
	[Enum.KeyCode.C] = 3,
	[Enum.KeyCode.V] = 4,
}

-- A press sets only a short pending lock against remote spam. The real cooldown and the
-- HUD start when the server replies "Accepted". "Declined" clears the lock, so a
-- rejected cast never costs a cooldown. cooldowns[skillName] is the os.time() when the
-- skill is free again.
local cooldowns = {}
-- The longest time a rejected cast stays locked, in seconds.
local PENDING_WINDOW = 1

local function GetCurrentWeapon()
	local char = player.Character
	if char then
		local tool = char:FindFirstChildWhichIsA("Tool")
		if tool then
			return tool.Name
		end
	end
	return nil
end

local function GetRaceSkill()
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local race = stats:FindFirstChild("Race")
		if race and SkillConfig.RaceSkills[race.Value] then
			return SkillConfig.RaceSkills[race.Value]
		end
	end
	return nil
end

local function CanCast(char)
	if char:GetAttribute("CantAnything") then
		return false
	end
	if char:GetAttribute("Stunned") then
		return false
	end
	if char:GetAttribute("Blocking") then
		return false
	end
	if char:GetAttribute("Parrying") then
		return false
	end
	if char:GetAttribute("Dodging") then
		return false
	end
	if char:GetAttribute("M1") then
		return false
	end
	if char:GetAttribute("M2") then
		return false
	end
	if char:GetAttribute("Carried") then
		return false
	end
	if char:GetAttribute("Downed") then
		return false
	end
	if char:GetAttribute("Carrying") then
		return false
	end
	return true
end

CastSkillRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Func ~= "CastResponse" then
		return
	end
	local skillName = data.Skill
	if not skillName then
		return
	end

	if data.Decision == "Accepted" then
		local cdDuration = data.Cooldown
			or (SkillConfig.Skills[skillName] and SkillConfig.Skills[skillName].Cooldown)
			or 1
		cooldowns[skillName] = os.time() + cdDuration
		TriggerCooldownEvent:Fire(skillName, cdDuration)
	elseif data.Decision == "Declined" then
		-- FIXME: This should clear only the pending lock, not a real cooldown from an earlier
		-- cast whose reply arrives out of order.
		cooldowns[skillName] = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local slot = KEYS[input.KeyCode]
	if not slot then
		return
	end

	local char = player.Character
	if not char then
		return
	end
	if not CanCast(char) then
		return
	end

	local skillName = nil

	if slot == 4 then
		skillName = GetRaceSkill()
	else
		-- Weapon skill: weapon to family to the skill equipped in this slot.
		local weaponName = GetCurrentWeapon()
		if weaponName then
			local family = SkillConfig.WeaponFamily[weaponName]
			if family then
				local slotKey = SkillConfig.SlotKeys[slot]
				local equippedFolder = player:FindFirstChild("PlayerStats")
				equippedFolder = equippedFolder and equippedFolder:FindFirstChild("EquippedSkills")
				local famFolder = equippedFolder and equippedFolder:FindFirstChild(family)
				local slotVal = famFolder and famFolder:FindFirstChild(slotKey)
				if slotVal and slotVal.Value ~= "" then
					skillName = slotVal.Value
				end
			end
		end
	end

	if not skillName then
		return
	end

	local skillData = SkillConfig.Skills[skillName]
	if not skillData then
		return
	end

	-- Weapon skills must be unlocked. The racial skill is always owned.
	local stats = player:FindFirstChild("PlayerStats")
	local isRaceSkill = (slot == 4)

	if not isRaceSkill then
		if not stats or not stats:WaitForChild("UnlockedSkills"):FindFirstChild(skillName) then
			return
		end
	end

	-- The cooldown covers both the real cooldown and the pending lock.
	if cooldowns[skillName] and os.time() < cooldowns[skillName] then
		return
	end

	local manaCost = skillData.Mana or 0
	if manaCost > 0 then
		local currentMana = stats and stats:FindFirstChild("Mana") and stats.Mana.Value or 0
		if currentMana < manaCost then
			-- TODO: Give feedback when the player has too little mana.
			return
		end
	end

	-- Messatsu needs the caster below half HP.
	if skillName == "Messatsu" and char.Humanoid.Health >= char.Humanoid.MaxHealth / 2 then
		return
	end

	if skillName == "Silk Grasp" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (mouse.Hit.Position - hrp.Position).Magnitude
			if dist > 77.5 then
				return
			end
		end
	end

	CastSkillRemote:FireServer(skillName, mouse.Hit)
	cooldowns[skillName] = os.time() + PENDING_WINDOW
end)
