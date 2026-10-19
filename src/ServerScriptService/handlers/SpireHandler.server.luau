-- [[ SPIRE SERVER ]]
-- Location: ServerScriptService
-- Handles attunement saving and teleportation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SpireConfig = require(ReplicatedStorage.SpireSystem.SpireConfig)
local DataManager = require(ServerScriptService.modules.dataManager)
local SpireRemote = ReplicatedStorage.SpireSystem:WaitForChild("SpireAction")
local SpireUpdate = ReplicatedStorage.SpireSystem:WaitForChild("SpireUpdate")
local StateHandler = require(ReplicatedStorage.modules:WaitForChild("stateHandler"))

-- Forward-declared so the rest helpers below can reference it.
local getSpireDef

-- Tracks who is currently resting, and where they were resting (the spire part)
-- so we can verify proximity and clean up on death/leave.
local restingPlayers = {}

-- Restore HP + Mana to full (matches the spawn-time full-restore pattern).
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

-- Begin resting: lock the character in place, disable PvP/aggro by moving to
-- noPVP, heal to full. Server-authoritative; refuses if in combat.
local function beginRest(player, spireId)
	local spireDef = getSpireDef(spireId)
	if not spireDef then
		return false, "Invalid Spire."
	end
	if not DataManager.IsAttuned(player, spireId) then
		return false, "You are not attuned to that Spire."
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

	-- Must be on the ground to rest. Airborne states (jumping, mid-fall, ragdolled)
	-- are refused so you cannot rest off a ledge / mid-jump / while knocked around.
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

	-- Move out of the PvP/aggro folder (mobs, bosses, lock-on, ESP all scan .alive)
	if workspace:FindFirstChild("plrManager") and workspace.plrManager:FindFirstChild("noPVP") then
		character.Parent = workspace.plrManager.noPVP
	end

	-- Lock: no actions, no movement. (CantAnything + Anchored, NOT Stunned.)
	StateHandler.SetState(character, "CantAnything", true)
	StateHandler.SetState(character, "Resting", true)
	hum:UnequipTools()
	root.Anchored = true

	fullRestore(player)
	restingPlayers[player] = { spireId = spireId }
	return true, nil
end

-- End resting: unlock, restore to the alive folder (which re-runs applyStats).
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

	-- Clear the rest lock BEFORE moving back to alive, so applyStats runs clean.
	StateHandler.RemoveStates(character, "CantAnything")
	StateHandler.RemoveStates(character, "Resting")
	if root then
		root.Anchored = false
	end

	if workspace:FindFirstChild("plrManager") and workspace.plrManager:FindFirstChild("alive") then
		character.Parent = workspace.plrManager.alive
	end
end

-- Safety: if a resting player dies somehow, clear their rest entry.
Players.PlayerRemoving:Connect(function(player)
	restingPlayers[player] = nil
end)

-- [[ VALIDATE SPIRE ID ]]
getSpireDef = function(spireId)
	for _, s in ipairs(SpireConfig.Spires) do
		if s.Id == spireId then
			return s
		end
	end
	return nil
end

-- [[ TELEPORT ]]
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

-- [[ RESTORE SESSION ]]
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

-- [[ REMOTE HANDLER ]]
SpireRemote.OnServerEvent:Connect(function(player, action, spireId)
	if action == "Attune" then
		if not getSpireDef(spireId) then
			return
		end
		local wasNew = DataManager.AddAttuned(player, spireId)
		if wasNew then
			print(player.Name .. " attuned to: " .. spireId)
		end
		-- Auto-rest on attune (whether newly attuned or re-interacting):
		-- begin the rest so the menu opens in a single press.
		local ok, err = beginRest(player, spireId)
		if ok then
			SpireUpdate:FireClient(player, "RestStarted", { spireId = spireId, wasNew = wasNew })
		else
			-- Still tell the client about a brand-new attunement for the toast/effect,
			-- even if resting was refused (e.g. in combat).
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
		-- Teleport between spires from within the rest menu. Set the destination
		-- position first (works while anchored), then end the rest so the player
		-- arrives un-anchored, free to move, and back in the alive (PvP) folder.
		-- Travelling leaves the spire you were resting at.
		local success, err = teleportToSpire(player, spireId)
		if not success then
			SpireUpdate:FireClient(player, "TeleportFailed", err)
		else
			endRest(player) -- auto-leave the old spire's rest
			SpireUpdate:FireClient(player, "TeleportSuccess", spireId)
		end
	end
end)
-- [[ STAT SPREAD REMOTE ]]
-- RemoteFunction so the rest-menu UI gets an immediate buy/respec result.
local StatAction = ReplicatedStorage.SpireSystem:WaitForChild("StatAction")

-- Builds the full menu snapshot every reply carries, so the UI can refresh
-- liturgy, owned/available skill points, per-stat values, and the next buy cost.
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
	-- Players may only manage their build while actually resting at a spire.
	if not restingPlayers[player] then
		return { ok = false, reason = "MustRest" }
	end

	if action == "BuySkill" then
		-- Buy one skill point with Liturgy (rising curve, capped at 150).
		local ok, costOrReason = DataManager.BuySkillPoint(player)
		return statSnapshot(player, ok, costOrReason, { cost = ok and costOrReason or nil })
	elseif action == "Assign" then
		-- Assign one available skill point to a stat (free, 1:1).
		local ok, reason = DataManager.AssignStatPoint(player, statName)
		return statSnapshot(player, ok, reason)
	elseif action == "Respec" then
		-- Free all assigned points back to the pool (no Liturgy involved).
		local ok, reason = DataManager.RespecStats(player)
		return statSnapshot(player, ok, reason)
	elseif action == "Query" then
		return statSnapshot(player, true, nil)
	end

	return { ok = false, reason = "BadAction" }
end

-- [[ SPELLBOOK EQUIP REMOTE ]]
-- Binds an owned skill to a slot of its family. Gated on resting, like stats.
local EquipSkillAction = ReplicatedStorage.SpireSystem:WaitForChild("EquipSkillAction")
EquipSkillAction.OnServerInvoke = function(player, action, family, slotKey, skillName)
	if not restingPlayers[player] then
		return { ok = false, reason = "MustRest" }
	end

	-- Query: return the full spellbook snapshot for the player's current weapon family.
	if action == "Query" then
		return DataManager.GetSpellbookSnapshot(player)
	end

	-- Equip: bind an owned skill to a slot of its family, then return a fresh snapshot.
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

-- [[ ARMORY REMOTE ]]
-- Browse owned armors, Equip (stats + vanity) or Transmog (vanity only).
-- Gated on resting, like stats/spellbook. Stats always come from CurrentArmor;
-- visuals from CurrentVanity (which falls back to CurrentArmor).
local ArmorConfig = require(ReplicatedStorage.modules:WaitForChild("ArmorConfig"))
local ArmorAction = ReplicatedStorage.SpireSystem:WaitForChild("ArmorAction")

-- Swap the character's shirt/pants to a given armor's clothing (visual only).
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

-- Push an armor's buff multipliers into the player's ArmorBuffs folder. The
-- .Changed listeners in mainGameHandler recompute HP/attributes live.
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

-- Read-only snapshot: owned armor names + their config stats, plus the current
-- stats-armor and vanity-armor. Ownership is resolved server-side; the client
-- never sees armors the player doesn't own.
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
		-- Equip = stats + vanity both become this armor; transmog override cleared.
		DataManager.SetCurrentArmor(player, armorName)
		DataManager.SetCurrentVanity(player, nil)
		applyArmorVisuals(player.Character, armorName)
		applyArmorStats(player, armorName)
		return armorSnapshot(player, true, nil)
	elseif action == "Transmog" then
		if type(armorName) ~= "string" or not DataManager.OwnsArmor(player, armorName) then
			return { ok = false, reason = "NotOwned" }
		end
		-- Transmog = vanity only; stats untouched.
		DataManager.SetCurrentVanity(player, armorName)
		applyArmorVisuals(player.Character, armorName)
		return armorSnapshot(player, true, nil)
	end

	return { ok = false, reason = "BadAction" }
end
