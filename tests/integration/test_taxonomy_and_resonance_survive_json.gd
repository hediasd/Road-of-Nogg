## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"

const StateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")


func describe() -> String:
	return "family, ascension, and Resonance charge survive a JSON serialize/restore round trip"


func run() -> void:
	var sim = makeSimulator(42, Vector2i(4, 2))
	var samarkand = sim.spawnMonster("Samarkand Stalker", 1, Vector2i(0, 1))
	samarkand.resonance_bars["fire"] = 2
	var serialized = JSON.parse_string(JSON.stringify(sim.state.serialize_state()))
	var restored = StateSerializerScript.deserialize(serialized).getMonster(samarkand.uniqueID)
	assertEqual(restored.family, "Paper Tiger", "family did not survive JSON round trip")
	assertEqual(restored.ascends_from, "Paper Cat", "ascends_from did not survive JSON round trip")
	assertEqual(restored.get_resonance("fire"), 2, "Resonance charge did not survive JSON round trip")
