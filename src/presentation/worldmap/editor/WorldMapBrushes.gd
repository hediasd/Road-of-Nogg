## Deterministic ground/detail brushes over WorldMapTileData.
##
## Geometry is computed here and mutations always pass through WorldMapEditHistory. The editor
## controller owns pointer gestures; this class owns what a point, rectangle, line, fill, stamp,
## scatter, or replace operation means. Keeping those halves apart lets the probe exercise every
## brush without a viewport and keeps one drag equal to one history command.
##
## HEX MAPS (WMH-4). `point`, `floodFill`, `eyedropper`, `randomFromSet` and `replaceAllOfKind`
## are already layout-agnostic -- they only ever reason about individual OFFSET cells or a raw
## `Rect2i` of them, and offset storage is a plain `cols x rows` rectangle whether the cells it
## holds are square or hex (see `WorldMapHexGrid`'s own header). Three tools are not, because
## their geometry is genuinely different on a hex lattice, and each says why at its definition:
## `line` (no diagonal on a hex, so no Bresenham), `rectangle` (a hex disc instead --
## see `disc`/`discCells`, what the editor UI calls RANGE), and `stamp` (offset deltas are not
## translation-invariant across a hex parity boundary -- see `stampHex`).

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


## SQUARE MAPS ONLY. A rectangle has no natural hex meaning -- a parallelogram in axial space
## looks skewed on screen -- so a hex map's equivalent area tool is `disc`, not this.
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


## The hex counterpart to `rectangle` -- what the editor UI calls RANGE. A disc of `radius` steps
## (in `WorldMapHexGrid.distance()` terms) around `centre`, which is what a user drawing on hexes
## expects an area tool to mean, where a rectangle or a parallelogram in axial space is not.
static func disc(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	centre: Vector2i, radius: int, tileID: String
) -> bool:
	return _applyCells(data, history, layerID, discCells(centre, radius), tileID)


## Standard cube-space disc enumeration: every axial offset `(dq, dr)` within `radius` steps of
## the centre, converted back to offset. Every cell this returns is exactly `WorldMapHexGrid.
## distance(centre, cell) <= radius` by construction, not by a separate filter pass.
static func discCells(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if radius < 0:
		return result
	var axialCentre := WorldMapHexGrid.offsetToAxial(centre)
	for dq in range(-radius, radius + 1):
		var rLow := maxi(-radius, -dq - radius)
		var rHigh := mini(radius, -dq + radius)
		for dr in range(rLow, rHigh + 1):
			result.append(WorldMapHexGrid.axialToOffset(axialCentre + Vector2i(dq, dr)))
	return result


static func line(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	from: Vector2i, to: Vector2i, tileID: String
) -> bool:
	var hex := data.layout == WorldMapTileData.LAYOUT_HEX_FLAT
	return _applyCells(data, history, layerID, lineCells(from, to, hex), tileID)


## Integer Bresenham, inclusive at both ends and identical in every octant. `hex` switches to a
## cube lerp instead: a hex has no diagonal neighbour the way a square does, so there is no
## "closest in each of two axes" step for Bresenham to generalise to, and the standard technique
## is instead to lerp the two endpoints' CUBE coordinates and round each of `WorldMapHexGrid.
## distance()` evenly-spaced samples -- the same cube rounding `WorldMapHexGrid.worldToCell` uses,
## reused here rather than re-derived, so a line and a pick agree on what "nearest hex" means.
static func lineCells(from: Vector2i, to: Vector2i, hex := false) -> Array[Vector2i]:
	if hex:
		return _hexLineCells(from, to)
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


static func _hexLineCells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var steps := WorldMapHexGrid.distance(from, to)
	if steps == 0:
		return [from]
	var a := WorldMapHexGrid.offsetToAxial(from)
	var b := WorldMapHexGrid.offsetToAxial(to)
	var result: Array[Vector2i] = []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var qf: float = lerp(float(a.x), float(b.x), t)
		var rf: float = lerp(float(a.y), float(b.y), t)
		result.append(WorldMapHexGrid.axialToOffset(WorldMapHexGrid.roundAxial(qf, rf)))
	return result


static func floodFill(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	start: Vector2i, tileID: String
) -> bool:
	var original := data.getCell(layerID, start)
	if original == tileID or not _inBounds(data, layerID, start):
		return false
	return _applyCells(data, history, layerID, floodCells(data, layerID, start), tileID)


## `data.layout` picks the neighbour set: 4 cardinal directions on a square map, the 6 the hex
## has instead -- via `WorldMapHexGrid.neighbours()`, so this does not re-derive hex adjacency --
## on a hex one. Hexes have no diagonal neighbours at all, which is why hex adjacency has none of
## the corner ambiguity a square flood fill has to define away.
static func floodCells(
	data: WorldMapTileData, layerID: String, start: Vector2i
) -> Array[Vector2i]:
	if not _inBounds(data, layerID, start):
		return []
	var original := data.getCell(layerID, start)
	var pending: Array[Vector2i] = [start]
	var visited := {start: true}
	var cells: Array[Vector2i] = []
	var hex := data.layout == WorldMapTileData.LAYOUT_HEX_FLAT
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if data.getCell(layerID, cell) != original:
			continue
		cells.append(cell)
		var candidates: Array[Vector2i]
		if hex:
			candidates = WorldMapHexGrid.neighbours(cell)
		else:
			candidates = [
				cell + Vector2i.LEFT, cell + Vector2i.RIGHT,
				cell + Vector2i.UP, cell + Vector2i.DOWN,
			]
		for neighbour in candidates:
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


## The hex counterpart to `stamp`. `pattern` maps an AXIAL offset from `origin` (a `Vector2i` of
## `(dq, dr)`) to a tile id; a key simply absent from the dictionary is a hole, matching `stamp`'s
## own `null`-skips convention.
##
## AXIAL, NOT A ROW/COL ARRAY, and this is the one place in the file that matters most: a stamp is
## meant to be orientation-stable, the same shape wherever it lands, but offset addition is NOT
## translation-invariant across a hex parity boundary -- the same `(dx, dy)` delta lands on a
## different relative hex depending on whether the anchor sits on an odd or even column. Axial
## addition has no such seam, which is the entire reason `WorldMapHexGrid` keeps axial as ITS
## maths space even though it stores offset -- see that file's own header.
static func stampHex(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	origin: Vector2i, pattern: Dictionary
) -> bool:
	var anchor := WorldMapHexGrid.offsetToAxial(origin)
	history.beginStroke(layerID)
	for delta in pattern:
		var cell := WorldMapHexGrid.axialToOffset(anchor + (delta as Vector2i))
		history.paintCell(data, cell, str(pattern[delta]))
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


## Paints one triangular detail slot (WMH-10), through the history like every other brush here.
##
## WMH-10 shipped this as `(data, layerID, cell, index, tileID)` -- a direct mutator with no undo
## -- because its Touches list did not include `WorldMapEditHistory.gd`, and it said so rather
## than hiding it. WMH-10B gave the detail slots a tool a person can reach, which turned that
## named gap into a defect, so the signature is now the same `(data, history, layerID, ...)`
## shape as its siblings and the anomaly is gone.
##
## One slot per call rather than a cell list: a detail gesture selects a triangle, not a set of
## cells, so there is no shape here for `_applyCells` to fill. The stroke is opened and closed by
## the caller, which is what lets a drag across twenty triangles undo as one edit.
static func paintTriangle(
	data: WorldMapTileData, history: WorldMapEditHistory, layerID: String,
	cell: Vector2i, triangleIndex: int, tileID: String
) -> bool:
	return history.paintDetail(data, cell, triangleIndex, tileID)


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
