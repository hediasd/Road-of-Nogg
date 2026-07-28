## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "Level 4 requires three charge and depletes the bar when cast"


func run() -> void:
	var caster = makeMonster(["fire"])
	var levelFour = Spell.new({"NAME": "Ascension", "ELEMENT": "fire", "SEQUENCE_LEVEL": 4})
	assertFalse(caster.can_cast(levelFour), "Level 4 must be unavailable at charge 0")

	for level in [1, 2, 3]:
		caster.record_cast(Spell.new({"NAME": "Step %d" % level, "ELEMENT": "fire", "SEQUENCE_LEVEL": level}))
	assertEqual(caster.get_resonance("fire"), 3, "three in-order casts should reach charge 3")
	assertTrue(caster.can_cast(levelFour), "Level 4 must be available at charge 3")

	caster.record_cast(levelFour)
	assertEqual(caster.get_resonance("fire"), 0, "Level 4 must deplete the bar when cast")
