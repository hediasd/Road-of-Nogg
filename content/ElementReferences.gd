class_name ElementReferences

## One catalog for single elements and their two- and three-element combinations.
##
## An entry with an `ELEMENTS` key is a combination; one without is a single
## element. Singles come first and keep their own contract -- `list`, `STANDARD`,
## `CODES`, `code()` and `isValid()` see singles only -- because spell validation
## and the HUD's element codes mean exactly one element by them, and a
## combination leaking in would change what every caller means. Combinations
## exist so each pair or triple can carry its own authored data; they live in
## `COMBINATIONS` and are reached through `getCombination()`.

const JSON_PATH := "res://data/elements.json"
const JsonCatalogLoaderScript = preload("res://content/JsonCatalogLoader.gd")
const NONE_ELEMENT := "none"
const COMBINATION_SEPARATOR := "+"
const MIN_COMBINATION_SIZE := 2
const MAX_COMBINATION_SIZE := 3

static var list: Array = []
static var STANDARD: Array[String] = []
static var CODES: Dictionary = {}
static var COMBINATIONS: Array = []
static var _combinationIndex: Dictionary = {}


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))
	var newList: Array = []
	var newStandard: Array[String] = []
	var newCodes: Dictionary = {}
	var usedCodes: Dictionary = {}
	var newCombinations: Array = []
	var newCombinationIndex: Dictionary = {}
	for reference in loaded["list"]:
		if reference.has("ELEMENTS"):
			var combined := _normalizeCombination(reference, newStandard)
			if not combined["success"]:
				return _fail(str(combined["error"]))
			newCombinations.append(reference)
			newCombinationIndex[reference["NAME"]] = reference
			continue
		if not newCombinations.is_empty():
			return _fail(
				"single element '%s' follows a combination; singles come first"
				% str(reference["NAME"])
			)
		var nameKey := str(reference["NAME"]).to_lower()
		var codeKey := str(reference.get("CODE", "")).to_upper()
		if nameKey.is_empty() or newStandard.has(nameKey):
			return _fail("invalid or duplicate element '%s'" % nameKey)
		if codeKey.length() != 2 or usedCodes.has(codeKey):
			return _fail("invalid or duplicate code '%s' for element '%s'" % [codeKey, nameKey])
		reference["NAME"] = nameKey
		reference["CODE"] = codeKey
		newList.append(reference)
		newStandard.append(nameKey)
		usedCodes[codeKey] = true
		newCodes[nameKey] = codeKey
	list = newList
	STANDARD = newStandard
	CODES = newCodes
	COMBINATIONS = newCombinations
	_combinationIndex = newCombinationIndex
	return true


## Validates one combination against the singles already read and rewrites its
## `ELEMENTS` into canonical order. Its `NAME` must already be the canonical key,
## so one set can only ever be written one way and a repeated set is caught here
## rather than surfacing as two differently spelled entries.
static func _normalizeCombination(reference: Dictionary, singles: Array[String]) -> Dictionary:
	var nameKey := str(reference["NAME"])
	if reference.has("CODE"):
		return _invalid("combination '%s' carries a CODE; only single elements have one" % nameKey)
	var elementsValue = reference["ELEMENTS"]
	if not elementsValue is Array:
		return _invalid("combination '%s' ELEMENTS is not an array" % nameKey)
	var elements: Array = elementsValue
	if elements.size() < MIN_COMBINATION_SIZE or elements.size() > MAX_COMBINATION_SIZE:
		return _invalid(
			"combination '%s' has %d elements; it needs %d to %d"
			% [nameKey, elements.size(), MIN_COMBINATION_SIZE, MAX_COMBINATION_SIZE]
		)
	var normalized: Array[String] = []
	for element in elements:
		var elementKey := str(element).to_lower()
		if elementKey == NONE_ELEMENT or not singles.has(elementKey):
			return _invalid("combination '%s' names '%s', which is not a combinable element" % [nameKey, elementKey])
		if normalized.has(elementKey):
			return _invalid("combination '%s' repeats '%s'" % [nameKey, elementKey])
		normalized.append(elementKey)
	var canonical := _canonicalOrder(normalized, singles)
	var canonicalName := COMBINATION_SEPARATOR.join(canonical)
	if nameKey != canonicalName:
		return _invalid("combination '%s' must be named '%s'" % [nameKey, canonicalName])
	reference["ELEMENTS"] = canonical
	return {"success": true, "error": ""}


static func _canonicalOrder(elements: Array[String], singles: Array[String]) -> Array[String]:
	var ordered := elements.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool: return singles.find(a) < singles.find(b))
	return ordered


static func _invalid(message: String) -> Dictionary:
	return {"success": false, "error": message}


static func _fail(message: String) -> bool:
	push_warning("ElementReferences: %s" % message)
	return false


static func code(element: String) -> String:
	var nameKey := element.to_lower()
	if CODES.has(nameKey):
		return str(CODES[nameKey])
	push_warning("ElementReferences: Unknown element '%s'." % element)
	return "??"

static func isValid(element: String) -> bool:
	return STANDARD.has(element.to_lower())


## The combination entry for a set of elements, in any order and any case, or
## `{}` when the set has no entry or names something that is not an element.
static func getCombination(elements: Array) -> Dictionary:
	var normalized: Array[String] = []
	for element in elements:
		var elementKey := str(element).to_lower()
		if elementKey == NONE_ELEMENT or not STANDARD.has(elementKey) or normalized.has(elementKey):
			return {}
		normalized.append(elementKey)
	var key := COMBINATION_SEPARATOR.join(_canonicalOrder(normalized, STANDARD))
	if not _combinationIndex.has(key):
		return {}
	return (_combinationIndex[key] as Dictionary).duplicate(true)
