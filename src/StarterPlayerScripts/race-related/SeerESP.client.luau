-- SPDX-License-Identifier: MIT
--
-- The Seer racial passive: highlights every living character within MAX_DISTANCE
-- through walls while the local character has the SeerESP attribute.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local ESP_COLOR = Color3.fromRGB(121, 11, 255)
-- In studs.
local MAX_DISTANCE = 150
local HIGHLIGHT_NAME = "SeerHighlight"

-- The active highlights, so they are not created and destroyed every frame.
local activeHighlights = {}

local function AddHighlight(targetChar)
	if targetChar:FindFirstChild(HIGHLIGHT_NAME) then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillColor = ESP_COLOR
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
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

local function UpdateESP()
	local myChar = LocalPlayer.Character

	if not myChar or not myChar:GetAttribute("SeerESP") then
		-- Not a Seer, or dead: clear every highlight.
		for char, _ in pairs(activeHighlights) do
			RemoveHighlight(char)
		end
		return
	end

	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return
	end

	for _, targetChar in ipairs(workspace.plrManager.alive:GetDescendants()) do
		if
			targetChar:IsA("Model")
			and targetChar:FindFirstChild("Humanoid")
			and targetChar ~= myChar
		then
			local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
			local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

			if targetChar and targetRoot and targetHum and targetHum.Health > 0 then
				local distance = (myRoot.Position - targetRoot.Position).Magnitude

				if distance <= MAX_DISTANCE then
					if not activeHighlights[targetChar] then
						AddHighlight(targetChar)
					end
				else
					if activeHighlights[targetChar] then
						RemoveHighlight(targetChar)
					end
				end
			else
				if targetChar and activeHighlights[targetChar] then
					RemoveHighlight(targetChar)
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(UpdateESP)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		RemoveHighlight(player.Character)
	end
end)
