## BattleSimTest — A simple test runner for the battle simulation.
## Attach this to a Node in a test scene and run it.
## It creates a 4v4 battle on an 8x8 board and runs it fully automated.

extends Node

func _ready() -> void:
	print("\n\n")
	print("=== BATTLE SIMULATION TEST ===")
	print("Starting a 4v4 battle on a 16x8 board with obstacles...")
	print("")

	var sim = BattleSimulator.new(Vector2i(16, 8))
	var console = ConsoleVisualAdapter.new(sim.state)
	sim.setVisualAdapter(console)

	# --- Obstacles ---
	sim.state.terrainBoard.set_at(1, Vector2i(1, 1))
	sim.state.terrainBoard.set_at(1, Vector2i(2, 1))
	sim.state.terrainBoard.set_at(1, Vector2i(1, 2))
	sim.state.terrainBoard.set_at(1, Vector2i(14, 6))
	sim.state.terrainBoard.set_at(1, Vector2i(13, 6))
	sim.state.terrainBoard.set_at(1, Vector2i(14, 5))
	sim.state.terrainBoard.set_at(1, Vector2i(8, 3))
	sim.state.terrainBoard.set_at(1, Vector2i(8, 4))
	sim.state.terrainBoard.set_at(1, Vector2i(7, 4))

	# --- Team 1: The Heroes ---
	sim.spawnMonster("Defaultgon", 1, Vector2i(7, 3)) # Frontline
	sim.spawnMonster("Wing of Sanctum", 1, Vector2i(6, 2)) # Petrifier / AOE Healer
	sim.spawnMonster("Emagnus", 1, Vector2i(5, 3)) # Single target Healer (Mending)
	sim.spawnMonster("Magedegon", 1, Vector2i(6, 4)) # Ranged/Ice

	# --- Team 2: The Villains ---
	sim.spawnMonster("Oracle of Megnos", 2, Vector2i(9, 3)) # Ranged/Fire (Eschatology)
	sim.spawnMonster("Megidos", 2, Vector2i(8, 2)) # Frontline / Burn
	sim.spawnMonster("Defaultgon", 2, Vector2i(8, 4)) # Frontline
	sim.spawnMonster("Dump", 2, Vector2i(10, 4)) # Fodder

	# Run the full battle
	var winner = sim.runFullBattle(30)  # Max 30 rounds

	print("\n=== TEST COMPLETE ===")
	print("Winning team: %s" % winner)
	print("")
	get_tree().quit()
