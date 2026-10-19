-- SPDX-License-Identifier: MIT
--
-- Shows the weapon selection hint and then the tutorial end hint when the player
-- touches the tutorial triggers.

local weapon1 = workspace:WaitForChild("triggers"):WaitForChild("weaponSelectionTrigger")
local weapon2 = workspace:WaitForChild("triggers"):WaitForChild("weaponSelectionTrigger2")
local wpntext = workspace:WaitForChild("triggers"):WaitForChild("weaponSelect")
local tutorialtext = workspace:WaitForChild("triggers"):WaitForChild("tutorialFin")

local weapontriggered = false

weapon1.Touched:Connect(function()
	if not weapontriggered then
		weapontriggered = true
		wpntext.BillboardGui.Enabled = true
	end
end)

weapon2.Touched:Connect(function()
	wpntext.BillboardGui.Enabled = false
	tutorialtext.BillboardGui.Enabled = true
end)
