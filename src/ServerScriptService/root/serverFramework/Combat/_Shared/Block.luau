-- Shared server Block. Identical across every weapon (no per-weapon config), so
-- all weapons route here via the dispatcher fallback. Handles the block/parry state
-- (ParryActive, BlockActive, Deactivated); ParryService is the cooldown authority.
local module = {}

local RP = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local TweenService = game:GetService("TweenService")

local Helper = require(SSS.modules.helperModule)
local SpeedService = require(SSS.modules.SpeedService)
local StateHandler = require(RP.modules.stateHandler)
local ParryService = require(SSS.modules.parryService)
local GuardBarService = require(SSS.modules.GuardBarService)

local parryHighlightTemplate = RP.assets.FX:WaitForChild("parryHighlight")
local blockVFXTemplate = RP.assets.FX:WaitForChild("blockVFXPart"):WaitForChild("blockVFXAttach")

local parryWindow = 0.28 -- widened from 0.2 for a more forgiving parry

module.ParryActive = function(plr)
	local char = plr.Character
	if not char then
		return
	end

	-- Server-authoritative parry cooldown gate.
	if not ParryService.CanParry(plr) then
		return
	end
	ParryService.StartCooldown(plr)

	StateHandler.SetState(char, "Parrying", true, parryWindow)

	local highlight = parryHighlightTemplate:Clone()
	highlight.Parent = char
	highlight.Adornee = char
	highlight.OutlineTransparency = 1

	local tweenIn = TweenService:Create(highlight, TweenInfo.new(0), { OutlineTransparency = 0 })
	tweenIn:Play()

	task.delay(parryWindow, function()
		if highlight and highlight.Parent then
			local tweenOut =
				TweenService:Create(highlight, TweenInfo.new(0.1), { OutlineTransparency = 1 })
			tweenOut:Play()
			game.Debris:AddItem(highlight, 0.1)
		end
	end)
end

module.BlockActive = function(plr)
	local char = plr.Character
	if not char then
		return
	end

	-- Guard-broken players cannot block until the recovery window ends. The client
	-- already gates this (and flashes the bar), but the server is authoritative.
	if GuardBarService.IsGuardBroken(char) then
		return
	end

	StateHandler.SetState(char, "Blocking", true, 99999999)
	-- Block owns its own speed modifier (priority BLOCK). It no longer routes through
	-- Helper.SetSpeed: that pushes a SKILL-priority "HelperSlow" and would collide with
	-- an M1's slow on the same key. A dedicated "Block" source means an M1 thrown while
	-- blocking layers cleanly on top and, when it ends, speed settles back to block.
	SpeedService.Push(char, "Block", 3, SpeedService.Priority.BLOCK)

	-- Block VFX: clone the attachment onto the HRP and keep it enabled for the
	-- duration of the block. Cleaned up in Deactivated (Debris'd so particles fade).
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and not hrp:FindFirstChild("blockVFXAttach") then
		local vfx = blockVFXTemplate:Clone()
		vfx.Name = "blockVFXAttach"
		vfx.Parent = hrp
		for _, emitter in ipairs(vfx:GetChildren()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = true
			end
		end
	end
end

module.Deactivated = function(plr)
	local char = plr.Character
	if not char then
		return
	end

	if StateHandler.GetState(char, "Blocking") then
		StateHandler.RemoveStates(char, "Blocking")
	end

	task.delay(0.2, function()
		StateHandler.RemoveStates(char, "Parrying")
		-- Pop the block speed modifier, but ONLY if the player hasn't started blocking
		-- again in the 0.2s window (a fast release+repress re-pushes Block; this delayed
		-- pop must not yank the speed out from under the new block). SpeedService then
		-- recomputes: a still-live stun/hitstop keeps its pin, otherwise full base speed.
		if not StateHandler.GetState(char, "Blocking") then
			SpeedService.Pop(char, "Block")
		end
	end)

	-- Tear down the block VFX immediately when block is released.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local vfx = hrp and hrp:FindFirstChild("blockVFXAttach")
	if vfx then
		vfx:Destroy()
	end
end

Players.PlayerRemoving:Connect(function(plr) end)

return module
