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

function module.SetSpeed(char, speed, optionalPrevSpeed)
	if not char then
		return warn("No character found!!!")
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No humanoid found!!!")
		return
	end

	-- originalSpeeds still tracks "is a helper slow active" so ResetSpeed knows to
	-- pop; the actual speed value is owned by SpeedService now (optionalPrevSpeed /
	-- the old stashed WalkSpeed are dead: the stack recomputes the correct restore).
	originalSpeeds[char] = true

	-- SKILL priority: sits above Block, so an M1 out of a held block briefly moves at
	-- the swing speed, then settles back to the block speed when ResetSpeed pops.
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
local BASE_JUMP_HEIGHT = 7.2

-- A character's real jump height: base * their race's JumpBoost.
local function getBaseJumpHeight(char)
	local player = Players:GetPlayerFromCharacter(char)
	local stats = player and player:FindFirstChild("PlayerStats")
	local jb = stats and stats:FindFirstChild("JumpBoost")
	local mult = (jb and jb.Value and jb.Value > 0) and jb.Value or 1
	return BASE_JUMP_HEIGHT * mult
end

function module.ResetSpeed(char)
	if not char then
		return warn("No character found!!!")
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No humanoid found!!!")
		return
	end

	if originalSpeeds[char] then
		-- Pop the helper slow and let SpeedService recompute. If the character is
		-- still blocking (or under any other live modifier) it settles to THAT, not
		-- to base: this is the fix for "moves fast while blocking after an M1".
		SpeedService.Pop(char, "HelperSlow")

		-- Was hardcoded to 7.2, which threw away the race JumpBoost. Every M1, M2 and
		-- E calls SetSpeed (JumpHeight = 0) and then ResetSpeed, so an Arach
		-- (JumpBoost 1.5, real jump height 10.8) had their jump permanently flattened
		-- to base by their first attack and never got it back until respawn.
		humanoid.JumpHeight = getBaseJumpHeight(char)

		originalSpeeds[char] = nil
	end
end

function module.ApplyKnockback(char, direction, strength, duration)
	if not char then
		return warn("No character found!!!")
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		warn("No root found!!!")
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
