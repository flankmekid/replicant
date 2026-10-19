-- SPDX-License-Identifier: MIT
--
-- Starts SmartBone, the third-party bone physics library, on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BonePhysics = require(ReplicatedStorage:WaitForChild("modules"):WaitForChild("SmartBone"))

BonePhysics.Start()
