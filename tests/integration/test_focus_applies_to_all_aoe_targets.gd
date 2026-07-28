## Regression test for P1-3 (AUDIT_REMEDIATION_PLAN.md). Before the fix,
## "focus" was consumed inside the per-target loop, so only the first affected
## target of an AOE spell received the caster's damage bonus.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "an AOE spell applies the caster's focus bonus to every affected target, not just the first"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(6, 3))
	var caster = sim.spawnMonster("Smoke Cloud", 1, Vector2i(0, 0))
	var enemyA = sim.spawnMonster("Wing of Sanctum", 2, Vector2i(2, 0))
	var enemyB = sim.spawnMonster("Wing of Sanctum", 2, Vector2i(3, 0))
	caster.spellSets = [[SpellFactory.createSpell("Dark Nova")]]
	sim.state.addEffect(caster.uniqueID, "focus", 4, caster.uniqueID, "test", 0, {"damage_multiplier": 1.25})

	var hpABefore = enemyA.hitpoints
	var hpBBefore = enemyB.hitpoints
	var result = sim.combatResolver.executeCastSpell(caster.uniqueID, enemyA.uniqueID, 0, 0)
	assertTrue(result.get("success", false), "Dark Nova should have hit both enemies")

	var damageToA = hpABefore - enemyA.hitpoints
	var damageToB = hpBBefore - enemyB.hitpoints
	assertTrue(damageToA > 0 and damageToB > 0, "both enemies within the AOE radius should take damage")
	assertEqual(damageToA, damageToB, "focus must apply equally to every AOE target, not just the first")
	assertFalse(
		sim.state.hasEffect(caster.uniqueID, "focus"),
		"focus should be consumed exactly once after the cast"
	)
