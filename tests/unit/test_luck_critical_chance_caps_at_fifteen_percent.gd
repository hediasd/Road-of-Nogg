## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "critical chance is capped at 15 percent regardless of Luck"


func run() -> void:
	var monster = makeMonster(["fire"])
	monster.luck = 15
	assertEqual(monster.get_critical_chance(), 0.15, "Luck critical chance is not capped at 15 percent")
	monster.luck = 99
	assertEqual(monster.get_critical_chance(), 0.15, "excess Luck must not exceed the cap")
