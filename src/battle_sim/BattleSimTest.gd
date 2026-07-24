## BattleSimTest — A simple test runner for the battle simulation.
## Attach this to a Node in a test scene and run it.
## It creates a 4v4 battle on an 8x8 board and runs it fully automated.

extends Node

func _ready() -> void:
	print("\n\n")
	print("=== BATTLE SIMULATION TEST ===")
	print("Starting a 4v4 battle on a 16x8 board with obstacles...")
	print("")

	var sim = BattleSimulator.new()
	sim.loadMap("Forest")
	var console = ConsoleVisualAdapter.new(sim.state)
	sim.setVisualAdapter(console)
	
	# Set deterministic seed for test consistency
	sim.setSeed(42)

	# --- Team 1: The Heroes (Lower Left) ---
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6)) # Frontline, retaliates
	sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 7)) # Tank
	sim.spawnMonster("Healer Mage", 1, Vector2i(1, 6)) # Single target Healer (Mending)
	sim.spawnMonster("Mage Dragon", 1, Vector2i(2, 7)) # Ranged/Ice

	# --- Team 2: The Villains (Top Right) ---
	sim.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0)) # Ranged/Fire AOE
	sim.spawnMonster("Megidos", 2, Vector2i(14, 1)) # Frontline / Burn
	sim.spawnMonster("Oracle of Ages", 2, Vector2i(14, 0)) # Support/Healer
	sim.spawnMonster("Snowzilla", 2, Vector2i(13, 1)) # Snowfall ON_DEATH AOE passive

	# Run the full battle
	var winner = sim.runFullBattle(30)  # Max 30 rounds

	print("\n=== TEST COMPLETE ===")
	print("Winning team: %s" % winner)
	print("")
	get_tree().quit()
