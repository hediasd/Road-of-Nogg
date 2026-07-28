## Ported from the GUT suite tests/test_resonance.gd
## (test_resonance_buffs_atk_and_def_from_highest_element_bar).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "the highest charged Resonance bar grants a non-stacking ATK/DEF bonus"


func run() -> void:
	var sim = makeSimulator(41, Vector2i(8, 4))
	var monster = sim.spawnMonster("Paper Cat", 1, Vector2i(1, 1))
	monster.resonance_bars["steel"] = 3
	monster.resonance_bars["fire"] = 2
	assertEqual(monster.get_resonance_bonus_percent(), 30)
	assertEqual(monster.get_effective_atk(), 9)
	assertEqual(monster.get_effective_def(), 3)
