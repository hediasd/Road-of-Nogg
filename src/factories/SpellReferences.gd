class_name SpellReferences

const JSON_PATH := "res://data/spells.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const INTEGER_DEFAULTS := {
	"RADIUS": 1,
	"MIN_RANGE": 0,
	"RANGE": 1,
	"MAX_HEIGHT_DELTA": 1,
	"DAMAGE": 0,
	"BUFFS_ATK": 0,
	"BUFF_DURATION": 0,
	"COOLDOWN": 0,
	"SEQUENCE_LEVEL": 0,
	"SELF_RADIUS": 0,
	"HEAL_AMOUNT": 0
}
const BOOLEAN_DEFAULTS := {
	"HEALS": false,
	"CAN_TARGET_EMPTY": false,
	"BYPASS_LOS": false,
	"REVERTS_DAMAGE": false
}
const STRING_DEFAULTS := {
	"ELEMENT": "none",
	"TARGET_TYPE": "single",
	"AREA_SHAPE": "circle",
	"INFLICTS_STATUS": "",
	"REMOVES_STATUS": "",
	"AOE_TARGETS": "self",
	"VFX_PROFILE": "",
	"DESC": ""
}
const EFFECT_INTEGER_FIELDS := [
	"DURATION", "ATK_BONUS", "DEF_BONUS", "SPD_BONUS",
	"MOVE_BONUS", "VALUE"
]

static var list: Array = []
static var _name_index: Dictionary = {}
static var _load_error: String = ""


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))

	var newList: Array = []
	var newIndex: Dictionary = {}
	for rawReference in loaded["list"]:
		var normalized := _normalizeReference(rawReference)
		if not normalized["success"]:
			return _fail(str(normalized["error"]))
		var reference: Dictionary = normalized["reference"]
		newList.append(reference)
		newIndex[reference["NAME"]] = reference

	list = newList
	_name_index = newIndex
	_load_error = ""
	return true


static func _normalizeReference(reference: Dictionary) -> Dictionary:
	for key in INTEGER_DEFAULTS:
		reference[key] = int(reference.get(key, INTEGER_DEFAULTS[key]))
	for key in BOOLEAN_DEFAULTS:
		reference[key] = bool(reference.get(key, BOOLEAN_DEFAULTS[key]))
	for key in STRING_DEFAULTS:
		reference[key] = str(reference.get(key, STRING_DEFAULTS[key]))

	## A spell resonates on its own element unless it explicitly names another.
	## This default cannot live in STRING_DEFAULTS: a blank value would still be
	## written into the reference, which overrides the fallback and collapses
	## every sequenced spell onto one shared "" resonance bar.
	var resonanceElement := str(reference.get("RESONANCE_ELEMENT", "")).strip_edges()
	reference["RESONANCE_ELEMENT"] = (
		resonanceElement if not resonanceElement.is_empty() else reference["ELEMENT"]
	)

	var linesValue = reference.get("DAMAGE_LINES", null)
	if linesValue != null:
		if not linesValue is Array:
			return _normalizationFailure("Spell '%s' DAMAGE_LINES is not an array" % reference["NAME"])
		var normalizedLines: Array = []
		for rawLine in linesValue:
			if not rawLine is Dictionary:
				return _normalizationFailure("Spell '%s' DAMAGE_LINES contains a non-dictionary entry" % reference["NAME"])
			var line: Dictionary = rawLine.duplicate(true)
			line["damage"] = int(line.get("damage", 0))
			line["element"] = str(line.get("element", reference["ELEMENT"]))
			normalizedLines.append(line)
		reference["DAMAGE_LINES"] = normalizedLines

	var aligned := _alignElements(reference)
	if not aligned["success"]:
		return aligned

	var effectsValue = reference.get("EFFECTS", [])
	if not effectsValue is Array:
		return _normalizationFailure("Spell '%s' EFFECTS is not an array" % reference["NAME"])
	var normalizedEffects: Array = []
	for rawEffect in effectsValue:
		if not rawEffect is Dictionary:
			return _normalizationFailure("Spell '%s' EFFECTS contains a non-dictionary entry" % reference["NAME"])
		var effect: Dictionary = rawEffect.duplicate(true)
		effect["NAME"] = str(effect.get("NAME", ""))
		if effect["NAME"].is_empty():
			return _normalizationFailure("Spell '%s' has an effect without NAME" % reference["NAME"])
		for key in EFFECT_INTEGER_FIELDS:
			if effect.has(key):
				effect[key] = int(effect[key])
		if effect.has("DAMAGE_MULTIPLIER"):
			effect["DAMAGE_MULTIPLIER"] = float(effect["DAMAGE_MULTIPLIER"])
		if effect.has("NEGATIVE"):
			effect["NEGATIVE"] = bool(effect["NEGATIVE"])
		normalizedEffects.append(effect)
	reference["EFFECTS"] = normalizedEffects
	return {"success": true, "reference": reference, "error": ""}


## A spell's declared elements and its damage lines' elements are always the same
## list, in the order the lines first use them: one element is authored as
## ELEMENT, several as ELEMENTS. Publishes ELEMENTS on every reference and leaves
## ELEMENT as the single element, or none when there are several.
static func _alignElements(reference: Dictionary) -> Dictionary:
	var spellName := str(reference["NAME"])
	var single := str(reference["ELEMENT"])
	var lineElements: Array[String] = []
	for line in reference.get("DAMAGE_LINES", []):
		var lineElement := str(line["element"])
		if lineElement != "none" and not lineElements.has(lineElement):
			lineElements.append(lineElement)

	var elements: Array[String] = []
	if reference.has("ELEMENTS"):
		var authored = reference["ELEMENTS"]
		if not authored is Array:
			return _normalizationFailure("Spell '%s' ELEMENTS is not an array" % spellName)
		if single != "none":
			return _normalizationFailure("Spell '%s' authors both ELEMENT and ELEMENTS" % spellName)
		for value in authored:
			var elementName := str(value)
			if elementName == "none" or not ElementReferencesScript.isValid(elementName) \
					or elements.has(elementName):
				return _normalizationFailure(
					"Spell '%s' ELEMENTS has an unknown or repeated element '%s'" % [spellName, elementName])
			elements.append(elementName)
		if elements.size() < 2:
			return _normalizationFailure(
				"Spell '%s' ELEMENTS names fewer than two elements; author ELEMENT instead" % spellName)
		if elements != lineElements:
			return _normalizationFailure("Spell '%s' ELEMENTS %s do not match its damage lines %s" % [
				spellName, str(elements), str(lineElements)])
	else:
		if single != "none":
			elements.append(single)
		if not lineElements.is_empty() and elements != lineElements:
			var hint := " (several elements are declared with ELEMENTS)" if lineElements.size() >= 2 else ""
			return _normalizationFailure("Spell '%s' element %s does not match its damage lines %s%s" % [
				spellName, str(elements), str(lineElements), hint])

	reference["ELEMENTS"] = elements
	return {"success": true, "reference": reference, "error": ""}


static func _normalizationFailure(message: String) -> Dictionary:
	return {"success": false, "reference": {}, "error": message}


static func _fail(message: String) -> bool:
	_load_error = message
	push_warning("SpellReferences: %s" % _load_error)
	return false


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	push_error("SpellReferences: Unknown spell '%s'." % name)
	return {}


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for name in _name_index:
		names.append(name)
	names.sort()
	return names
