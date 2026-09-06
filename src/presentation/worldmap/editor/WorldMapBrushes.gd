## Deterministic ground/detail brushes over WorldMapTileData.
##
## Geometry is computed here and mutations always pass through WorldMapEditHistory. The editor
## controller owns pointer gestures; this class owns what a point, rectangle, line, fill, stamp,
## scatter, or replace operation means. Keeping those halves apart lets the probe exercise every
## brush without a viewport and keeps one drag equal to one history command.

class_name WorldMapBrushes
extends RefCounted


static func beginStroke(history: WorldMapEditHistory, layerID: String) -> void:
	history.beginStroke(layerID)


static func paintPoint(
	data: WorldMapTileData, history: WorldMapEditHistory, cell: Vector2i, tileID: String
) -> bool:
	return history.paintCell(data, cell, tileID)


static func endStroke(history: WorldMapEditHistory) -> bool:
	return history.endStroke()


static func point(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	cell: Vector2i, tileID: String
) -> bool:
	return _applyCells(data, history, layerID, [cell], tileID)


static func rectangle(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	from: Vector2i, to: Vector2i, tileID: String
) -> bool:
	return _applyCells(data, history, layerID, rectangleCells(from, to), tileID)


static func rectangleCells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var first := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var last := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y))
	var result: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			result.append(Vector2i(x, y))
	return result


static func line(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	from: Vector2i, to: Vector2i, tileID: String
) -> bool:
	return _applyCells(data, history, layerID, lineCells(from, to), tileID)


## Integer Bresenham, inclusive at both ends and identical in every octant.
static func lineCells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var current := from
	var dx := absi(to.x - from.x)
	var sx := 1 if from.x < to.x else -1
	var dy := -absi(to.y - from.y)
	var sy := 1 if from.y < to.y else -1
	var error := dx + dy
	while true:
		result.append(current)
		if current == to:
			break
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			current.x += sx
		if doubled <= dx:
			error += dx
			current.y += sy
	return result


static func floodFill(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	start: Vector2i, tileID: String
) -> bool:
	var original := data.getCell(layerID, start)
	if original == tileID or not _inBounds(data, layerID, start):
		return false
	return _applyCells(data, history, layerID, floodCells(data, layerID, start), tileID)


static func floodCells(
	data: WorldMapTileData, layerID: String, start: Vector2i
) -> Array[Vector2i]:
	if not _inBounds(data, layerID, start):
		return []
	var original := data.getCell(layerID, start)
	var pending: Array[Vector2i] = [start]
	var visited := {start: true}
	var cells: Array[Vector2i] = []
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if data.getCell(layerID, cell) != original:
			continue
		cells.append(cell)
		for neighbour in [
			cell + Vector2i.LEFT, cell + Vector2i.RIGHT,
			cell + Vector2i.UP, cell + Vector2i.DOWN,
		]:
			if _inBounds(data, layerID, neighbour) and not visited.has(neighbour):
				visited[neighbour] = true
				pending.append(neighbour)
	return cells


## `pattern` is an array of rows. EMPTY entries erase; callers that want transparent stamp
## holes can omit positions by using null instead.
static func stamp(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	origin: Vector2i, pattern: Array
) -> bool:
	history.beginStroke(layerID)
	for y in pattern.size():
		var row = pattern[y]
		if not row is Array and not row is PackedStringArray:
			continue
		for x in row.size():
			if row[x] == null:
				continue
			history.paintCell(data, origin + Vector2i(x, y), str(row[x]))
	return history.endStroke()


## Deterministic scatter. The chosen tile ids are persisted in the map, so a later bake does
## not draw randomness again. Supplying the same seed, rect, and ordered id list reproduces the
## exact edit; the controller exposes the seed instead of consulting the system clock.
static func randomFromSet(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	rect: Rect2i, tileIDs: Array[String], seed: int
) -> bool:
	if tileIDs.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	history.beginStroke(layerID)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var chosen: String = tileIDs[rng.randi_range(0, tileIDs.size() - 1)]
			history.paintCell(data, Vector2i(x, y), chosen)
	return history.endStroke()


## Replaces every cell with the source tile's terrain class. Bootstrap sheets have no terrain
## metadata yet; in that case this degrades honestly to replacing the exact source id.
static func replaceAllOfKind(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	sourceTileID: String, replacementTileID: String, terrainByID: Dictionary = {}
) -> bool:
	var sourceKind := str(terrainByID.get(sourceTileID, ""))
	var cells: Array[Vector2i] = []
	var size := data.layerSize(layerID)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var existing := data.getCell(layerID, cell)
			var matches := existing == sourceTileID if sourceKind.is_empty() else str(terrainByID.get(existing, "")) == sourceKind
			if matches:
				cells.append(cell)
	return _applyCells(data, history, layerID, cells, replacementTileID)


static func eyedropper(data: WorldMapTileData, layerID: String, cell: Vector2i) -> String:
	return data.getCell(layerID, cell)


static func _applyCells(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	cells: Array[Vector2i], tileID: String
) -> bool:
	history.beginStroke(layerID)
	for cell in cells:
		history.paintCell(data, cell, tileID)
	return history.endStroke()


static func _inBounds(data: WorldMapTileData, layerID: String, cell: Vector2i) -> bool:
	var size := data.layerSize(layerID)
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y
