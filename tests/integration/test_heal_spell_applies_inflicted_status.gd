## Regression test for P1-2 (AUDIT_REMEDIATION_PLAN.md). Before the fix,
## applySpellEffects() returned early inside the heals branch, so Timeoff's
## heal landed but its speed debuff never applied.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a healing spell still applies its declared status/buff payload"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(4, 4))
	var caster = sim.spawnMonster("Oracle of Ages", 1, Vector2i(1, 1))
	var target = sim.spawnMonster("Oracle of Ages", 1, Vector2i(1, 2))
	target.hitpoints = 1
	caster.spellSets = [[SpellFactory.createSpell("Timeoff")]]

	var result = sim.combatResolver.executeCastSpell(caster.uniqueID, target.uniqueID, 0, 0)

	assertTrue(result.get("success", false), "Timeoff should have cast successfully")
	assertTrue(target.hitpoints > 1, "Timeoff should have healed its target")
	assertTrue(
		sim.state.hasEffect(target.uniqueID, "spd_debuff"),
		"Timeoff should still apply its speed debuff despite healing"
	)
	var appliedBonus := 0
	for effect in sim.state.getActiveEffects(target.uniqueID):
		if effect["name"] == "spd_debuff":
			appliedBonus = int(effect.get("spd_bonus", 0))
	assertEqual(appliedBonus, -2, "Timeoff's speed debuff should reduce SPD by exactly 2")
