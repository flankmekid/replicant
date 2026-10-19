-- SPDX-License-Identifier: MIT
--
-- Runs the server side of the M1, M2, and E attacks and resolves their hits. Weapon
-- modules call RunM1, RunM2, or RunE with their WeaponConfig entry. Every hit goes
-- through resolveHit, which handles dodge, clash, parry, block, guard break, and damage.
-- The design reasons for the timing values are in docs/combat-design.md.

local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicateRemote = RP.remotes.replicate

local Helper = require(SSS.modules.helperModule)
local SpeedService = require(SSS.modules.SpeedService)
local StateHandler = require(RP.modules.stateHandler)
local ParryService = require(SSS.modules.parryService)
local AnimationHandler = require(RP.modules.animationHandler)
local HitboxClass = require(RP.modules.hitboxClass)
local ragdollManager = require(SSS.modules.ragdollManager)
local DataManager = require(SSS.modules.dataManager)
local damageCalculator = require(SSS.modules.damageCalculator)
local BuffService = require(SSS.modules.BuffService)
local LungeService = require(SSS.modules.LungeService)
local BlockResolver = require(SSS.modules.BlockResolver)
local WeaponConfig = require(RP.modules.WeaponConfig)
local DashConfig = require(RP.modules.DashConfig)

-- A landed M2 has a short recovery, so the player can cancel into M1, E, a skill, or a
-- dash. A whiff has a long recovery, so M2 is not free to spam. The M2 cooldown
-- (cfg.postCooldown) is separate, so M2 still cannot chain into another M2.
local M2_ENDLAG_HIT = 0.1
local M2_ENDLAG_WHIFF = 0.65

-- An extra lock after an M1 or E that hit nothing, so a missed swing can be punished.
-- A landed swing skips it, so combos keep their timing.
local M1E_WHIFF_RECOVERY = 0.2

-- Hitstun decides what combos into what. A combo is true when the victim's hitstun
-- outlasts the attacker's recovery. It is a read (parryable) when the victim recovers
-- around the time the next hitbox is live. All values are in seconds.
--
-- M1 hitstun is the weapon's M1 cooldown plus M1_ADVANTAGE, so light and medium weapons
-- all link the same way at different speeds. At 0.20, a landed M1 string can only be
-- escaped with a parry, which is allowed during stun. M2 and E use flat values, so
-- landing one reliably leads into M1.
local M1_ADVANTAGE = 0.20
-- A floor so fast weapons still stun.
local M1_MIN_HITSTUN = 0.45
-- Greatsword-family M1s stun for less than their recovery, so a second M1 is a read.
local GREATSWORD_M1_HITSTUN = 1.0
local M2_HITSTUN = 1.10
local E_HITSTUN = 1.00
-- WalkSpeed during weapon hitstun. It is low so that walking backward cannot escape.
local HITSTUN_STUNSPEED = 1

-- Returns the hitstun in seconds for a landed hit of the given action.
local function computeHitstun(action, weaponName)
	if action == "M2" then
		return M2_HITSTUN
	elseif action == "E" then
		return E_HITSTUN
	end
	local wc = weaponName and WeaponConfig[weaponName]
	if wc and wc.family == "Greatsword" then
		return GREATSWORD_M1_HITSTUN
	end
	local recovery = (wc and wc.client and wc.client.m1 and wc.client.m1.cooldown) or 0.5
	return math.max(recovery + M1_ADVANTAGE, M1_MIN_HITSTUN)
end

-- An M2 that lands while an M1 combo is open is a combo ender. It launches the victim
-- up and away and stuns longer. Combo is 1-indexed, so 2 means at least two M1s.
local M2_FINISHER_MIN_COMBO = 2
local M2_FINISHER_LAUNCH_UP = 40
local M2_FINISHER_LAUNCH_BACK = 20
local M2_FINISHER_STUN = 1.2

-- The uppercut (slide + M1) lifts the attacker and the victim into a short hang, so the
-- attacker can follow up in the air. Both get the Launched attribute for the hang, and
-- RunM1 then uses the ground combo instead of the aerial attack. The victim is stunned
-- and not ragdolled, because a ragdoll falls out of hitboxes.
local LAUNCH_WINDOW = WeaponConfig.Uppercut.HangWindow

local comboResetTime = 5
local comboResetTasks = {}
local playerM1Debounces = {}
local playerM2Debounces = {}
-- The attack in flight for each character. The clash check reads the other fighter's
-- token from here.
local activeAttacks = setmetatable({}, { __mode = "k" })

local function getEquippedTool(plr)
	local currentCharacter = plr.Character
	if not currentCharacter then
		return nil
	end
	local tool = currentCharacter:FindFirstChildOfClass("Tool")
	if tool and tool.Parent == currentCharacter then
		return tool.Name
	end
	return nil
end

-- A strong upward burst, then a weaker lift that holds the character in the air. back
-- also pushes the character along lookVec, away from the attacker.
local function floatUp(char, burstUp, hangUp, back, lookVec, window)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Two launches must not stack their drives.
	local old = root:FindFirstChild("JuggleForce")
	if old then
		old:Destroy()
	end

	local horizontal = Vector3.new(0, 0, 0)
	if back and lookVec then
		local flat = Vector3.new(lookVec.X, 0, lookVec.Z)
		if flat.Magnitude > 0.01 then
			horizontal = flat.Unit * back
		end
	end

	local BV = Instance.new("BodyVelocity")
	BV.Name = "JuggleForce"
	BV.MaxForce = Vector3.new(25000, 25000, 25000)
	BV.P = 3000
	BV.Velocity = Vector3.new(horizontal.X, burstUp, horizontal.Z)
	BV.Parent = root

	-- The weaker lift makes the character float instead of shooting up.
	task.delay(0.12, function()
		if BV.Parent then
			BV.Velocity = Vector3.new(0, hangUp, 0)
		end
	end)

	game.Debris:AddItem(BV, window)
end

-- AlignPosition replicates to the victim's own client and moves the victim there, so
-- this works without network ownership of the victim.
local function juggleFloat(hrp, targetPos, window, responsiveness)
	if not hrp then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "UppercutApex"
	att.Parent = hrp
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = targetPos
	ap.MaxForce = math.huge
	ap.Responsiveness = responsiveness
	ap.RigidityEnabled = false
	ap.ApplyAtCenterOfMass = true
	ap.Parent = hrp
	game.Debris:AddItem(ap, window)
	game.Debris:AddItem(att, window)
end

-- Hitstop freezes the animations of both fighters on every client and locks the
-- victim's movement on the server for the freeze. The animation freeze is cosmetic.
local HITSTOP_DEFAULT = 0.12
-- The jump and rotation values of each victim in hitstop, restored when it ends.
local hitstopLocks = setmetatable({}, { __mode = "k" })

local function applyHitstop(plr, attackerChar, targetChar, action, duration)
	duration = duration or HITSTOP_DEFAULT

	ReplicateRemote:FireAllClients({
		Type = "Combat",
		Action = action,
		Func = "Hitstop",
		FolderName = getEquippedTool(plr),
	}, attackerChar, targetChar)

	-- A Stunned or Downed victim already has a hit reaction that owns their movement.
	-- Hitstop must not shorten it.
	local humanoid = targetChar:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end
	if StateHandler.GetState(targetChar, "Stunned") then
		return
	end
	if StateHandler.GetState(targetChar, "Downed") then
		return
	end
	if hitstopLocks[targetChar] then
		return
	end

	hitstopLocks[targetChar] = {
		jumpP = humanoid.JumpPower,
		jumpH = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}
	-- Hitstop uses the STUN priority so that a real stun starting during the freeze is not
	-- outranked. Jump and AutoRotate are not part of SpeedService, so they are saved here.
	SpeedService.Push(targetChar, "Hitstop", 0, SpeedService.Priority.STUN)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	task.delay(duration, function()
		local saved = hitstopLocks[targetChar]
		hitstopLocks[targetChar] = nil
		if not saved then
			return
		end
		local h = targetChar:FindFirstChild("Humanoid")
		if not h then
			-- Pop the modifier anyway, so it cannot stay on a reused rig.
			SpeedService.Pop(targetChar, "Hitstop")
			return
		end
		-- A stun that started during the freeze has its own modifier, so popping this one is
		-- safe. Jump and AutoRotate belong to that stun until it ends.
		SpeedService.Pop(targetChar, "Hitstop")
		if StateHandler.GetState(targetChar, "Stunned") then
			return
		end
		h.JumpPower = saved.jumpP
		h.JumpHeight = saved.jumpH
		h.AutoRotate = saved.autoRotate
	end)
end

-- TODO: slash FX are disabled. Callers still pass their FX data, so the function stays.
local function emitSlash(char, folderPath, slashChild, partName) end

-- In comboMap, R plays SlashFXLeft, L plays SlashFXRight, and U plays SlashFXUp.
local function genericSwing(char, combo, cfg)
	local fx = cfg.swingFX
	if not fx then
		return
	end
	local m = cfg.comboMap and cfg.comboMap[combo]
	if not m then
		return
	end
	if m:find("R") then
		emitSlash(char, fx.folder, "SlashFXLeft", fx.rightPart)
	end
	if m:find("L") then
		emitSlash(char, fx.folder, "SlashFXRight", fx.rightPart)
	end
	if m:find("U") then
		emitSlash(char, fx.folder, "SlashFXUp", fx.upPart)
	end
end

local function setTrail(char, trailBlade, on)
	if not trailBlade then
		return
	end
	local model = char:FindFirstChild(trailBlade.model)
	local blade = model and model:FindFirstChild(trailBlade.part)
	if not blade then
		return
	end
	local t1 = blade:FindFirstChild("MeleeTrail")
	if t1 then
		t1.Enabled = on
	end
	local t2 = blade:FindFirstChild("MeleeTrail2")
	if t2 then
		t2.Enabled = on
	end
end

-- Leaves a fading black afterimage of the character for the M2 dash.
local function dashEff(char)
	for _, v in pairs(char:GetChildren()) do
		if v:IsA("BasePart") and v.Transparency ~= 1 then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Transparency = 0.1
			part.CanCollide = false
			part.Parent = workspace
			part.BrickColor = BrickColor.new("Really black")
			part.Material = Enum.Material.Neon
			part.Size = v.Size
			part.CFrame = v.CFrame
			if v:FindFirstChildOfClass("SpecialMesh") then
				v:FindFirstChildOfClass("SpecialMesh"):Clone().Parent = part
			end
			TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			game.Debris:AddItem(part, 0.5)
		end
	end
end

-- A combo-ender M2 launches the victim up and back and stuns longer. RunM2 decides this
-- once per swing, and the closure keeps the decision fixed for the whole swing.
local function makeM2Knockback(isFinisher)
	return function(char, targetChar, targetHRP, attackerHRP, direction, knockbackDistance)
		if isFinisher then
			local lookVec = attackerHRP.CFrame.LookVector
			floatUp(
				targetChar,
				M2_FINISHER_LAUNCH_UP,
				M2_FINISHER_LAUNCH_UP * 0.4,
				M2_FINISHER_LAUNCH_BACK,
				lookVec,
				0.6
			)
			StateHandler.SetStun(targetChar, true, M2_FINISHER_STUN, HITSTUN_STUNSPEED)
		else
			Helper.ApplyKnockback(targetChar, direction, knockbackDistance, 0.2)
			StateHandler.SetStun(targetChar, true, M2_HITSTUN, HITSTUN_STUNSPEED)
		end
	end
end

local function eKnockback(char, targetChar, targetHRP, attackerHRP, direction, knockbackDistance)
	Helper.ApplyKnockback(targetChar, direction, knockbackDistance * 2, 0.2)
	StateHandler.SetStun(targetChar, true, E_HITSTUN, HITSTUN_STUNSPEED)
end

-- The action argument is the replication tag: "M1", "M2", or "E". The ctx table holds
-- dmg, guardbreak, onDamage, xpMultiplier, xpName, applyKnockback, hitstopDuration,
-- and token.
local function resolveHit(plr, char, Hitbox, action, ctx)
	local alreadyHit = {}
	Hitbox.HitSomeone:Connect(function(hitCharsTable)
		for _, hit in pairs(hitCharsTable) do
			local humanoid = hit:FindFirstChild("Humanoid")
			local targetChar = humanoid and humanoid.Parent
			if
				not targetChar
				or targetChar:IsA("Model") and not targetChar:FindFirstChild("Humanoid")
			then
				continue
			end

			local isPlayer = Players:GetPlayerFromCharacter(targetChar)

			if humanoid and (not isPlayer or isPlayer ~= plr) and not alreadyHit[targetChar] then
				local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
				local attackerHRP = char:FindFirstChild("HumanoidRootPart")
				if not attackerHRP then
					return
				end
				-- A target without a root part is skipped, not the rest of the batch.
				if not targetHRP then
					continue
				end

				if StateHandler.GetState(char, "Stunned") then
					continue
				end

				if StateHandler.GetState(targetChar, "Dodging") then
					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if
						targetPlrData
						and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8
					then
						targetPlrData.Mana.Value += 8
					end
					local sound = RP.assets.sounds.Dodged:Clone()
					sound.Parent = targetHRP
					sound:Play()
					local effect = RP.assets.FX.Dodged:Clone()
					effect.Parent = targetHRP
					effect.Enabled = true
					game.Debris:AddItem(sound, 3)
					game.Debris:AddItem(effect, 0.3)
					if targetChar.Torso then
						for _, part in pairs(targetChar:GetChildren()) do
							if
								part:IsA("BasePart")
								and part ~= targetHRP
								and part.Name ~= "Head"
								and part.Name ~= "Left Arm"
							then
								local oldTrans = part.Transparency
								part.Transparency = 0.7
								task.delay(0.3, function()
									part.Transparency = oldTrans
								end)
							end
						end
					end
					continue
				end

				local function doAttack(extraDmg, knockbackDistance)
					local direction = (targetHRP.Position - attackerHRP.Position).Unit
					-- Knockback runs before damage, so a hit that downs the target never stuns or
					-- juggles the downed body. The knockback closure is the only source of weapon
					-- hitstun. damageCalculator skips its own stun for the "Weapon" damage type.
					ctx.applyKnockback(
						char,
						targetChar,
						targetHRP,
						attackerHRP,
						direction,
						knockbackDistance
					)

					if ctx.onDamage then
						ctx.onDamage(plr, char, targetChar, ctx.dmg, extraDmg)
					else
						BuffService.ApplyDamage(plr, char, targetChar, ctx.dmg, extraDmg, "Weapon")
					end
					local xpName = ctx.xpName or getEquippedTool(plr)
					-- No XP for hitting a Downed body. It takes no damage and cannot fight back, so
					-- the XP would be free to farm.
					if
						targetChar.Humanoid.Health > 0
						and targetChar.Humanoid.MaxHealth < 10000
						and not StateHandler.GetState(targetChar, "Downed")
					then
						DataManager.AddWeaponXP(
							game.Players:GetPlayerFromCharacter(char),
							xpName,
							(ctx.dmg + extraDmg) * (ctx.xpMultiplier or 1)
						)
					end

					local highlight = game.ReplicatedStorage.assets.FX.h1:Clone()
					highlight.Parent = humanoid.Parent
					game.Debris:AddItem(highlight, 0.1)
					local hitEff =
						game:GetService("ReplicatedStorage").assets.FX.BloodHitEff.Attachment
							:Clone()
					hitEff.Parent = targetChar:FindFirstChild("Torso")
					game:GetService("Debris"):AddItem(hitEff, 1)
					task.delay(0.5, function()
						for _, v in pairs(hitEff:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								v.Enabled = false
							end
						end
					end)
					alreadyHit[targetChar] = true

					-- The endlag and the whiff recovery depend on whether the swing connected.
					if ctx.token then
						ctx.token.didHit = true
					end

					-- On-hit mana for the attacker: 2% of MaxMana on M1, 4% on M2 and E. It is here
					-- and not in BuffService, so the amount is the same with or without a buff. The
					-- action comes from the token, because the E path uses "M1" as its tag.
					if plr and plr:FindFirstChild("PlayerStats") then
						local stats = plr.PlayerStats
						local manaVal = stats:FindFirstChild("Mana")
						local maxManaVal = stats:FindFirstChild("MaxMana")
						if manaVal and maxManaVal and maxManaVal.Value > 0 then
							local tokenAction = ctx.token and ctx.token.action
							local pct = (tokenAction == "M1") and 0.02 or 0.04
							local restore = maxManaVal.Value * pct
							manaVal.Value = math.min(manaVal.Value + restore, maxManaVal.Value)
						end
					end
				end

				-- When the target is mid-attack, the fighter whose hitbox started first wins.
				local targetToken = activeAttacks[targetChar]
				if targetToken then
					local iAmArmored = ctx.token and ctx.token.hyperArmored
					if
						targetToken.hitboxStart
						and ctx.token
						and ctx.token.hitboxStart
						and targetToken.hitboxStart < ctx.token.hitboxStart
					then
						-- The target started first. An armored move trades instead: it takes
						-- the hit and keeps swinging.
						if not iAmArmored then
							ctx.token.cancelled = true
							AnimationHandler.StopAnim(char, "ALL")
							Hitbox:Destroy()
							return
						end
					elseif not targetToken.hyperArmored then
						-- We started first, it is a tie, or the target is still in windup.
						-- An armored target is not cancelled.
						targetToken.cancelled = true
						AnimationHandler.StopAnim(targetChar, "ALL")
					end
				end
				if StateHandler.GetState(targetChar, "Parrying") then
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = action,
						Func = "Parry",
						FolderName = getEquippedTool(plr),
					}, char, targetChar)
					local parryE =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
							:Clone()
					local effect2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit:Clone()
					local clash =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
							:Clone()
					local clash2 =
						game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].Clash
							:Clone()
					clash2.Parent = targetChar:WaitForChild("Right Arm")
					clash2:Emit(30)
					game.Debris:AddItem(clash2, 0.7)
					local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
					h1.Parent = char
					game.Debris:AddItem(h1, 0.1)
					parryE.Parent = char:WaitForChild("Torso")
					effect2.Parent = char:WaitForChild("Torso")
					clash.Parent = char:WaitForChild("Right Arm")
					parryE.Enabled = true
					effect2.Enabled = true
					clash:Emit(30)
					game.Debris:AddItem(clash, 0.7)
					game.Debris:AddItem(parryE, 0.7)
					game.Debris:AddItem(effect2, 0.7)
					StateHandler.SetStun(char, true, 0.85, 0.01)
					StateHandler.SetState(char, "CantAnything", true, 0.85)
					ParryService.ResetParry(game.Players:GetPlayerFromCharacter(targetChar))
					-- A landed parry relieves the parrier's guard bar.
					BlockResolver.OnParrySuccess(targetChar)
					local _tp = game.Players:GetPlayerFromCharacter(targetChar)
					local targetPlrData = _tp and _tp.PlayerStats
					if
						targetPlrData
						and targetPlrData.Mana.Value < targetPlrData.MaxMana.Value - 8
					then
						targetPlrData.Mana.Value += 8
					end
					AnimationHandler.StopAnim(char, "ALL")
					AnimationHandler.LoadAnim(
						char,
						"Parried",
						"rbxassetid://74891530644094",
						nil,
						false
					)
				elseif StateHandler.GetState(targetChar, "Blocking") then
					-- BlockResolver applies the guard bar and state effects and returns a verdict.
					-- Damage and FX vary per weapon, so they stay here.
					local class = (ctx.token and ctx.token.action) or action
					local verdict = BlockResolver.Resolve({
						attacker = char,
						target = targetChar,
						attackerHRP = attackerHRP,
						targetHRP = targetHRP,
						guardbreak = ctx.guardbreak,
						attackClass = class,
						dmg = ctx.dmg,
					})

					-- Because doAttack adds extraDmg to ctx.dmg, this makes the total chipDamage.
					local extra = verdict.chipDamage - ctx.dmg

					if verdict.outcome == "GuardBreak" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						if verdict.broke then
							-- The guard bar broke. GuardBarService already set the stun and
							-- the break animation.
							doAttack(extra, verdict.knockback)
						else
							-- The attack itself is a guard break, for example an M2, so it deals
							-- full damage.
							damageCalculator.CalculateDamage(
								char,
								targetChar,
								ctx.dmg,
								verdict.knockback,
								false,
								"Weapon"
							)
						end
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = action,
							Func = "GB",
							FolderName = getEquippedTool(plr),
						}, char, targetChar)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = "Block",
							Func = "GB",
							FolderName = getEquippedTool(plr),
						}, char, targetChar)
					elseif verdict.outcome == "Bypass" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						doAttack(extra, verdict.knockback)
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = action,
							Func = "Blocked",
							FolderName = getEquippedTool(plr),
						}, char, targetChar)
					else
						-- A blocked hit deals only chip damage and a short stagger. It skips
						-- doAttack, because a block must not land the full weapon hitstun or give
						-- the attacker mana and XP. A nil damage type is true damage, because
						-- chipDamage is already final.
						local BLOCK_STUN = 0.18
						-- The blocker can still move a little, unlike in a real hitstun.
						local BLOCK_STUN_SPEED = 8
						BlockResolver.OnAttackerLandedHit(char)
						local direction = (targetHRP.Position - attackerHRP.Position).Unit
						Helper.ApplyKnockback(targetChar, direction, verdict.knockback, 0.2)
						if verdict.chipDamage > 0 then
							damageCalculator.CalculateDamage(
								char,
								targetChar,
								verdict.chipDamage,
								0,
								false,
								nil,
								BLOCK_STUN,
								BLOCK_STUN_SPEED
							)
						else
							StateHandler.SetStun(targetChar, true, BLOCK_STUN, BLOCK_STUN_SPEED)
						end
						ReplicateRemote:FireAllClients({
							Type = "Combat",
							Action = action,
							Func = "Blocked",
							FolderName = getEquippedTool(plr),
						}, char, targetChar)
						local parryE =
							game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].parry
								:Clone()
						local effect2 =
							game:GetService("ReplicatedStorage").assets.FX["parry/blocked"].hit
								:Clone()
						local h1 = game.ReplicatedStorage.assets.FX.h1:Clone()
						h1.Parent = targetChar
						game.Debris:AddItem(h1, 0.1)
						parryE.Parent = targetChar:WaitForChild("Torso")
						effect2.Parent = targetChar:WaitForChild("Torso")
						parryE.Enabled = true
						effect2.Enabled = true
						game.Debris:AddItem(parryE, 0.7)
						game.Debris:AddItem(effect2, 0.7)
					end
				else
					ReplicateRemote:FireAllClients({
						Type = "Combat",
						Action = action,
						Func = "Hit",
						FolderName = getEquippedTool(plr),
					}, char, targetChar)
					doAttack(0, 5)
					applyHitstop(plr, char, targetChar, action, ctx.hitstopDuration)
				end
			end
		end
	end)
end

-- CombatCore.RunM1() - run one M1 swing on the server and resolve its hit
-- @plr: the attacking player
-- @cfg: the server.m1 entry of the weapon in WeaponConfig
-- @opts: optional hooks and values:
--        swingDispatch(char, combo) plays custom swing FX,
--        onWindupStart(char, combo) runs when the windup starts,
--        onDamage(plr, char, target, dmg, extraDmg) replaces the damage step,
--        xpMultiplier scales the weapon XP,
--        subType is the client movement state ("Lunge", "AirLunge", "Uppercut", or nil)
--
-- Yields for the windup.
--
-- Return: nothing.
function module.RunM1(plr, cfg, opts)
	opts = opts or {}
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	local dmg = cfg.dmg
	local guardbreak = cfg.guardbreak
	local windupDelay = cfg.windup
	local MAX_COMBO = cfg.maxCombo

	local Combo = StateHandler.GetState(char, "Combo")

	-- Only one attack per character can be in flight.
	if activeAttacks[char] then
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "M1",
			Func = "ServerResponse",
			FolderName = getEquippedTool(plr),
		}, plr, "Declined")
		return
	end

	local token = { cancelled = false, hitboxStart = nil, action = "M1" }
	activeAttacks[char] = token

	-- An M1 has armor only when WeaponConfig flags it. The clash check always reads
	-- token.hyperArmored.
	local hyperArmored = (cfg.guardbreak or cfg.hyperArmor) and true or false
	token.hyperArmored = hyperArmored
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
	end

	-- A stun or a down during the swing cancels it.
	local stopWatch = StateHandler.WatchInterrupt(char, windupDelay + 0.6, function()
		if hyperArmored then
			return
		end
		token.cancelled = true
		AnimationHandler.StopAnim(char, "ALL")
	end)
	local function finish()
		stopWatch()
		if hyperArmored then
			char:SetAttribute("HyperArmor", nil)
		end
		if activeAttacks[char] == token then
			activeAttacks[char] = nil
		end
	end
	local function abort()
		StateHandler.RemoveStates(char, "Windup")
		StateHandler.RemoveStates(char, "Active")
		-- The M1 slow lasts through the recovery. An interrupted swing must reset it here,
		-- or the attacker stays slow. ResetSpeed does nothing when no slow is stored.
		if cfg.setSpeed then
			Helper.ResetSpeed(char)
		end
		AnimationHandler.StopAnim(char, "ALL")
		finish()
	end

	StateHandler.SetState(char, "CantAnything", true, windupDelay + 0.05)
	StateHandler.SetState(char, "Windup", true, windupDelay + 0.2)

	setTrail(char, cfg.trailBlade, true)

	-- Running and Sliding are client-set attributes and do not replicate, so the movement
	-- state comes from opts.subType. Freefall is read here, because Humanoid states
	-- replicate. A Launched player is in Freefall during the juggle but gets the ground
	-- combo, the same as on the client.
	local subType = opts.subType
	local launched = char:GetAttribute("Launched")
	local extraAtk = 0
	if launched then
		extraAtk = 0
	elseif subType == "Lunge" then
		extraAtk = 6
	elseif
		subType == "AirLunge" or (char.Humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	then
		extraAtk = 7
	elseif subType == "Uppercut" then
		extraAtk = 8
	else
		extraAtk = 0
	end

	local nextCombo
	if type(Combo) ~= "number" then
		nextCombo = 1
	else
		nextCombo = (Combo % MAX_COMBO) + 1
	end
	StateHandler.SetState(char, "Combo", nextCombo)

	if comboResetTasks[plr] then
		task.cancel(comboResetTasks[plr])
	end
	comboResetTasks[plr] = task.delay(comboResetTime, function()
		StateHandler.RemoveStates(char, "Combo")
		comboResetTasks[plr] = nil
	end)

	-- The running attack (extraAtk 6) skips the setSpeed slow. With the slow, a sprinting
	-- target walks back out of range before the hitbox, and the lunge gains nothing.
	if extraAtk ~= 6 then
		if cfg.setSpeed then
			Helper.SetSpeed(char, cfg.setSpeed[1], cfg.setSpeed[2])
		end
	end

	-- The boost always fires. Against a target who runs away, the lunge also steers
	-- toward them during the windup. Steering is rate-limited, so a sharp cut, a dodge,
	-- or a parry still beats it. The token stops the lunge on a parry or a stun.
	if extraAtk == 6 then
		-- A nil speed means the lunge is off for this weapon.
		local lungeSpeed = DashConfig.Get("M1Lunge", getEquippedTool(plr))
		if lungeSpeed then
			local chaseUntil = windupDelay + (cfg.lungeWait or 0.4)
			LungeService.Start(char, lungeSpeed, chaseUntil, token)
		end
	end

	task.delay(0.2, function()
		if token.cancelled then
			return
		end
		ReplicateRemote:FireAllClients({
			Type = "Combat",
			Action = "M1",
			Func = "Swing",
			FolderName = getEquippedTool(plr),
		}, char)
	end)

	if opts.onWindupStart then
		local movePattern = (extraAtk ~= 0) and extraAtk or nextCombo
		opts.onWindupStart(char, movePattern)
	end

	task.wait(windupDelay - 0.1)

	if token.cancelled then
		abort()
		return
	end

	local oldCombo = nextCombo
	local newCombo = 0
	if extraAtk ~= 0 then
		newCombo = extraAtk
	end
	if newCombo ~= 0 then
		nextCombo = newCombo
		oldCombo = oldCombo - 1
	end

	if opts.swingDispatch then
		opts.swingDispatch(char, nextCombo)
	else
		genericSwing(char, nextCombo, cfg)
	end

	nextCombo = oldCombo

	task.wait(0.1)

	if token.cancelled then
		abort()
		return
	end

	-- The clash check compares hitbox start times.
	StateHandler.RemoveStates(char, "Windup")
	StateHandler.SetState(char, "Active", true, 0.25)
	token.hitboxStart = os.clock()

	local humrp = char.HumanoidRootPart
	local hitboxParams = {
		SizeOrPart = cfg.hitboxSize,
		SpatialOption = cfg.hitboxShape,
		Debug = false,
		DebounceTime = 0.5,
	}
	local Hitbox, connected = HitboxClass.new(hitboxParams)
	Hitbox:WeldTo(humrp, cfg.hitboxOffset)
	Hitbox:Start()

	StateHandler.SetState(char, "M1", true, 0.2)

	-- Decided once and captured by the knockback closure, so it is fixed for the swing.
	local isUppercut = (extraAtk == 8)

	-- The attacker rises only when the uppercut connects, in m1Knockback. A whiffed
	-- uppercut is a normal M1 that can be punished.

	-- Only plain M1 hits use this. The uppercut and the combo-5 finisher have their own
	-- stuns.
	local m1Hitstun = computeHitstun("M1", getEquippedTool(plr))

	local function m1Knockback(
		kchar,
		ktargetChar,
		ktargetHRP,
		kattackerHRP,
		direction,
		knockbackDistance
	)
		if isUppercut then
			-- Move the victim to the apex height of the attacker, UC.Offset studs in front of
			-- the attacker, so the follow-up M1 string reaches them.
			local UC = WeaponConfig.Uppercut
			local thrp = ktargetChar:FindFirstChild("HumanoidRootPart")
			local look = kattackerHRP.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = (flat.Magnitude > 0.001) and flat.Unit or Vector3.new(0, 0, 0)
			if thrp then
				local apex = Vector3.new(
					kattackerHRP.Position.X + flat.X * UC.Offset,
					thrp.Position.Y + UC.RiseHeight,
					kattackerHRP.Position.Z + flat.Z * UC.Offset
				)
				juggleFloat(thrp, apex, UC.HangWindow, UC.Responsiveness)
			end
			ktargetChar:SetAttribute("Launched", true)
			task.delay(LAUNCH_WINDOW, function()
				if ktargetChar then
					ktargetChar:SetAttribute("Launched", nil)
				end
			end)
			StateHandler.SetStun(ktargetChar, true, LAUNCH_WINDOW, HITSTUN_STUNSPEED)

			-- This runs only on a connect. The attacker gets Launched so the follow-up reads as
			-- the ground combo, and the attacker's own client performs the rise.
			kchar:SetAttribute("Launched", true)
			task.delay(LAUNCH_WINDOW, function()
				if kchar then
					kchar:SetAttribute("Launched", nil)
				end
			end)
			ReplicateRemote:FireClient(plr, {
				Type = "Combat",
				Action = "M1",
				Func = "UppercutRise",
				FolderName = getEquippedTool(plr),
			}, kchar)
		elseif StateHandler.GetState(kchar, "Combo") == 5 then
			Helper.ApplyKnockback(ktargetChar, direction, knockbackDistance * 2, 0.2)
			StateHandler.SetStun(ktargetChar, true, 0.5, HITSTUN_STUNSPEED)
		else
			Helper.ApplyKnockback(ktargetChar, direction, knockbackDistance, 0.2)
			StateHandler.SetStun(ktargetChar, true, m1Hitstun, HITSTUN_STUNSPEED)
		end
	end

	resolveHit(plr, char, Hitbox, "M1", {
		dmg = dmg,
		guardbreak = guardbreak,
		onDamage = opts.onDamage,
		xpMultiplier = opts.xpMultiplier,
		xpName = cfg.xpName,
		applyKnockback = m1Knockback,
		hitstopDuration = cfg.hitstopDuration,
		token = token,
	})

	task.delay(0.1, function()
		Hitbox:Destroy()
		setTrail(char, cfg.trailBlade, false)
		StateHandler.RemoveStates(char, "Active")
		StateHandler.SetState(char, "Recovery", true, 0.25)
		if not token.didHit then
			StateHandler.SetState(char, "CantAnything", true, M1E_WHIFF_RECOVERY)
		end
		-- Release the slow 0.2 seconds after the 0.25-second recovery. Running attacks never
		-- took the slow.
		if cfg.setSpeed and extraAtk ~= 6 then
			task.delay(0.45, function()
				if char and char.Parent then
					Helper.ResetSpeed(char)
				end
			end)
		end
		finish()
	end)
end

-- CombatCore.RunM2() - run one M2 swing on the server and resolve its hit
-- @plr: the attacking player
-- @cfg: the server.m2 entry of the weapon in WeaponConfig
-- @opts: optional hooks and values:
--        swingM2(char) plays a custom swing,
--        onDamage(plr, char, target, dmg, extraDmg) replaces the damage step,
--        xpMultiplier scales the weapon XP
--
-- Yields for the windup.
--
-- Return: nothing.
function module.RunM2(plr, cfg, opts)
	opts = opts or {}
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	local WINDUP_DELAY = cfg.windup
	local HITBOX_DURATION = cfg.hitboxDuration or 0.2
	local POST_COOLDOWN = cfg.postCooldown or 3

	local isBusy = false
	if activeAttacks[char] then
		isBusy = true
	elseif playerM2Debounces[plr] then
		isBusy = true
	elseif StateHandler.GetState(char, "M1") then
		isBusy = true
	elseif StateHandler.GetState(char, "M2") then
		isBusy = true
	elseif StateHandler.GetState(char, "CantAnything") then
		isBusy = true
	elseif StateHandler.GetState(char, "Blocking") then
		isBusy = true
	elseif StateHandler.GetState(char, "Stunned") then
		isBusy = true
	elseif StateHandler.GetState(char, "Dodging") then
		isBusy = true
	end
	if isBusy then
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "M2",
			Func = "ServerResponse",
			FolderName = getEquippedTool(plr),
		}, plr, "Declined")
		return
	end

	-- Decide once, before the swing starts, whether this M2 is a combo ender.
	local comboNow = StateHandler.GetState(char, "Combo")
	local isFinisher = (type(comboNow) == "number" and comboNow >= M2_FINISHER_MIN_COMBO)
	local m2Knockback = makeM2Knockback(isFinisher)

	local token = { cancelled = false, hitboxStart = nil, action = "M2" }
	activeAttacks[char] = token
	playerM2Debounces[plr] = true

	-- Every M2 is a guard break and has armor. With the HyperArmor attribute, SetStun
	-- does nothing on this character, so a hit still deals damage but does not stop the
	-- swing. The clash check reads token.hyperArmored.
	local hyperArmored = (cfg.guardbreak or cfg.hyperArmor) and true or false
	token.hyperArmored = hyperArmored
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
	end

	StateHandler.SetState(char, "CantAnything", true, WINDUP_DELAY + HITBOX_DURATION + 0.5)
	StateHandler.SetState(char, "Windup", true, WINDUP_DELAY + 0.2)

	local stopWatch = StateHandler.WatchInterrupt(char, 3, function()
		if hyperArmored then
			return
		end
		token.cancelled = true
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, mover in ipairs(hrp:GetChildren()) do
				if mover:IsA("BodyVelocity") or mover:IsA("LinearVelocity") then
					mover:Destroy()
				end
			end
		end
		AnimationHandler.StopAnim(char, "ALL")
	end)
	local function finish()
		stopWatch()
		if hyperArmored then
			char:SetAttribute("HyperArmor", nil)
		end
		if activeAttacks[char] == token then
			activeAttacks[char] = nil
		end
	end

	local NewShield = RP.assets.FX.danger:Clone()
	game.Debris:AddItem(NewShield, 1)
	local WeldCon = Instance.new("WeldConstraint", NewShield)
	NewShield.Parent = char
	local parrysfx = Instance.new("Sound")
	parrysfx.Parent = char.Torso
	parrysfx.SoundId = "rbxassetid://7100154577"
	parrysfx.Volume = 0.5
	parrysfx.RollOffMaxDistance = 60
	parrysfx.RollOffMinDistance = 10
	parrysfx.RollOffMode = Enum.RollOffMode.Inverse
	NewShield.CFrame = char.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
	WeldCon.Part0 = char.HumanoidRootPart
	WeldCon.Part1 = NewShield
	TweenService:Create(
		NewShield,
		TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
		{ Transparency = 1, Color = Color3.fromRGB(255, 0, 0) }
	):Play()
	parrysfx:Play()
	game.Debris:AddItem(parrysfx, 3)

	-- Read the weapon now. A weapon swap during the delay must not change the dash of a
	-- swing that the old weapon started.
	local m2Weapon = getEquippedTool(plr)
	task.delay(0.3, function()
		if token.cancelled then
			return
		end
		local m2Speed, m2Life = DashConfig.Get("M2", m2Weapon)
		if m2Speed then
			local BV = Instance.new("BodyVelocity", char.HumanoidRootPart)
			BV.MaxForce = Vector3.new(25000, 0, 25000)
			BV.Velocity = char.HumanoidRootPart.CFrame.lookVector * m2Speed
			game.Debris:AddItem(BV, m2Life)
		end
		dashEff(char)
	end)

	if cfg.setSpeed then
		Helper.SetSpeed(char, cfg.setSpeed[1], cfg.setSpeed[2])
	end
	task.delay(WINDUP_DELAY, function()
		if cfg.setSpeed then
			Helper.ResetSpeed(char)
		end
	end)

	task.delay(0.25, function()
		if token.cancelled then
			return
		end
		ReplicateRemote:FireAllClients({
			Type = "Combat",
			Action = "M2",
			Func = "Swing",
			FolderName = getEquippedTool(plr),
		}, char)
	end)

	task.wait(WINDUP_DELAY)

	if token.cancelled then
		StateHandler.RemoveStates(char, "Windup")
		if cfg.setSpeed then
			Helper.ResetSpeed(char)
		end
		if NewShield then
			NewShield:Destroy()
		end
		AnimationHandler.StopAnim(char, "ALL")
		finish()
		task.delay(POST_COOLDOWN, function()
			playerM2Debounces[plr] = nil
		end)
		return
	end

	StateHandler.RemoveStates(char, "Windup")
	StateHandler.SetState(char, "Active", true, HITBOX_DURATION + 0.1)
	token.hitboxStart = os.clock()

	if opts.swingM2 then
		opts.swingM2(char)
	else
		local fx = cfg.swingFX
		if fx then
			emitSlash(char, fx.folder, fx.slash, fx.part)
		end
	end

	local humrp = char.HumanoidRootPart
	local hitboxParams = {
		SizeOrPart = cfg.hitboxSize,
		SpatialOption = cfg.hitboxShape,
		Debug = false,
		DebounceTime = 0.5,
	}
	local Hitbox = HitboxClass.new(hitboxParams)
	Hitbox:WeldTo(humrp, cfg.hitboxOffset)
	Hitbox:Start()

	StateHandler.SetState(char, "M2", true, HITBOX_DURATION)

	resolveHit(plr, char, Hitbox, "M2", {
		dmg = cfg.dmg,
		guardbreak = cfg.guardbreak,
		onDamage = opts.onDamage,
		xpMultiplier = opts.xpMultiplier,
		xpName = cfg.xpName,
		applyKnockback = m2Knockback,
		hitstopDuration = cfg.hitstopDuration,
		token = token,
	})

	-- Replace the long lock from the start of the swing with the endlag for a hit or a
	-- whiff.
	task.delay(HITBOX_DURATION, function()
		Hitbox:Destroy()
		StateHandler.RemoveStates(char, "Active")

		local endlag = token.didHit and M2_ENDLAG_HIT or M2_ENDLAG_WHIFF

		-- RemoveStates cancels the original timer, so the old lock cannot expire on top of
		-- this one.
		StateHandler.RemoveStates(char, "CantAnything")
		if endlag > 0 then
			StateHandler.SetState(char, "CantAnything", true, endlag)
		end
		StateHandler.SetState(char, "Recovery", true, endlag + 0.1)

		finish()
	end)

	task.delay(POST_COOLDOWN, function()
		playerM2Debounces[plr] = nil
	end)
end

-- CombatCore.RunE() - run one E swing on the server and resolve its hit
-- @plr: the attacking player
-- @cfg: the server.e entry of the weapon in WeaponConfig
-- @opts: optional hooks and values:
--        onWindupStart(char) runs when the windup starts,
--        swingE(char) plays a custom swing,
--        onDamage(plr, char, target, dmg, extraDmg) replaces the damage step,
--        xpMultiplier scales the weapon XP
--
-- Yields for the windup.
--
-- Return: nothing.
function module.RunE(plr, cfg, opts)
	opts = opts or {}
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	if activeAttacks[char] then
		ReplicateRemote:FireClient(plr, {
			Type = "Combat",
			Action = "E",
			Func = "ServerResponse",
			FolderName = getEquippedTool(plr),
		}, plr, "Declined")
		return
	end

	local windupDelay = cfg.windup
	local token = { cancelled = false, hitboxStart = nil, action = "E" }
	activeAttacks[char] = token

	-- An E has armor only when WeaponConfig flags it.
	local hyperArmored = (cfg.guardbreak or cfg.hyperArmor) and true or false
	token.hyperArmored = hyperArmored
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
	end

	local stopWatch = StateHandler.WatchInterrupt(char, windupDelay + 0.6, function()
		if hyperArmored then
			return
		end
		token.cancelled = true
		AnimationHandler.StopAnim(char, "ALL")
	end)
	local function finish()
		stopWatch()
		if hyperArmored then
			char:SetAttribute("HyperArmor", nil)
		end
		if activeAttacks[char] == token then
			activeAttacks[char] = nil
		end
	end
	local function abort()
		StateHandler.RemoveStates(char, "Windup")
		setTrail(char, cfg.trailBlade, false)
		AnimationHandler.StopAnim(char, "ALL")
		finish()
	end

	-- E starts combos, so the lock ends with the windup, the same as in RunM1.
	StateHandler.SetState(char, "CantAnything", true, windupDelay + 0.05)
	StateHandler.SetState(char, "Windup", true, windupDelay + 0.2)
	setTrail(char, cfg.trailBlade, true)

	if cfg.setSpeed then
		Helper.SetSpeed(char, cfg.setSpeed[1], cfg.setSpeed[2])
	end

	if opts.onWindupStart then
		opts.onWindupStart(char)
	end

	task.delay(0.4, function()
		if token.cancelled then
			return
		end
		ReplicateRemote:FireAllClients({
			Type = "Combat",
			Action = "M1",
			Func = "Swing",
			FolderName = getEquippedTool(plr),
		}, char)
	end)

	task.wait(windupDelay - 0.1)

	if token.cancelled then
		abort()
		return
	end

	if opts.swingE then
		opts.swingE(char)
	else
		local fx = cfg.swingFX
		if fx then
			emitSlash(char, fx.folder, fx.slash, fx.part)
		end
	end

	task.wait(0.1)
	if cfg.setSpeed then
		Helper.ResetSpeed(char)
	end

	if token.cancelled then
		abort()
		return
	end

	StateHandler.RemoveStates(char, "Windup")
	StateHandler.SetState(char, "Active", true, 0.25)
	token.hitboxStart = os.clock()

	local humrp = char.HumanoidRootPart
	local hitboxParams = {
		SizeOrPart = cfg.hitboxSize,
		SpatialOption = cfg.hitboxShape,
		Debug = false,
		DebounceTime = 0.5,
	}
	local Hitbox = HitboxClass.new(hitboxParams)
	Hitbox:WeldTo(humrp, cfg.hitboxOffset)
	Hitbox:Start()

	StateHandler.SetState(char, "M1", true, 0.2)

	resolveHit(plr, char, Hitbox, "M1", {
		dmg = cfg.dmg,
		guardbreak = cfg.guardbreak,
		onDamage = opts.onDamage,
		xpMultiplier = opts.xpMultiplier,
		xpName = cfg.xpName,
		applyKnockback = eKnockback,
		hitstopDuration = cfg.hitstopDuration,
		token = token,
	})

	-- RunM1 declines input until finish() releases activeAttacks, so this delay must match
	-- the lock above. Heavy weapons set a longer eRecovery in WeaponConfig.
	local E_RECOVERY = cfg.eRecovery or 0.1

	task.delay(E_RECOVERY, function()
		Hitbox:Destroy()
		setTrail(char, cfg.trailBlade, false)
		StateHandler.RemoveStates(char, "Active")
		StateHandler.SetState(char, "Recovery", true, 0.25)
		if not token.didHit then
			StateHandler.SetState(char, "CantAnything", true, M1E_WHIFF_RECOVERY)
		end
		finish()
	end)
end

Players.PlayerRemoving:Connect(function(plr)
	playerM1Debounces[plr] = nil
	playerM2Debounces[plr] = nil
	if comboResetTasks[plr] then
		task.cancel(comboResetTasks[plr])
		comboResetTasks[plr] = nil
	end
end)

-- CombatCore.BeginAttack() - register an attack in flight for clash checks
-- @char: the attacking character, a player or a mob
--
-- Players and mob AI share the registry.
--
-- Return: the attack token. Pass it to MarkHitbox and FinishAttack.
function module.BeginAttack(char)
	local token = { cancelled = false, hitboxStart = nil }
	activeAttacks[char] = token
	return token
end
-- CombatCore.GetAttack() - get the attack in flight of a character
-- @char: the character
--
-- Return: the attack token, or nil.
function module.GetAttack(char)
	return activeAttacks[char]
end
-- CombatCore.MarkHitbox() - record that the hitbox of an attack is live
-- @token: the attack token from BeginAttack, or nil
--
-- Return: nothing.
function module.MarkHitbox(token)
	if token then
		token.hitboxStart = os.clock()
	end
end
-- CombatCore.FinishAttack() - remove an attack from the registry
-- @char: the attacking character
-- @token: the attack token from BeginAttack
--
-- Does nothing if a newer attack replaced the token.
--
-- Return: nothing.
function module.FinishAttack(char, token)
	if activeAttacks[char] == token then
		activeAttacks[char] = nil
	end
end
-- CombatCore.ResolveClash() - decide a clash when an attack hits a fighter
-- @attackerToken: the token of the attack that hit
-- @targetChar: the character that was hit
--
-- Return: "lose" when the target's hitbox started first, "win" and the target's token
-- otherwise, or nil when the target is not attacking.
function module.ResolveClash(attackerToken, targetChar)
	local targetToken = activeAttacks[targetChar]
	if not targetToken then
		return nil
	end
	if
		targetToken.hitboxStart
		and attackerToken
		and attackerToken.hitboxStart
		and targetToken.hitboxStart < attackerToken.hitboxStart
	then
		return "lose"
	end
	return "win", targetToken
end

-- CombatCore.EmitSlash() - play a slash FX on a character
-- @char: the character
-- @folderPath: the FX folder path under ReplicatedStorage.assets.FX
-- @slashChild: the name of the slash template
-- @partName: the part to attach to when the character has no HumanoidRootPart
--
-- Slash FX are disabled, so this does nothing.
--
-- Return: nothing.
module.EmitSlash = emitSlash

return module
