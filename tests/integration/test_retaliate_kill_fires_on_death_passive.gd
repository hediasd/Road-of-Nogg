## Regression test for P1-1 (AUDIT_REMEDIATION_PLAN.md). Before the fix, a
## retaliate-passive kill routed through PassiveSkillResolver.fireOnTargeted()'s
## own _handleDefeat() call and skipped the dying attacker's own ON_DEATH
## passive.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a monster killed by a retaliate passive still fires its own ON_DEATH passive"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(5, 5))
	var attacker = sim.spawnMonster("Snowzilla", 1, Vector2i(1, 1))
	var defender = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 2))
	var neighbor = sim.spawnMonster("Brickamount", 1, Vector2i(1, 0))
	attacker.hitpoints = 1

	var neighborHPBefore = neighbor.hitpoints
	var result = sim.combatResolver.executeBasicAttack(attacker.uniqueID, defender.uniqueID)

	assertEqual(
		result.get("reason", ""), "attacker_died_to_passive",
		"the attack should fizzle because Storm Surge killed the attacker first"
	)
	assertFalse(attacker.is_alive(), "the retaliation should have killed the low-HP attacker")
	assertTrue(
		neighbor.hitpoints < neighborHPBefore,
		"Snowfall's ON_DEATH AOE damage did not fire for a retaliation death"
	)
