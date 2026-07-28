class_name MonsterReferences

const CatalogValidatorScript = preload("res://src/factories/CatalogValidator.gd")

static var list

static func _static_init():
	list = [
		{
			"NAME" = "Defaultgon",
			"HP" = 30, "ATK" = 4, "DEF" = 4, "SPD" = 3, "MOVE" = 2, "LUCK" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "Frostkin",
			"FAMILY" = "Training Drake",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [["Ice Punch"]]
		},{
			"NAME" = "Mage Dragon",
			"HP" = 50, "ATK" = 4, "DEF" = 3, "SPD" = 3, "MOVE" = 3, "LUCK" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "Helvengesk",
			"FAMILY" = "Frost Wyrm",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Think", "Ice Punch", "Ice Plume"],
				["Thought", "Ice Plow"]]
		},{
			"NAME" = "Magemornus",
			"HP" = 28, "ATK" = 3, "DEF" = 3, "SPD" = 5, "MOVE" = 2, "LUCK" = 5,
			"ELEMENTS" = ["darkness"], "RACE" = "Shadogus",
			"FAMILY" = "Dark Mage",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Dark Bolt", "Dark Nova"]]
		},{
			"NAME" = "Healer Mage",
			"HP" = 50, "ATK" = 2, "DEF" = 4, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["light"], "RACE" = "Sephilim",
			"FAMILY" = "Light Mender",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [["Mending", "Holy Cross"]]
		},{
			"NAME" = "Megidos",
			"HP" = 50, "ATK" = 5, "DEF" = 3, "SPD" = 3, "MOVE" = 3, "LUCK" = 3,
			"ELEMENTS" = ["fire"], "RACE" = "Lizardon",
			"FAMILY" = "Flame Brawler",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [["Ember Strike", "Pyre Blast"]]
		},{
			"NAME" = "Envoy of Lightning",
			"HP" = 40, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3, "LUCK" = 4,
			"ELEMENTS" = ["thunder"], "RACE" = "Stormborn",
			"FAMILY" = "Storm Herald",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Lightningbolt"]],
			"PASSIVES" = ["Storm Surge"]
		},{
			"NAME" = "Gigasaurus",
			"HP" = 50, "ATK" = 6, "DEF" = 5, "SPD" = 2, "MOVE" = 4,
			"ELEMENTS" = ["wood"], "RACE" = "Nymph",
			"FAMILY" = "Elder Treant",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Empower"]],
			"PASSIVES" = ["Tough Skin"]
		},{
			"NAME" = "Snowzilla",
			"HP" = 28, "ATK" = 7, "DEF" = 3, "SPD" = 3, "MOVE" = 3, "LUCK" = 6,
			"ELEMENTS" = ["ice"], "RACE" = "Frostkin",
			"FAMILY" = "Frost Titan",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Ice Punch"]],
			"PASSIVES" = ["Snowfall"]
		},{
			"NAME" = "Dump",
			"HP" = 28, "ATK" = 3, "DEF" = 3, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "Frostkin",
			"FAMILY" = "Frost Runt",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = []
		},{
			"NAME" = "Smoke Cloud",
			"HP" = 45, "ATK" = 4, "DEF" = 3, "SPD" = 4, "MOVE" = 3, "LUCK" = 3,
			"ELEMENTS" = ["fire", "darkness"], "RACE" = "Terrorugon",
			"FAMILY" = "Smoke Fiend",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Smoke Tower"]]
		},{
			"NAME" = "Oracle of Megnos",
			"HP" = 50, "ATK" = 3, "DEF" = 2, "SPD" = 4, "MOVE" = 3, "LUCK" = 2,
			"ELEMENTS" = ["fire", "light"], "RACE" = "Sephilim",
			"FAMILY" = "Flame Oracle",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [["Eschatology"]]
		},{
			"NAME" = "Wing of Sanctum",
			"HP" = 50, "ATK" = 2, "DEF" = 4, "SPD" = 3, "MOVE" = 2,
			"ELEMENTS" = ["light", "darkness"], "RACE" = "Terrorugon",
			"FAMILY" = "Sanctum Wing",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [["Closing of the Third Sanctuary", "Opening of the Third Sanctuary"]]
		},{
			"NAME" = "Oracle of Ages",
			"HP" = 40, "ATK" = 2, "DEF" = 4, "SPD" = 5, "MOVE" = 3,
			"ELEMENTS" = ["wood", "steel"], "RACE" = "Mechans",
			"FAMILY" = "Chrono Sage",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [["Timeoff", "Ages Ago"]]
		},
		{
			"NAME" = "Grid Demon",
			"HP" = 38, "ATK" = 4, "DEF" = 5, "SPD" = 4, "MOVE" = 3, "LUCK" = 3,
			"ELEMENTS" = ["darkness"], "RACE" = "Shadogus",
			"FAMILY" = "Extrafolk",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [["Dark Bolt", "Dark Nova"]],
			"DESCRIPTION" = "Floating shadow entity, evasion tank"
		},
		{
			"NAME" = "Polar Weather Wizard",
			"HP" = 34, "ATK" = 5, "DEF" = 3, "SPD" = 3, "MOVE" = 3, "LUCK" = 2,
			"ELEMENTS" = ["ice"], "RACE" = "Helvengesk",
			"FAMILY" = "Hanansk",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Ice Punch", "Ice Plume", "Ice Plow"]],
			"DESCRIPTION" = "Magical cold-wielder, northern origin"
		},
		{
			"NAME" = "Fireblood Lizard",
			"HP" = 42, "ATK" = 6, "DEF" = 3, "SPD" = 5, "MOVE" = 4, "LUCK" = 6,
			"ELEMENTS" = ["fire", "thunder"], "RACE" = "Lizardon",
			"FAMILY" = "Exogator",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Ember Strike", "Pyre Blast"], ["Lightningbolt"]],
			"DESCRIPTION" = "Hyper-aggressive plasma crocodilian, fast melee striker"
		},
		{
			"NAME" = "Walker of the Woods",
			"HP" = 40, "ATK" = 3, "DEF" = 4, "SPD" = 3, "MOVE" = 3,
			"ELEMENTS" = ["wood", "wind"], "RACE" = "Nymph",
			"FAMILY" = "Woodsland Nymph",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [
				["Stroll", "Flourish", "Insatiable Famine"],
				["Gather", "Thornlash", "Bramble Crown", "Roses at Summers End"]
			],
			"DESCRIPTION" = "Serene nature spirit, dedicated healer, combo-protector"
		},
		{
			"NAME" = "Blue Crowned Pidgeon",
			"HP" = 30, "ATK" = 4, "DEF" = 2, "SPD" = 6, "MOVE" = 5, "LUCK" = 5,
			"ELEMENTS" = ["wind"], "RACE" = "Wingedos",
			"FAMILY" = "Crowned Birdo",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [],
			"DESCRIPTION" = "Agile, crested avian, high-mobility scout"
		},
		{
			"NAME" = "Purple Dungeon Slime",
			"HP" = 46, "ATK" = 3, "DEF" = 4, "SPD" = 2, "MOVE" = 2,
			"ELEMENTS" = ["water", "darkness"], "RACE" = "Gel",
			"FAMILY" = "Blob",
			"BRAIN" = "SupportBrain",
			"SPELLS" = [["Splash", "Ooze Shield", "Corrupting Splatter"]],
			"DESCRIPTION" = "Amorphous gelatinous mass, adaptable utility, immune to physical crits"
		},
		{
			"NAME" = "Kickatoo",
			"HP" = 34, "ATK" = 5, "DEF" = 3, "SPD" = 5, "MOVE" = 8, "LUCK" = 5,
			"ELEMENTS" = ["steel", "wind"], "RACE" = "Mechans",
			"FAMILY" = "Clock-Bird",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Peck", "Feather Time", "Sudden Storm"]],
			"DESCRIPTION" = "Ticking mechanical automaton, precision ranged strikes"
		},
		{
			"NAME" = "Lord of the Mine",
			"HP" = 55, "ATK" = 5, "DEF" = 6, "SPD" = 1, "MOVE" = 2,
			"ELEMENTS" = ["earth"], "RACE" = "Kemetos",
			"FAMILY" = "Mumitomo",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Earth Spike"]],
			"DESCRIPTION" = "Mud-bound desert dweller, heavily armored bruiser"
		},
		{
			"NAME" = "Night Hunter Panther",
			"HP" = 32, "ATK" = 6, "DEF" = 2, "SPD" = 6, "MOVE" = 4, "LUCK" = 9,
			"ELEMENTS" = ["darkness"], "RACE" = "Tigerfolk",
			"FAMILY" = "Night Panther",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Dark Bolt", "Dark Nova"]],
			"DESCRIPTION" = "Lethal feline humanoid, high-speed assassin"
		},
		{
			"NAME" = "Lilypad Tender",
			"HP" = 44, "ATK" = 4, "DEF" = 4, "SPD" = 3, "MOVE" = 3, "LUCK" = 3,
			"ELEMENTS" = ["water", "wood"], "RACE" = "Pondtenders",
			"FAMILY" = "Basic Kappa",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [["Splash"], ["Wood Splinter", "Empower"]],
			"DESCRIPTION" = "Amphibious shell-backed creature, balanced fighter"
		},
		{
			"NAME" = "Paper Cat",
			"HP" = 28, "ATK" = 7, "DEF" = 2, "SPD" = 5, "MOVE" = 4, "LUCK" = 8,
			"ELEMENTS" = ["steel", "fire"], "RACE" = "Paperfolk",
			"FAMILY" = "Paper Tiger",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Steel Blade"], ["Ember Strike", "Pyre Blast"]],
			"DESCRIPTION" = "Sharp origami construct, fragile glass cannon"
		},
		{
			"NAME" = "Samarkand Stalker",
			"HP" = 42, "ATK" = 8, "DEF" = 4, "SPD" = 6, "MOVE" = 5, "LUCK" = 10,
			"ELEMENTS" = ["steel", "fire"], "RACE" = "Paperfolk",
			"FAMILY" = "Paper Tiger",
			"ASCENDS_FROM" = "Paper Cat",
			"BRAIN" = "BerserkBrain",
			"SPELLS" = [["Steel Blade"], ["Ember Strike", "Pyre Blast"]]
		},
		{
			"NAME" = "Warden of the Dunes",
			"HP" = 36, "ATK" = 6, "DEF" = 3, "SPD" = 3, "MOVE" = 3, "LUCK" = 2,
			"ELEMENTS" = ["light"], "RACE" = "Sephilim",
			"FAMILY" = "Wheel Watcher",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Mending", "Holy Cross", "Opening of the Third Sanctuary"]]
		},
		{
			"NAME" = "Six-Winged Terror",
			"HP" = 48, "ATK" = 5, "DEF" = 4, "SPD" = 4, "MOVE" = 4, "LUCK" = 3,
			"ELEMENTS" = ["darkness", "earth"], "RACE" = "Terrorugon",
			"FAMILY" = "Winged Lion",
			"BRAIN" = "MageBrain",
			"SPELLS" = [["Dark Bolt", "Dark Nova", "Closing of the Third Sanctuary"], ["Earth Spike"]]
		},
		{
			"NAME" = "Brickamount",
			"HP" = 60, "ATK" = 4, "DEF" = 8, "SPD" = 1, "MOVE" = 1,
			"ELEMENTS" = ["earth"], "RACE" = "Golemfolk",
			"FAMILY" = "Brickamon",
			"BRAIN" = "TacticalBrain",
			"SPELLS" = [["Earth Spike"]]
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
		reference["FAMILY"] = str(reference.get("FAMILY", "none"))
		reference["ASCENDS_FROM"] = str(reference.get("ASCENDS_FROM", ""))

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	push_error("MonsterReferences: Unknown monster '%s'." % name)
	return {}

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


static func validateAll() -> Dictionary:
	return CatalogValidatorScript.validateMonsters(list)
