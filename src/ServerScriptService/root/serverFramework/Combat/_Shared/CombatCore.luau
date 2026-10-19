-- CombatCore: shared server-side combat flow + hit resolution for M1 and M2.
-- Weapons call RunM1 / RunM2 with their config. resolveHit is the single shared
-- resolution core (dodge, damage, parry, block, guardbreak), parameterized by the
-- action string and an injected knockback function. Optional opts hooks:
--   opts.swingDispatch(char, combo)   -> custom M1 swing FX (greatsword downSwing)
--   opts.onWindupStart(char, combo)   -> M1 windup hook (fist FX)
--   opts.swingM2(char)                -> custom M2 swing (fist aerial)
--   opts.onDamage(plr,char,tgt,dmg,extra) -> custom damage step (buffs)
--   opts.xpMultiplier                 -> XP scaling (Caestus half)
--   opts.subType                      -> client-reported movement state for M1
--                                        ("Lunge" / "AirLunge" / "Uppercut" / nil)
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

-- [[ M2 ENDLAG ]] --
-- How long CantAnything holds AFTER the M2 hitbox closes. Landing the hit buys you a
-- much shorter recovery, which is what turns M2 from a standalone commit into a combo
-- extender: connect, then cancel into M1 / E / a skill / a dash.
--
-- Whiffing still costs you. If both were short, M2 would be a free spam button with no
-- read attached to it.
--
-- These do NOT touch the M2 cooldown (cfg.postCooldown, 3-7s). You still cannot chain
-- M2 into another M2. M2 opens a window; it does not become the window.
local M2_ENDLAG_HIT = 0.1
local M2_ENDLAG_WHIFF = 0.65 -- +0.2: whiffing a guardbreak is punished harder

-- [[ M1 / E WHIFF RECOVERY ]] --
-- M1 and E have no hit/whiff split of their own: recovery is uniform (M1's is the
-- client cooldown; E's is cfg.eRecovery). This is the whiff-only penalty added AFTER
-- the hitbox resolves, as an extra CantAnything, ONLY when the swing connected with
-- nothing (token.didHit is false). On hit it never applies, so combos are untouched;
-- it only makes a missed swing cost you. token.didHit is already recorded by resolveHit
-- for every action, so both paths just read it.
local M1E_WHIFF_RECOVERY = 0.2

-- [[ HITSTUN (per-move victim freeze) ]] --
-- How long a hit victim is frozen (the "Stunned" duration passed down to
-- damageCalculator). This is what decides what combos into what. A combo is
-- TRUE (unbreakable) when the victim's hitstun outlasts the attacker's own
-- recovery; it is a READ (parryable) when they come out of stun around the
-- time the next hitbox is live.
--
-- The attacker's recovery for a basic M1 is its per-weapon client cooldown
-- (WeaponConfig[weapon].client.m1.cooldown: dagger 0.4 ... greatsword 1.1).
-- M1 hitstun is (that recovery + a small margin), which keeps the LINK
-- consistent across weapons even though their raw speeds differ: every
-- light/medium weapon lands at +M1_ADVANTAGE frame advantage whether it is a
-- fast dagger or a slower guandao. Startup/recovery vary; the link does not.
-- (Same idea as a 4f jab vs a 7f heavy jab still linking into the same follow-up.)
--
-- M2 and E are punctuation, not part of the tight M1 rhythm, so they take a
-- flat generous hitstun rather than a recovery-scaled one: landing one should
-- reliably let you continue, escapable by burst but not by a reactive parry.
--
-- Tune freely. Raising M1_ADVANTAGE makes M1 strings harder to parry out of
-- (toward true combos); lowering it (or negative) opens the parry window.
local M1_ADVANTAGE = 0.20 -- seconds of frame advantage on a light/med M1.
-- At 0.20 the victim's hitstun outlasts the attacker's
-- recovery by enough that the NEXT M1's startup lands
-- while they are still frozen: a landed M1 is now a TRUE
-- combo (no walk-out, no dash-out). The only escape is a
-- parry, which is allowed mid-stun (see _Shared.Block).
local M1_MIN_HITSTUN = 0.45 -- floor so a fast weapon still stuns meaningfully
local GREATSWORD_M1_HITSTUN = 1.0 -- heavies do NOT get a free M1 chain: recovery
-- 1.1 minus this = negative advantage (a read,
-- never a guaranteed second light). Keyed by
-- WeaponConfig `family` (GS / DS / Deathbringer).
local M2_HITSTUN = 1.10 -- flat: links into M1 on every weapon
local E_HITSTUN = 1.00 -- flat: E is the combo STARTER, flows into M1
local HITSTUN_STUNSPEED = 1 -- walkspeed while in weapon hitstun (near-immobile; kills S-hold backpedal-out)

-- Resolve hitstun for a landed weapon hit. `action` is the move type
-- ("M1"/"M2"/"E"). `weaponName` is the equipped weapon, used for the M1 cooldown
-- lookup and the greatsword family check. Returns the stun duration in seconds.
-- In practice each knockback closure knows its own move, so it calls this with a
-- literal action; M2/E use the flat constants directly and M1 is the only one
-- that actually needs the weapon lookup.
local function computeHitstun(action, weaponName)
	if action == "M2" then
		return M2_HITSTUN
	elseif action == "E" then
		return E_HITSTUN
	end
	-- M1
	local wc = weaponName and WeaponConfig[weaponName]
	if wc and wc.family == "Greatsword" then
		return GREATSWORD_M1_HITSTUN
	end
	local recovery = (wc and wc.client and wc.client.m1 and wc.client.m1.cooldown) or 0.5
	return math.max(recovery + M1_ADVANTAGE, M1_MIN_HITSTUN)
end

-- [[ M2 AS COMBO ENDER ]] --
-- M2 always works as a standalone heavy. But when it lands WHILE an M1 combo is still
-- open (the server's Combo counter is at or above this threshold), it gets a finisher
-- payload: a launch + a longer stun instead of the plain push. "Combo ender" =
-- the move you cash an M1 string out into. Below the threshold it is the normal heavy.
-- Combo is 1-indexed and set on the first M1, so >= 2 means "you have thrown at least a
-- couple of M1s and the window has not lapsed."
local M2_FINISHER_MIN_COMBO = 2
local M2_FINISHER_LAUNCH_UP = 40 -- upward pop on a combo-ender M2
local M2_FINISHER_LAUNCH_BACK = 20 -- backward shove so they travel away as they rise
local M2_FINISHER_STUN = 1.2

-- [[ UPPERCUT / JUGGLE ]] --
-- The uppercut (slide + M1) launches BOTH the attacker and the victim into a short
-- hang, so the attacker can follow with an M1 string / E / M2 while both are airborne.
-- The hang is a real gravity-suspend: a sustained upward drive for LAUNCH_WINDOW, not a
-- one-frame pop. Both parties get the "Launched" attribute for the window, which the
-- M1 path reads to force a GROUND combo in the air (see RunM1) instead of the aerial
-- attack. The victim is held in a hittable stun (NOT ragdolled: a ragdoll flops out of
-- hitboxes and cannot be cleanly juggled).
local LAUNCH_WINDOW = WeaponConfig.Uppercut.HangWindow -- apex hold + Launched-flag lifetime (shared with client M1 via WeaponConfig.Uppercut)

local comboResetTime = 5
local comboResetTasks = {}
local playerM1Debounces = {}
local playerM2Debounces = {}
local activeAttacks = setmetatable({}, { __mode = "k" }) -- [char] = { cancelled, hitboxStart, action }

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

-- Suspend a character in the air for `window` seconds: a strong upward burst followed
-- by a weaker sustained lift that fights gravity so they hang instead of dropping.
-- `back` is an optional horizontal component along the reference look vector (used to
-- push a launched victim away from the attacker as they rise). Cleans itself up.
local function floatUp(char, burstUp, hangUp, back, lookVec, window)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- clear any prior launch mover so two uppercuts do not stack drives
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

	-- after the burst, drop to the weaker hold so they float rather than rocket
	task.delay(0.12, function()
		if BV.Parent then
			BV.Velocity = Vector3.new(0, hangUp, 0)
		end
	end)

	game.Debris:AddItem(BV, window)
end

-- Eases an HRP up to `targetPos` and HOLDS it there for `window`, then releases. Used for
-- the uppercut juggle: an AlignPosition replicates to the target's own client and moves it,
-- so this works on a victim we do NOT own the network ownership of, no ownership juggling.
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

-- Hitstop: on a clean landed hit, briefly freeze both fighters' animations (via a
-- replicated client call) and lock the victim's movement so they are stuck in the
-- hit for the freeze window. Movement lock is server-authoritative (WalkSpeed etc.
-- replicate from here); animation freeze is cosmetic and done per-client.
local HITSTOP_DEFAULT = 0.12
local hitstopLocks = setmetatable({}, { __mode = "k" }) -- [char] = { walk, jumpP, jumpH, autoRotate }

local function applyHitstop(plr, attackerChar, targetChar, action, duration)
	duration = duration or HITSTOP_DEFAULT

	-- tell every client to freeze both fighters' animations
	ReplicateRemote:FireAllClients({
		Type = "Combat",
		Action = action,
		Func = "Hitstop",
		FolderName = getEquippedTool(plr),
	}, attackerChar, targetChar)

	-- lock the victim in place for the freeze window (server side, so it holds).
	-- do NOT touch a victim who is already fully Stunned or Downed (a real hit
	-- reaction owns their movement; hitstop must not shorten or fight it).
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
	end -- already frozen; let it ride

	hitstopLocks[targetChar] = {
		jumpP = humanoid.JumpPower,
		jumpH = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}
	-- WalkSpeed is owned by SpeedService now (STUN priority, same band as a real stun
	-- so a stun taking over during the freeze doesn't get out-prioritised). Jump and
	-- AutoRotate are still stashed/restored locally: they aren't part of the speed race.
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
			-- humanoid gone: still drop the modifier so it can't linger on a rig reuse
			SpeedService.Pop(targetChar, "Hitstop")
			return
		end
		-- Always pop the hitstop speed modifier. If a real stun took over during the
		-- freeze it pushed its own STUN modifier, so Resolve keeps the 0-lock; we don't
		-- need the old "return early to avoid stomping" dance. Jump/AutoRotate are only
		-- restored when no stun owns them (a live stun owns those for its duration).
		SpeedService.Pop(targetChar, "Hitstop")
		if StateHandler.GetState(targetChar, "Stunned") then
			return
		end
		h.JumpPower = saved.jumpP
		h.JumpHeight = saved.jumpH
		h.AutoRotate = saved.autoRotate
	end)
end

-- generic slash emitter (rightSwing/leftSwing/upSwing collapsed to data)
local function emitSlash(char, folderPath, slashChild, partName)
	--[[
	local folder = RP.assets.FX
	for seg in folderPath:gmatch("[^.]+") do
		folder = folder and folder:FindFirstChild(seg)
	end
	if not folder then return end
	local template = folder:FindFirstChild(slashChild)
	if not template then return end
	local host = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild(partName) or char:FindFirstChild("Torso")
	if not host then return end
	local attachment = template:Clone()
	attachment.CFrame = host.CFrame
	attachment.Parent = host
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachment.Parent
	weld.Part1 = host
	weld.Parent = attachment.Parent
	for _, v in pairs(attachment:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 10)
		end
	end
	game.Debris:AddItem(attachment, 2)
	]]
end

-- combo -> swing FX using the comboMap ("R"=rightSwing/SlashFXLeft, "L"=leftSwing/SlashFXRight, "U"=upSwing/SlashFXUp)
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

-- afterimage effect (shared by the M2 dash)
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

-- M2 knockback. Plain push + brief stun by default. When `isFinisher` is set (M2 landed
-- as a combo ender), it launches the victim up-and-back and holds a longer stun, so the
-- ender reads as a real payoff for the M1 string that fed it. It is a closure captured
-- per-call in RunM2 so the combo decision (made once, up front) is fixed for the swing.
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

-- shared hit resolution. action = "M1"/"M2"/"E" (replication tag).
-- ctx = { dmg, guardbreak, onDamage, xpMultiplier, xpName, applyKnockback }
-- E knockback: strong push (x2) + E hitstun (the combo-starter freeze)
local function eKnockback(char, targetChar, targetHRP, attackerHRP, direction, knockbackDistance)
	Helper.ApplyKnockback(targetChar, direction, knockbackDistance * 2, 0.2)
	StateHandler.SetStun(targetChar, true, E_HITSTUN, HITSTUN_STUNSPEED)
end

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
				if not targetHRP or not attackerHRP then
					return
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
					-- Knockback first: it must run before a hit can down the target, so
					-- we never stun/juggle a freshly-downed body. The knockback closure
					-- is the sole HITSTUN authority for weapon hits (per-move values set
					-- in eKnockback / makeM2Knockback / m1Knockback). damageCalculator
					-- deliberately SKIPS its own stun when dmgType == "Weapon", so there
					-- is no second writer to clobber the per-move value.
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
						-- default path: BuffService applies any active buff, else plain damage
						BuffService.ApplyDamage(plr, char, targetChar, ctx.dmg, extraDmg, "Weapon")
					end
					local xpName = ctx.xpName or getEquippedTool(plr)
					-- no XP off a downed body: they take no damage (damageCalculator bails on
					-- Downed) and cannot fight back, so awarding XP here is a free farm.
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

					-- Record the connect on the attack token. RunM2 reads this to cut
					-- its endlag on hit: landing an M2 should reward you with a faster
					-- recovery than whiffing one.
					if ctx.token then
						ctx.token.didHit = true
					end

					-- On-hit mana restore for the attacker. Buff-agnostic by design:
					-- it lives in doAttack (the shared damage-landed point) rather than
					-- in BuffService, so it fires the same amount whether or not a buff
					-- is active. M1 = 2% of MaxMana, M2/E = 4%. The action string arg is
					-- unreliable (the E path tags itself "M1" for replication), so we key
					-- off ctx.token.action, which is set correctly per Run function.
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

				-- clash / interrupt-on-hit: target mid-attack resolves by who started first
				local targetToken = activeAttacks[targetChar]
				if targetToken then
					local iAmArmored = ctx.token and ctx.token.hyperArmored
					if
						targetToken.hitboxStart
						and ctx.token
						and ctx.token.hitboxStart
						and targetToken.hitboxStart < ctx.token.hitboxStart
					then
						-- their hitbox started first: I lose the clash, unless my move is
						-- armored, in which case I trade (eat their hit, keep swinging).
						if not iAmArmored then
							ctx.token.cancelled = true
							AnimationHandler.StopAnim(char, "ALL")
							Hitbox:Destroy()
							return
						end
					elseif not targetToken.hyperArmored then
						-- I started first, tie, or they are still in windup: I win, cancel them.
						-- An armored (guardbreak) move can't be clashed out: they eat the hit
						-- and keep swinging, so we leave their token alone.
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
					-- All block outcomes route through BlockResolver (the single
					-- chokepoint that also owns the guard bar). It performs the guard
					-- bar / state side effects and returns a verdict; we apply damage
					-- (via doAttack) and FX here, since those vary per weapon.
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

					-- doAttack takes an ADDITIVE extraDmg on top of ctx.dmg, so to land
					-- exactly verdict.chipDamage we pass (chipDamage - ctx.dmg).
					local extra = verdict.chipDamage - ctx.dmg

					if verdict.outcome == "GuardBreak" then
						AnimationHandler.StopAnim(targetChar, "", "rbxassetid://96311777205911")
						if verdict.broke then
							-- bar-triggered block-break: GuardBarService already set the
							-- stun + break anim. Deal the chip and announce the break.
							doAttack(extra, verdict.knockback)
						else
							-- attack-guardbreak (e.g. M2): full damage.
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
						-- normal successful block (chip + frame advantage already set).
						--
						-- BUGFIX: this used to call doAttack(), which routes through
						-- applyKnockback and lands the FULL per-move weapon hitstun on the
						-- blocker (0.45s on M1, ~1.0s on E). Blocking a hit is not the same as
						-- eating one: it should barely stagger. So we no longer run the on-hit
						-- pipeline (that also wrongly gave the attacker mana/XP for a blocked
						-- swing). We deal only the chip and a short, light block-stun here.
						-- dmgType nil = true damage (no stat re-scaling; chip is already final),
						-- with an explicit small stunOverride so the blocker is only briefly
						-- checked, not comboed.
						local BLOCK_STUN = 0.18
						local BLOCK_STUN_SPEED = 8 -- can still shuffle; not pinned like a real hit
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

	-- one attack in flight per player; also the clash/interrupt registry
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

	-- HYPERARMOR: M1 is not a guardbreak by default, but honor cfg.hyperArmor so any
	-- move flagged in WeaponConfig gets armor, and always stamp token.hyperArmored so
	-- the clash logic reads a real value. See RunM2 for the full rationale.
	local hyperArmored = (cfg.guardbreak or cfg.hyperArmor) and true or false
	token.hyperArmored = hyperArmored
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
	end

	-- reactive interrupt: a stun/downed cancels the whole sequence
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
		-- Safety net: the M1 slow (SetSpeed) is no longer reset before the hitbox; it is
		-- held through the endlag now (see the finish block). If the swing is interrupted
		-- after windup, reset here so an aborted attacker is never left slowed. ResetSpeed
		-- no-ops when no slow was stored, so the running-attack case needs no guard.
		if cfg.setSpeed then
			Helper.ResetSpeed(char)
		end
		AnimationHandler.StopAnim(char, "ALL")
		finish()
	end

	StateHandler.SetState(char, "CantAnything", true, windupDelay + 0.05)
	StateHandler.SetState(char, "Windup", true, windupDelay + 0.2)

	setTrail(char, cfg.trailBlade, true)

	-- combo + extra-attack (per call, not shared state)
	--
	-- READ opts.subType, NOT GetAttribute. Running and Sliding are set by LocalScripts
	-- (StarterCharacterScripts.Movement.Running / .Slide) via stateHandler.SetState.
	-- SetState writes a Lua table AND calls char:SetAttribute, but BOTH are client-only
	-- here: the state table is the client VM's, and a client's SetAttribute does not
	-- replicate up to the server (only server->client attribute writes replicate). So
	-- the old GetAttribute("Running") on the server was ALWAYS nil, exactly like the
	-- GetState before it, and the running/slide branches never fired server-side.
	--
	-- The honest channel is the M1 remote: the client, which DOES know its own state,
	-- stamps SubType into the payload and we trust that. Freefall we can still verify
	-- ourselves, because Humanoid states genuinely replicate.
	--
	-- Launched (the uppercut juggle-float) forces a ground combo: a juggled player is
	-- technically in Freefall, but their M1 should read as the normal combo performed
	-- in the air, not the aerial attack. Same gate the client applies.
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

	-- [[ RUNNING ATTACK ]] --
	-- extraAtk 6 is the running attack, and it does NOT take the setSpeed slow.
	--
	-- The slow is the right call for a standing M1: it is the commitment, the tell
	-- the defender reads. On a running attack it was self-defeating. The boost closes
	-- roughly 15 studs (50 * 0.3s), then setSpeed pins the attacker at walkspeed 4
	-- while a sprinting target keeps doing ~28. Over the ~0.6s from boost-end to
	-- hitbox they take back 13-15 studs: every stud the lunge just bought. Net
	-- displacement against a runner was about zero, which is exactly why the running
	-- attack never landed on one, and why a bigger hitbox would not have helped.
	if extraAtk ~= 6 then
		if cfg.setSpeed then
			Helper.SetSpeed(char, cfg.setSpeed[1], cfg.setSpeed[2])
		end
	end

	-- The lunge itself. Server-side now: it used to be a client one-shot BodyVelocity
	-- fired down lookVector at t=0, so it went wherever the target USED to be and
	-- never corrected. It now steers.
	--
	-- The step-in timing is unchanged (burst, then the animation plays, then the
	-- swing). What is new is that with a target acquired it keeps a weaker drive
	-- through the wait, so a sprinter cannot simply out-accelerate the windup. With
	-- NO target it is a plain forward burst and dies at 0.3s, exactly as before.
	--
	-- Beatable by design: steering is rate-limited, so cutting hard across the
	-- attacker's facing breaks the track, and a well-timed dodge or parry wins
	-- outright, because the lunge only closes DISTANCE. The hitbox still has to land.
	-- `token` kills it on a parry or stun rather than dragging the attacker onward.
	if extraAtk == 6 then
		-- Speed comes from DashConfig now, not from WeaponConfig. A nil back means the
		-- lunge dash is switched off for this weapon, so we skip the whole thing.
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

	-- interrupted during windup: no swing VFX, no hitbox
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
	-- The M1 slow is intentionally NOT reset here anymore. It used to lift right after
	-- the swing (before the hitbox even went active), so the commitment vanished the
	-- instant you swung. It now holds through the endlag and is reset in the finish
	-- block below (recovery + 0.2s), with abort() as the interrupt safety net.

	-- interrupted right before the hitbox: abort cleanly
	if token.cancelled then
		abort()
		return
	end

	-- ACTIVE phase: hitbox live; stamp the clash timestamp
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

	-- Is this swing the uppercut (slide + M1)? Decided once, here, from the honest
	-- signal, and captured by the knockback closure so it is fixed for the swing.
	local isUppercut = (extraAtk == 8)

	-- On the uppercut, BOTH the attacker's launch and the Launched flag are now gated on
	-- a confirmed hit. Nothing happens to the attacker here at hitbox-start: if the swing
	-- whiffs, they do not rise and are never flagged Launched. The attacker's rise + flag
	-- are set inside m1Knockback (the on-hit closure), right where the victim is juggled,
	-- so attacker and victim only ever leave the ground together and only on a connect.
	-- (A whiffing uppercut is just a committed swing that missed, punishable like any M1.)

	-- Per-move M1 hitstun, resolved once from the equipped weapon (recovery-scaled
	-- for light/med, flat for greatswords) and captured by the closure below so it
	-- is fixed for this swing. Only the plain-hit branch uses it; uppercut and the
	-- combo-5 finisher keep their own longer launch stuns.
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
			-- Launch the victim to the SAME apex height the attacker rides to (client-side),
			-- placed UC.Offset studs ahead of the attacker so the follow-up M1 string reaches
			-- them. AlignPosition eases them up and holds; the constraint replicates to the
			-- victim's own client and moves them, so no network-ownership juggling. Held in a
			-- hittable stun (NOT ragdolled: a ragdoll flops out of the hitbox).
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

			-- HIT-GATED ATTACKER LAUNCH. We are inside the on-hit closure, so this only
			-- runs when the uppercut actually connected. Flag the attacker Launched (so
			-- their follow-up M1/E/M2 reads as the ground combo in the air) and tell THEIR
			-- client to author the rise (client owns the lift; see _Shared.M1 UppercutRise).
			-- On a whiff, m1Knockback never fires, so the attacker neither rises nor gets
			-- flagged. Attacker and victim leave the ground together and only on a connect.
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
			-- Plain M1: the per-move hitstun that makes M1 strings a parry READ.
			-- m1Hitstun is computed once in RunM1 from the equipped weapon (recovery
			-- + margin, or the flat greatsword value) and captured by this closure.
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
		-- Whiff recovery: a missed M1 (nothing in the hitbox) eats an extra lock so a
		-- fished swing is punishable. A landed M1 skips this entirely, so the combo
		-- string keeps its normal timing. token.didHit is set by resolveHit on connect.
		if not token.didHit then
			StateHandler.SetState(char, "CantAnything", true, M1E_WHIFF_RECOVERY)
		end
		-- Hold the movement slow through the endlag, then lift it 0.2s past the
		-- recovery window (0.25 recovery + 0.2). Running attacks (extraAtk 6) never
		-- took the slow, so they are skipped. abort() covers the interrupted case.
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

	-- [[ COMBO ENDER DECISION ]] --
	-- Read the live M1 combo counter BEFORE the M2 sequence starts. If a combo is open
	-- (>= threshold), this M2 is a finisher and its knockback launches + longer-stuns.
	-- Standalone M2 (no combo, or the window lapsed) uses the plain push. Decided once,
	-- here, so the whole swing commits to one behavior.
	local comboNow = StateHandler.GetState(char, "Combo")
	local isFinisher = (type(comboNow) == "number" and comboNow >= M2_FINISHER_MIN_COMBO)
	local m2Knockback = makeM2Knockback(isFinisher)

	local token = { cancelled = false, hitboxStart = nil, action = "M2" }
	activeAttacks[char] = token
	playerM2Debounces[plr] = true

	-- HYPERARMOR: every M2 is a guardbreak, so every M2 gets armor; cfg.hyperArmor lets
	-- any other move opt in. token.hyperArmored is read by the clash logic in resolveHit
	-- so a clash can't cancel an armored swing either. The HyperArmor attribute makes
	-- SetStun no-op on this character for the window, so an incoming hit deals damage but
	-- does not stop the swing anim or stun us out of it. Cleared in finish().
	local hyperArmored = (cfg.guardbreak or cfg.hyperArmor) and true or false
	token.hyperArmored = hyperArmored
	if hyperArmored then
		char:SetAttribute("HyperArmor", true)
	end

	StateHandler.SetState(char, "CantAnything", true, WINDUP_DELAY + HITBOX_DURATION + 0.5)
	StateHandler.SetState(char, "Windup", true, WINDUP_DELAY + 0.2)

	local stopWatch = StateHandler.WatchInterrupt(char, 3, function()
		-- Armored: absorb the interrupt, keep swinging. Non-armored: cancel as before.
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

	-- Resolve the weapon now, not inside the delay. A swap during those 0.3s would
	-- otherwise read the new weapon's dash for a swing the old weapon started.
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

	-- [[ M2 ENDLAG ]] --
	--
	-- CantAnything was set up front for WINDUP + HITBOX + 0.5, so you were frozen for
	-- half a second after the hitbox closed no matter what happened. That is what made
	-- M2 a dead end: you could not cancel it into anything, so it was a standalone
	-- commit rather than a combo tool.
	--
	-- Now the lock is released as soon as the hitbox resolves, and how fast depends on
	-- whether you connected:
	--
	--   ON HIT  -> M2_ENDLAG_HIT   : short. You earned the cancel. Chain into M1, E,
	--                                a skill, a dash. M2 becomes a combo extender.
	--   ON WHIFF-> M2_ENDLAG_WHIFF : longer. Missing a guardbreak should still cost
	--                                you something, or M2 is a free spam button with
	--                                no read attached.
	--
	-- The M2 COOLDOWN (POST_COOLDOWN, 3-7s) is untouched: you still cannot chain M2
	-- into another M2. Only the endlag moves. That is the point: M2 opens a window,
	-- it does not become the window.
	task.delay(HITBOX_DURATION, function()
		Hitbox:Destroy()
		StateHandler.RemoveStates(char, "Active")

		local endlag = token.didHit and M2_ENDLAG_HIT or M2_ENDLAG_WHIFF

		-- Clear the long lock set at the top and re-apply only the endlag we actually
		-- want. RemoveStates cancels the original timer, so there is no race between
		-- the old CantAnything expiring and this one.
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

	-- HYPERARMOR: honor cfg.hyperArmor / cfg.guardbreak (an E can be flagged guardbreak
	-- in WeaponConfig) and always stamp token.hyperArmored for the clash logic.
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

	-- E is a combo STARTER, so the lock has to expire WITH the swing, not on a flat timer.
	-- This sat at 0.8s regardless of weapon while RunM1 used windupDelay + 0.05. On a fast
	-- E (windup 0.6) that left you locked out long after the hitbox resolved, which is why
	-- a landed E could not chain into anything. Windup-relative now, matching RunM1.
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

	-- Teardown. This was a flat 0.5s against RunM1's 0.1s, and finish() is what releases
	-- activeAttacks[char]. Until it fires, RunM1 hits its busy-check and DECLINES, so the
	-- follow-up M1 was not merely slow, it was being eaten. The lock above and this release
	-- have to land together or you just move the dead input somewhere else.
	--
	-- eRecovery is per-weapon (WeaponConfig server.e) so the heavy classes can keep a real
	-- tail. Default matches RunM1.
	local E_RECOVERY = cfg.eRecovery or 0.1

	task.delay(E_RECOVERY, function()
		Hitbox:Destroy()
		setTrail(char, cfg.trailBlade, false)
		StateHandler.RemoveStates(char, "Active")
		StateHandler.SetState(char, "Recovery", true, 0.25)
		-- Whiff recovery: a missed E eats an extra lock so a fished starter is
		-- punishable. A landed E skips it, so E still flows into the M1 string as a
		-- combo starter. token.didHit is set by resolveHit on connect.
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

-- ── shared attack registry (players + mob AI share this for clash / interrupt) ──
function module.BeginAttack(char)
	local token = { cancelled = false, hitboxStart = nil }
	activeAttacks[char] = token
	return token
end
function module.GetAttack(char)
	return activeAttacks[char]
end
function module.MarkHitbox(token)
	if token then
		token.hitboxStart = os.clock()
	end
end
function module.FinishAttack(char, token)
	if activeAttacks[char] == token then
		activeAttacks[char] = nil
	end
end
-- attackerToken's hitbox hits targetChar. Returns "lose" (attacker beaten, cancel self),
-- "win" + targetToken (attacker wins, cancel target), or nil (target not mid-attack).
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

module.EmitSlash = emitSlash

return module
