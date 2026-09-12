extends SceneTree

## FHB-2: a battlefield derived from the ground layer's own art rather than decided cell by cell.
## Today's vocabulary is walkable versus not, with no movement-point difference between them --
## `rough` is never produced by `derivedFrom()`, and this cycle does not ask it to be.
##
## Uses in-memory documents and the real starter tileset catalog already on disk. No editor
## scene, no camera, no window.

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const Tactical = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")

const STARTER := "temp2_hex32_starter"
const LATTICE := Vector2i(2, 2)

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
	_require(Tilesets.isWalkable(STARTER, "t000"), "authored-true land tile read as not walkable")
	_require(not Tilesets.isWalkable(STARTER, "t001"), "authored-false sea tile read as walkable")
	_require(Tilesets.isWalkable(STARTER, "t002"), "authored-true grass tile read as not walkable")
	_require(Tilesets.isWalkable(STARTER, "t999"), "an unknown tile id did not default to walkable")
	_require(Tilesets.isWalkable("nonexistent_tileset", "t000"),
		"an unknown tileset id did not default to walkable")
	_require(Tilesets.walkableFor(STARTER, "t000") == "true", "walkableFor lost the authored value")
	_require(Tilesets.walkableFor(STARTER, "t999") == "", "walkableFor invented a value for an unknown tile")


## One cell of land, one of sea, one of grass, and one left empty -- the four cases the class
## note's derivation rule distinguishes. Both land and grass derive to the SAME id: this cycle
## makes no movement-point distinction between them.
func _checkDerivedFromWalkableSignal() -> void:
	var data := _buildFixture()
	var derived := Tactical.derivedFrom(data, "ground")
	_require(derived.size() == LATTICE.x * LATTICE.y,
		"derivedFrom answered for %d cells, expected %d" % [derived.size(), LATTICE.x * LATTICE.y])

	_require(str(derived.get(Vector2i(0, 0), "")) == "clear", "land did not derive to clear")
	_require(str(derived.get(Vector2i(1, 0), "")) == "blocked", "sea did not derive to blocked")
	_require(str(derived.get(Vector2i(0, 1), "")) == "clear", "grass did not derive to clear")
	_require(str(derived.get(Vector2i(1, 1), "")) == "blocked",
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
	_require(str(once.get(Vector2i(1, 0), "")) == "blocked", "the applied layer disagrees with derivedFrom")


## A document with no battlefield layer gains one, populated, rather than needing it added first.
func _checkAppliedCreatesTheLayer() -> void:
	var data := _buildFixture()
	_require(not Tactical.has(data), "the fixture unexpectedly already has a battlefield layer")
	Tactical.applyDerived(data, "ground")
	_require(Tactical.has(data), "applyDerived did not create the battlefield layer")
	_require(Tactical.playableCount(data) == LATTICE.x * LATTICE.y,
		"applyDerived left cells outside the battlefield on a document with a full ground layer")


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


func _buildFixture() -> WorldMapTileData:
	var data := MapDataScript.create("probe_terrain_derivation", LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = STARTER
	data.setCell("ground", Vector2i(0, 0), "t000")  # land, walkable
	data.setCell("ground", Vector2i(1, 0), "t001")  # sea, not walkable
	data.setCell("ground", Vector2i(0, 1), "t002")  # grass, walkable
	# (1, 1) left EMPTY on purpose -- nothing painted there.
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
