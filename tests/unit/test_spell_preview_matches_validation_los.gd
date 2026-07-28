## Regression test for P1-7 (AUDIT_REMEDIATION_PLAN.md). CombatResolver exposes
## two LoS-sensitive queries for the same fact — "can this spell reach this
## tile" — and they must never disagree: canSpellReachPositionFrom() (used by
## the movement/targeting preview) and getSpellTargetsFrom() (used by
## validateCommand()). This checks both a clear line and an intervening-tile
## blocked line.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "canSpellReachPositionFrom() and getSpellTargetsFrom() agree on LoS, clear and blocked"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(5, 1))
	var caster = sim.spawnMonster("Grid Demon", 1, Vector2i(0, 0))
	var target = sim.spawnMonster("Smoke Cloud", 2, Vector2i(3, 0))
	caster.spellSets = [[SpellFactory.createSpell("Dark Bolt")]]

	var clearTargets = sim.combatResolver.getSpellTargetsFrom(caster.uniqueID, 0, 0, caster.position)
	var clearPreview = sim.combatResolver.canSpellReachPositionFrom(
		caster.uniqueID, 0, 0, caster.position, target.position
	)
	assertTrue(clearTargets.has(target.uniqueID), "getSpellTargetsFrom should accept an unobstructed target")
	assertEqual(clearPreview, clearTargets.has(target.uniqueID), "preview must agree with validation on a clear line")

	var blocker = sim.spawnMonster("Megidos", 1, Vector2i(1, 0))
	var blockedTargets = sim.combatResolver.getSpellTargetsFrom(caster.uniqueID, 0, 0, caster.position)
	var blockedPreview = sim.combatResolver.canSpellReachPositionFrom(
		caster.uniqueID, 0, 0, caster.position, target.position
	)
	assertFalse(blockedTargets.has(target.uniqueID), "an intervening monster should block validation's LoS")
	assertEqual(blockedPreview, blockedTargets.has(target.uniqueID), "preview must agree with validation once a bystander blocks LoS")
