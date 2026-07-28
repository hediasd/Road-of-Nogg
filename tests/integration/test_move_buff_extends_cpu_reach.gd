## Regression test for P1-6 (AUDIT_REMEDIATION_PLAN.md). Before the fix,
## BattleCommandEvaluator enumerated destinations using the buffed effective
## move but capped findPath()'s step budget at the unbuffed base MOVE, so a
## move_buff never actually extended the CPU's real pathing reach.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "the CPU command evaluator can path beyond base MOVE when a move buff is active"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(6, 1))
	var actor = sim.spawnMonster("Brickamount", 1, Vector2i(0, 0))  # base MOVE = 1
	sim.spawnMonster("Envoy of Lightning", 2, Vector2i(5, 0))
	sim.state.addEffect(actor.uniqueID, "move_buff", 3, actor.uniqueID, "test", 0, {"move_bonus": 2})

	var evaluator = BattleCommandEvaluator.new(sim.state, sim.movementResolver, sim.combatResolver)
	sim.state.currentMonsterID = actor.uniqueID
	var command: Dictionary = evaluator.chooseCommand(actor.uniqueID, {})

	assertTrue(
		command["move_path"].size() > 1,
		"a monster with base MOVE 1 and +2 move_bonus should be able to path more than one step"
	)
