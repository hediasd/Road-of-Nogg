class_name MapReferences

const JSON_PATH := "res://data/maps.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

static var list: Array[Dictionary] = []
static var _name_index: Dictionary = {}


static func _static_init():
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))
	var newList: Array[Dictionary] = []
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
	return true


static func _normalizeReference(reference: Dictionary) -> Dictionary:
	var mapName := str(reference["NAME"])
	reference["REVISION"] = int(reference.get("REVISION", 1))
	var sizeResult := _vectorFromJson(reference.get("SIZE"), "SIZE", mapName)
	if not sizeResult["success"]:
		return sizeResult
	reference["SIZE"] = sizeResult["value"]

	var heightsValue = reference.get("HEIGHTS", [])
	if not heightsValue is Array:
		return _failure("Map '%s' HEIGHTS is not an array" % mapName)
	var heights: Array = []
	for rawRow in heightsValue:
		if not rawRow is Array:
			return _failure("Map '%s' HEIGHTS contains a non-array row" % mapName)
		var row: Array = []
		for value in rawRow:
			row.append(int(value))
		heights.append(row)
	reference["HEIGHTS"] = heights

	var layoutValue = reference.get("LAYOUT", [])
	if not layoutValue is Array:
		return _failure("Map '%s' LAYOUT is not an array" % mapName)
	var layout: Array = []
	for rowValue in layoutValue:
		layout.append(str(rowValue))
	reference["LAYOUT"] = layout

	for key in ["TEAM_1_SLOTS", "TEAM_2_SLOTS"]:
		var slotsValue = reference.get(key, [])
		if not slotsValue is Array:
			return _failure("Map '%s' %s is not an array" % [mapName, key])
		var slots: Array = []
		for rawSlot in slotsValue:
			var slotResult := _vectorFromJson(rawSlot, key, mapName)
			if not slotResult["success"]:
				return slotResult
			slots.append(slotResult["value"])
		reference[key] = slots
	return {"success": true, "reference": reference, "error": ""}


static func _vectorFromJson(value, fieldName: String, mapName: String) -> Dictionary:
	if not value is Array or value.size() != 2:
		return _failure("Map '%s' %s must be a [x, y] pair" % [mapName, fieldName])
	return {"success": true, "value": Vector2i(int(value[0]), int(value[1])), "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"success": false, "reference": {}, "value": Vector2i.ZERO, "error": message}


static func _fail(message: String) -> bool:
	push_warning("MapReferences: %s" % message)
	return false


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	if list.is_empty():
		return {}
	return list[0]


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for reference in list:
		names.append(reference["NAME"])
	return names


static func getDeploymentSlots(name: String, team: int) -> Array:
	var reference := getReference(name)
	var key := "TEAM_1_SLOTS" if team == 1 else "TEAM_2_SLOTS"
	return reference.get(key, []).duplicate()
