extends SceneTree

## Bounded check on the hex map's outward-border rule: row 0 of every even column is not part of
## the lattice. Nothing can be painted there, a file that carries paint there opens with it
## cleared and counted, the ground mesh has no surface there, the battle export masks it out, and
## every size the New Map dialog offers has an odd column count.

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const TacticalLayer = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")

var failures: Array[String] = []


func _init() -> void:
	_checkLattice()
	_checkPaintAndLoad()
	_checkSurfaceAndExport()
	if failures.is_empty():
		print("WORLD MAP OUTWARD BORDERS OK")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _checkLattice() -> void:
	_require(not WorldMapHexGrid.contains(Vector2i(0, 0), 5, 4), "even column row 0 is still a cell")
	_require(not WorldMapHexGrid.contains(Vector2i(4, 0), 5, 4), "last even column row 0 is still a cell")
	_require(WorldMapHexGrid.contains(Vector2i(1, 0), 5, 4), "odd column row 0 is not a cell")
	_require(WorldMapHexGrid.contains(Vector2i(0, 1), 5, 4), "even column row 1 is not a cell")
	_require(WorldMapHexGrid.contains(Vector2i(0, 3), 5, 4), "even column's last row is not a cell")
	for lattice in WorldMapHexGrid.exactSquareLattices():
		_require(lattice.x % 2 == 1, "New Map offers an even column count: %s" % str(lattice))


func _checkPaintAndLoad() -> void:
	var data := MapData.create("borders", Vector2i(5, 4), MapData.LAYOUT_HEX_FLAT)
	_require(not data.setCell("ground", Vector2i(2, 0), "t000"), "a trimmed cell accepted paint")
	_require(data.getCell("ground", Vector2i(2, 0)) == MapData.EMPTY, "a trimmed cell reads as painted")
	_require(data.setCell("ground", Vector2i(3, 0), "t000"), "an odd row-0 cell refused paint")

	# A file from before the rule: paint in all three trimmed cells of the ground layer.
	var raw := data.toDictionary()
	for block in raw["LAYERS"]:
		if str(block["ID"]) == "ground":
			var cells := PackedStringArray()
			cells.resize(20)
			cells.fill("t001")
			block["RLE"] = MapData.encodeRLE(cells)
	var loaded := MapData.fromDictionary(raw)
	_require(loaded != null, "a pre-rule file did not load")
	if loaded == null:
		return
	_require(loaded.trimmedOnLoad == 3, "expected 3 cleared values, got %d" % loaded.trimmedOnLoad)
	_require(loaded.getCell("ground", Vector2i(1, 0)) == "t001", "clearing touched a real cell")
	var cleared := MapData.fromDictionary(loaded.toDictionary())
	_require(cleared.trimmedOnLoad == 0, "a re-saved map still carried trimmed paint")


func _checkSurfaceAndExport() -> void:
	var data := MapData.create("borders", Vector2i(5, 4), MapData.LAYOUT_HEX_FLAT)
	var mesh := HeightField.buildSurfaceMesh(data)
	var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	_require(indices.size() == (5 * 4 - 3) * 6 * 3, "surface mesh has %d indices for 17 hexes" % indices.size())

	TacticalLayer.ensureLayer(data)
	for col in 5:
		for row in 4:
			data.setCell(TacticalLayer.DEFAULT_LAYER, Vector2i(col, row), "clear")
	var built := BattleExport.buildDefinition(data)
	_require(bool(built.get("ok", false)), "export failed: %s" % built.get("error", ""))
	if not bool(built.get("ok", false)):
		return
	var mask: Array = built["definition"]["VALID_MASK"]
	_require(str(mask[0]) == "01010", "row 0 mask should be 01010, is %s" % mask[0])
	_require(str(mask[3]) == "11111", "last row mask should be full, is %s" % mask[3])


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
