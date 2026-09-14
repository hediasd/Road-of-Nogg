extends SceneTree

## Bounded check on the `honeycomb` sheet layout: the hex mask tiles with no gap or overlap at the
## 3/4-frame column step, the sheet has only outward borders, it unpacks to an atlas whose cells
## hash exactly as its config ledger records, the picker hit-tests it as hexes, and a config that
## omits `LAYOUT` still serialises without the key.

const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const PickerScript = preload("res://src/presentation/worldmap/editor/WorldMapTilesetPicker.gd")
const SHEET_ID := "temp2_hex32_starter_v2-Recovered-export"

var failures: Array[String] = []


func _init() -> void:
	_checkMaskTiles()
	_checkSheet()
	_checkGridConfigUnchanged()
	_checkPicker()
	if failures.is_empty():
		print("WORLD MAP HONEYCOMB LAYOUT OK")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


## Stamps a 4 x 3 honeycomb of masks and requires every pixel of the interior to be covered once.
func _checkMaskTiles() -> void:
	var frame := 32
	var coverage: Dictionary = {}
	for column in 4:
		for row in 3:
			var origin := Vector2i(column * 24, row * frame + (16 if column % 2 == 1 else 0))
			for y in frame:
				for x in frame:
					if Catalog.hexContains(frame, x, y):
						var key := origin + Vector2i(x, y)
						coverage[key] = int(coverage.get(key, 0)) + 1
	for key in coverage:
		_require(int(coverage[key]) == 1, "hex masks overlap at %s" % str(key))
	# Interior: past the first column's left notch and the dropped columns' top and bottom notches.
	for y in range(16, 3 * frame):
		for x in range(16, 3 * 24 + 16):
			_require(coverage.has(Vector2i(x, y)), "gap between hex masks at (%d, %d)" % [x, y])


func _checkSheet() -> void:
	var reference := Catalog.tilesetFor(SHEET_ID)
	_require(str(reference.get("LAYOUT", "")) == Catalog.LAYOUT_HONEYCOMB, "sheet is not honeycomb")
	var atlas := Catalog.loadTilesetImage(reference)
	_require(atlas != null, "sheet did not load")
	if atlas == null:
		return
	var cut := Catalog.cutSheet(atlas, int(reference["FRAME_PX"]))
	var byCell: Dictionary = {}
	for entry in cut["cells"]:
		byCell[(entry as Dictionary)["cell"]] = (entry as Dictionary)["hash"]
	var tiles: Array = reference["TILES"]
	_require(tiles.size() == 22 and byCell.size() == 22, "expected 22 tiles, ledger %d, cut %d" % [tiles.size(), byCell.size()])
	var sheet := Catalog.loadSheetImage(str(reference["SHEET"]))
	_require(sheet.get_size() == Vector2i(128, 160), "5 x 5 honeycomb should be 128 x 160, is %s" % str(sheet.get_size()))
	# Outward borders: the long odd columns reach the sheet's top and bottom edge, the short even
	# columns stop half a frame short of both.
	_require(sheet.get_pixel(40, 0).a > 0.5 and sheet.get_pixel(40, 159).a > 0.5, "odd column 1 does not reach both edges")
	_require(sheet.get_pixel(16, 8).a < 0.5 and sheet.get_pixel(16, 152).a < 0.5, "even column 0 is not recessed at both edges")
	for tile in tiles:
		var cell: Vector2i = tile["CELL"]
		_require(Catalog.honeycombHasSlot(cell), "%s sits in a border slot a honeycomb does not have" % tile["ID"])
		_require(str(byCell.get(cell, "")) == str(tile["HASH"]), "%s hash differs after unpacking" % tile["ID"])
	_require(Catalog.serialise(reference).contains("\"LAYOUT\": \"honeycomb\""), "honeycomb LAYOUT not serialised")


func _checkGridConfigUnchanged() -> void:
	var path := Catalog.configPathFor("temp2_hex32_starter")
	var onDisk := FileAccess.get_file_as_string(path)
	_require(Catalog.serialise(Catalog.tilesetFor("temp2_hex32_starter")) == onDisk, "grid config no longer re-saves byte-identical")


## The picker places and hit-tests honeycomb frames as hexes: a point in a hex's centre picks that
## hex, and a point in the transparent corner of one frame's rect picks the neighbour that fills it.
func _checkPicker() -> void:
	var reference := Catalog.tilesetFor(SHEET_ID)
	var tiles: Array[Dictionary] = []
	var idByCell: Dictionary = {}
	for tile in reference["TILES"]:
		tiles.append(tile as Dictionary)
		idByCell[(tile as Dictionary)["CELL"]] = str((tile as Dictionary)["ID"])
	var picker = PickerScript.new()
	var texture := ImageTexture.create_from_image(Catalog.loadSheetImage(str(reference["SHEET"])))
	picker.configure(SHEET_ID, texture, 32, tiles, Catalog.LAYOUT_HONEYCOMB)
	# Hex (1, 0) spans x 24..55, y 0..31; hex (2, 1) spans x 48..79, y 16..47.
	_require(picker.tileAtSheetPoint(Vector2(40, 16)) == idByCell[Vector2i(1, 0)], "centre of hex (1, 0) did not pick it")
	_require(picker.tileAtSheetPoint(Vector2(64, 32)) == idByCell[Vector2i(2, 1)], "centre of hex (2, 1) did not pick it")
	_require(picker.tileAtSheetPoint(Vector2(54, 30)) == idByCell[Vector2i(2, 1)], "corner of (1, 0)'s rect did not pick neighbour (2, 1)")
	_require(picker.tileAtSheetPoint(Vector2(4, 4)) == "", "the recessed top-left corner picked a tile")
	picker.free()


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
