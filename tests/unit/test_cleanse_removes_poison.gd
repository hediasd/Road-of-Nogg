## Regression test for P2-2 (AUDIT_REMEDIATION_PLAN.md), applied minimally:
## _cleanseNegativeEffects()'s hardcoded status list omitted "poison". The full
## P2-2 item (a data-driven StatusEffectReferences catalog replacing every
## hardcoded status list/match statement) remains open; this only covers the
## specific bug this test targets.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "casting a cleanse effect removes poison"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(3, 3))
	var caster = sim.spawnMonster("Warden of the Dunes", 1, Vector2i(1, 1))
	caster.spellSets = [[SpellFactory.createSpell("Elucidate")]]
	sim.state.addEffect(caster.uniqueID, "poison", 3, caster.uniqueID, "test", 1)

	assertTrue(sim.state.hasEffect(caster.uniqueID, "poison"), "fixture setup should have applied poison")
	var result = sim.combatResolver.executeCastSpell(caster.uniqueID, caster.uniqueID, 0, 0)
	assertTrue(result.get("success", false), "Elucidate should self-cast successfully")
	assertFalse(sim.state.hasEffect(caster.uniqueID, "poison"), "cleanse must remove poison")
