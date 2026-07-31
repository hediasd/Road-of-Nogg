class_name RaceReferences

const JSON_PATH := "res://data/taxonomy.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

static var list: Array = []
static var _name_index: Dictionary = {}
static var _load_error: String = ""


static func _static_init():
	reloadCatalog()


## Named reloadCatalog(), not reload(): see MonsterReferences.gd.
static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path, "races")
	if not loaded["success"]:
		return _fail(str(loaded["error"]))

	var newList: Array = []
	var newIndex: Dictionary = {}
	for reference in loaded["list"]:
		var resistancesValue = reference.get("RESISTANCES", {})
		if not resistancesValue is Dictionary:
			return _fail(
				"Race '%s' RESISTANCES is not a dictionary"
				% str(reference.get("NAME", ""))
			)
		var resistances: Dictionary = {}
		for element in resistancesValue:
			resistances[str(element)] = float(resistancesValue[element])
		reference["RESISTANCES"] = resistances
		newList.append(reference)
		newIndex[reference["NAME"]] = reference

	list = newList
	_name_index = newIndex
	_load_error = ""
	return true


static func _fail(message: String) -> bool:
	_load_error = message
	push_warning("RaceReferences: %s" % _load_error)
	return false


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	return _name_index.get("none", {"NAME": "none", "RESISTANCES": {}})


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getDamageMultiplier(race_name: String, element: String) -> float:
	var race = getReference(race_name)
	if race["RESISTANCES"].has(element):
		return float(race["RESISTANCES"][element])
	return 1.0
