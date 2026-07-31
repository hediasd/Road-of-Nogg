class_name ArchetypeReferences

const JSON_PATH := "res://data/archetypes.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const INTEGER_FIELDS := ["SPREAD_MIN", "SPREAD_MAX", "DEF_MIN", "SPD_MIN"]

static var list: Array = []
static var _name_index: Dictionary = {}


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))
	var newList: Array = []
	var newIndex: Dictionary = {}
	for reference in loaded["list"]:
		reference["DESCRIPTION"] = str(reference.get("DESCRIPTION", ""))
		for key in INTEGER_FIELDS:
			if reference.has(key):
				reference[key] = int(reference[key])
		newList.append(reference)
		newIndex[reference["NAME"]] = reference
	list = newList
	_name_index = newIndex
	return true


static func _fail(message: String) -> bool:
	push_warning("ArchetypeReferences: %s" % message)
	return false


static func getReference(name: String) -> Dictionary:
	return _name_index.get(name, {})


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for reference in list:
		names.append(reference["NAME"])
	return names
