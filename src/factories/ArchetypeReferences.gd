## ArchetypeReferences — Registry of the four D&D 4th-Edition combat roles
## every monster is assigned to via its ARCHETYPE field. Same static-registry
## pattern as RaceReferences.gd.
##
## This is organizational metadata only: grouping, coloring, and filtering the
## catalog (e.g. the Stage 3 editor panel), and a basis for an optional
## per-role stat-band lint. It carries no crit/Luck contract: no design
## contract restricts which archetypes may carry LUCK, so critical-hit
## balancing is purely post-hoc via playtest rather than an archetype rule.

class_name ArchetypeReferences

## Stat bands (item 2.3). SPREAD means ATK minus DEF — the one dimension where
## the four roles genuinely separate on the current roster:
##
##   defender   spread -4..+1   striker    spread +1..+5
##   controller spread -2..+2   leader     spread -2..+3
##
## So the bands below encode "a defender must not out-attack its own defense,
## a striker must", plus one viability floor for each melee-facing role. HP,
## MOVE, and SPD bands were deliberately NOT added for controller/leader: those
## roles overlap heavily on every other axis, so bands there would generate
## false positives without catching anything a human would call drift.
##
## Bounds carry roughly one point of headroom past the observed range, except
## where the bound IS the role's definition (striker SPREAD_MIN, the two
## floors). Absent key means unbounded in that direction.
static var list = [
	{
		"NAME": "defender",
		"DESCRIPTION": "Durable, holds ground, punishes attackers who ignore it",
		"SPREAD_MAX": 2,
		"DEF_MIN": 3
	},
	{
		"NAME": "striker",
		"DESCRIPTION": "Concentrated damage, mobility, burst",
		"SPREAD_MIN": 1,
		"SPD_MIN": 3
	},
	{
		"NAME": "controller",
		"DESCRIPTION": "Affects many enemies at once: zones, debuffs, action denial",
		"SPREAD_MIN": -3,
		"SPREAD_MAX": 3
	},
	{
		"NAME": "leader",
		"DESCRIPTION": "Heals, buffs, and enables allies",
		"SPREAD_MIN": -3,
		"SPREAD_MAX": 3
	}
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
