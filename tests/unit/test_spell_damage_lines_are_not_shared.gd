## Regression test for P1-8 (AUDIT_REMEDIATION_PLAN.md). SpellFactory.createSpell()
## passes the SAME dictionary object from the static SpellReferences.list into
## every Spell.new() call. "Eschatology" is a spell whose reference explicitly
## provides DAMAGE_LINES as a literal array, so it is a real fixture for the
## aliasing bug (spells built from the DAMAGE/ELEMENT scalar fields instead
## construct a fresh array every time and would never have exposed it).
extends "res://tests/TestCase.gd"

const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")


func describe() -> String:
	return "each Spell instance owns its own damage_lines array, independent of the shared reference catalog"


func run() -> void:
	var spellA = SpellFactory.createSpell("Eschatology")
	var spellB = SpellFactory.createSpell("Eschatology")
	var originalDamage: int = spellB.damage_lines[0]["damage"]

	spellA.damage_lines[0]["damage"] = 999

	assertEqual(spellB.damage_lines[0]["damage"], originalDamage, "mutating one Spell instance must not affect another instance of the same spell")
	assertEqual(
		SpellReferencesScript.getReference("Eschatology")["DAMAGE_LINES"][0]["damage"],
		originalDamage,
		"mutating a Spell instance must not corrupt the static reference catalog"
	)
