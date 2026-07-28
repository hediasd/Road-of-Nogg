## ArchetypeReferences — Registry of the four D&D 4th-Edition combat roles
## every monster is assigned to via its ARCHETYPE field. Same static-registry
## pattern as RaceReferences.gd.
##
## This is organizational metadata only: grouping, coloring, and filtering the
## catalog (e.g. the Stage 3 editor panel), and a basis for an optional
## per-role stat-band lint. It carries no crit/Luck contract — see
## GAME_DESIGN.md and AUDIT_COMPLETED.md for why Luck was deliberately kept
## free of archetype rules.

class_name ArchetypeReferences

static var list = [
	{"NAME": "defender", "DESCRIPTION": "Durable, holds ground, punishes attackers who ignore it"},
	{"NAME": "striker", "DESCRIPTION": "Concentrated damage, mobility, burst"},
	{"NAME": "controller", "DESCRIPTION": "Affects many enemies at once: zones, debuffs, action denial"},
	{"NAME": "leader", "DESCRIPTION": "Heals, buffs, and enables allies"}
]


static func getReference(name: String) -> Dictionary:
	for archetype in list:
		if archetype["NAME"] == name:
			return archetype
	return {}


static func hasReference(name: String) -> bool:
	for archetype in list:
		if archetype["NAME"] == name:
			return true
	return false


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for archetype in list:
		names.append(archetype["NAME"])
	return names
