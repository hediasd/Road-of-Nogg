## CatalogValidator — Single authoritative implementation of monster-reference
## validation. Before this existed, MonsterReferences.validateAll() and the
## reference-catalog check implemented overlapping but different rules (the
## former never checked spell/element compatibility or spell-set shape), so
## content could pass one and fail the other. Both now delegate here. See
## AUDIT_REMEDIATION_PLAN.md P2-3.

class_name CatalogValidator

const MAX_SPELL_SETS := 4

const RaceReferencesScript = preload("res://src/factories/RaceReferences.gd")
const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const PassiveSkillReferencesScript = preload("res://src/factories/PassiveSkillReferences.gd")
const ArchetypeReferencesScript = preload("res://src/factories/ArchetypeReferences.gd")


static func validateMonsters(monsterList: Array) -> Dictionary:
	## Validates every monster reference. Returns {"success": bool, "errors": Array[String]}.
	var errors: Array[String] = []

	## First pass collects every declared name so ASCENDS_FROM can resolve a
	## parent declared later in the catalog (order-independent, see P1-10).
	var allNames: Dictionary = {}
	for reference in monsterList:
		var declaredName := str(reference.get("NAME", ""))
		if not declaredName.is_empty():
			allNames[declaredName] = true

	var seenNames: Dictionary = {}
	for reference in monsterList:
		_validateOne(reference, allNames, seenNames, errors)

	return {"success": errors.is_empty(), "errors": errors}


static func _validateOne(reference: Dictionary, allNames: Dictionary, seenNames: Dictionary, errors: Array[String]) -> void:
	var name := str(reference.get("NAME", ""))
	if name.is_empty():
		errors.append("Monster reference is missing NAME.")
	elif seenNames.has(name):
		errors.append("Duplicate monster reference: %s." % name)
	else:
		seenNames[name] = true

	for key in ["RACE", "FAMILY", "ELEMENTS", "SPELLS", "ARCHETYPE"]:
		if not reference.has(key):
			errors.append("%s is missing %s." % [name, key])

	var race := str(reference.get("RACE", "none"))
	if not RaceReferencesScript.hasReference(race):
		errors.append("%s has unknown race %s." % [name, race])

	var archetype := str(reference.get("ARCHETYPE", ""))
	if not archetype.is_empty() and not ArchetypeReferencesScript.hasReference(archetype):
		errors.append("%s has unknown archetype %s." % [name, archetype])

	var elements: Array = reference.get("ELEMENTS", [])
	for element in elements:
		if not ElementReferencesScript.isValid(str(element)) or element == "none":
			errors.append("%s has invalid element %s." % [name, element])

	var spellSets: Array = reference.get("SPELLS", [])
	if spellSets.size() > MAX_SPELL_SETS:
		errors.append("%s has %d spell sets; the maximum is %d." % [name, spellSets.size(), MAX_SPELL_SETS])
	for spellSet in spellSets:
		if not spellSet is Array:
			errors.append("%s has a non-array spell set." % name)
			continue
		_validateVerticalSet(name, spellSet, errors)
		for spellName in spellSet:
			if not SpellReferencesScript.hasReference(str(spellName)):
				errors.append("%s has unknown spell %s." % [name, spellName])
				continue
			_validateSpellCompatibility(name, elements, SpellReferencesScript.getReference(str(spellName)), errors)

	for passiveName in reference.get("PASSIVES", []):
		if not PassiveSkillReferencesScript.hasReference(str(passiveName)):
			errors.append("%s references unknown passive %s." % [name, passiveName])

	var parent := str(reference.get("ASCENDS_FROM", ""))
	if not parent.is_empty() and not allNames.has(parent):
		errors.append("%s ascends from unknown monster %s." % [name, parent])


static func _validateVerticalSet(monsterName: String, spellSet: Array, errors: Array[String]) -> void:
	## A set holds at most one spell per Level 1-4 and stays on a single
	## element. Partial sets are legal: a set does not have to fill every Level.
	var tiers: Dictionary = {}
	var element := ""
	for spellName in spellSet:
		if not SpellReferencesScript.hasReference(str(spellName)):
			continue
		var spell: Dictionary = SpellReferencesScript.getReference(str(spellName))
		var tier = int(spell.get("SEQUENCE_LEVEL", 0))
		if tier <= 0:
			continue
		if tiers.has(tier):
			errors.append("monster %s has duplicate Level %d spells in one set." % [monsterName, tier])
		tiers[tier] = true
		var spellElement := str(spell.get("ELEMENT", "none"))
		if element.is_empty():
			element = spellElement
		elif element != spellElement:
			errors.append("monster %s mixes elements in a tiered spell set." % monsterName)


static func _validateSpellCompatibility(monsterName: String, elements: Array, spell: Dictionary, errors: Array[String]) -> void:
	## Matches Monster.can_cast()'s element-requirement logic exactly, so a
	## monster this validator accepts can actually cast every spell it owns.
	var required: Dictionary = {}
	var primary := str(spell.get("ELEMENT", "none"))
	if primary != "none":
		required[primary] = true
	for line in spell.get("DAMAGE_LINES", []):
		if line is Dictionary:
			var element := str(line.get("element", "none"))
			if element != "none":
				required[element] = true
	for element in required:
		if not elements.has(element):
			errors.append("monster %s cannot cast %s because it lacks %s." % [monsterName, spell.get("NAME", ""), element])


## --- Archetype stat bands (item 2.3) -----------------------------------------
##
## Deliberately NOT part of validateMonsters(), and therefore not part of
## MonsterReferences.validateAll(). Those answer "is this data referentially
## correct" — does this race exist, can this monster actually cast the spells it
## owns. Those are facts. Stat bands are balance heuristics with headroom and
## taste baked in, and folding them into the same gate would mean a deliberate
## balance experiment fails identically to a typo, and that the runtime catalog
## check starts enforcing opinion. Kept separate so the two can evolve — and be
## overridden — independently.
static func validateArchetypeBands(monsterList: Array) -> Dictionary:
	## Returns {"success": bool, "errors": Array[String], "warnings": Array[String]}.
	## Errors are out-of-band stats. Warnings are stats sitting exactly ON a bound,
	## i.e. content with no headroom left in that direction.
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for reference in monsterList:
		_validateOneBand(reference, errors, warnings)
	return {"success": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _validateOneBand(reference: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var name := str(reference.get("NAME", ""))
	var archetype := str(reference.get("ARCHETYPE", ""))
	## A missing or unknown archetype is validateMonsters()'s error to report,
	## not this one's — reporting it twice would double-count the same defect.
	if not ArchetypeReferencesScript.hasReference(archetype):
		return
	var band: Dictionary = ArchetypeReferencesScript.getReference(archetype)

	var attack := int(reference.get("ATK", 0))
	var defense := int(reference.get("DEF", 0))
	var spread := attack - defense

	_checkFloor(name, archetype, band, "SPREAD_MIN", spread, "ATK-DEF spread", errors, warnings)
	_checkCeiling(name, archetype, band, "SPREAD_MAX", spread, "ATK-DEF spread", errors, warnings)
	_checkFloor(name, archetype, band, "DEF_MIN", defense, "DEF", errors, warnings)
	_checkFloor(name, archetype, band, "SPD_MIN", int(reference.get("SPD", 0)), "SPD", errors, warnings)


static func _checkFloor(name: String, archetype: String, band: Dictionary, key: String, actual: int, label: String, errors: Array[String], warnings: Array[String]) -> void:
	if not band.has(key):
		return
	var floorValue := int(band[key])
	if actual < floorValue:
		errors.append("%s is a %s but its %s is %d, under the %d floor." % [name, archetype, label, actual, floorValue])
	elif actual == floorValue:
		warnings.append("%s sits exactly on the %s %s floor (%d)." % [name, archetype, label, floorValue])


static func _checkCeiling(name: String, archetype: String, band: Dictionary, key: String, actual: int, label: String, errors: Array[String], warnings: Array[String]) -> void:
	if not band.has(key):
		return
	var ceilingValue := int(band[key])
	if actual > ceilingValue:
		errors.append("%s is a %s but its %s is %d, over the %d ceiling." % [name, archetype, label, actual, ceilingValue])
	elif actual == ceilingValue:
		warnings.append("%s sits exactly on the %s %s ceiling (%d)." % [name, archetype, label, ceilingValue])
