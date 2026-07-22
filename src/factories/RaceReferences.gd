class_name RaceReferences

static var list = [
	{
		"NAME": "none",
		"RESISTANCES": {}
	},
	{
		"NAME": "Chrononaut",
		"RESISTANCES": {
			"wood": 0.9,
			"steel": 0.9,
			"ice": 1.1 # Taking 10% more damage from ice
		}
	}
]

static func getReference(name: String) -> Dictionary:
	for race in list:
		if race["NAME"] == name:
			return race
	return list[0]

static func getDamageMultiplier(race_name: String, element: String) -> float:
	var race = getReference(race_name)
	if race["RESISTANCES"].has(element):
		return float(race["RESISTANCES"][element])
	return 1.0
