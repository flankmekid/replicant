local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local SkillConfig = require(ReplicatedStorage.modules.SkillConfig)

-- Remotes
local CastSkillRemote = ReplicatedStorage.remotes:WaitForChild("CastSkill") 
local serverRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("server")
local TriggerCooldownEvent = ReplicatedStorage.remotes:WaitForChild("TriggerCooldown")

local mouse = player:GetMouse()

-- 1 = Z, 2 = X, 3 = C, 4 = V (Race)
local KEYS = {
	[Enum.KeyCode.Z] = 1, 
	[Enum.KeyCode.X] = 2, 
	[Enum.KeyCode.C] = 3,
	[Enum.KeyCode.V] = 4, 
}

-- [[ COOLDOWNS ARE SERVER-CONFIRMED ]] --
-- We no longer arm the real cooldown (or the HUD swipe) the instant we fire the cast.
-- A cast the server rejects (state/ownership/resource desync, or the server-cooldown
-- guard) must NOT lock the skill on our end, otherwise pressing the button at the wrong
-- moment eats a full cooldown for nothing (brutal on high-cd skills). Instead:
--   * On press we set a SHORT "pending" lock (PENDING_WINDOW) just to stop remote spam
--     during the round-trip. This is not the skill's real cooldown.
--   * The server replies via CastSkillRemote (Func = "CastResponse"):
--       - "Accepted": we promote the lock to the authoritative cooldown and fire the HUD.
--       - "Declined": we clear the pending lock immediately so the player can retry at once.
-- cooldowns[skillName] holds the os.time() the skill is free again (pending or real).
local cooldowns = {}
local PENDING_WINDOW = 1 -- seconds; upper bound on how long a rejected cast stays locked

local function GetCurrentWeapon()
	local char = player.Character
	if char then
		local tool = char:FindFirstChildWhichIsA("Tool")
		if tool then return tool.Name end
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
	if char:GetAttribute("CantAnything") then return false end
	if char:GetAttribute("Stunned") then return false end
	if char:GetAttribute("Blocking") then return false end
	if char:GetAttribute("Parrying") then return false end
	if char:GetAttribute("Dodging") then return false end
	if char:GetAttribute("M1") then return false end
	if char:GetAttribute("M2") then return false end
	if char:GetAttribute("Carried") then return false end
	if char:GetAttribute("Downed") then return false end
	if char:GetAttribute("Carrying") then return false end
	return true
end

-- [[ SERVER REPLY: arm or release the cooldown ]] --
-- The server tells us whether the cast actually happened. Only an accepted cast arms
-- the real cooldown + HUD; a declined cast releases the short pending lock.
CastSkillRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Func ~= "CastResponse" then return end
	local skillName = data.Skill
	if not skillName then return end

	if data.Decision == "Accepted" then
		local cdDuration = data.Cooldown or (SkillConfig.Skills[skillName] and SkillConfig.Skills[skillName].Cooldown) or 1
		cooldowns[skillName] = os.time() + cdDuration
		TriggerCooldownEvent:Fire(skillName, cdDuration)
	elseif data.Decision == "Declined" then
		-- Only clear if it's still the pending lock we set (don't wipe a real cooldown
		-- from some earlier successful cast that happens to arrive out of order).
		cooldowns[skillName] = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	local slot = KEYS[input.KeyCode]
	if not slot then return end 

	local char = player.Character
	if not char then return end
	if not CanCast(char) then return end

	local skillName = nil

	-- [[ CHECK IF RACIAL SKILL (SLOT 4 / V) ]] --
	if slot == 4 then
		skillName = GetRaceSkill()
	else
		-- [[ CHECK IF WEAPON SKILL (spellbook loadout) ]] --
		-- Resolve equipped weapon -> seed family -> the player's equipped skill for this slot.
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

	if not skillName then return end 

	local skillData = SkillConfig.Skills[skillName]
	if not skillData then return end -- Logic safety

	-- Check unlock (Weapons only) or inherent (Race)
	local stats = player:FindFirstChild("PlayerStats")
	local isRaceSkill = (slot == 4)

	if not isRaceSkill then
		-- If it's a weapon skill, verify we unlocked it in inventory
		if not stats or not stats:WaitForChild("UnlockedSkills"):FindFirstChild(skillName) then return end
	end

	-- Cooldown Check (covers both the real cooldown and the short pending lock)
	if cooldowns[skillName] and os.time() < cooldowns[skillName] then return end

	-- [[ MANA CHECK (NEW) ]] --
	local manaCost = skillData.Mana or 0
	if manaCost > 0 then
		local currentMana = stats and stats:FindFirstChild("Mana") and stats.Mana.Value or 0
		if currentMana < manaCost then
			-- Optional: Play a "No Mana" sound or UI shake here
			return 
		end
	end

	-- Special HP Conditions
	if skillName == "Messatsu" and char.Humanoid.Health >= (char.Humanoid.MaxHealth) / 2 then return end

	if skillName == "Silk Grasp" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (mouse.Hit.Position - hrp.Position).Magnitude
			if dist > 77.5 then 
				return
			end
		end
	end

	-- [[ CAST REQUEST ]] --
	-- Fire the request and set only the SHORT pending lock. The real cooldown + HUD are
	-- armed in OnClientEvent above IF (and only if) the server accepts. If it rejects,
	-- the pending lock is cleared there and the player can immediately try again.
	CastSkillRemote:FireServer(skillName, mouse.Hit)
	cooldowns[skillName] = os.time() + PENDING_WINDOW
end)