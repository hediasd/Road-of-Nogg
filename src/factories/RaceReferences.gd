class_name RaceReferences

static var list = [
	{"NAME": "none", "RESISTANCES": {}},
	{"NAME": "Shadogus", "RESISTANCES": {"darkness": 0.8, "wood": 0.8, "light": 1.2, "wind": 1.2}},
	{"NAME": "Helvengesk", "RESISTANCES": {"ice": 0.8, "wind": 0.8, "fire": 1.2, "thunder": 1.2}},
	{"NAME": "Lizardon", "RESISTANCES": {"fire": 0.8, "earth": 0.8, "water": 1.2, "ice": 1.2}},
	{"NAME": "Nymph", "RESISTANCES": {"wood": 0.8, "water": 0.8, "fire": 1.2, "steel": 1.2}},
	{"NAME": "Wingedos", "RESISTANCES": {"wind": 0.8, "light": 0.8, "earth": 1.2, "thunder": 1.2}},
	{"NAME": "Gel", "RESISTANCES": {"water": 0.8, "darkness": 0.8, "wind": 1.2, "light": 1.2}},
	{"NAME": "Mechans", "RESISTANCES": {"steel": 0.8, "earth": 0.8, "wind": 1.2, "water": 1.2}},
	{"NAME": "Kemetos", "RESISTANCES": {"earth": 0.8, "ice": 0.8, "water": 1.2, "light": 1.2}},
	{"NAME": "Tigerfolk", "RESISTANCES": {"darkness": 0.8, "wind": 0.8, "light": 1.2, "steel": 1.2}},
	{"NAME": "Pondtenders", "RESISTANCES": {"water": 0.8, "wood": 0.8, "darkness": 1.2, "fire": 1.2}},
	{"NAME": "Paperfolk", "RESISTANCES": {"steel": 0.8, "wind": 0.8, "darkness": 1.2, "water": 1.2}},
	{"NAME": "Sephilim", "RESISTANCES": {"light": 0.8, "thunder": 0.8, "darkness": 1.2, "earth": 1.2}},
	{"NAME": "Terrorugon", "RESISTANCES": {"darkness": 0.8, "fire": 0.8, "wood": 1.2, "thunder": 1.2}},
	{"NAME": "Golemfolk", "RESISTANCES": {"earth": 0.8, "steel": 0.8, "water": 1.2, "wood": 1.2}},
	{"NAME": "Frostkin", "RESISTANCES": {"ice": 0.8, "water": 0.8, "fire": 1.2, "wind": 1.2}},
	{"NAME": "Stormborn", "RESISTANCES": {"thunder": 0.8, "wind": 0.8, "earth": 1.2, "steel": 1.2}}
]
static func getReference(name: String) -> Dictionary:
	for race in list:
		if race["NAME"] == name:
			return race
	return list[0]


static func hasReference(name: String) -> bool:
	for race in list:
		if race["NAME"] == name:
			return true
	return false


static func getDamageMultiplier(race_name: String, element: String) -> float:
	var race = getReference(race_name)
	if race["RESISTANCES"].has(element):
		return float(race["RESISTANCES"][element])
	return 1.0
