class_name ElementReferences

const JSON_PATH := "res://data/elements.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

static var list: Array = []
static var STANDARD: Array[String] = []


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		push_warning("ElementReferences: %s" % loaded["error"])
		return false
	var newList: Array = []
	var newStandard: Array[String] = []
	for reference in loaded["list"]:
		var nameKey := str(reference["NAME"]).to_lower()
		if nameKey.is_empty() or newStandard.has(nameKey):
			push_warning("ElementReferences: invalid or duplicate element '%s'" % nameKey)
			return false
		reference["NAME"] = nameKey
		newList.append(reference)
		newStandard.append(nameKey)
	list = newList
	STANDARD = newStandard
	return true


static func isValid(element: String) -> bool:
	return STANDARD.has(element.to_lower())
