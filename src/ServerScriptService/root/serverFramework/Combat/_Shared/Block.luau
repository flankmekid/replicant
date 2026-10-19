-- SPDX-License-Identifier: MIT
--
-- Server side of block and parry for every weapon. No weapon has its own block module,
-- so serverFramework always routes here. ParryService owns the parry cooldown.
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

-- Length of the parry window in seconds.
local parryWindow = 0.28

-- Block.ParryActive() - open the parry window for a player
-- @plr: the player who pressed parry
--
-- Return: nothing.
module.ParryActive = function(plr)
	local char = plr.Character
	if not char then
		return
	end

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

-- Block.BlockActive() - start blocking and slow the player
-- @plr: the player who pressed block
--
-- Return: nothing.
module.BlockActive = function(plr)
	local char = plr.Character
	if not char then
		return
	end

	-- A guard-broken player cannot block until recovery ends. The client checks this too,
	-- but the server has the final say.
	if GuardBarService.IsGuardBroken(char) then
		return
	end

	StateHandler.SetState(char, "Blocking", true, 99999999)
	-- Block has its own speed source, so an M1 thrown while blocking stacks on top, and
	-- the speed returns to block speed when the M1 ends.
	SpeedService.Push(char, "Block", 3, SpeedService.Priority.BLOCK)

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

-- Block.Deactivated() - stop blocking and parrying
-- @plr: the player who released block
--
-- Return: nothing.
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
		-- Keep the block speed if the player blocked again during the delay.
		if not StateHandler.GetState(char, "Blocking") then
			SpeedService.Pop(char, "Block")
		end
	end)

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local vfx = hrp and hrp:FindFirstChild("blockVFXAttach")
	if vfx then
		vfx:Destroy()
	end
end

Players.PlayerRemoving:Connect(function(plr) end)

return module
