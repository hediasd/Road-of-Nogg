## Regression test for P1-1 (AUDIT_REMEDIATION_PLAN.md). Before the fix, only
## CombatResolver's own kill paths fired ON_DEATH passives; a status-tick death
## routed through PassiveSkillResolver's separate _handleDefeat() and skipped
## it entirely.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a monster killed by a status-effect tick still fires its own ON_DEATH passive"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(5, 5))
	var dying = sim.spawnMonster("Snowzilla", 1, Vector2i(2, 2))
	var neighbor = sim.spawnMonster("Brickamount", 1, Vector2i(2, 3))
	dying.hitpoints = 1
	sim.state.addEffect(dying.uniqueID, "burn", 3, neighbor.uniqueID, "test", 5)

	var neighborHPBefore = neighbor.hitpoints
	sim.passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, dying.uniqueID)

	assertFalse(dying.is_alive(), "the burn tick should have killed the low-HP monster")
	assertTrue(
		neighbor.hitpoints < neighborHPBefore,
		"Snowfall's ON_DEATH AOE damage did not fire for a status-tick death"
	)
