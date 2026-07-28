## Ported from the GUT suite tests/test_battle_rules.gd (test_elemental_multipliers).
extends "res://tests/TestCase.gd"

const RaceReferencesScript = preload("res://src/factories/RaceReferences.gd")


func describe() -> String:
	return "an elemental weakness increases spell damage over the same non-elemental hit"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	var attacker = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var target = sim.spawnMonster("Polar Weather Wizard", 2, Vector2i(1, 2))

	# Helvengesk currently provides the focused fire-weakness fixture.
	var fireMultiplier = RaceReferencesScript.getDamageMultiplier(target.race, "fire")

	var baseDamage = 10
	var noElementDamage = sim.combatResolver.calculateSpellDamage(attacker, target, baseDamage, "none")
	var fireElementDamage = sim.combatResolver.calculateSpellDamage(attacker, target, baseDamage, "fire")

	assertTrue(fireMultiplier > 1.0, "Helvengesk should be weak to fire")
	assertTrue(fireElementDamage > noElementDamage, "Fire damage should be higher than non-elemental damage due to weakness")
