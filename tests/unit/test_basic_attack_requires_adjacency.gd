## Ported from the GUT suite tests/test_battle_rules.gd (test_basic_attack_adjacency).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a basic attack is rejected out of range and succeeds when adjacent"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var m2 = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3))  # Distance 2

	var result = sim.combatResolver.executeBasicAttack(m1.uniqueID, m2.uniqueID)
	assertFalse(result["success"], "Attack should fail if distance is greater than 1")
	assertEqual(result["reason"], "out_of_range", "Failure reason should be out_of_range")

	sim.state.moveMonsterTo(m2.uniqueID, Vector2i(1, 2))
	var resultSuccess = sim.combatResolver.executeBasicAttack(m1.uniqueID, m2.uniqueID)
	assertTrue(resultSuccess["success"], "Attack should succeed when adjacent")
