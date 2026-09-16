extends SceneTree

## FHB-2: a battlefield derived from the ground layer's own art rather than decided cell by cell.
## Today's vocabulary is walkable versus not, with no movement-point difference between them --
## `rough` is never produced by `derivedFrom()`, and this cycle does not ask it to be.
##
## Uses in-memory documents and the real starter tileset catalog already on disk, whose walkability
## it authors in memory rather than reading whatever the sheet currently says. Nothing is written
## back -- `setWalkable()` only touches the loaded catalog. No editor scene, no camera, no window.

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const Tactical = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")

const STARTER := "temp2_hex32_starter"
## Four by four, and the painted cells are inside it: a hex document trims the top hex of some
## columns, and a trimmed cell cannot be painted at all. See `WorldMapTileData._isTrimmed`.
const LATTICE := Vector2i(4, 4)
const CELL_LAND := Vector2i(1, 1)
const CELL_SEA := Vector2i(2, 1)
const CELL_GRASS := Vector2i(1, 2)
const CELL_EMPTY := Vector2i(2, 2)

var failures: Array[String] = []


func _init() -> void:
	_checkIsWalkableDefaults()
	_checkDerivedFromWalkableSignal()
	_checkAppliedTwiceIsIdempotent()
	_checkAppliedCreatesTheLayer()
	_checkNoGroundLayerDerivesNothing()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HEX_TERRAIN_DERIVATION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX_TERRAIN_DERIVATION_OK")
	quit(0)


## The safe-default half of the contract: an unset field, an unknown tile, and an unknown
## tileset all read as walkable, so a sheet nobody has annotated does not silently wall off
## everything painted from it.
func _checkIsWalkableDefaults() -> void:
	# Set here rather than asserted off the shipped sheet: `WALKABLE` is authored in the editor now,
	# so what a tile currently says is the author's business, and a probe that asserted today's
	# values would fail the first time someone changed one on purpose. The derivation's contract is
	# what this checks: whatever the catalog says is what the battlefield reads.
	_require(Tilesets.setWalkable(STARTER, "t001", false), "could not author t001 as not walkable")
	_require(Tilesets.setWalkable(STARTER, "t000", true), "could not author t000 as walkable")
	_require(Tilesets.setWalkable(STARTER, "t002", true), "could not author t002 as walkable")
	_require(Tilesets.isWalkable(STARTER, "t000"), "authored-true land tile read as not walkable")
	_require(not Tilesets.isWalkable(STARTER, "t001"), "authored-false sea tile read as walkable")
	_require(Tilesets.isWalkable(STARTER, "t002"), "authored-true grass tile read as not walkable")
	_require(Tilesets.isWalkable(STARTER, "t999"), "an unknown tile id did not default to walkable")
	_require(Tilesets.isWalkable("nonexistent_tileset", "t000"),
		"an unknown tileset id did not default to walkable")
	_require(not Tilesets.setWalkable(STARTER, "t999", false), "setWalkable accepted an unknown tile")


## One cell of land, one of sea, one of grass, and one left empty -- the four cases the class
## note's derivation rule distinguishes. Both land and grass derive to the SAME id: this cycle
## makes no movement-point distinction between them.
func _checkDerivedFromWalkableSignal() -> void:
	var data := _buildFixture()
	var derived := Tactical.derivedFrom(data, "ground")
	_require(derived.size() == LATTICE.x * LATTICE.y,
		"derivedFrom answered for %d cells, expected %d" % [derived.size(), LATTICE.x * LATTICE.y])

	_require(str(derived.get(CELL_LAND, "")) == "clear", "land did not derive to clear")
	_require(str(derived.get(CELL_SEA, "")) == "blocked", "sea did not derive to blocked")
	_require(str(derived.get(CELL_GRASS, "")) == "clear", "grass did not derive to clear")
	_require(str(derived.get(CELL_EMPTY, "")) == "blocked",
		"an empty ground cell did not derive to blocked")

	# No movement-point effects: only the two ids this cycle asked for ever appear.
	var seenIDs: Dictionary = {}
	for cell in derived:
		seenIDs[str(derived[cell])] = true
	_require(not seenIDs.has("rough"), "derivedFrom produced 'rough', which this cycle does not use")
	for id in seenIDs:
		_require(id == "clear" or id == "blocked",
			"derivedFrom produced an id outside the walkable/not vocabulary: %s" % id)


## Applying twice overwrites with the same answer both times -- a re-derive is not additive and
## does not compound.
func _checkAppliedTwiceIsIdempotent() -> void:
	var data := _buildFixture()
	Tactical.applyDerived(data, "ground")
	var once := _readTactical(data)
	Tactical.applyDerived(data, "ground")
	var twice := _readTactical(data)
	_require(once == twice, "applying the derivation twice did not produce identical results")
	_require(str(once.get(CELL_SEA, "")) == "blocked", "the applied layer disagrees with derivedFrom")


## A document with no battlefield layer gains one, populated, rather than needing it added first.
func _checkAppliedCreatesTheLayer() -> void:
	var data := _buildFixture()
	_require(not Tactical.has(data), "the fixture unexpectedly already has a battlefield layer")
	Tactical.applyDerived(data, "ground")
	_require(Tactical.has(data), "applyDerived did not create the battlefield layer")
	_require(Tactical.playableCount(data) == _writableCells(),
		"applyDerived covered %d cells of the %d it could write" % [
			Tactical.playableCount(data), _writableCells()])


## A document whose named ground layer does not exist derives nothing rather than guessing --
## `applyDerived` on it must not crash and must not populate the (still freshly-created, empty)
## battlefield layer with an invented answer.
func _checkNoGroundLayerDerivesNothing() -> void:
	var data := MapDataScript.create("probe_no_ground", LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	var derived := Tactical.derivedFrom(data, "nonexistent_layer")
	_require(derived.is_empty(), "derivedFrom answered for a ground layer that does not exist")
	Tactical.applyDerived(data, "nonexistent_layer")
	_require(Tactical.playableCount(data) == 0,
		"applyDerived populated the battlefield from a ground layer that does not exist")


## How many cells this lattice accepts a write for: a hex document trims the top hex of some
## columns, and those cells hold nothing on any layer.
func _writableCells() -> int:
	var blank := MapDataScript.create("probe_writable", LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	var count := 0
	for row in range(LATTICE.y):
		for col in range(LATTICE.x):
			if blank.setCell("ground", Vector2i(col, row), "t000"):
				count += 1
	return count


func _buildFixture() -> WorldMapTileData:
	var data := MapDataScript.create("probe_terrain_derivation", LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = STARTER
	_require(data.setCell("ground", CELL_LAND, "t000"), "the land cell could not be painted")
	_require(data.setCell("ground", CELL_SEA, "t001"), "the sea cell could not be painted")
	_require(data.setCell("ground", CELL_GRASS, "t002"), "the grass cell could not be painted")
	# CELL_EMPTY is left EMPTY on purpose -- nothing painted there.
	return data


func _readTactical(data: WorldMapTileData) -> Dictionary:
	var result: Dictionary = {}
	for row in range(LATTICE.y):
		for col in range(LATTICE.x):
			var cell := Vector2i(col, row)
			result[cell] = Tactical.terrainAt(data, cell)
	return result


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
