class_name StatusEffectReferences

const JSON_PATH := "res://data/status_effects.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

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
		reference["DURATION"] = int(reference.get("DURATION", 2))
		reference["DAMAGE_PER_TURN"] = int(reference.get("DAMAGE_PER_TURN", 0))
		reference["NEGATIVE"] = bool(reference.get("NEGATIVE", false))
		newList.append(reference)
		newIndex[reference["NAME"]] = reference
	list = newList
	_name_index = newIndex
	return true


static func _fail(message: String) -> bool:
	push_warning("StatusEffectReferences: %s" % message)
	return false


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	push_error("StatusEffectReferences: Unknown status effect '%s'." % name)
	return {"NAME": name, "DURATION": 2, "DAMAGE_PER_TURN": 0, "NEGATIVE": false}


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func isNegative(name: String) -> bool:
	return bool(getReference(name).get("NEGATIVE", false))


static func getDuration(name: String) -> int:
	return int(getReference(name).get("DURATION", 2))


static func getDamagePerTurn(name: String) -> int:
	return int(getReference(name).get("DAMAGE_PER_TURN", 0))
