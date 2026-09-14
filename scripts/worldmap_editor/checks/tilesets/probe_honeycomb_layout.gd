extends SceneTree

## Bounded check on the `honeycomb` sheet layout: the hex mask tiles with no gap or overlap at the
## 3/4-frame column step, a honeycomb sheet unpacks to an atlas whose cells hash exactly as its
## config ledger records, and a config that omits `LAYOUT` still serialises without the key.

const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const SHEET_ID := "temp2_hex32_starter_v2-Recovered-export"

var failures: Array[String] = []


func _init() -> void:
	_checkMaskTiles()
	_checkSheet()
	_checkGridConfigUnchanged()
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
	_require(tiles.size() == 20 and byCell.size() == 20, "expected 20 tiles, ledger %d, cut %d" % [tiles.size(), byCell.size()])
	for tile in tiles:
		var cell: Vector2i = tile["CELL"]
		_require(str(byCell.get(cell, "")) == str(tile["HASH"]), "%s hash differs after unpacking" % tile["ID"])
	_require(Catalog.serialise(reference).contains("\"LAYOUT\": \"honeycomb\""), "honeycomb LAYOUT not serialised")


func _checkGridConfigUnchanged() -> void:
	var path := Catalog.configPathFor("temp2_hex32_starter")
	var onDisk := FileAccess.get_file_as_string(path)
	_require(Catalog.serialise(Catalog.tilesetFor("temp2_hex32_starter")) == onDisk, "grid config no longer re-saves byte-identical")


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
