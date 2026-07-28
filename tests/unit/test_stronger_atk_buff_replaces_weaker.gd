## Regression test for P1-4 (AUDIT_REMEDIATION_PLAN.md). Before the fix,
## _applyAttackBuff() patched atk_bonus only when the existing effect's bonus
## was still 0, so a stronger buff cast over a weaker one was silently ignored.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "re-casting a stronger ATK buff replaces a weaker one, in either cast order"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(4, 4))
	var weakBuff = Spell.new({"NAME": "Weak Buff", "TARGET_TYPE": "self", "BUFFS_ATK": 2, "BUFF_DURATION": 3})
	var strongBuff = Spell.new({"NAME": "Strong Buff", "TARGET_TYPE": "self", "BUFFS_ATK": 5, "BUFF_DURATION": 3})

	var weakThenStrong = sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 1))
	weakThenStrong.spellSets = [[weakBuff, strongBuff]]
	sim.combatResolver.executeCastSpell(weakThenStrong.uniqueID, weakThenStrong.uniqueID, 0, 0)
	sim.combatResolver.executeCastSpell(weakThenStrong.uniqueID, weakThenStrong.uniqueID, 0, 1)
	assertEqual(
		_atkBonus(sim, weakThenStrong.uniqueID), 5,
		"the stronger buff must win when cast after the weaker one"
	)

	var strongThenWeak = sim.spawnMonster("Gigasaurus", 1, Vector2i(2, 1))
	strongThenWeak.spellSets = [[strongBuff, weakBuff]]
	sim.combatResolver.executeCastSpell(strongThenWeak.uniqueID, strongThenWeak.uniqueID, 0, 0)
	sim.combatResolver.executeCastSpell(strongThenWeak.uniqueID, strongThenWeak.uniqueID, 0, 1)
	assertEqual(
		_atkBonus(sim, strongThenWeak.uniqueID), 5,
		"the stronger buff must remain when cast before the weaker one"
	)


func _atkBonus(sim: BattleSimulator, monsterID: int) -> int:
	for effect in sim.state.getActiveEffects(monsterID):
		if effect["name"] == "atk_buff":
			return int(effect.get("atk_bonus", 0))
	return 0
