## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "an elemental weakness hit decays exactly one Resonance charge"


func run() -> void:
	var sim = makeSimulator(42, Vector2i(4, 2))
	var caster = sim.spawnMonster("Fireblood Lizard", 1, Vector2i(0, 0))
	var target = sim.spawnMonster("Polar Weather Wizard", 2, Vector2i(1, 0))
	target.resonance_bars["ice"] = 3
	if not sim.combatResolver.executeCastSpell(caster.uniqueID, target.uniqueID, 0, 0)["success"]:
		fail("existing Fire spell could not be cast")
		return
	assertEqual(target.get_resonance("ice"), 2, "elemental weakness did not decay exactly one charge")
