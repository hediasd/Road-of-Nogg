## POLICY GUARD for the archetype stat bands (item 2.3), plus a non-vacuity
## check so the guard cannot quietly stop guarding.
##
## Lives in integration/ rather than unit/ because it asserts against the live
## authored catalog, the same way test_reference_catalog.gd does.
##
## Warnings (content sitting exactly on a bound, with no headroom left) are
## informational and stable run to run, so listing them every time is noise in
## hook output. The count travels in describe(); pass `verbose` to see them.
extends "res://tests/TestCase.gd"

const CatalogValidatorScript = preload("res://src/factories/CatalogValidator.gd")

var _warningCount: int = 0


func describe() -> String:
	return "every monster's stats sit inside its archetype's bands (warnings=%d)" % _warningCount


func run() -> void:
	## --- The guard proper: the authored roster respects its own bands. ---
	var result := CatalogValidatorScript.validateArchetypeBands(MonsterReferences.list)
	_warningCount = result["warnings"].size()

	for issue in result["errors"]:
		fail(issue)

	if "verbose" in OS.get_cmdline_user_args():
		for warning in result["warnings"]:
			print("ARCHETYPE_BAND_WARNING: %s" % warning)

	## --- Non-vacuity: the lint must actually reject out-of-band content. ---
	## Without this, deleting the band data or mistyping a key would leave the
	## guard passing forever while checking nothing.
	var brokenDefender := {
		"NAME": "OverAggressiveWall", "ARCHETYPE": "defender",
		"ATK": 9, "DEF": 3, "SPD": 3
	}
	var defenderResult := CatalogValidatorScript.validateArchetypeBands([brokenDefender])
	assertFalse(
		defenderResult["success"],
		"lint accepted a defender whose ATK exceeds its DEF by 6"
	)

	var brokenStriker := {
		"NAME": "PacifistAssassin", "ARCHETYPE": "striker",
		"ATK": 2, "DEF": 6, "SPD": 5
	}
	var strikerResult := CatalogValidatorScript.validateArchetypeBands([brokenStriker])
	assertFalse(
		strikerResult["success"],
		"lint accepted a striker whose DEF exceeds its ATK"
	)

	var sluggishStriker := {
		"NAME": "SlowAssassin", "ARCHETYPE": "striker",
		"ATK": 7, "DEF": 2, "SPD": 1
	}
	assertFalse(
		CatalogValidatorScript.validateArchetypeBands([sluggishStriker])["success"],
		"lint accepted a striker under the SPD floor"
	)

	## An unknown archetype is validateMonsters()'s error to report, so the band
	## lint must stay silent on it rather than double-counting the same defect.
	var unknownArchetype := {
		"NAME": "Mystery", "ARCHETYPE": "necromancer",
		"ATK": 99, "DEF": 1, "SPD": 1
	}
	assertTrue(
		CatalogValidatorScript.validateArchetypeBands([unknownArchetype])["success"],
		"band lint reported an unknown archetype that validateMonsters() already owns"
	)
