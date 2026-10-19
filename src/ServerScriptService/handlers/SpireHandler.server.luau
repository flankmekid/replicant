-- SPDX-License-Identifier: MIT
--
-- Owns the spires: attunement, resting (a safe heal that opens the rest menu),
-- teleport between attuned spires, and the rest-menu remotes for stats, the
-- spellbook, and the armory. Every menu action works only while resting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SpireConfig = require(ReplicatedStorage.SpireSystem.SpireConfig)
local DataManager = require(ServerScriptService.modules.dataManager)
local SpireRemote = ReplicatedStorage.SpireSystem:WaitForChild("SpireAction")
local SpireUpdate = ReplicatedStorage.SpireSystem:WaitForChild("SpireUpdate")
local StateHandler = require(ReplicatedStorage.modules:WaitForChild("stateHandler"))

-- Declared here because the rest helpers below use them.
local getSpireDef, isNearSpire

-- The spire part each player rests at, for the proximity check and cleanup on death
-- or leave.
local restingPlayers = {}

-- Restores HP and mana to full, the same as on spawn.
local function fullRestore(player)
	local character = player.Character
	if not character then
		return
	end
	local hum = character:FindFirstChild("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = hum.MaxHealth
	end
	local stats = player:FindFirstChild("PlayerStats")
	if stats then
		local mana = stats:FindFirstChild("Mana")
		local maxMana = stats:FindFirstChild("MaxMana")
		if mana and maxMana then
			mana.Value = maxMana.Value
		end
	end
end

-- Starts a rest: locks the character in place, removes it from PvP and aggro, and heals
-- it to full. Refused in combat.
local function beginRest(player, spireId)
	local spireDef = getSpireDef(spireId)
	if not spireDef then
		return false, "Invalid Spire."
	end
	if not DataManager.IsAttuned(player, spireId) then
		return false, "You are not attuned to that Spire."
	end
	if not isNearSpire(player, spireDef) then
		return false, "You are too far from the Spire."
	end

	local character = player.Character
	if not character then
		return false, "Character not found."
	end
	if character:GetAttribute("InCombat") then
		return false, "You cannot rest while in combat."
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChild("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return false, "Character not ready."
	end

	-- Resting needs the ground, so a player cannot rest off a ledge, during a jump, or
	-- while ragdolled.
	local restHumState = hum:GetState()
	if
		restHumState == Enum.HumanoidStateType.Jumping
		or restHumState == Enum.HumanoidStateType.Freefall
		or restHumState == Enum.HumanoidStateType.FallingDown
		or restHumState == Enum.HumanoidStateType.Ragdoll
		or restHumState == Enum.HumanoidStateType.Flying
	then
		return false, "You must be on the ground to rest."
	end

	-- Leave plrManager.alive, which mobs, bosses, lock-on, and ESP scan.
	if workspace:FindFirstChild("plrManager") and workspace.plrManager:FindFirstChild("noPVP") then
		character.Parent = workspace.plrManager.noPVP
	end

	-- Lock actions and movement with CantAnything and Anchored, not with Stunned.
	StateHandler.SetState(character, "CantAnything", true)
	StateHandler.SetState(character, "Resting", true)
	hum:UnequipTools()
	root.Anchored = true

	fullRestore(player)
	restingPlayers[player] = { spireId = spireId }
	return true, nil
end

-- Ends a rest: unlocks the character and moves it back to plrManager.alive, which runs
-- applyStats again.
local function endRest(player)
	if not restingPlayers[player] then
		return
	end
	restingPlayers[player] = nil

	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")

	-- Clear the rest lock before the move, so applyStats runs clean.
	StateHandler.RemoveStates(character, "CantAnything")
	StateHandler.RemoveStates(character, "Resting")
	if root then
		root.Anchored = false
	end

	if workspace:FindFirstChild("plrManager") and workspace.plrManager:FindFirstChild("alive") then
		character.Parent = workspace.plrManager.alive
	end
end

-- A resting player who dies loses their rest entry.
Players.PlayerRemoving:Connect(function(player)
	restingPlayers[player] = nil
end)

getSpireDef = function(spireId)
	for _, s in ipairs(SpireConfig.Spires) do
		if s.Id == spireId then
			return s
		end
	end
	return nil
end

-- The spire prompt reaches 16 studs. The extra distance covers latency.
local spireRange = 22

-- Returns true if the player stands within spireRange of the spire part.
isNearSpire = function(player, spireDef)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local part = workspace:FindFirstChild(spireDef.PartName, true)
	if not root or not part or not part:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= spireRange
end

local function teleportToSpire(player, spireId)
	local spireDef = getSpireDef(spireId)
	if not spireDef then
		return false, "Invalid Spire."
	end

	if not DataManager.IsAttuned(player, spireId) then
		return false, "You are not attuned to that Spire."
	end

	local success = DataManager.RemoveLiturgy(player, SpireConfig.TeleportCost)
	if not success then
		return false,
			"Not enough Liturgy. Teleportation costs " .. SpireConfig.TeleportCost .. " L."
	end

	local targetPart = workspace:FindFirstChild(spireDef.PartName, true)
	if not targetPart then
		DataManager.AddLiturgy(player, SpireConfig.TeleportCost)
		return false, "Spire location not found."
	end

	local character = player.Character
	if not character then
		DataManager.AddLiturgy(player, SpireConfig.TeleportCost)
		return false, "Character not found."
	end

	if character:GetAttribute("InCombat") then
		DataManager.AddLiturgy(player, SpireConfig.TeleportCost)
		return false, "You cannot teleport while in combat."
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		DataManager.AddLiturgy(player, SpireConfig.TeleportCost)
		return false, "Character not ready."
	end

	root.CFrame = targetPart.CFrame * CFrame.new(0, 3, 6)
	return true, nil
end

local function restoreSession(player)
	DataManager.YieldUntilLoaded(player)
	local attuned = DataManager.GetAttuned(player)
	SpireUpdate:FireClient(player, "Restore", attuned)
end

Players.PlayerAdded:Connect(function(player)
	task.wait(0.5)
	restoreSession(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		restoreSession(player)
	end)
end)

SpireRemote.OnServerEvent:Connect(function(player, action, spireId)
	if action == "Attune" then
		local spireDef = getSpireDef(spireId)
		if not spireDef or not isNearSpire(player, spireDef) then
			return
		end
		local wasNew = DataManager.AddAttuned(player, spireId)
		-- Attuning also starts a rest, so the menu opens with one press.
		local ok, err = beginRest(player, spireId)
		if ok then
			SpireUpdate:FireClient(player, "RestStarted", { spireId = spireId, wasNew = wasNew })
		else
			-- Tell the client about a new attunement even when the rest was refused.
			if wasNew then
				SpireUpdate:FireClient(player, "Attuned", spireId)
			end
			SpireUpdate:FireClient(player, "RestFailed", err)
		end
	elseif action == "Rest" then
		local ok, err = beginRest(player, spireId)
		if ok then
			SpireUpdate:FireClient(player, "RestStarted", { spireId = spireId, wasNew = false })
		else
			SpireUpdate:FireClient(player, "RestFailed", err)
		end
	elseif action == "EndRest" then
		endRest(player)
		SpireUpdate:FireClient(player, "RestEnded")
	elseif action == "Teleport" then
		-- The travel map opens only from the rest menu.
		if not restingPlayers[player] then
			SpireUpdate:FireClient(player, "TeleportFailed", "You must rest at a Spire to travel.")
			return
		end
		-- Set the destination first, which works while anchored, then end the rest, so the
		-- player arrives free to move and back in plrManager.alive.
		local success, err = teleportToSpire(player, spireId)
		if not success then
			SpireUpdate:FireClient(player, "TeleportFailed", err)
		else
			endRest(player)
			SpireUpdate:FireClient(player, "TeleportSuccess", spireId)
		end
	end
end)
-- A RemoteFunction, so the rest menu gets the result of a buy or respec at once.
local StatAction = ReplicatedStorage.SpireSystem:WaitForChild("StatAction")

-- Builds the snapshot that every reply carries: Liturgy, owned and available skill
-- points, each stat, and the next skill point cost.
local function statSnapshot(player, ok, reason, extra)
	local prof = DataManager.GetProfile(player)
	local snap = {
		ok = ok,
		reason = (not ok) and reason or nil,
		stats = prof and prof.Data.Stats or nil,
		liturgy = DataManager.GetLiturgy(player),
		owned = DataManager.GetSkillPointsOwned(player),
		available = DataManager.GetAvailableSkillPoints(player),
		maxSkillPoints = require(ReplicatedStorage.modules.StatScaling).MAX_SKILL_POINTS,
		nextCost = DataManager.GetNextSkillPointCost(player),
	}
	if extra then
		for k, v in pairs(extra) do
			snap[k] = v
		end
	end
	return snap
end

StatAction.OnServerInvoke = function(player, action, statName)
	if not restingPlayers[player] then
		return { ok = false, reason = "MustRest" }
	end

	if action == "BuySkill" then
		local ok, costOrReason = DataManager.BuySkillPoint(player)
		return statSnapshot(player, ok, costOrReason, { cost = ok and costOrReason or nil })
	elseif action == "Assign" then
		local ok, reason = DataManager.AssignStatPoint(player, statName)
		return statSnapshot(player, ok, reason)
	elseif action == "Respec" then
		local ok, reason = DataManager.RespecStats(player)
		return statSnapshot(player, ok, reason)
	elseif action == "Query" then
		return statSnapshot(player, true, nil)
	end

	return { ok = false, reason = "BadAction" }
end

-- Equips an owned skill into a slot of its family.
local EquipSkillAction = ReplicatedStorage.SpireSystem:WaitForChild("EquipSkillAction")
EquipSkillAction.OnServerInvoke = function(player, action, family, slotKey, skillName)
	if not restingPlayers[player] then
		return { ok = false, reason = "MustRest" }
	end

	if action == "Query" then
		return DataManager.GetSpellbookSnapshot(player)
	end

	if action == "Equip" then
		if type(family) ~= "string" or type(slotKey) ~= "string" or type(skillName) ~= "string" then
			return { ok = false, reason = "BadAction" }
		end
		local ok = DataManager.EquipSkill(player, family, slotKey, skillName)
		if not ok then
			return { ok = false, reason = "EquipFailed" }
		end
		local snap = DataManager.GetSpellbookSnapshot(player)
		snap.equippedSkill = skillName
		snap.equippedSlot = slotKey
		return snap
	end

	return { ok = false, reason = "BadAction" }
end

-- Lists owned armors, and handles Equip (stats and looks) and Transmog (looks only).
-- Stats always come from CurrentArmor, and looks from CurrentVanity, which falls back
-- to CurrentArmor.
local ArmorConfig = require(ReplicatedStorage.modules:WaitForChild("ArmorConfig"))
local ArmorAction = ReplicatedStorage.SpireSystem:WaitForChild("ArmorAction")

-- Shows an armor's clothing on the character. Looks only.
local function applyArmorVisuals(character, armorName)
	if not character then
		return
	end
	local data = ArmorConfig.Armors[armorName] or ArmorConfig.Armors["Rags"]
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "ArmorShirt"
		shirt.Parent = character
	end
	shirt.ShirtTemplate = data.ShirtID
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "ArmorPants"
		pants.Parent = character
	end
	pants.PantsTemplate = data.PantsID
end

-- Writes an armor's buff multipliers to ArmorBuffs. mainGameHandler listens to those
-- values and updates HP and attributes.
local function applyArmorStats(player, armorName)
	local stats = player:FindFirstChild("PlayerStats")
	if not stats then
		return
	end
	local buffs = stats:FindFirstChild("ArmorBuffs")
	if not buffs then
		return
	end
	local data = ArmorConfig.Armors[armorName] or ArmorConfig.Armors["Rags"]
	if buffs:FindFirstChild("HPBuff") then
		buffs.HPBuff.Value = data.HPBuff
	end
	if buffs:FindFirstChild("DefenseBuff") then
		buffs.DefenseBuff.Value = data.DefBuff
	end
	if buffs:FindFirstChild("DamageBuff") then
		buffs.DamageBuff.Value = data.DmgBuff
	end
end

-- Lists the owned armors with their stats, and the current stats and looks armor. The
-- client never sees armors that the player does not own.
local function armorSnapshot(player, ok, reason)
	local prof = DataManager.GetProfile(player)
	local owned, armors = {}, {}
	if prof then
		for _, name in ipairs(prof.Data.OwnedArmors) do
			local cfg = ArmorConfig.Armors[name]
			if cfg then
				table.insert(owned, name)
				armors[name] = {
					DisplayName = cfg.DisplayName or name,
					HPBuff = cfg.HPBuff,
					DefBuff = cfg.DefBuff,
					DmgBuff = cfg.DmgBuff,
					ShirtID = cfg.ShirtID,
					PantsID = cfg.PantsID,
				}
			end
		end
	end
	return {
		ok = ok,
		reason = (not ok) and reason or nil,
		owned = owned,
		armors = armors,
		currentArmor = DataManager.GetCurrentArmor(player),
		currentVanity = DataManager.GetCurrentVanity(player),
	}
end

ArmorAction.OnServerInvoke = function(player, action, armorName)
	if not restingPlayers[player] then
		return { ok = false, reason = "MustRest" }
	end

	if action == "Query" then
		return armorSnapshot(player, true, nil)
	elseif action == "Equip" then
		if type(armorName) ~= "string" or not DataManager.OwnsArmor(player, armorName) then
			return { ok = false, reason = "NotOwned" }
		end
		-- Equip sets both stats and looks to this armor and clears the transmog.
		DataManager.SetCurrentArmor(player, armorName)
		DataManager.SetCurrentVanity(player, nil)
		applyArmorVisuals(player.Character, armorName)
		applyArmorStats(player, armorName)
		return armorSnapshot(player, true, nil)
	elseif action == "Transmog" then
		if type(armorName) ~= "string" or not DataManager.OwnsArmor(player, armorName) then
			return { ok = false, reason = "NotOwned" }
		end
		-- Transmog changes only the looks.
		DataManager.SetCurrentVanity(player, armorName)
		applyArmorVisuals(player.Character, armorName)
		return armorSnapshot(player, true, nil)
	end

	return { ok = false, reason = "BadAction" }
end
