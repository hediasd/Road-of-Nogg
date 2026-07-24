class_name MapReferences

static var list: Array[Dictionary]

static func _static_init():
	list = [
		{
			"NAME": "Meadow",
			"SIZE": Vector2i(16, 8),
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
