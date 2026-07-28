## Regression test for P1-5 (AUDIT_REMEDIATION_PLAN.md). spd_debuff used to be
## applied through two separate code paths: _applyStatus() via
## INFLICTS_STATUS (duration 2), then _applySpeedDebuff() unconditionally
## overwriting it to a hardcoded 99-turn duration. Timeoff now declares it
## once through EFFECTS, and _applySpeedDebuff() no longer exists.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "Timeoff's speed debuff applies exactly once, at -2 SPD, survives a re-cast, and changes turn order"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(4, 4))
	var caster = sim.spawnMonster("Oracle of Ages", 1, Vector2i(1, 1))
	var target = sim.spawnMonster("Oracle of Ages", 1, Vector2i(1, 2))
	caster.spellSets = [[SpellFactory.createSpell("Timeoff")]]

	sim.combatResolver.executeCastSpell(caster.uniqueID, target.uniqueID, 0, 0)
	assertEqual(_countSpdDebuffs(sim, target.uniqueID), 1, "spd_debuff must be applied exactly once")
	assertEqual(_spdBonus(sim, target.uniqueID), -2, "spd_debuff must reduce speed by exactly 2")

	# Re-casting (e.g. to top up the heal) must not duplicate or weaken it.
	target.hitpoints = 1
	sim.combatResolver.executeCastSpell(caster.uniqueID, target.uniqueID, 0, 0)
	assertEqual(_countSpdDebuffs(sim, target.uniqueID), 1, "re-casting must not duplicate the debuff")
	assertEqual(_spdBonus(sim, target.uniqueID), -2, "re-casting must not weaken the existing debuff")

	# The debuff must have a real effect on turn order, not just sit inertly in state.
	var turnManager := TurnManager.new(sim.state, sim.events)
	turnManager.startNewRound()
	assertTrue(
		turnManager.turnOrder.find(caster.uniqueID) < turnManager.turnOrder.find(target.uniqueID),
		"the slowed target should act after the equal-base-speed caster once debuffed"
	)


func _countSpdDebuffs(sim: BattleSimulator, monsterID: int) -> int:
	var count := 0
	for effect in sim.state.getActiveEffects(monsterID):
		if effect["name"] == "spd_debuff":
			count += 1
	return count


func _spdBonus(sim: BattleSimulator, monsterID: int) -> int:
	for effect in sim.state.getActiveEffects(monsterID):
		if effect["name"] == "spd_debuff":
			return int(effect.get("spd_bonus", 0))
	return 0
