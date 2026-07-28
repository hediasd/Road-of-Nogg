## Ported from the GUT suite tests/test_resonance.gd
## (test_monster_catalog_is_valid_and_contains_new_entries). Spot-checks
## specific catalog entries in addition to the general schema validation
## already covered by tests/integration/test_reference_catalog.gd.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "the monster catalog validates and contains the expected authored entries"


func run() -> void:
	var validation = MonsterReferences.validateAll()
	assertTrue(validation["success"], str(validation["errors"]))
	assertTrue(MonsterReferences.hasReference("Samarkand Stalker"))
	assertEqual(MonsterReferences.getReference("Samarkand Stalker")["ASCENDS_FROM"], "Paper Cat")
	assertEqual(MonsterReferences.getReference("Blue Crowned Pidgeon")["ELEMENTS"], ["wind"])
