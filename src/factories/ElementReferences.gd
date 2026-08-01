class_name ElementReferences

const JSON_PATH := "res://data/elements.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

static var list: Array = []
static var STANDARD: Array[String] = []
static var CODES: Dictionary = {}


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		push_warning("ElementReferences: %s" % loaded["error"])
		return false
	var newList: Array = []
	var newStandard: Array[String] = []
	var newCodes: Dictionary = {}
	var usedCodes: Dictionary = {}
	for reference in loaded["list"]:
		var nameKey := str(reference["NAME"]).to_lower()
		var codeKey := str(reference.get("CODE", "")).to_upper()
		if nameKey.is_empty() or newStandard.has(nameKey):
			push_warning("ElementReferences: invalid or duplicate element '%s'" % nameKey)
			return false
		if codeKey.length() != 2 or usedCodes.has(codeKey):
			push_warning(
				"ElementReferences: invalid or duplicate code '%s' for element '%s'"
				% [codeKey, nameKey]
			)
			return false
		reference["NAME"] = nameKey
		reference["CODE"] = codeKey
		newList.append(reference)
		newStandard.append(nameKey)
		usedCodes[codeKey] = true
		newCodes[nameKey] = codeKey
	list = newList
	STANDARD = newStandard
	CODES = newCodes
	return true


static func code(element: String) -> String:
	var nameKey := element.to_lower()
	if CODES.has(nameKey):
		return str(CODES[nameKey])
	push_warning("ElementReferences: Unknown element '%s'." % element)
	return "??"

static func isValid(element: String) -> bool:
	return STANDARD.has(element.to_lower())
