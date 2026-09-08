## Strict JSON boundary for versioned headless hex battle maps.

class_name BattleMapFactory
extends RefCounted

const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")

const FORMAT_VERSION := 1
const GRID_KIND := "hex_flat"
const COORDINATES := "odd_q_offset"
const SURFACE_MODEL := "single"
const MIN_HEIGHT := 0
const MAX_HEIGHT := 8


static func loadDefinition(mapID: String) -> Dictionary:
	if not mapID.is_valid_identifier() or mapID.to_lower() != mapID:
		return _failure("invalid_map_id", mapID)
	return loadFromPath("res://data/battle/maps/%s.json" % mapID)


static func loadFromPath(path: String) -> Dictionary:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _failure("map_resource_error", str(loaded["error"]))
	if loaded["list"].size() != 1:
		return _failure("map_file_entry_count", path)
	return fromDictionary(loaded["list"][0])


static func fromDictionary(rawValue) -> Dictionary:
	if not rawValue is Dictionary:
		return _failure("map_not_dictionary")
	var raw: Dictionary = rawValue.duplicate(true)
	var versionResult := _nonnegativeInteger(raw.get("FORMAT_VERSION"))
	if not versionResult["success"] or int(versionResult["value"]) != FORMAT_VERSION:
		return _failure("unsupported_map_version")
	var mapID := str(raw.get("NAME", ""))
	if mapID.is_empty():
		return _failure("missing_map_id")
	if str(raw.get("GRID_KIND", "")) != GRID_KIND:
		return _failure("unsupported_grid_kind")
	if str(raw.get("COORDINATES", "")) != COORDINATES:
		return _failure("unsupported_coordinate_convention")
	if str(raw.get("SURFACE_MODEL", "")) != SURFACE_MODEL:
		return _failure("unsupported_surface_model")

	var sizeResult := _vectorPair(raw.get("SIZE"), "invalid_map_size")
	if not sizeResult["success"]:
		return sizeResult
	var boardSize: Vector2i = sizeResult["value"]
	if boardSize.x <= 0 or boardSize.y <= 0:
		return _failure("invalid_map_size")

	var metricsValue = raw.get("CELL_METRICS")
	if not metricsValue is Dictionary:
		return _failure("invalid_cell_metrics")
	var metrics: Dictionary = metricsValue
	for key in ["WIDTH", "HEIGHT", "HEIGHT_STEP"]:
		if not (metrics.get(key) is float or metrics.get(key) is int):
			return _failure("invalid_cell_metrics", key)
		var metric := float(metrics[key])
		if not is_finite(metric) or metric <= 0.0:
			return _failure("invalid_cell_metrics", key)

	var sourceValue = raw.get("SOURCE")
	if not sourceValue is Dictionary:
		return _failure("invalid_source_identity")
	var source: Dictionary = sourceValue
	var sourceID := str(source.get("ID", ""))
	var sourceRevisionResult := _positiveInteger(source.get("REVISION"))
	var fingerprint := str(source.get("FINGERPRINT", ""))
	var visualPath := str(source.get("VISUAL_SCENE_PATH", ""))
	var headlessOnly := bool(source.get("HEADLESS_ONLY", false))
	if sourceID.is_empty() or not sourceRevisionResult["success"] or not _validFingerprint(fingerprint):
		return _failure("invalid_source_identity")
	if visualPath.is_empty():
		if not headlessOnly or not mapID.begins_with("technical_"):
			return _failure("missing_visual_resource")
	elif not ResourceLoader.exists(visualPath):
		return _failure("missing_visual_resource", visualPath)

	var terrainResult := _terrainDefinitions(raw.get("TERRAIN_DEFINITIONS"))
	if not terrainResult["success"]:
		return terrainResult
	var terrainDefinitions: Dictionary = terrainResult["value"]
	var defaultValue = raw.get("DEFAULT_SURFACE")
	if not defaultValue is Dictionary:
		return _failure("invalid_default_surface")
	var defaultSurfaceResult := _surface(defaultValue, terrainDefinitions)
	if not defaultSurfaceResult["success"]:
		return defaultSurfaceResult

	var maskValue = raw.get("VALID_MASK")
	if not maskValue is Array or maskValue.size() != boardSize.y:
		return _failure("malformed_valid_mask")
	var validCells: Array[Vector2i] = []
	var cellData: Dictionary = {}
	for y in range(boardSize.y):
		if not maskValue[y] is String or str(maskValue[y]).length() != boardSize.x:
			return _failure("malformed_valid_mask")
		for x in range(boardSize.x):
			var marker := str(maskValue[y]).substr(x, 1)
			if marker not in ["0", "1"]:
				return _failure("malformed_valid_mask")
			if marker == "1":
				var cell := Vector2i(x, y)
				validCells.append(cell)
				cellData[cell] = defaultSurfaceResult["value"].duplicate(true)
	if validCells.is_empty():
		return _failure("empty_valid_mask")

	var overridesValue = raw.get("CELL_OVERRIDES", [])
	if not overridesValue is Array:
		return _failure("invalid_cell_overrides")
	var overridden: Dictionary = {}
	for overrideValue in overridesValue:
		if not overrideValue is Dictionary:
			return _failure("invalid_cell_override")
		var override: Dictionary = overrideValue
		if override.has("SURFACES") or override.has("DECKS"):
			return _failure("unsupported_stacked_surfaces")
		var cellResult := _vectorPair(override.get("CELL"), "invalid_override_cell")
		if not cellResult["success"]:
			return cellResult
		var cell: Vector2i = cellResult["value"]
		if not cellData.has(cell):
			return _failure("override_outside_valid_mask", str(cell))
		if overridden.has(cell):
			return _failure("duplicate_cell_override", str(cell))
		overridden[cell] = true
		var current: Dictionary = cellData[cell]
		var merged: Dictionary = {
			"TERRAIN": current["terrain"],
			"ELEVATION": current["height"],
		}
		if current.has("movement_cost"):
			merged["MOVEMENT_COST"] = current["movement_cost"]
		for key in ["TERRAIN", "ELEVATION", "MOVEMENT_COST"]:
			if override.has(key):
				merged[key] = override[key]
		var surfaceResult := _surface(merged, terrainDefinitions)
		if not surfaceResult["success"]:
			return surfaceResult
		cellData[cell] = surfaceResult["value"]

	var revisionResult := _positiveInteger(raw.get("REVISION", 1))
	if not revisionResult["success"]:
		return _failure("invalid_map_revision")
	var definition = BattleMapDefinitionScript.new()
	definition.formatVersion = FORMAT_VERSION
	definition.mapID = mapID
	definition.revision = int(revisionResult["value"])
	definition.gridKind = GRID_KIND
	definition.coordinateConvention = COORDINATES
	definition.boardSize = boardSize
	definition.cellWidth = float(metrics["WIDTH"])
	definition.cellHeight = float(metrics["HEIGHT"])
	definition.heightStep = float(metrics["HEIGHT_STEP"])
	definition.sourceID = sourceID
	definition.sourceRevision = int(sourceRevisionResult["value"])
	definition.sourceFingerprint = fingerprint
	definition.visualScenePath = visualPath
	definition.headlessOnly = headlessOnly
	definition.terrainDefinitions = terrainDefinitions
	definition.sourceData = raw
	definition.configureCells(validCells, cellData)
	return {"success": true, "definition": definition, "error": ""}


static func _terrainDefinitions(value) -> Dictionary:
	if not value is Array or value.is_empty():
		return _failure("invalid_terrain_definitions")
	var result: Dictionary = {}
	for entryValue in value:
		if not entryValue is Dictionary:
			return _failure("invalid_terrain_definition")
		var entry: Dictionary = entryValue
		var terrainID := str(entry.get("ID", ""))
		if terrainID.is_empty() or result.has(terrainID):
			return _failure("duplicate_or_missing_terrain_id", terrainID)
		for key in ["CAN_ENTER", "CAN_PASS", "CAN_STOP", "ENDS_MOVEMENT", "BLOCKS_LOS"]:
			if not entry.get(key) is bool:
				return _failure("invalid_terrain_definition", "%s.%s" % [terrainID, key])
		var costResult := _nonnegativeInteger(entry.get("MOVE_COST"))
		var stateCodeResult := _nonnegativeInteger(entry.get("STATE_CODE"))
		if not costResult["success"] or not stateCodeResult["success"]:
			return _failure("invalid_terrain_definition", terrainID)
		var canEnter := bool(entry["CAN_ENTER"])
		if (bool(entry["CAN_PASS"]) or bool(entry["CAN_STOP"])) and not canEnter:
			return _failure("invalid_terrain_invariants", terrainID)
		if (canEnter and int(costResult["value"]) <= 0) or (not canEnter and int(costResult["value"]) != 0):
			return _failure("invalid_terrain_cost", terrainID)
		result[terrainID] = {
			"traversable": canEnter,
			"passable": bool(entry["CAN_PASS"]),
			"stoppable": bool(entry["CAN_STOP"]),
			"movement_cost": int(costResult["value"]),
			"ends_movement": bool(entry["ENDS_MOVEMENT"]),
			"blocks_los": bool(entry["BLOCKS_LOS"]),
			"state_code": int(stateCodeResult["value"]),
		}
	return {"success": true, "value": result, "error": ""}


static func _surface(value: Dictionary, terrainDefinitions: Dictionary) -> Dictionary:
	var terrainID := str(value.get("TERRAIN", ""))
	if not terrainDefinitions.has(terrainID):
		return _failure("unknown_terrain", terrainID)
	var elevationResult := _nonnegativeInteger(value.get("ELEVATION"))
	if not elevationResult["success"] or int(elevationResult["value"]) > MAX_HEIGHT:
		return _failure("invalid_elevation")
	var normalized := {
		"terrain": terrainID,
		"height": int(elevationResult["value"]),
	}
	if value.has("MOVEMENT_COST"):
		var costResult := _positiveInteger(value["MOVEMENT_COST"])
		if not costResult["success"] or not bool(terrainDefinitions[terrainID]["traversable"]):
			return _failure("invalid_movement_cost_override")
		normalized["movement_cost"] = int(costResult["value"])
	return {"success": true, "value": normalized, "error": ""}


static func _vectorPair(value, errorCode: String) -> Dictionary:
	if not value is Array or value.size() != 2:
		return _failure(errorCode)
	var xResult := _nonnegativeInteger(value[0])
	var yResult := _nonnegativeInteger(value[1])
	if not xResult["success"] or not yResult["success"]:
		return _failure(errorCode)
	return {"success": true, "value": Vector2i(int(xResult["value"]), int(yResult["value"])), "error": ""}


static func _positiveInteger(value) -> Dictionary:
	var result := _nonnegativeInteger(value)
	if not result["success"] or int(result["value"]) <= 0:
		return _failure("invalid_positive_integer")
	return result


static func _nonnegativeInteger(value) -> Dictionary:
	if not (value is int or value is float):
		return _failure("invalid_integer")
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number != floor(number):
		return _failure("invalid_integer")
	return {"success": true, "value": int(number), "error": ""}


static func _validFingerprint(value: String) -> bool:
	if not value.begins_with("sha256:") or value.length() != 71:
		return false
	for character in value.substr(7):
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _failure(code: String, detail: String = "") -> Dictionary:
	return {"success": false, "definition": null, "error": code, "detail": detail}
