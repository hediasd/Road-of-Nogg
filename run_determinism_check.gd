extends SceneTree

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")


func _init() -> void:
	var first = _runScenario(42)
	var second = _runScenario(42)

	if first["winner"] != second["winner"]:
		_fail("winner mismatch")
		return
	if first["history"] != second["history"]:
		_fail("event history mismatch")
		return
	if first["snapshot"] != second["snapshot"]:
		_fail("serialized replay snapshot mismatch")
		return

	print("DETERMINISM_OK seed=42 winner=%s events=%s" % [
		first["winner"],
		first["history"].size()
	])
	quit(0)


func _runScenario(seedValue: int) -> Dictionary:
	var simulator = BattleSimulatorScript.new(seedValue)
	simulator.loadMap("Forest")

	simulator.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6))
	simulator.spawnMonster("Gigasaurus", 1, Vector2i(1, 7))
	simulator.spawnMonster("Healer Mage", 1, Vector2i(1, 6))
	simulator.spawnMonster("Mage Dragon", 1, Vector2i(2, 7))

	simulator.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0))
	simulator.spawnMonster("Megidos", 2, Vector2i(14, 1))
	simulator.spawnMonster("Oracle of Ages", 2, Vector2i(14, 0))
	simulator.spawnMonster("Snowzilla", 2, Vector2i(13, 1))

	var winner = simulator.runFullBattle(30)
	return {
		"winner": winner,
		"history": simulator.state.history.duplicate(true),
		"snapshot": simulator.createReplaySnapshot()
	}


func _fail(reason: String) -> void:
	push_error("DETERMINISM_FAILED: %s" % reason)
	quit(1)
