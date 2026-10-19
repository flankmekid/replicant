--[[
	ClientCameraShake
	Single client-side owner of one CameraShaker instance bound to the local camera.

	Why this exists: several systems want to shake the camera (climbing, parry, taking/
	dealing damage). Each newing its own CameraShaker means multiple render-step binds all
	writing camera.CFrame, fighting each other. This module is the one shaker; everyone
	calls into it.

	Client only. Requiring it on the server is a no-op guard (returns the table, methods
	just bail) so shared paths don't error.

	API:
		ClientCameraShake.Bump()                       -- quick snappy hit (parry)
		ClientCameraShake.Damage(taken)                -- damage shake; taken=true is bigger
		ClientCameraShake.ShakeOnce(mag, rough, fIn, fOut)  -- generic passthrough

	The server fires ReplicatedStorage.remotes.CameraShake to a client with a descriptor;
	this module listens for that and routes it, so the damage shake needs no extra receiver.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientCameraShake = {}

-- server guard: never build a shaker off a real camera on the server
if not RunService:IsClient() then
	function ClientCameraShake.Bump() end
	function ClientCameraShake.Damage() end
	function ClientCameraShake.ShakeOnce() end
	return ClientCameraShake
end

local CameraShaker = require(ReplicatedStorage:WaitForChild("modules"):WaitForChild("CameraShaker"))

local renderPriority = Enum.RenderPriority.Camera.Value + 1

-- the shaker applies its offset on top of whatever the camera currently is
local shaker
local function applyShake(shakeCf)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CFrame = cam.CFrame * shakeCf
	end
end

shaker = CameraShaker.new(renderPriority, applyShake)
shaker:Start()

-- ===== public shakes =====

-- quick, snappy single hit. used for a landed parry.
function ClientCameraShake.Bump()
	shaker:ShakeOnce(4, 10, 0, 0.4)
end

-- damage shake. taking a hit rattles harder than landing one.
function ClientCameraShake.Damage(taken)
	if taken then
		shaker:ShakeOnce(6, 9, 0, 0.55) -- bigger when you take it
	else
		shaker:ShakeOnce(3.5, 9, 0, 0.4) -- smaller when you deal it
	end
end

-- generic passthrough for callers that want exact control (e.g. climbing's grab).
function ClientCameraShake.ShakeOnce(magnitude, roughness, fadeIn, fadeOut)
	shaker:ShakeOnce(magnitude, roughness, fadeIn or 0, fadeOut or 0.5)
end

-- ===== server-driven shakes (damage) =====
-- descriptor: { kind = "Damage", taken = bool } or { kind = "Bump" }
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
