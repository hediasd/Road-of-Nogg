## Ported from the GUT suite tests/test_battle_rules.gd (test_spell_friendly_fire).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "heal spells target allies only and damage spells target enemies only"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var ally = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 1))
	var enemy = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3))

	var healSpell = Spell.new({})
	healSpell.name = "Test Heal"
	healSpell.heals = true
	healSpell.range = 5
	healSpell.targetType = "single"

	var damageSpell = Spell.new({})
	damageSpell.name = "Test Damage"
	damageSpell.heals = false
	damageSpell.range = 5
	damageSpell.targetType = "single"

	m1.spellSets = [[healSpell, damageSpell]]

	var healTargets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	var damageTargets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 1)

	assertHas(healTargets, ally.uniqueID, "Heal spell should target ally")
	assertDoesNotHave(healTargets, enemy.uniqueID, "Heal spell should not target enemy")

	assertHas(damageTargets, enemy.uniqueID, "Damage spell should target enemy")
	assertDoesNotHave(damageTargets, ally.uniqueID, "Damage spell should not target ally")
