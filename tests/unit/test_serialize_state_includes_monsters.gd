## Ported from the GUT suite tests/test_battle_state.gd (test_serialization).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "serialize_state() includes exactly the monsters currently on the board"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(4, 4))
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))

	var stateDict = sim.state.serialize_state()

	assertTrue(stateDict.has("monsters"), "State should contain 'monsters' key")
	assertEqual(stateDict["monsters"].size(), 1, "There should be exactly 1 monster serialized")
