class_name SpellReferences

const JSON_PATH := "res://data/spells.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
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
	"RESONANCE_ELEMENT": "",
	"AOE_TARGETS": "self",
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