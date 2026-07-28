## Ported from run_determinism_check.gd. Running the same seeded battle twice
## must produce identical outcome, event history, and replay snapshot.
extends "res://tests/TestCase.gd"

var _winner
var _eventCount: int = 0


func describe() -> String:
	return "identical seed produces identical winner/history/snapshot (winner=%s events=%d)" % [_winner, _eventCount]


func run() -> void:
	var first = _runScenario(42)
	var second = _runScenario(42)

	if first["winner"] != second["winner"]:
		fail("winner mismatch")
		return
	if first["history"] != second["history"]:
		fail("event history mismatch")
		return
	if first["snapshot"] != second["snapshot"]:
		fail("serialized replay snapshot mismatch")
		return

	_winner = first["winner"]
	_eventCount = first["history"].size()


func _runScenario(seedValue: int) -> Dictionary:
	var simulator = BattleSimulator.new(seedValue)
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
