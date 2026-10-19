-- SPDX-License-Identifier: MIT
--
-- The developer accounts, by Roblox UserId, in one place. Only server code reads them:
-- the developer titles in TitleManager, the Identity overhead title, and the Maw colors
-- in RaceHandler. A fork replaces these with its own accounts.

local DevConfig = {}

DevConfig.UserIds = {
	-- Angel's Thanatos.
	thanatos = 107650965,
	-- The Primal Maw, and the red Maw skin.
	primalMaw = 1526974131,
	-- The Unforgiven and the Dragon Knight.
	unforgiven = 1718017878,
}

return DevConfig
