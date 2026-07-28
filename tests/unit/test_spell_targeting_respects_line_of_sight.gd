## Ported from the GUT suite tests/test_battle_rules.gd (test_line_of_sight).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a blocked spell cannot reach behind a blocker unless bypass_los is set"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var blocker = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 2))
	var target = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3))

	var spell = Spell.new({})
	spell.name = "LoS Spell"
	spell.range = 5
	spell.bypass_los = false

	m1.spellSets = [[spell]]

	var targets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	assertDoesNotHave(targets, target.uniqueID, "Should not be able to target behind blocker without bypass_los")
	assertHas(targets, blocker.uniqueID, "Should be able to target the blocker")

	spell.bypass_los = true
	var bypassTargets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	assertHas(bypassTargets, target.uniqueID, "Should target behind blocker with bypass_los")
