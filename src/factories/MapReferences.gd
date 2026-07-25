class_name MapReferences

static var list: Array[Dictionary]

static func _static_init():
	list = [
		{
			"NAME": "Meadow",
			"SIZE": Vector2i(16, 8),
			"TEAM_1_SLOTS": [
				Vector2i(2, 6), Vector2i(1, 7),
				Vector2i(1, 6), Vector2i(2, 7)
			],
			"TEAM_2_SLOTS": [
				Vector2i(13, 0), Vector2i(14, 1),
				Vector2i(14, 0), Vector2i(13, 1)
			],
			"LAYOUT": [
				"................",
				".TT.............",
				".T..............",
				".......WW.......",
				".......WW.......",
				"..............T.",
				".............TT.",
				"................"
			]
		},
		{
			"NAME": "Crossroads",
			"SIZE": Vector2i(8, 8),
			"TEAM_1_SLOTS": [
				Vector2i(0, 5), Vector2i(0, 6),
				Vector2i(1, 5), Vector2i(1, 6)
			],
			"TEAM_2_SLOTS": [
				Vector2i(7, 1), Vector2i(7, 2),
				Vector2i(6, 1), Vector2i(6, 2)
			],
			"LAYOUT": [
				"........",
				"..W..W..",
				"..W..W..",
				"........",
				"........",
				"..W..W..",
				"..W..W..",
				"........"
			]
		},
		{
			"NAME": "Forest",
			"SIZE": Vector2i(16, 16),
			"TEAM_1_SLOTS": [
				Vector2i(1, 13), Vector2i(1, 14),
				Vector2i(2, 13), Vector2i(2, 14)
			],
			"TEAM_2_SLOTS": [
				Vector2i(14, 1), Vector2i(14, 2),
				Vector2i(13, 1), Vector2i(13, 2)
			],
			"LAYOUT": [
				"...............T",
				"T..............T",
				"T..TT......TT..T",
				"T..TT......TT..T",
				"T..............T",
				"T....TT..TT....T",
				"T....T....T....T",
				"T..............T",
				"T..............T",
				"T....T....T....T",
				"T....TT..TT....T",
				"T..............T",
				"T..TT......TT..T",
				"T..TT......TT..T",
				"T..............T",
				"T..............."
			]
		}
	]
	pass

static func getReference(name: String) -> Dictionary:
	for reference in list:
		if reference["NAME"] == name:
			return reference
	# Fallback to the first map if not found
	return list[0]

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


static func getDeploymentSlots(name: String, team: int) -> Array:
	var reference = getReference(name)
	var key = "TEAM_1_SLOTS" if team == 1 else "TEAM_2_SLOTS"
	return reference.get(key, []).duplicate()
