-- SPDX-License-Identifier: MIT
--
-- Small server helpers for attacks: the attack slow, knockback, and hitbox cleanup.

local module = {}

local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local RP = game:GetService("ReplicatedStorage")

local stateHandler = require(RP.modules.stateHandler)
local StatScaling = require(RP.modules.StatScaling)
local SpeedService = require(game:GetService("ServerScriptService").modules.SpeedService)

local originalSpeeds = {}

local function cleanupChar(char)
	originalSpeeds[char] = nil
end
local function onCharacterRemoving(char)
	cleanupChar(char)
end
local function onPlayerRemoving(player)
	if player.Character then
		cleanupChar(player.Character)
	end
	originalSpeeds[player] = nil
end

-- helperModule.SetSpeed() - slow a character for an attack and disable jumping
-- @char: the character
-- @speed: the WalkSpeed during the attack
-- @optionalPrevSpeed: not used
--
-- Return: nothing.
function module.SetSpeed(char, speed, optionalPrevSpeed)
	if not char then
		return warn("[helperModule] SetSpeed called without a character.")
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[helperModule] SetSpeed: {char.Name} has no Humanoid.`)
		return
	end

	-- The originalSpeeds table marks an active helper slow, so ResetSpeed pops it.
	-- SpeedService owns the speed value.
	originalSpeeds[char] = true

	-- SKILL priority is above Block, so an M1 out of a held block moves at the swing
	-- speed and then returns to the block speed.
	SpeedService.Push(char, "HelperSlow", speed, SpeedService.Priority.SKILL)
	humanoid.JumpHeight = 0

	if not char.AncestryChanged or not char:GetAttribute("SpeedCleanupConnected") then
		char.AncestryChanged:Connect(function(_, parent)
			if not parent then
				onCharacterRemoving(char)
			end
		end)
		char:SetAttribute("SpeedCleanupConnected", true)
	end
end

-- The base jump height, before the race multiplier.
local baseJumpHeight = 7.2

-- A character's real jump height: base * their race's JumpBoost.
local function getBaseJumpHeight(char)
	local player = Players:GetPlayerFromCharacter(char)
	local stats = player and player:FindFirstChild("PlayerStats")
	local jb = stats and stats:FindFirstChild("JumpBoost")
	local mult = (jb and jb.Value and jb.Value > 0) and jb.Value or 1
	return baseJumpHeight * mult
end

-- helperModule.ResetSpeed() - end the attack slow and restore the jump height
-- @char: the character
--
-- Does nothing when no slow is active.
--
-- Return: nothing.
function module.ResetSpeed(char)
	if not char then
		return warn("[helperModule] ResetSpeed called without a character.")
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[helperModule] ResetSpeed: {char.Name} has no Humanoid.`)
		return
	end

	if originalSpeeds[char] then
		-- SpeedService computes the speed again, so a character who is still blocking
		-- settles to the block speed, not to base.
		SpeedService.Pop(char, "HelperSlow")

		-- Restore the jump height with the race JumpBoost, not the base value.
		humanoid.JumpHeight = getBaseJumpHeight(char)

		originalSpeeds[char] = nil
	end
end

-- helperModule.ApplyKnockback() - push a character with a short BodyVelocity
-- @char: the character
-- @direction: the push direction
-- @strength: the speed of the push in studs per second
-- @duration: the push length in seconds, 0.2 by default
--
-- Return: nothing.
function module.ApplyKnockback(char, direction, strength, duration)
	if not char then
		return warn("[helperModule] ApplyKnockback called without a character.")
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		warn(`[helperModule] ApplyKnockback: {char.Name} has no HumanoidRootPart.`)
		return
	end

	direction = direction.Unit
	local velocity = direction * strength

	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.Velocity = velocity
	bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVel.P = 10000
	bodyVel.Name = "KnockbackForce"
	bodyVel.Parent = root

	game:GetService("Debris"):AddItem(bodyVel, duration or 0.2)
end

-- helperModule.RemoveHitboxesByNameForCharacter() - remove a character's named hitboxes
-- @char: the character that owns the hitboxes
-- @attackName: the AttackName value to match
--
-- Return: nothing.
function module.RemoveHitboxesByNameForCharacter(char, attackName)
	local hitboxesFolder = workspace:FindFirstChild("Hitboxes")
	if not hitboxesFolder then
		return
	end

	local charName = char.Name

	for _, hitbox in pairs(hitboxesFolder:GetChildren()) do
		if
			hitbox:IsA("BasePart")
			and hitbox:FindFirstChild("AttackName")
			and hitbox:FindFirstChild("Owner")
		then
			if hitbox.AttackName.Value == attackName and hitbox.Owner.Value == charName then
				hitbox:Destroy()
			end
		end
	end
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

return module
