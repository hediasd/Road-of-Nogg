class_name MonsterReferences

static var list

static func _static_init():
	list = [
		{
			"NAME" = "Defaultgon",
			"HP" =  10, "ATK" = 3, "DEF" = 3, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "MeleeBrain",
			"SPELLS" =
				[[ "Ice Punch" ]]
		},{
			"NAME" = "Mage Dragon",
			"HP" =  50, "ATK" = 4, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["ice"], "RACE" = "none",
			"BRAIN" = "RangedMageBrain",
			"SPELLS" =
				[[ "Think", "Ice Punch", "Ice Plume" ],
				[ "Thought", "Ice Plow", "Ice Flow" ]]
		},{
			# Dark-ranged mage: low physical ATK, hits hard from afar with DARKNESS
			"NAME" = "Magemornus",
			"HP" =  8, "ATK" = 2, "DEF" = 2, "SPD" = 4, "MOVE" = 2,
			"ELEMENTS" = ["darkness"], "RACE" = "none",
			"BRAIN" = "RangedMageBrain",
			"SPELLS" =
				[[ "Dark Bolt", "Dark Nova" ]]
		},{
			# Support healer: low damage, has Mending Light to restore ally HP
			"NAME" = "Healer Mage",
			"HP" =  50, "ATK" = 2, "DEF" = 4, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["light"], "RACE" = "none",
			"BRAIN" = "HealerBrain",
			"SPELLS" =
				[[ "Mending", "Holy Cross" ]]
		},{
			# Fire brawler: medium physical ATK, fire spells inflict BURN
			"NAME" = "Megidos",
			"HP" =  50, "ATK" = 5, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["fire"], "RACE" = "none",
			"BRAIN" = "BrawlerBrain",
			"SPELLS" =
				[[ "Ember Strike", "Pyre Blast" ]]
		},{
			"NAME" = "Mangrovesaurus",
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
			"BRAIN" = "MeleeBrain",
			"SPELLS" = []
		},{
			"NAME" = "Smoke Cloud",
			"HP" = 45, "ATK" = 4, "DEF" = 3, "SPD" = 4, "MOVE" = 3,
			"ELEMENTS" = ["fire", "darkness"], "RACE" = "none",
			"BRAIN" = "RangedMageBrain",
			"SPELLS" = [[ "Smoke Tower" ]]
		},{
			"NAME" = "Oracle of Megnos",
			"HP" = 50, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3,
			"ELEMENTS" = ["fire", "light"], "RACE" = "none",
			"BRAIN" = "SimpleBrain",
			"SPELLS" = [[ "Eschatology" ]]
		},{
			"NAME" = "Wing of Sanctum",
			"HP" = 50, "ATK" = 2, "DEF" = 4, "SPD" = 3, "MOVE" = 2,
			"ELEMENTS" = ["light", "darkness"], "RACE" = "none",
			"BRAIN" = "HealerBrain",
			"SPELLS" = [[ "Closing of the Third Sanctuary", "Opening of the Third Sanctuary" ]]
		},{
			"NAME" = "Oracle of Ages",
			"HP" = 40, "ATK" = 2, "DEF" = 4, "SPD" = 5, "MOVE" = 3,
			"ELEMENTS" = ["wood", "steel"], "RACE" = "Chrononaut",
			"BRAIN" = "HealerBrain",
			"SPELLS" = [[ "Timeoff", "Ages Ago" ]]
		}
	]
pass

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	return list.back()
