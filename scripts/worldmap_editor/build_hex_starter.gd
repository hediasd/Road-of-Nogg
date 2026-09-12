extends SceneTree

## Rebuilds the small, deliberately manual hex starter sheet. This is not an
## importer: its output is a stable authored example with a fixed id ledger.

const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

const SHEET_PATH := "res://assets/worldmap/tilesets/temp2_hex32_starter.png"
const GUIDE_PATH := "res://assets/worldmap/tilesets/templates/hex32_guides.svg"
const CATALOG_PATH := "res://data/worldmap/tilesets.json"
const REGION_PATH := "res://assets/worldmap/regions/temp2.png"
const FRAME_PX := 32
const COLUMNS := 5
const ROWS := 3
const PALETTE_COUNTS := {
	"ffd363": 11569,
	"37aeae": 27200,
	"bdd106": 3654,
}
const LAND := Color8(0xff, 0xd3, 0x63)
const SEA := Color8(0x37, 0xae, 0xae)
const GRASS := Color8(0xbd, 0xd1, 0x06)
const VERTICES := [Vector2(32, 16), Vector2(24, 32), Vector2(8, 32), Vector2(0, 16), Vector2(8, 0), Vector2(24, 0)]
const EDGE_NAMES := ["lower-right", "bottom", "lower-left", "upper-left", "top", "upper-right"]


func _init() -> void:
	if not _verifyPalette():
		quit(1)
		return
	var sheet := _buildSheet()
	if sheet.save_png(SHEET_PATH) != OK:
		_fail("could not save %s" % SHEET_PATH)
		quit(1)
		return
	if not _writeText(GUIDE_PATH, _guideText()):
		quit(1)
		return
	if not _upsertCatalog(sheet):
		quit(1)
		return
	print("WORLD MAP HEX STARTER BUILT")
	quit(0)


func _verifyPalette() -> bool:
	var region := Catalog.loadSheetImage(REGION_PATH)
	if region == null:
		_fail("could not read palette region %s" % REGION_PATH)
		return false
	var counts := {"ffd363": 0, "37aeae": 0, "bdd106": 0}
	for y in region.get_height():
		for x in region.get_width():
			var key := "%02x%02x%02x" % [
				int(round(region.get_pixel(x, y).r * 255.0)),
				int(round(region.get_pixel(x, y).g * 255.0)),
				int(round(region.get_pixel(x, y).b * 255.0)),
			]
			if counts.has(key):
				counts[key] = int(counts[key]) + 1
	for key: String in PALETTE_COUNTS:
		var actual := int(counts[key])
		var expected := int(PALETTE_COUNTS[key])
		if actual != expected:
			_fail("temp2 palette #%s measured %d (expected %d; difference %+d)" % [key, actual, expected, actual - expected])
			return false
	return true


func _buildSheet() -> Image:
	var image := Image.create(COLUMNS * FRAME_PX, ROWS * FRAME_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for index in COLUMNS * ROWS:
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
		_paintHex(image, Vector2i((index % COLUMNS) * FRAME_PX, (index / COLUMNS) * FRAME_PX), fill, edge, edgeIndex)
	return image


func _paintHex(image: Image, origin: Vector2i, fill: Color, edge: Color, edgeIndex: int) -> void:
	for y in FRAME_PX:
		var py := float(y) + 0.5
		var left := 8.0 - py * 0.5 if py <= 16.0 else (py - 16.0) * 0.5
		for x in FRAME_PX:
			var px := float(x) + 0.5
			if px < left or px > 32.0 - left:
				continue
			var colour := fill
			if edgeIndex >= 0 and _distanceToEdge(Vector2(px, py), edgeIndex) < 4.0:
				colour = edge
			image.set_pixelv(origin + Vector2i(x, y), colour)


func _distanceToEdge(point: Vector2, edgeIndex: int) -> float:
	var start: Vector2 = VERTICES[edgeIndex]
	var end: Vector2 = VERTICES[(edgeIndex + 1) % VERTICES.size()]
	var line := end - start
	var lengthSquared := line.length_squared()
	var progress := clampf((point - start).dot(line) / lengthSquared, 0.0, 1.0)
	return point.distance_to(start + line * progress)


## Only this rebuild's own entry may be replaced. `JSON.parse_string()` always
## returns floats for every JSON number (there is no int/float distinction in
## the JSON spec), so round-tripping donor entries through parse+stringify
## would silently rewrite their ints (e.g. `"FRAME_PX": 16`) as floats
## (`16.0`). Parsing is therefore read-only here, used only to locate the
## existing entry (if any) and to validate structure; writing splices this
## rebuild's freshly-typed dictionary into the raw source text so every other
## byte of every other entry is left untouched.
func _upsertCatalog(sheet: Image) -> bool:
	var source := FileAccess.get_file_as_string(CATALOG_PATH)
	var raw = JSON.parse_string(source)
	if not raw is Array:
		_fail("could not parse tileset catalog")
		return false
	var spans := _topLevelObjectSpans(source)
	if spans.size() != (raw as Array).size():
		_fail("tileset catalog text did not match its parsed structure")
		return false
	var tiles: Array = []
	for index in COLUMNS * ROWS:
		var edgeIndex := index - 3 if index >= 3 and index <= 8 else index - 9 if index >= 9 else -1
		var terrain := "land" if index == 0 or (index >= 3 and index <= 8) else "sea" if index == 1 else "grass"
		var border := "sea" if index >= 3 and index <= 8 else "land"
		var variant := "base" if edgeIndex < 0 else "%s_edge_%d" % [border, edgeIndex]
		var label := terrain.capitalize() if edgeIndex < 0 else "%s with %s %s edge" % [terrain.capitalize(), border, EDGE_NAMES[edgeIndex]]
		var cell := Vector2i(index % COLUMNS, index / COLUMNS)
		# FHB-2: authored here rather than left blank, per this field's own reservation note in
		# `WorldMapTilesetCatalog._normaliseTiles()` -- "authoring them from the first import costs
		# a default and saves that". The only unwalkable frame is the one whose whole 32 px is sea
		# (index 1); every land and grass frame is walkable, including the sea-bordered edge
		# variants (index 3-8 border land, 9-14 border grass), because their standable area is the
		# land or grass half, not the border.
		var walkable := "false" if terrain == "sea" else "true"
		tiles.append({
			"AUTOTILE": "",
			"CELL": [cell.x, cell.y],
			"HASH": Catalog.hashCell(sheet, Rect2i(cell * FRAME_PX, Vector2i.ONE * FRAME_PX)),
			"ID": "t%03d" % index,
			"LABEL": label,
			"LIFTABLE": false,
			"TERRAIN": terrain,
			"VARIANT": variant,
			"WALKABLE": walkable,
		})
	var starter := {
		"DESCRIPTION": "A clean 15-frame flat-top hex starter at 32 px. It uses the verified temp2 land, sea and grass colours as manual base and edge examples; it is not a complete autotile or Wang set. Frames are 5 columns by 3 rows with zero margin and spacing, and transparent corners preserve the project’s stretched 32 px flat-top geometry.",
		"FRAME_PX": FRAME_PX,
		"GRID_KIND": "tile",
		"NAME": "temp2_hex32_starter",
		"NEXT_ID": 15,
		"PALETTE_REGION": "temp2",
		"SHEET": SHEET_PATH,
		"TILES": tiles,
	}
	var catalog: Array = raw
	var existingIndex := -1
	for index in catalog.size():
		var reference = catalog[index]
		if reference is Dictionary and str((reference as Dictionary).get("NAME", "")) == "temp2_hex32_starter":
			existingIndex = index
			break
	var entryText := _indentEntryLines(JSON.stringify(starter, "\t"))
	var newSource: String
	if existingIndex >= 0:
		var span: Vector2i = spans[existingIndex]
		newSource = source.substr(0, span.x) + entryText + source.substr(span.y)
	else:
		var insertPos: int = spans[spans.size() - 1].y
		newSource = source.substr(0, insertPos) + ",\n\t" + entryText + source.substr(insertPos)
	return _writeText(CATALOG_PATH, newSource)


## Prefixes every line but the first with one tab, so a standalone
## `JSON.stringify(dict, "\t")` (which starts at column 0) matches the one
## extra indent level every entry has as an element of the top-level array.
func _indentEntryLines(text: String) -> String:
	var lines := text.split("\n")
	for index in range(1, lines.size()):
		lines[index] = "\t" + lines[index]
	return "\n".join(lines)


## Returns the (start, end) byte spans of each brace-balanced object that is a
## direct element of the outer array, ignoring braces inside quoted strings.
## Depth returning to zero marks the end of a top-level object regardless of
## how deeply its own fields (e.g. TILES) nest further braces.
func _topLevelObjectSpans(text: String) -> Array:
	var spans: Array = []
	var depth := 0
	var inString := false
	var escaped := false
	var objectStart := -1
	for i in text.length():
		var ch := text[i]
		if inString:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				inString = false
			continue
		if ch == "\"":
			inString = true
		elif ch == "{":
			if depth == 0:
				objectStart = i
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				spans.append(Vector2i(objectStart, i + 1))
	return spans


func _writeText(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not open %s for writing" % path)
		return false
	file.store_string(text)
	file.close()
	return true


func _guideText() -> String:
	return """<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"160\" height=\"96\" viewBox=\"0 0 160 96\">
  <title>Road of Nogg 32 px flat-top hex starter guides</title>
  <desc>Guide only. Hide the guides group before exporting art; it is not part of the PNG.</desc>
  <g id=\"guides\" fill=\"none\" stroke=\"#ff00ff\" stroke-width=\"1\" opacity=\"0.75\">
    <path d=\"M0 0H160M0 32H160M0 64H160M0 96H160M0 0V96M32 0V96M64 0V96M96 0V96M128 0V96M160 0V96\"/>
    <g id=\"hex-polygons\">
      <path d=\"M32 16L24 32H8L0 16L8 0H24Z M64 16L56 32H40L32 16L40 0H56Z M96 16L88 32H72L64 16L72 0H88Z M128 16L120 32H104L96 16L104 0H120Z M160 16L152 32H136L128 16L136 0H152Z\"/>
      <path d=\"M32 48L24 64H8L0 48L8 32H24Z M64 48L56 64H40L32 48L40 32H56Z M96 48L88 64H72L64 48L72 32H88Z M128 48L120 64H104L96 48L104 32H120Z M160 48L152 64H136L128 48L136 32H152Z\"/>
      <path d=\"M32 80L24 96H8L0 80L8 64H24Z M64 80L56 96H40L32 80L40 64H56Z M96 80L88 96H72L64 80L72 64H88Z M128 80L120 96H104L96 80L104 64H120Z M160 80L152 96H136L128 80L136 64H152Z\"/>
    </g>
    <g id=\"centres\"><path d=\"M16 13V19M13 16H19M48 13V19M45 16H51M80 13V19M77 16H83M112 13V19M109 16H115M144 13V19M141 16H147M16 45V51M13 48H19M48 45V51M45 48H51M80 45V51M77 48H83M112 45V51M109 48H115M144 45V51M141 48H147M16 77V83M13 80H19M48 77V83M45 80H51M80 77V83M77 80H83M112 77V83M109 80H115M144 77V83M141 80H147\"/></g>
  </g>
</svg>
"""


func _fail(message: String) -> void:
	printerr("HXW_HEX_STARTER_FAILURE: %s" % message)
