extends SceneTree

func _init() -> void:
	print("Starting simulation script...")
	var BattleSimulator = preload("res://src/battle_sim/BattleSimulator.gd")
	var ConsoleVisualAdapter = preload("res://src/battle_sim/ConsoleVisualAdapter.gd")
	
	var sim = BattleSimulator.new()
	sim.loadMap("Forest")
	
	var console = ConsoleVisualAdapter.new(sim.state)
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
