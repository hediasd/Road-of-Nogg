class_name MonsterReferences

static var list

static func _static_init():
	list = [
		{
			"NAME" = "Defaultgon",
			"HP" =  10, "ATK" = 3, "DEF" = 3, "SPD" = 2, "MOVE" = 2,
			"BRAIN" = "MeleeBrain",
			"SPELLS" =
				[[ "Ice Punch" ]]
		},{
			"NAME" = "Magedegon",
			"HP" =  50, "ATK" = 4, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"BRAIN" = "RangedMageBrain",
			"SPELLS" =
				[[ "Think", "Ice Punch", "Ice Plume" ],
				[ "Thought", "Ice Plow", "Ice Flow" ]]
		},{
			# Dark-ranged mage: low physical ATK, hits hard from afar with DARKNESS
			"NAME" = "Magemornus",
			"HP" =  8, "ATK" = 2, "DEF" = 2, "SPD" = 4, "MOVE" = 2,
			"BRAIN" = "RangedMageBrain",
			"SPELLS" =
				[[ "Dark Bolt", "Dark Nova" ]]
		},{
			# Support healer: low damage, has Mending Light to restore ally HP
			"NAME" = "Emagnus",
			"HP" =  50, "ATK" = 2, "DEF" = 4, "SPD" = 2, "MOVE" = 2,
			"BRAIN" = "HealerBrain",
			"SPELLS" =
				[[ "Mending" ]]
		},{
			# Fire brawler: medium physical ATK, fire spells inflict BURN
			"NAME" = "Megidos",
			"HP" =  50, "ATK" = 5, "DEF" = 3, "SPD" = 3, "MOVE" = 3,
			"BRAIN" = "BrawlerBrain",
			"SPELLS" =
				[[ "Ember Strike", "Pyre Blast" ]]
		},{
			"NAME" = "Dump",
			"HP" =  1, "ATK" = 1, "DEF" = 1, "SPD" = 1, "MOVE" = 1,
			"BRAIN" = "SimpleBrain",
			"SPELLS" =
				[[ "Ice Punch" ]]
		},{
			"NAME" = "Oracle of Megnos",
			"HP" = 50, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3,
			"BRAIN" = "RangedMageBrain",
			"SPELLS" = [[ "Eschatology" ]]
		},{
			"NAME" = "Wing of Sanctum",
			"HP" = 50, "ATK" = 2, "DEF" = 4, "SPD" = 3, "MOVE" = 2,
			"BRAIN" = "HealerBrain",
			"SPELLS" = [[ "Closing of the Third Sanctuary", "Opening of the Third Sanctuary" ]]
		}
	]
pass

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	return list.back()
