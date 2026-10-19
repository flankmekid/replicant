local module = {}

module.Armors = {
	["Rags"] = {
		DisplayName = "Rags",
		ShirtID = "rbxassetid://2366827682",
		PantsID = "rbxassetid://2366829065",
		HPBuff = 1, -- 1.0 = No change
		DefBuff = 1,
		DmgBuff = 1,
		Cost = 0
	},
	
	["Elven"] = {
		DisplayName = "Elven Armor",
		ShirtID = "rbxassetid://135586256426680", -- Placeholder generic RPG shirt
		PantsID = "rbxassetid://82544693774259", 
		HPBuff = 1.1,
		DefBuff = 1.25,
		DmgBuff = 1,
		Cost = 1000
	},
	
	-- KNIGHT
	["Knight Initiate"] = {
		DisplayName = "Knight Initiate",
		ShirtID = "rbxassetid://18858472870",
		PantsID = "rbxassetid://18858478083",
		HPBuff = 1.25,
		DefBuff = 1.05,
		DmgBuff = 1,
		Cost = 1500
	},
	["Elite Knight"] = {
		DisplayName = "Elite Knight",
		ShirtID = "rbxassetid://13223844543",
		PantsID = "rbxassetid://13223845803",
		HPBuff = 1.4,
		DefBuff = 1.1,
		DmgBuff = 1,
		Cost = 2500
	},
	
	-- SAMURAI
	["Ashigaru"] = {
		DisplayName = "Ashigaru Armor",
		ShirtID = "rbxassetid://5268607204",
		PantsID = "rbxassetid://5268608766",
		HPBuff = 1.2,
		DefBuff = 1,
		DmgBuff = 1,
		Cost = 750
	},
	["Samurai Elite"] = {
		DisplayName = "Samurai Elite",
		ShirtID = "rbxassetid://2572644471", 
		PantsID = "rbxassetid://2572645490", 
		HPBuff = 1,
		DefBuff = 0.8,
		DmgBuff = 1.3,
		Cost = 1500
	},
	
	["Tradesman"] = {
		DisplayName = "Tradesman",
		ShirtID = "rbxassetid://104989989851202",
		PantsID = "rbxassetid://139522231418442",
		HPBuff = 1.1,
		DefBuff = 1.1,
		DmgBuff = 1,
		Cost = 400
	},
	
	["Contempt"] = {
		DisplayName = "Contempt",
		ShirtID = "rbxassetid://77566422527202",
		PantsID = "rbxassetid://111001964653567",
		HPBuff = 1.3,
		DefBuff = 1.2,
		DmgBuff = 1.05,
		Cost = 8000
	},
	
	["ZERG"] = {
		DisplayName = "ZERG",
		ShirtID = "rbxassetid://16843509195",
		PantsID = "rbxassetid://16843516621",
		HPBuff = 1.7,
		DefBuff = 1.2,
		DmgBuff = 0.9,
		Cost = 10000
	},
	
	["Hoss"] = {
		DisplayName = "Hoss",
		ShirtID = "rbxassetid://17323702047",
		PantsID = "rbxassetid://17323709487",
		HPBuff = 1.3,
		DefBuff = 1,
		DmgBuff = 1.2,
		Cost = 1000
	},
	
	["Ashen Watcher"] = {
		DisplayName = "Ashen Watcher",
		ShirtID = "rbxassetid://15138979170",
		PantsID = "rbxassetid://14874807332",
		HPBuff = 1.15,
		DefBuff = 0.85,
		DmgBuff = 1.45,
		Cost = 4500
	},
}

return module