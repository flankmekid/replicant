-- SPDX-License-Identifier: MIT
--
-- Every world zone that the zone GUI shows. To add a zone, add an entry to zones, keyed
-- by the exact name of its part in workspace.Locations (the raycast matches hit.Name),
-- with a title, a body, and a climate. The climate is a key in climates, which sets the
-- atmosphere and whether snow shows.

local ZoneConfig = {}

ZoneConfig.zones = {
	tutorial = {
		title = "Eclipsaris Isle",
		body = "A long lost sanctuary filled with the hopes and dreams of forgotten people.",
		climate = "desert",
	},
	start = {
		title = "The Proving Grounds",
		body = "A place where disputes were settled, now forgotten to the hands of time.",
		climate = "desert",
	},
	chasm = {
		title = "The Chasm",
		body = "Old trade routes merged together into a treacherous passage above the Abyss.",
		climate = "desert",
	},
	fort = {
		title = "Fort Dusk",
		body = "A training grounds for members of The Order, now populated by the lifeless husks of once proud knights.",
		climate = "desert",
	},
	samuraivillage = {
		title = "Ashenmere",
		body = "A settlement past the Ashen Span, built in the Void's shadow. The red fog that clings to the air has no explanation the locals are willing to give.",
		climate = "desert",
	},
	forest = {
		title = "The Verdant Wound",
		body = "An unshakeable feeling of loneliness overwhelms you as trees line the scenery.",
		climate = "forest",
	},
	temple = {
		title = "Zhendao Temple",
		body = "A place of worship for the monks amongst the ranks of the Kensei, before the Imperial Ruler exiled them for 'treason', forcing the monks to retreat amongst the mountaintops.",
		climate = "desert",
	},
	littlevillage = {
		title = "Vaels' Rest",
		body = "What remains of a refuge that outlasted the war that created it. The people here are still waiting for something, though most have forgotten what.",
		climate = "desert",
	},
	bridge1 = {
		title = "The Ashen Span",
		body = "A bridge of silverstone spanning the Chasm, connecting the Proving Grounds to Ashenmere. One of two crossings that still stand.",
		climate = "desert",
	},
	void1 = {
		title = "The Void",
		body = "The most destructive force in the world, slowly waiting, biding its time.",
		climate = "desert",
	},
	redmore = {
		title = "Redmore",
		body = "One of the last 'safe' places left, the dangers that lurk outside aren't to be underestimated.",
		climate = "forest",
	},
}

-- Atmosphere presets. default applies outside every zone.
ZoneConfig.climates = {
	desert = { Density = 0.34, Offset = 0.375, Color = Color3.fromRGB(72, 71, 63), snow = false },
	forest = { Density = 0.3, Offset = 0.3, Color = Color3.fromRGB(70, 72, 62), snow = false },
	snowy = { Density = 0.5, Offset = 0.286, Color = Color3.fromRGB(218, 201, 201), snow = true },
	caves = { Density = 0.68, Offset = 0.47, Color = Color3.fromRGB(106, 106, 106), snow = false },

	default = { Density = 0.34, Offset = 0.375, Color = Color3.fromRGB(72, 71, 63), snow = false },
}

return ZoneConfig
