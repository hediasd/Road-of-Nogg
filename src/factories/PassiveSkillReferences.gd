class_name PassiveSkillReferences

const JSON_PATH := "res://data/passives.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

static var list: Array = []
static var _name_index: Dictionary = {}


static func _static_init() -> void:
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))
	var newList: Array = []
	var newIndex: Dictionary = {}
	for reference in loaded["list"]:
		reference["TRIGGER"] = str(reference.get("TRIGGER", ""))
		reference["EFFECT_TYPE"] = str(reference.get("EFFECT_TYPE", ""))
		reference["VALUE"] = float(reference.get("VALUE", 0.0))
		reference["ELEMENT"] = str(reference.get("ELEMENT", "none"))
		reference["RADIUS"] = int(reference.get("RADIUS", 0))
		newList.append(reference)
		newIndex[reference["NAME"]] = reference
	list = newList
	_name_index = newIndex
	return true


static func _fail(message: String) -> bool:
	push_warning("PassiveSkillReferences: %s" % message)
	return false


static func getReference(passiveName: String) -> Dictionary:
	if _name_index.has(passiveName):
		return _name_index[passiveName]
	push_error("PassiveSkillReferences: Unknown passive '%s'" % passiveName)
	return {}


static func hasReference(passiveName: String) -> bool:
	return _name_index.has(passiveName)
