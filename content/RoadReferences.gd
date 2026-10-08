## Loads and validates the road catalog, `data/roads.json`.
##
## A road is authored data: where it lies on the world map, the company that walks it, and the
## stops along it, each a battle on a committed battle map against authored enemy parties. This
## file turns one record into a normalized Dictionary and refuses anything a battle could not be
## built from -- an unknown monster, a cell the map cannot stand a unit on, two units on one cell
## -- so a bad record fails when the road is opened, never halfway through a battle.
##
## Every validated road has this shape (keys lowercase, values typed):
##   name, revision, title, region, seed, start: Vector2, field_size,
##   company: Array[String] (monster names), fielded: Array[int], commander: int,
##   stops: Array of {id, title, position: Vector2, map_path, player_cells: Array[Vector2i],
##                    enemies: Array of {commander: int, members: Array of {monster, level, cell}}}
##
## Headless: reads data and battle maps through `content/`, never presentation.

extends RefCounted

const JSON_PATH := "res://data/roads.json"
const FORMAT_VERSION := 1
const JsonCatalogLoaderScript = preload("res://content/JsonCatalogLoader.gd")
const BattleMapFactoryScript = preload("res://content/BattleMapFactory.gd")
const MonsterReferencesScript = preload("res://content/MonsterReferences.gd")


static func names(path: String = JSON_PATH) -> Array[String]:
	var found: Array[String] = []
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if loaded["success"]:
		for entry: Dictionary in loaded["list"]:
			found.append(str(entry["NAME"]))
	return found


## `{success, road, error}`. `road` is the normalized shape described above.
static func loadRoad(roadName: String, path: String = JSON_PATH) -> Dictionary:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _failure("road catalog unreadable: %s" % str(loaded["error"]))
	var index: Dictionary = loaded["index"]
	if not index.has(roadName):
		return _failure("no road named '%s' in %s" % [roadName, path])
	return fromDictionary(index[roadName])


static func fromDictionary(raw: Dictionary) -> Dictionary:
	var roadName := str(raw.get("NAME", ""))
	if roadName.is_empty():
		return _failure("road has no NAME")
	if not _isInteger(raw.get("FORMAT_VERSION")) or int(raw["FORMAT_VERSION"]) != FORMAT_VERSION:
		return _failure("road '%s': unsupported FORMAT_VERSION" % roadName)
	if not _isInteger(raw.get("REVISION")) or int(raw["REVISION"]) < 1:
		return _failure("road '%s': REVISION must be a positive integer" % roadName)
	if not _isInteger(raw.get("SEED")) or int(raw["SEED"]) < 0:
		return _failure("road '%s': SEED must be a non-negative integer" % roadName)
	var region := str(raw.get("REGION", ""))
	if region.is_empty():
		return _failure("road '%s': REGION is empty" % roadName)
	var start = _vector2(raw.get("START"))
	if start == null:
		return _failure("road '%s': START must be [x, z]" % roadName)
	if not _isInteger(raw.get("FIELD_SIZE")) or int(raw["FIELD_SIZE"]) < 1:
		return _failure("road '%s': FIELD_SIZE must be a positive integer" % roadName)
	var fieldSize := int(raw["FIELD_SIZE"])

	var company: Array[String] = []
	var companyValue = raw.get("COMPANY")
	if not companyValue is Array or (companyValue as Array).is_empty():
		return _failure("road '%s': COMPANY is empty" % roadName)
	for entry in companyValue:
		var monsterName := str((entry as Dictionary).get("MONSTER", "")) if entry is Dictionary else ""
		if not MonsterReferencesScript.hasReference(monsterName):
			return _failure("road '%s': unknown company monster '%s'" % [roadName, monsterName])
		company.append(monsterName)

	var fielded: Array[int] = []
	var fieldedValue = raw.get("FIELDED")
	if not fieldedValue is Array or (fieldedValue as Array).is_empty():
		return _failure("road '%s': FIELDED is empty" % roadName)
	for slot in fieldedValue:
		if not _isInteger(slot) or int(slot) < 0 or int(slot) >= company.size() or fielded.has(int(slot)):
			return _failure("road '%s': FIELDED names an invalid or repeated slot" % roadName)
		fielded.append(int(slot))
	if fielded.size() > fieldSize:
		return _failure("road '%s': FIELDED is larger than FIELD_SIZE" % roadName)
	if not _isInteger(raw.get("COMMANDER")) or not fielded.has(int(raw["COMMANDER"])):
		return _failure("road '%s': COMMANDER must be a fielded slot" % roadName)

	var stops: Array = []
	var stopIDs: Dictionary = {}
	var stopsValue = raw.get("STOPS")
	if not stopsValue is Array or (stopsValue as Array).is_empty():
		return _failure("road '%s': STOPS is empty" % roadName)
	for stopValue in stopsValue:
		if not stopValue is Dictionary:
			return _failure("road '%s': a stop is not a dictionary" % roadName)
		var stop := _stop(stopValue as Dictionary, fieldSize)
		if not stop["success"]:
			return _failure("road '%s': %s" % [roadName, str(stop["error"])])
		var normalized: Dictionary = stop["stop"]
		if stopIDs.has(normalized["id"]):
			return _failure("road '%s': duplicate stop id '%s'" % [roadName, normalized["id"]])
		stopIDs[normalized["id"]] = true
		stops.append(normalized)

	return {"success": true, "error": "", "road": {
		"name": roadName,
		"revision": int(raw["REVISION"]),
		"title": str(raw.get("TITLE", "")),
		"region": region,
		"seed": int(raw["SEED"]),
		"start": start,
		"field_size": fieldSize,
		"company": company,
		"fielded": fielded,
		"commander": int(raw["COMMANDER"]),
		"stops": stops,
	}}


static func _stop(raw: Dictionary, fieldSize: int) -> Dictionary:
	var stopID := str(raw.get("ID", ""))
	if stopID.is_empty():
		return _failure("a stop has no ID")
	var position = _vector2(raw.get("POSITION"))
	if position == null:
		return _failure("stop '%s': POSITION must be [x, z]" % stopID)
	var mapPath := str(raw.get("MAP", ""))
	var mapResult := BattleMapFactoryScript.loadFromPath(mapPath)
	if not mapResult["success"]:
		return _failure("stop '%s': map %s did not load: %s" % [stopID, mapPath, str(mapResult["error"])])
	var definition = mapResult["definition"]

	var occupied: Dictionary = {}
	var playerCells: Array[Vector2i] = []
	var cellsValue = raw.get("PLAYER_CELLS")
	if not cellsValue is Array:
		return _failure("stop '%s': PLAYER_CELLS is missing" % stopID)
	for cellValue in cellsValue:
		var cell = _cell(cellValue)
		var refusal := _cellRefusal(cell, definition, occupied)
		if not refusal.is_empty():
			return _failure("stop '%s': player cell %s %s" % [stopID, str(cellValue), refusal])
		occupied[cell] = true
		playerCells.append(cell)
	if playerCells.size() < fieldSize:
		return _failure("stop '%s': %d player cells for a field of %d" % [stopID, playerCells.size(), fieldSize])

	var enemies: Array = []
	var enemiesValue = raw.get("ENEMIES")
	if not enemiesValue is Array or (enemiesValue as Array).is_empty():
		return _failure("stop '%s': ENEMIES is empty" % stopID)
	for partyValue in enemiesValue:
		if not partyValue is Dictionary:
			return _failure("stop '%s': an enemy party is not a dictionary" % stopID)
		var members: Array = []
		var membersValue = (partyValue as Dictionary).get("MEMBERS")
		if not membersValue is Array or (membersValue as Array).is_empty():
			return _failure("stop '%s': an enemy party has no MEMBERS" % stopID)
		for memberValue in membersValue:
			var member: Dictionary = memberValue if memberValue is Dictionary else {}
			var monsterName := str(member.get("MONSTER", ""))
			if not MonsterReferencesScript.hasReference(monsterName):
				return _failure("stop '%s': unknown enemy monster '%s'" % [stopID, monsterName])
			if not _isInteger(member.get("LEVEL")) or int(member["LEVEL"]) < 1:
				return _failure("stop '%s': %s has no positive LEVEL" % [stopID, monsterName])
			var cell = _cell(member.get("CELL"))
			var refusal := _cellRefusal(cell, definition, occupied)
			if not refusal.is_empty():
				return _failure("stop '%s': %s's cell %s %s" % [stopID, monsterName, str(member.get("CELL")), refusal])
			occupied[cell] = true
			members.append({"monster": monsterName, "level": int(member["LEVEL"]), "cell": cell})
		var commanderValue = (partyValue as Dictionary).get("COMMANDER")
		if not _isInteger(commanderValue) or int(commanderValue) < 0 or int(commanderValue) >= members.size():
			return _failure("stop '%s': an enemy party's COMMANDER is not one of its members" % stopID)
		enemies.append({"commander": int(commanderValue), "members": members})

	return {"success": true, "error": "", "stop": {
		"id": stopID,
		"title": str(raw.get("TITLE", "")),
		"position": position,
		"map_path": mapPath,
		"player_cells": playerCells,
		"enemies": enemies,
	}}


## Empty when a unit may be deployed on `cell`; otherwise why not.
static func _cellRefusal(cell, definition, occupied: Dictionary) -> String:
	if cell == null:
		return "is not [x, y]"
	if not definition.containsCell(cell):
		return "is not on the map"
	if not definition.isStoppable(cell):
		return "cannot hold a unit"
	if occupied.has(cell):
		return "is already taken"
	return ""


static func _cell(value):
	if not value is Array or (value as Array).size() != 2:
		return null
	if not _isInteger(value[0]) or not _isInteger(value[1]):
		return null
	return Vector2i(int(value[0]), int(value[1]))


static func _vector2(value):
	if not value is Array or (value as Array).size() != 2:
		return null
	if not (value[0] is float or value[0] is int) or not (value[1] is float or value[1] is int):
		return null
	return Vector2(float(value[0]), float(value[1]))


## JSON numbers arrive as floats; an integer field must hold a whole number.
static func _isInteger(value) -> bool:
	return (value is int) or (value is float and is_equal_approx(value, roundf(value)))


static func _failure(message: String) -> Dictionary:
	return {"success": false, "error": message, "road": {}}
