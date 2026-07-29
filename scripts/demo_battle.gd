## demo_battle — Headless console demo of a full seeded battle. Run manually
## via Godot's -s flag; not a test and not part of any check.
extends SceneTree

func _init() -> void:
	print("Starting simulation script...")
	var battleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
	var consoleVisualAdapterScript = preload("res://src/presentation/ConsoleVisualAdapter.gd")
	
	var sim = battleSimulatorScript.new()
	sim.loadMap("Forest")
	
	var console = consoleVisualAdapterScript.new(sim.state)
	sim.setVisualAdapter(console)
	sim.setSeed(42)
	
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6))
	sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 7))
	sim.spawnMonster("Healer Mage", 1, Vector2i(1, 6))
	sim.spawnMonster("Mage Dragon", 1, Vector2i(2, 7))

	sim.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0))
	sim.spawnMonster("Megidos", 2, Vector2i(14, 1))
	sim.spawnMonster("Oracle of Ages", 2, Vector2i(14, 0))
	sim.spawnMonster("Snowzilla", 2, Vector2i(13, 1))
	
	print("Running full battle...")
	sim.runFullBattle(30)
	print("Battle complete! Check docs/battle_log.txt")
	quit()
