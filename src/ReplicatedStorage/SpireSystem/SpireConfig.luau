local SpireConfig = {}

-- Each Spire entry:
-- Id          : unique string key, used for saving attunement
-- Name        : display name shown on the world map
-- Zone        : zone label shown beneath the name
-- PartName    : name of the Part in Workspace the ProximityPrompt is attached to

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
