## CatalogValidator must require every monster to declare a known ARCHETYPE
## (one of the four D&D 4e roles in ArchetypeReferences), the same way it
## already requires a known RACE. Uses synthetic references so this test is
## independent of whatever the live catalog currently has assigned.
extends "res://tests/TestCase.gd"

const CatalogValidatorScript = preload("res://src/factories/CatalogValidator.gd")


func describe() -> String:
	return "CatalogValidator rejects a missing or unknown ARCHETYPE"


func _baseReference() -> Dictionary:
	return {
		"NAME": "Fixture",
		"RACE": "none",
		"FAMILY": "none",
		"ELEMENTS": ["fire"],
		"SPELLS": []
	}


func run() -> void:
	## Missing ARCHETYPE entirely
	var missing := _baseReference()
	var result := CatalogValidatorScript.validateMonsters([missing])
	assertFalse(result["success"], "validator accepted a monster with no ARCHETYPE")

	## Unknown ARCHETYPE value
	var unknown := _baseReference()
	unknown["ARCHETYPE"] = "necromancer"
	result = CatalogValidatorScript.validateMonsters([unknown])
	assertFalse(result["success"], "validator accepted an unknown archetype")

	## Each of the four known roles is accepted
	for role in ["defender", "striker", "controller", "leader"]:
		var valid := _baseReference()
		valid["ARCHETYPE"] = role
		result = CatalogValidatorScript.validateMonsters([valid])
		assertTrue(result["success"], "validator rejected known archetype '%s': %s" % [role, result["errors"]])
