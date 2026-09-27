extends SceneTree

## A spell's declared elements and its damage lines' elements are always the
## same list; a multi-element spell casts, charges and depletes Resonance on
## every one of its elements.

const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const SpellFactoryScript = preload("res://src/factories/SpellFactory.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const HexUnitFactsScript = preload("res://src/presentation/battle/ui/HexUnitFacts.gd")

const FIXTURE_PATH := "user://probe_spell_elements_fixture.json"

var failures: Array[String] = []


func _init() -> void:
	_check(SpellReferencesScript.reloadCatalog(), "production spell catalog did not load")
	_checkCatalogAligned()
	_checkRejections()
	_check(SpellReferencesScript.reloadCatalog(), "production spell catalog did not reload")
	_checkMultiElementCasting()
	_finish()


func _checkCatalogAligned() -> void:
	for reference: Dictionary in SpellReferencesScript.list:
		var spellName := str(reference["NAME"])
		var published: Array = reference.get("ELEMENTS", [])
		var spell: Spell = SpellFactoryScript.createSpell(spellName)
		_check(Array(spell.getElements()) == published,
			"%s runtime elements %s differ from catalog %s" % [spellName, spell.getElements(), published])
		if published.size() >= 2:
			_check(str(reference["ELEMENT"]) == "none",
				"%s has several elements but a single ELEMENT %s" % [spellName, reference["ELEMENT"]])
	var wicker := SpellReferencesScript.getReference("Wicker Man")
	_check(wicker.get("ELEMENTS", []) == ["light", "wood"], "Wicker Man is not light/wood")
	_check(int(wicker.get("SEQUENCE_LEVEL", 0)) == 3, "Wicker Man is not Level 3")
	_check(SpellReferencesScript.getReference("Ember Strike").get("ELEMENTS", []) == ["fire"],
		"a single-element spell did not publish its element")
	_check(SpellReferencesScript.getReference("Empower").get("ELEMENTS", []) == ["wood"],
		"a non-damaging spell lost its element")
	_check(SpellReferencesScript.getReference("Think").get("ELEMENTS", []) == [],
		"an elementless spell published an element")


func _checkRejections() -> void:
	var twoLines := [{"damage": 2, "element": "light"}, {"damage": 2, "element": "wood"}]
	_expectLoad(true, {"NAME": "Aligned", "ELEMENTS": ["light", "wood"], "DAMAGE_LINES": twoLines},
		"an aligned multi-element spell")
	_expectLoad(false, {"NAME": "Undeclared", "DAMAGE_LINES": twoLines},
		"several damage elements without ELEMENTS")
	_expectLoad(false, {"NAME": "Single Mismatch", "ELEMENT": "fire",
		"DAMAGE_LINES": [{"damage": 2, "element": "water"}]}, "ELEMENT unlike its only damage line")
	_expectLoad(false, {"NAME": "Undeclared Single", "DAMAGE_LINES": [{"damage": 2, "element": "water"}]},
		"a damage element with no declared element")
	_expectLoad(false, {"NAME": "Wrong Pair", "ELEMENTS": ["light", "fire"], "DAMAGE_LINES": twoLines},
		"ELEMENTS unlike the damage lines")
	_expectLoad(false, {"NAME": "Wrong Order", "ELEMENTS": ["wood", "light"], "DAMAGE_LINES": twoLines},
		"ELEMENTS out of damage-line order")
	_expectLoad(false, {"NAME": "Both", "ELEMENT": "light", "ELEMENTS": ["light", "wood"],
		"DAMAGE_LINES": twoLines}, "both ELEMENT and ELEMENTS")
	_expectLoad(false, {"NAME": "Lonely", "ELEMENTS": ["light"],
		"DAMAGE_LINES": [{"damage": 2, "element": "light"}]}, "ELEMENTS with one element")
	_expectLoad(false, {"NAME": "Unknown", "ELEMENTS": ["light", "plasma"],
		"DAMAGE_LINES": [{"damage": 2, "element": "light"}, {"damage": 2, "element": "plasma"}]},
		"ELEMENTS with an unknown element")
	_expectLoad(false, {"NAME": "Lineless", "ELEMENTS": ["light", "wood"]},
		"ELEMENTS with no damage lines")


func _expectLoad(expected: bool, spell: Dictionary, label: String) -> void:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify([spell]))
	file.close()
	var loaded := SpellReferencesScript.reloadCatalog(FIXTURE_PATH)
	_check(loaded == expected, "%s: expected load %s, got %s" % [label, expected, loaded])


func _checkMultiElementCasting() -> void:
	var wicker: Spell = SpellFactoryScript.createSpell("Wicker Man")
	var caster: Monster = MonsterFactoryScript.createMonster("Walker of the Woods", 9001)
	caster.elements = ["wood"]
	_check(not caster.can_cast(wicker), "a wood-only caster could cast a light/wood spell")
	caster.elements = ["light", "wood"]
	_check(caster.can_cast(wicker), "a light/wood caster could not cast a light/wood spell")
	_check(HexUnitFactsScript.spellSummary(wicker).begins_with("Light/Wood."),
		"spell summary does not name both elements: %s" % HexUnitFactsScript.spellSummary(wicker))

	caster.resonance_bars = {"light": 2, "wood": 2}
	_check(caster.would_advance_resonance(wicker), "Level 3 at charge 2 would not advance")
	caster.record_cast(wicker)
	_check(caster.get_resonance("light") == 3 and caster.get_resonance("wood") == 3,
		"Level 3 did not charge both bars: %s" % caster.resonance_bars)

	caster.spell_cooldowns.clear()
	caster.resonance_bars = {"light": 2, "wood": 0}
	caster.record_cast(wicker)
	_check(caster.get_resonance("light") == 3 and caster.get_resonance("wood") == 0,
		"each bar should follow its own charge: %s" % caster.resonance_bars)

	caster.spell_cooldowns.clear()
	caster.resonance_bars = {"light": 0, "wood": 0}
	_check(not caster.would_advance_resonance(wicker), "Level 3 at charge 0 claimed to advance")

	var finisher: Spell = SpellFactoryScript.createSpell("Wicker Man")
	finisher.sequence_level = 4
	finisher.cooldown = 0
	caster.resonance_bars = {"light": 3, "wood": 2}
	_check(not caster.can_cast(finisher), "Level 4 cast with one bar short of full")
	caster.resonance_bars = {"light": 3, "wood": 3}
	_check(caster.can_cast(finisher), "Level 4 refused with every bar full")
	caster.record_cast(finisher)
	_check(caster.get_resonance("light") == 0 and caster.get_resonance("wood") == 0,
		"Level 4 did not deplete every bar: %s" % caster.resonance_bars)

	var single: Spell = SpellFactoryScript.createSpell("Thornlash")
	_check(Array(single.getResonanceElements()) == ["wood"], "a wood spell resonates on %s" % [
		single.getResonanceElements()])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	if not failures.is_empty():
		for failure in failures:
			printerr("SPELL_ELEMENTS_FAILURE: %s" % failure)
		quit(1)
		return
	print("SPELL_ELEMENTS_OK")
	quit(0)
