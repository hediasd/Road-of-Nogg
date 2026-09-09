extends SceneTree

## Read-only verification of the built temp2_hex32_starter sheet and its
## catalog entry. This never rewrites the catalog or the sheet; a failure here
## means the builder's output disagrees with the documented contract, not that
## this probe should paper over it.

const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

const SHEET_PATH := "res://assets/worldmap/tilesets/temp2_hex32_starter.png"
const CATALOG_PATH := "res://data/worldmap/tilesets.json"
const FRAME_PX := 32
const COLUMNS := 5
const ROWS := 3
const LAND := Color8(0xff, 0xd3, 0x63)
const SEA := Color8(0x37, 0xae, 0xae)
const GRASS := Color8(0xbd, 0xd1, 0x06)
const VERTICES := [Vector2(32, 16), Vector2(24, 32), Vector2(8, 32), Vector2(0, 16), Vector2(8, 0), Vector2(24, 0)]

const COL_STEP := 24
const ROW_STEP := 32
const ODD_DROP := 16
const LATTICE_COLUMNS := 6
const LATTICE_ROWS := 5

var failures: Array[String] = []


func _init() -> void:
	var sheet := Catalog.loadSheetImage(SHEET_PATH)
	if sheet == null:
		printerr("HXW_HEX_STARTER_PROBE_FAILURE: could not load %s" % SHEET_PATH)
		quit(1)
		return
	_checkDimensions(sheet)
	var starterEntry := _loadStarterEntry()
	if starterEntry.is_empty():
		failures.append("catalog is missing the temp2_hex32_starter entry")
	else:
		_checkCatalogEntry(starterEntry)
		_checkTileHashesAndPixels(sheet, starterEntry)
	_checkDonorEntriesUnchanged()
	_checkTessellation()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_HEX_STARTER_PROBE_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP HEX STARTER OK")
	quit(0)


func _checkDimensions(sheet: Image) -> void:
	_require(sheet.get_width() == COLUMNS * FRAME_PX and sheet.get_height() == ROWS * FRAME_PX, "sheet is %dx%d, expected %dx%d" % [sheet.get_width(), sheet.get_height(), COLUMNS * FRAME_PX, ROWS * FRAME_PX])
	_require(sheet.get_format() == Image.FORMAT_RGBA8, "sheet format is not RGBA8")


func _loadStarterEntry() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not raw is Array:
		return {}
	for reference in raw as Array:
		if reference is Dictionary and str((reference as Dictionary).get("NAME", "")) == "temp2_hex32_starter":
			return reference as Dictionary
	return {}


func _checkCatalogEntry(entry: Dictionary) -> void:
	_require(int(entry.get("FRAME_PX", -1)) == FRAME_PX, "FRAME_PX mismatch")
	_require(str(entry.get("GRID_KIND", "")) == "tile", "GRID_KIND mismatch")
	_require(str(entry.get("PALETTE_REGION", "")) == "temp2", "PALETTE_REGION mismatch")
	_require(int(entry.get("NEXT_ID", -1)) == COLUMNS * ROWS, "NEXT_ID mismatch")
	_require(str(entry.get("SHEET", "")) == SHEET_PATH, "SHEET path mismatch")
	var tiles: Array = entry.get("TILES", [])
	_require(tiles.size() == COLUMNS * ROWS, "expected %d tiles, found %d" % [COLUMNS * ROWS, tiles.size()])
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		_require(str(tile.get("ID", "")) == "t%03d" % index, "tile %d has id %s" % [index, str(tile.get("ID", ""))])
		var cell: Array = tile.get("CELL", [])
		_require(cell.size() == 2 and int(cell[0]) == index % COLUMNS and int(cell[1]) == index / COLUMNS, "tile %d has wrong CELL %s" % [index, str(cell)])


func _checkTileHashesAndPixels(sheet: Image, entry: Dictionary) -> void:
	var tiles: Array = entry.get("TILES", [])
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var cell := Vector2i(index % COLUMNS, index / COLUMNS)
		var expectedHash := Catalog.hashCell(sheet, Rect2i(cell * FRAME_PX, Vector2i.ONE * FRAME_PX))
		_require(str(tile.get("HASH", "")) == expectedHash, "tile %d hash does not match its frame pixels" % index)
		_checkFramePixels(sheet, cell, index)


## Independently reconstructs the documented geometry/palette rule (not by
## calling the builder) and compares it pixel-for-pixel against the shipped
## sheet, proving the PNG matches its own written contract.
func _checkFramePixels(sheet: Image, cell: Vector2i, index: int) -> void:
	var fill := LAND
	var edge := Color(0, 0, 0, 0)
	var edgeIndex := -1
	if index == 1:
		fill = SEA
	elif index == 2:
		fill = GRASS
	elif index >= 3 and index <= 8:
		edge = SEA
		edgeIndex = index - 3
	elif index >= 9:
		fill = GRASS
		edge = LAND
		edgeIndex = index - 9
	var origin := cell * FRAME_PX
	for y in FRAME_PX:
		var py := float(y) + 0.5
		var left := 8.0 - py * 0.5 if py <= 16.0 else (py - 16.0) * 0.5
		for x in FRAME_PX:
			var px := float(x) + 0.5
			var actual := sheet.get_pixel(origin.x + x, origin.y + y)
			if px < left or px > 32.0 - left:
				_require(actual.a == 0.0, "frame %d pixel (%d,%d) outside the hex is not transparent" % [index, x, y])
				continue
			_require(actual.a == 1.0, "frame %d pixel (%d,%d) inside the hex is not opaque" % [index, x, y])
			var expected := fill
			if edgeIndex >= 0 and _distanceToEdge(Vector2(px, py), edgeIndex) < 4.0:
				expected = edge
			_require(actual.is_equal_approx(expected), "frame %d pixel (%d,%d) is %s, expected %s" % [index, x, y, actual, expected])


func _distanceToEdge(point: Vector2, edgeIndex: int) -> float:
	var start: Vector2 = VERTICES[edgeIndex]
	var end: Vector2 = VERTICES[(edgeIndex + 1) % VERTICES.size()]
	var line := end - start
	var lengthSquared := line.length_squared()
	var progress := clampf((point - start).dot(line) / lengthSquared, 0.0, 1.0)
	return point.distance_to(start + line * progress)


## The builder must upsert only its own entry. This asserts the two pre-
## existing donor tilesets kept their identity and full tile counts; the
## companion `git diff` (recorded in the commit body) additionally proves
## every other byte of the file, including numeric types, is untouched.
func _checkDonorEntriesUnchanged() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not raw is Array:
		failures.append("could not parse tileset catalog for donor check")
		return
	var expected := {
		"temp2_ground": {"FRAME_PX": 16, "NEXT_ID": 40, "TILES": 40},
		"temp2_hex32_ground": {"FRAME_PX": 32, "NEXT_ID": 75, "TILES": 75},
	}
	var seen: Dictionary = {}
	for reference in raw as Array:
		if not reference is Dictionary:
			continue
		var name := str((reference as Dictionary).get("NAME", ""))
		if expected.has(name):
			seen[name] = true
			var want: Dictionary = expected[name]
			_require(int((reference as Dictionary).get("FRAME_PX", -1)) == int(want["FRAME_PX"]), "%s FRAME_PX changed" % name)
			_require(int((reference as Dictionary).get("NEXT_ID", -1)) == int(want["NEXT_ID"]), "%s NEXT_ID changed" % name)
			var tiles: Array = (reference as Dictionary).get("TILES", [])
			_require(tiles.size() == int(want["TILES"]), "%s TILES count changed" % name)
	for name: String in expected:
		_require(seen.has(name), "donor entry %s is missing" % name)


## Flat-top hexes at this frame size and lattice step must tessellate the
## plane with no gaps or overlaps. Builds a virtual 6x5 composition spanning
## both column parities and asserts every interior pixel is claimed by
## exactly one hex frame, using the same containment rule the sheet was
## painted with.
func _checkTessellation() -> void:
	var origins: Array[Vector2i] = []
	var maxX := 0
	var maxY := 0
	for col in LATTICE_COLUMNS:
		for row in LATTICE_ROWS:
			var origin := Vector2i(col * COL_STEP, row * ROW_STEP + (ODD_DROP if col % 2 == 1 else 0))
			origins.append(origin)
			maxX = max(maxX, origin.x + FRAME_PX)
			maxY = max(maxY, origin.y + FRAME_PX)
	var margin := FRAME_PX
	var checked := 0
	for y in range(margin, maxY - margin):
		for x in range(margin, maxX - margin):
			var coverers := 0
			for origin: Vector2i in origins:
				if _insideHexLocal(x - origin.x, y - origin.y):
					coverers += 1
			checked += 1
			if coverers != 1:
				failures.append("lattice pixel (%d,%d) covered by %d hexes, expected exactly 1" % [x, y, coverers])
				return
	_require(checked > 0, "tessellation check covered no pixels")


func _insideHexLocal(lx: int, ly: int) -> bool:
	if lx < 0 or lx >= FRAME_PX or ly < 0 or ly >= FRAME_PX:
		return false
	var py := float(ly) + 0.5
	var left := 8.0 - py * 0.5 if py <= 16.0 else (py - 16.0) * 0.5
	var px := float(lx) + 0.5
	return px >= left and px <= 32.0 - left


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
