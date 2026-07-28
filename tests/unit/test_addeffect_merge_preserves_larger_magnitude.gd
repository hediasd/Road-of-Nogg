## Direct unit test for BattleState.addEffect()'s refresh-merge rule
## (_mergedEffectValue), introduced by P1-4 (AUDIT_REMEDIATION_PLAN.md).
## test_stronger_atk_buff_replaces_weaker.gd already covers positive bonuses
## through the atk_buff spell path; this exercises the merge function directly
## and specifically covers negative values (e.g. spd_bonus), whose
## sign-preserving branch a naive plain-max() merge would get wrong.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "addEffect()'s refresh merge keeps the larger-magnitude value and preserves its sign"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(3, 3))
	var monster = sim.spawnMonster("Defaultgon", 1, Vector2i(1, 1))

	# Positive bonuses: the stronger value must win regardless of order.
	sim.state.addEffect(monster.uniqueID, "atk_buff", 3, monster.uniqueID, "a", 0, {"atk_bonus": 2})
	sim.state.addEffect(monster.uniqueID, "atk_buff", 3, monster.uniqueID, "b", 0, {"atk_bonus": 5})
	assertEqual(_bonus(sim, monster.uniqueID, "atk_buff", "atk_bonus"), 5, "a stronger positive bonus must win")
	sim.state.addEffect(monster.uniqueID, "atk_buff", 3, monster.uniqueID, "c", 0, {"atk_bonus": 1})
	assertEqual(_bonus(sim, monster.uniqueID, "atk_buff", "atk_bonus"), 5, "a weaker positive bonus must not downgrade an existing stronger one")

	# Negative bonuses (e.g. spd_bonus): the larger magnitude must win, sign preserved.
	sim.state.addEffect(monster.uniqueID, "spd_debuff", 3, monster.uniqueID, "a", 0, {"spd_bonus": -1})
	sim.state.addEffect(monster.uniqueID, "spd_debuff", 3, monster.uniqueID, "b", 0, {"spd_bonus": -3})
	assertEqual(_bonus(sim, monster.uniqueID, "spd_debuff", "spd_bonus"), -3, "a stronger (more negative) debuff must win")
	sim.state.addEffect(monster.uniqueID, "spd_debuff", 3, monster.uniqueID, "c", 0, {"spd_bonus": -1})
	assertEqual(_bonus(sim, monster.uniqueID, "spd_debuff", "spd_bonus"), -3, "a weaker debuff must not overwrite a stronger existing one")


func _bonus(sim: BattleSimulator, monsterID: int, effectName: String, key: String) -> int:
	for effect in sim.state.getActiveEffects(monsterID):
		if effect["name"] == effectName:
			return int(effect.get(key, 0))
	return 0
