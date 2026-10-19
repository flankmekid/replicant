-- SPDX-License-Identifier: MIT
--
-- The spires and the teleport cost between them.

local SpireConfig = {}

-- Each spire has an Id (the key saved for attunement), a Name (shown on the world
-- map), a Zone (shown under the name), and a PartName (the Workspace part that holds
-- the ProximityPrompt).

SpireConfig.Spires = {
	{
		Id = "Spire_VaelsRest",
		Name = "Spire of Vael's Rest",
		Zone = "Vael's Rest",
		PartName = "Spire_VaelsRest",
	},
	{
		Id = "Spire_Ashenmere",
		Name = "Spire of Ashenmere",
		Zone = "Ashenmere",
		PartName = "Spire_Ashenmere",
	},
	{
		Id = "Spire_FortDusk",
		Name = "Spire of Fort Dusk",
		Zone = "Fort Dusk",
		PartName = "Spire_FortDusk",
	},
	{
		Id = "Spire_Redmore",
		Name = "Spire of Redmore",
		Zone = "The Verdant Wound",
		PartName = "Spire_Redmore",
	},
	{
		Id = "Spire_Azim",
		Name = "Spire of the Azim",
		Zone = "The Verdant Wound",
		PartName = "Spire_Azim",
	},
}

SpireConfig.TeleportCost = 250

return SpireConfig
