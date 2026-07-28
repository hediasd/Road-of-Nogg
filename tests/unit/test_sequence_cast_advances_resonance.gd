## Split from run_resonance_check.gd. See AUDIT_REMEDIATION_PLAN.md P3-4.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "casting Level 1-3 spells advances Resonance only when the level equals current charge + 1"


func run() -> void:
	var caster = makeMonster(["fire"])
	var sequence = [
		Spell.new({"NAME": "Sequence 1", "ELEMENT": "fire", "SEQUENCE_LEVEL": 1}),
		Spell.new({"NAME": "Sequence 2", "ELEMENT": "fire", "SEQUENCE_LEVEL": 2}),
		Spell.new({"NAME": "Sequence 3", "ELEMENT": "fire", "SEQUENCE_LEVEL": 3})
	]
	for spell in sequence:
		assertTrue(caster.can_cast(spell), "sequence spell %s was unexpectedly unavailable" % spell.name)
		caster.record_cast(spell)
	assertEqual(caster.get_resonance("fire"), 3, "three in-order casts should reach charge 3")

	# An out-of-order cast (charge is already 3) must not reset or advance further.
	caster.record_cast(Spell.new({"NAME": "Repeat 1", "ELEMENT": "fire", "SEQUENCE_LEVEL": 1}))
	assertEqual(caster.get_resonance("fire"), 3, "an out-of-order cast must not change existing charge")
