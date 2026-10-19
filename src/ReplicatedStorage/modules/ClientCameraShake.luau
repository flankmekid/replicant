-- SPDX-License-Identifier: MIT
--
-- The one CameraShaker on the client. Several systems shake the camera (climbing,
-- parry, damage), and separate shakers would each write camera.CFrame every frame and
-- fight each other, so everyone calls this module. It also handles the CameraShake
-- remote from the server. On the server every function does nothing.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientCameraShake = {}

-- On the server there is no camera to shake.
if not RunService:IsClient() then
	function ClientCameraShake.Bump() end
	function ClientCameraShake.Damage() end
	function ClientCameraShake.ShakeOnce() end
	return ClientCameraShake
end

local CameraShaker = require(ReplicatedStorage:WaitForChild("modules"):WaitForChild("CameraShaker"))

local renderPriority = Enum.RenderPriority.Camera.Value + 1

-- The shake offset applies on top of the current camera CFrame.
local shaker
local function applyShake(shakeCf)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CFrame = cam.CFrame * shakeCf
	end
end

shaker = CameraShaker.new(renderPriority, applyShake)
shaker:Start()

-- ClientCameraShake.Bump() - a quick, snappy shake, used for a landed parry
--
-- Return: nothing.
function ClientCameraShake.Bump()
	shaker:ShakeOnce(4, 10, 0, 0.4)
end

-- ClientCameraShake.Damage() - a damage shake
-- @taken: true when the local player took the hit, which shakes harder
--
-- Return: nothing.
function ClientCameraShake.Damage(taken)
	if taken then
		shaker:ShakeOnce(6, 9, 0, 0.55)
	else
		shaker:ShakeOnce(3.5, 9, 0, 0.4)
	end
end

-- ClientCameraShake.ShakeOnce() - a custom shake, such as the climbing grab
-- @magnitude: the shake strength
-- @roughness: the shake speed
-- @fadeIn: the fade-in time in seconds, 0 by default
-- @fadeOut: the fade-out time in seconds, 0.5 by default
--
-- Return: nothing.
function ClientCameraShake.ShakeOnce(magnitude, roughness, fadeIn, fadeOut)
	shaker:ShakeOnce(magnitude, roughness, fadeIn or 0, fadeOut or 0.5)
end

-- The server sends { kind = "Damage", taken = bool } or { kind = "Bump" }.
local remote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("CameraShake")
remote.OnClientEvent:Connect(function(descriptor)
	if type(descriptor) ~= "table" then
		return
	end
	if descriptor.kind == "Damage" then
		ClientCameraShake.Damage(descriptor.taken == true)
	elseif descriptor.kind == "Bump" then
		ClientCameraShake.Bump()
	end
end)

return ClientCameraShake
