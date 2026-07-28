## Regression test for a monster with one element being assigned a spell of a
## different element. Uses a synthetic fixture rather than a catalog entry so
## fixing content (e.g. Walker of the Woods, see BACKLOG_CRITICAL.md history)
## does not delete this test.
##
## The third assertion this scenario deserves — a shared catalog validator
## reporting the incompatibility — is deferred until AUDIT_REMEDIATION_PLAN.md
## P2-3 introduces that shared validator; MonsterReferences.validateAll() does
## not check spell/element compatibility today, only
## tests/integration/test_reference_catalog.gd's private logic does.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "can_cast() rejects a foreign-element spell, and targeting agrees"


func run() -> void:
	var caster = makeMonster(["wood"], {}, 900)
	var foreignSpell = Spell.new({"NAME": "Foreign", "ELEMENT": "wind", "RANGE": 5, "TARGET_TYPE": "single"})
	assertFalse(caster.can_cast(foreignSpell), "a wood-only monster must not be able to cast a wind spell")

	var sim = makeSimulator(0, Vector2i(4, 4))
	sim.state.addMonster(caster, Vector2i(1, 1), 1)
	var enemy = makeMonster(["thunder"], {"NAME": "Enemy Fixture"}, 901)
	sim.state.addMonster(enemy, Vector2i(2, 1), 2)
	caster.spellSets = [[foreignSpell]]

	var targets = sim.combatResolver.getSpellTargetsFrom(caster.uniqueID, 0, 0, caster.position)
	assertTrue(targets.is_empty(), "getSpellTargetsFrom must return no targets for a spell the monster cannot cast")
