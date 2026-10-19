-- [[ SEER ESP HANDLER ]] --
-- Location: StarterPlayerScripts (LocalScript)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local ESP_COLOR = Color3.fromRGB(121, 11, 255) -- Bright Green
local MAX_DISTANCE = 150 -- Distance in studs
local HIGHLIGHT_NAME = "SeerHighlight"

-- Cache to track active highlights so we don't spam create/destroy
local activeHighlights = {}

-- [[ HELPER FUNCTIONS ]] --

local function AddHighlight(targetChar)
	if targetChar:FindFirstChild(HIGHLIGHT_NAME) then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillColor = ESP_COLOR
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.5 -- Semi-transparent fill
	highlight.OutlineTransparency = 0 -- Solid outline
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- This makes it visible through walls
	highlight.Adornee = targetChar
	highlight.Parent = targetChar

	activeHighlights[targetChar] = highlight
end

local function RemoveHighlight(targetChar)
	local hl = targetChar:FindFirstChild(HIGHLIGHT_NAME)
	if hl then
		hl:Destroy()
	end
	activeHighlights[targetChar] = nil
end

-- [[ MAIN LOOP ]] --

local function UpdateESP()
	local myChar = LocalPlayer.Character

	-- 1. Check if WE are allowed to see (Have the Attribute)
	if not myChar or not myChar:GetAttribute("SeerESP") then
		-- If we aren't a Seer (or dead), clear all existing highlights immediately
		for char, _ in pairs(activeHighlights) do
			RemoveHighlight(char)
		end
		return
	end

	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return
	end

	-- 2. Check every other player
	for _, targetChar in ipairs(workspace.plrManager.alive:GetDescendants()) do
		if
			targetChar:IsA("Model")
			and targetChar:FindFirstChild("Humanoid")
			and targetChar ~= myChar
		then
			local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
			local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

			-- Only highlight alive players
			if targetChar and targetRoot and targetHum and targetHum.Health > 0 then
				local distance = (myRoot.Position - targetRoot.Position).Magnitude

				if distance <= MAX_DISTANCE then
					-- Player is close: Add Highlight if missing
					if not activeHighlights[targetChar] then
						AddHighlight(targetChar)
					end
				else
					-- Player is too far: Remove Highlight if present
					if activeHighlights[targetChar] then
						RemoveHighlight(targetChar)
					end
				end
			else
				-- Player is dead/missing: Clean up
				if targetChar and activeHighlights[targetChar] then
					RemoveHighlight(targetChar)
				end
			end
		end
	end
	--[[
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local targetChar = player.Character
			local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
			local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

			-- Only highlight alive players
			if targetChar and targetRoot and targetHum and targetHum.Health > 0 then
				local distance = (myRoot.Position - targetRoot.Position).Magnitude

				if distance <= MAX_DISTANCE then
					-- Player is close: Add Highlight if missing
					if not activeHighlights[targetChar] then
						AddHighlight(targetChar)
					end
				else
					-- Player is too far: Remove Highlight if present
					if activeHighlights[targetChar] then
						RemoveHighlight(targetChar)
					end
				end
			else
				-- Player is dead/missing: Clean up
				if targetChar and activeHighlights[targetChar] then
					RemoveHighlight(targetChar)
				end
			end
		end
	end
	]]
end

-- Run every frame for smooth updates
RunService.RenderStepped:Connect(UpdateESP)

-- Cleanup when players leave
Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		RemoveHighlight(player.Character)
	end
end)
