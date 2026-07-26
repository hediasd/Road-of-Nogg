class_name MonsterReferences

static var list

static func _static_init():
	list = [
		{
			"NAME" = "Defaultgon",
			"HP" =  10, "ATK" = 3, "DEF" = 3, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "TacticalBrain",
			"SPELLS" =
				[[ "Ice Punch" ]]
		},{
			"NAME" = "Mage Dragon",
			"HP" =  50, "ATK" = 4, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "MageBrain",
			"SPELLS" =
				[[ "Think", "Ice Punch", "Ice Plume" ],
				[ "Thought", "Ice Plow", "Ice Flow" ]]
		},{
			# Dark-ranged mage: low physical ATK, hits hard from afar with DARKNESS
			"NAME" = "Magemornus",
			"HP" =  8, "ATK" = 2, "DEF" = 2, "SPD" = 4, "MOVE" = 2,
			"ELEMENTS" = ["darkness"], "RACE" = "none",
			"BRAIN" = "MageBrain",
			"SPELLS" =
				[[ "Dark Bolt", "Dark Nova" ]]
		},{
			# Support healer: low damage, has Mending Light to restore ally HP
			"NAME" = "Healer Mage",
			"HP" =  50, "ATK" = 2, "DEF" = 4, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["light"], "RACE" = "none",
			"BRAIN" = "SupportBrain",
			"SPELLS" =
				[[ "Mending", "Holy Cross" ]]
		},{
			# Fire brawler: medium physical ATK, fire spells inflict BURN
			"NAME" = "Megidos",
			"HP" =  50, "ATK" = 5, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["fire"], "RACE" = "none",
			"BRAIN" = "TacticalBrain",
			"SPELLS" =
				[[ "Ember Strike", "Pyre Blast" ]]
		},{
			# Lightning envoy: prefers close combat (BerserkBrain), but has long-range spell and retaliates when targeted
			"NAME" = "Envoy of Lightning",
			"HP" =  40, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3,
			"ELEMENTS" = ["thunder"], "RACE" = "none",
			"BRAIN" = "BerserkBrain",
			"SPELLS" =
				[[ "Lightningbolt" ]],
			"PASSIVES" = [ "Storm Surge" ]
		},{
			"NAME" = "Gigasaurus",
			"HP" = 50, "ATK" = 6, "DEF" = 5, "SPD" = 2, "MOVE" = 4,
			"ELEMENTS" = ["wood"], "RACE" = "none",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [[ "Empower" ]],
			"PASSIVES" = ["Tough Skin"]
		},{
			"NAME" = "Snowzilla",
			"HP" = 28, "ATK" = 7, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [[ "Ice Punch" ]],
			"PASSIVES" = ["Snowfall"]
		},{
			"NAME" = "Dump",
			"HP" =  1, "ATK" = 1, "DEF" = 1, "SPD" = 1, "MOVE" = 1,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = []
		},{
			"NAME" = "Smoke Cloud",
			"HP" = 45, "ATK" = 4, "DEF" = 3, "SPD" = 4, "MOVE" = 3,
			"ELEMENTS" = ["fire", "darkness"], "RACE" = "none",
			"BRAIN" = "MageBrain",
			"SPELLS" = [[ "Smoke Tower" ]]
		},{
			"NAME" = "Oracle of Megnos",
			"HP" = 50, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3,
			"ELEMENTS" = ["fire", "light"], "RACE" = "none",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [[ "Eschatology" ]]
		},{
			"NAME" = "Wing of Sanctum",
			"HP" = 50, "ATK" = 2, "DEF" = 4, "SPD" = 3, "MOVE" = 2,
			"ELEMENTS" = ["light", "darkness"], "RACE" = "none",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [[ "Closing of the Third Sanctuary", "Opening of the Third Sanctuary" ]]
		},{
			"NAME" = "Oracle of Ages",
			"HP" = 40, "ATK" = 2, "DEF" = 4, "SPD" = 5, "MOVE" = 3,
			"ELEMENTS" = ["wood", "steel"], "RACE" = "Chrononaut",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [[ "Timeoff", "Ages Ago" ]]
		}
	]
	for reference in list:
		reference["BASE_HP"] = int(reference.get("BASE_HP", reference.get("HP", 1)))
		reference["BASE_ATK"] = int(reference.get("BASE_ATK", reference.get("ATK", 1)))
		reference["BASE_DEF"] = int(reference.get("BASE_DEF", reference.get("DEF", 1)))
		reference["HP_GROWTH"] = int(reference.get("HP_GROWTH", 0))
		reference["ATK_GROWTH"] = int(reference.get("ATK_GROWTH", 0))
		reference["DEF_GROWTH"] = int(reference.get("DEF_GROWTH", 0))
		reference["JUMP"] = int(reference.get("JUMP", 1))

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	return list.back()

static func hasReference(name: String) -> bool:
	for reference in list:
		if reference["NAME"] == name:
			return true
	return false


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for reference in list:
		names.append(reference["NAME"])
	return names
