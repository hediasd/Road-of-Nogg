## Verify that JSON.parse_string returns floats, but MonsterReferences int-coerces
## stats back to integers before exposing them. This gate ensures the hidden
## type mismatch never leaks into downstream code.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "monster stats loaded from JSON are integers, not floats"


func run() -> void:
	## Get a reference after reload (which happens at static init)
	var reference = MonsterReferences.getReference("Defaultgon")
	assertTrue(not reference.is_empty(), "Could not load Defaultgon")

	## Check every numeric stat field
	for key in ["HP", "ATK", "DEF", "SPD", "MOVE", "LUCK"]:
		if reference.has(key):
			var value = reference[key]
			var type_name = type_string(typeof(value))
			assertTrue(
				typeof(value) == TYPE_INT,
				"%s.%s is %s, expected int" % [reference["NAME"], key, type_name]
			)

	## Also check normalized fields
	assertTrue(typeof(reference["BASE_HP"]) == TYPE_INT, "BASE_HP is not int")
	assertTrue(typeof(reference["BASE_ATK"]) == TYPE_INT, "BASE_ATK is not int")
	assertTrue(typeof(reference["BASE_DEF"]) == TYPE_INT, "BASE_DEF is not int")
