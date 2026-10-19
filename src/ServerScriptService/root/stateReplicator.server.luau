local RP = game:GetService("ReplicatedStorage")
local stateRemote = RP.remotes.stateRepl
local stateHandler = require(RP.modules.stateHandler)

stateRemote.OnServerEvent:Connect(function(plr, args)
	if not plr then
		return
	end

	local char = plr.Character or plr.CharacterAdded:Wait()

	local plrStats = plr:FindFirstChild("PlayerStats")
	local dashDuration = plrStats:FindFirstChild("DashDuration")

	if args == "Dodge" then
		stateHandler.SetState(char, "Dodging", true, dashDuration.Value)
		--print("Dodging?: ", stateHandler.GetState(char, "Dodging"))
	elseif args == "SlideOn" then
		stateHandler.SetState(char, "Sliding", true, 99999)
	elseif args == "SlideOff" then
		stateHandler.RemoveStates(char, "Sliding")
	elseif args == "VaultOn" then
		stateHandler.SetState(char, "CantAnything", true, 99999)
	elseif args == "VaultOff" then
		stateHandler.RemoveStates(char, "CantAnything")
	elseif args == "StartWallR" then
		stateHandler.SetState(char, "CantAnything", true, 99999)
	elseif args == "StopWallR" then
		stateHandler.RemoveStates(char, "CantAnything")
	end
end)
