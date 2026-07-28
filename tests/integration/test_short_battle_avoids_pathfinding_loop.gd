## Ported from the GUT suite tests/test_battle_rules.gd (test_short_battle_no_loop).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a bounded battle on a tree-obstructed map terminates without pathfinding loops"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	# Use Meadow, which has real trees, to test pathfinding loop avoidance.
	sim.loadMap("Meadow")
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6))
	sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 7))

	sim.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0))
	sim.spawnMonster("Megidos", 2, Vector2i(14, 1))

	sim.setSeed(42)

	sim.runFullBattle(5)  # Run 5 rounds max.

	assertTrue(sim.state.roundCount <= 6, "Battle should not exceed 5 rounds (+1 for final increment)")
	assertTrue(sim.state.turnCount > 0, "At least some turns should have been taken")
