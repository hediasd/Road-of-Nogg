## Replaces test_roster_luck_is_dormant.gd, the temporary guard that failed the
## build if any monster defined LUCK at all. P4-4 introduced Luck deliberately
## as an archetype signature, so the guard's job changes rather than disappears:
## it now holds the archetype contract instead of holding the mechanic shut.
##
## POLICY GUARD, not a behavior test. The crit maths themselves are unit-tested
## in test_zero_luck_has_no_critical_chance.gd and
## test_luck_critical_chance_caps_at_fifteen_percent.gd.
extends "res://tests/TestCase.gd"

const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")

## Luck is a characterisation tool, not universal variance: the roster ceiling
## sits below the engine's own 15% cap so no unit is ever a coin flip, and the
## archetypes that must stay deterministic are pinned at zero.
const ROSTER_LUCK_CEILING := 10

## Bruisers, walls, and dedicated support never crit. Pinning these by name
## stops a future balance pass from quietly handing a DEF 8 wall a crit rate.
const MUST_NOT_CRIT := [
	"Brickamount", "Lord of the Mine", "Gigasaurus", "Purple Dungeon Slime",
	"Healer Mage", "Wing of Sanctum", "Oracle of Ages", "Walker of the Woods"
]


func describe() -> String:
	return "roster Luck stays within the archetype ceiling and pinned archetypes never crit"


func run() -> void:
	var catalogValidation = MonsterReferences.validateAll()
	if not catalogValidation["success"]:
		fail("monster catalog invalid: %s" % catalogValidation["errors"])
		return

	var luckyCount := 0
	for reference in MonsterReferences.list:
		var name := str(reference["NAME"])
		var luck := int(reference.get("LUCK", 0))

		if luck < 0 or luck > ROSTER_LUCK_CEILING:
			fail("%s has Luck %d, outside the roster range 0-%d" % [name, luck, ROSTER_LUCK_CEILING])
		if luck > 0:
			luckyCount += 1
		if name in MUST_NOT_CRIT and luck != 0:
			fail("%s is a pinned no-crit archetype but has Luck %d" % [name, luck])

		## The reference value must survive into the built entity, and the
		## resulting chance must respect the engine cap. Reading it back through
		## the factory is what makes this a contract rather than a data lint.
		var monster = MonsterFactoryScript.createMonster(name, 900)
		assertEqual(monster.luck, luck, "%s did not carry its reference Luck into the entity" % name)
		var chance := monster.get_critical_chance()
		assertTrue(
			chance >= 0.0 and chance <= 0.15,
			"%s has a critical chance of %f, outside the documented 0-15%% band" % [name, chance]
		)

	## Guards against Luck silently going dormant again: if a future edit zeroes
	## the roster, criticals become dead code and this test says so.
	assertTrue(luckyCount > 0, "no monster defines Luck, so critical hits are dead code again")
