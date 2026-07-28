## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "a monster with zero Luck has no critical chance"


func run() -> void:
	var monster = makeMonster(["fire"])
	assertEqual(monster.get_critical_chance(), 0.0, "zero-Luck monster has a critical chance")
