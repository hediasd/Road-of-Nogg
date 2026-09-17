## WMH-7's self-contained validation: ids stay stable across edits and a save/reload, an object
## re-anchors when the terrain under it moves, and objects survive export.
##
## THE ID CHECK IS THE ONE THAT MATTERS MOST. Quests, save data and triggers will reference these
## ids, so an id that changes when a building is moved, or when an unrelated object is deleted,
## or when the document is reloaded, is a broken reference somewhere nothing looks. That failure
## is silent and arrives long after the edit that caused it, which is exactly why it gets the
## most cases here.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const ObjectLayer = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")

const SCRATCH := "user://probe_scratch/worldmap/_probe_objects.json"
const EXPORTED := "user://probe_scratch/worldmap/_probe_objects.tscn"

var _failures := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_cleanup()
	_checkPlacementAndFields()
	_checkIdsSurviveEdits()
	_checkIdsSurviveSaveReload()
	_checkRemovedIdsAreNeverReissued()
	_checkFootprint()
	_checkReanchorsWhenTerrainMoves()
	_checkObjectsSurviveExport()
	_checkBridgeDeckIsAuthoredNotDerived()
	_checkClearanceReportsTheWorstSurface()
	_checkClearanceSkipsDryCells()
	_cleanup()

	print("")
	print("probe_object_layer: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP OBJECT LAYER OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _cleanup() -> void:
	for path in [SCRATCH, EXPORTED]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fresh() -> WorldMapTileData:
	return MapData.create("_probe_objects", Vector2i(9, 7), MapData.LAYOUT_HEX_FLAT)


func _checkPlacementAndFields() -> void:
	print("-- a placed object carries every field the record promises --")
	var data := _fresh()
	var record := ObjectLayer.place(data, "house", Vector2i(3, 2), ObjectLayer.DEFAULT_LAYER, 2, 1)
	for key in [
		ObjectLayer.K_ID, ObjectLayer.K_KIND, ObjectLayer.K_CELL, ObjectLayer.K_FACING,
		ObjectLayer.K_FOOTPRINT, ObjectLayer.K_ANCHOR, ObjectLayer.K_HEIGHT,
	]:
		if not record.has(key):
			_fail("a placed object has no %s" % key)
			return
	if ObjectLayer.cellOf(record) != Vector2i(3, 2):
		_fail("cell round-trip gave %s" % ObjectLayer.cellOf(record))
		return
	if int(record[ObjectLayer.K_FACING]) != 2:
		_fail("facing is %s, expected 2" % record[ObjectLayer.K_FACING])
		return
	# CELL is an array, not a Vector2i: JSON has no Vector2i, and a record that cannot serialise
	# is a record that silently loses its position on save.
	if not (record[ObjectLayer.K_CELL] is Array):
		_fail("CELL is %s, which JSON cannot write" % typeof(record[ObjectLayer.K_CELL]))
		return
	# Facing wraps rather than growing without bound -- there is no seventh direction.
	var wrapped := ObjectLayer.place(data, "tower", Vector2i(1, 1), ObjectLayer.DEFAULT_LAYER, 8)
	if int(wrapped[ObjectLayer.K_FACING]) != 2:
		_fail("facing 8 stored as %s, expected it to wrap to 2" % wrapped[ObjectLayer.K_FACING])
		return
	print("  ok    all seven fields present, cell serialisable, facing wraps into 0-5")


## Moving, rotating and deleting neighbours must all leave an id alone -- each is a thing an
## author does routinely, and each would break a quest reference if it renamed the building.
func _checkIdsSurviveEdits() -> void:
	print("-- an id survives moving, rotating and its neighbours being deleted --")
	var data := _fresh()
	var first := ObjectLayer.place(data, "house", Vector2i(1, 1))
	var subject := ObjectLayer.place(data, "tower", Vector2i(3, 3))
	var third := ObjectLayer.place(data, "house", Vector2i(5, 5))
	var id := str(subject[ObjectLayer.K_ID])

	ObjectLayer.move(data, id, Vector2i(6, 2))
	ObjectLayer.setFacing(data, id, 4)
	ObjectLayer.remove(data, str(first[ObjectLayer.K_ID]))
	ObjectLayer.remove(data, str(third[ObjectLayer.K_ID]))

	var found := ObjectLayer.find(data, id)
	if found.is_empty():
		_fail("the object could not be found by its id after being edited")
		return
	if ObjectLayer.cellOf(found) != Vector2i(6, 2):
		_fail("move did not take: cell is %s" % ObjectLayer.cellOf(found))
		return
	if int(found[ObjectLayer.K_FACING]) != 4:
		_fail("setFacing did not take: facing is %s" % found[ObjectLayer.K_FACING])
		return
	print("  ok    '%s' kept its id through a move, a rotation and two deletions" % id)


func _checkIdsSurviveSaveReload() -> void:
	print("-- ids and records survive a save and reload --")
	var data := _fresh()
	var ids: Array[String] = []
	for index in 4:
		var record := ObjectLayer.place(
			data, "house", Vector2i(index + 1, index), ObjectLayer.DEFAULT_LAYER, index, 1
		)
		ids.append(str(record[ObjectLayer.K_ID]))
	if not data.saveTo(SCRATCH):
		_fail("could not write the scratch document")
		return
	var reloaded := MapData.loadFrom(SCRATCH)
	if reloaded == null:
		_fail("could not read the scratch document back")
		return
	if ObjectLayer.count(reloaded) != 4:
		_fail("reloaded document has %d objects, expected 4" % ObjectLayer.count(reloaded))
		return
	for index in ids.size():
		var record := ObjectLayer.find(reloaded, ids[index])
		if record.is_empty():
			_fail("'%s' did not survive the reload" % ids[index])
			return
		if ObjectLayer.cellOf(record) != Vector2i(index + 1, index):
			_fail("'%s' came back at %s" % [ids[index], ObjectLayer.cellOf(record)])
			return
		if int(record[ObjectLayer.K_FOOTPRINT]) != 1:
			_fail("'%s' lost its footprint" % ids[index])
			return
	print("  ok    4 objects, ids and fields all identical after a round trip through disk")


## The contract that makes an id safe to reference: a removed id is retired, not recycled. A
## reissued id would silently redirect an old reference to a completely different building.
func _checkRemovedIdsAreNeverReissued() -> void:
	print("-- a removed id is never reissued --")
	var data := _fresh()
	var seen := {}
	for index in 5:
		seen[str(ObjectLayer.place(data, "house", Vector2i(index, 0))[ObjectLayer.K_ID])] = true
	# Delete everything, then place more: the allocator must keep climbing.
	for id in seen.keys():
		ObjectLayer.remove(data, str(id))
	if ObjectLayer.count(data) != 0:
		_fail("removal left %d objects behind" % ObjectLayer.count(data))
		return
	for index in 3:
		var id := str(ObjectLayer.place(data, "tower", Vector2i(index, 1))[ObjectLayer.K_ID])
		if seen.has(id):
			_fail("'%s' was reissued after being removed" % id)
			return
		seen[id] = true

	# And the allocator survives a reload of a document whose items were all deleted -- the
	# derived fallback must not reset to zero just because ITEMS is empty.
	data.saveTo(SCRATCH)
	var reloaded := MapData.loadFrom(SCRATCH)
	var afterReload := str(ObjectLayer.place(reloaded, "house", Vector2i(0, 2))[ObjectLayer.K_ID])
	if seen.has(afterReload):
		_fail("'%s' was reissued after a reload" % afterReload)
		return
	print("  ok    8 ids across deletions and a reload, no id ever reused")


func _checkFootprint() -> void:
	print("-- a footprint covers the anchor cell and its hex disc --")
	var data := _fresh()
	var alone := ObjectLayer.place(data, "house", Vector2i(4, 3))
	var cells := ObjectLayer.footprintCells(alone)
	if cells.size() != 1 or cells[0] != Vector2i(4, 3):
		_fail("footprint 0 gave %s, expected just the anchor cell" % [cells])
		return
	var wide := ObjectLayer.place(data, "keep", Vector2i(4, 3), ObjectLayer.DEFAULT_LAYER, 0, 1)
	var wideCells := ObjectLayer.footprintCells(wide)
	if wideCells.size() != 7:
		_fail("footprint 1 covers %d cells, expected 7" % wideCells.size())
		return
	for neighbour in WorldMapHexGrid.neighbours(Vector2i(4, 3)):
		if not wideCells.has(neighbour):
			_fail("footprint 1 is missing neighbour %s" % neighbour)
			return
	print("  ok    radius 0 is one cell; radius 1 is the cell plus all six neighbours")


## The item's own words: raising ground under a building lifts it rather than burying it. Terrain
## heights are WMH-8's, so the sampler stands in for them -- which is the point of taking one.
func _checkReanchorsWhenTerrainMoves() -> void:
	print("-- an object re-anchors when the terrain under it moves --")
	var data := _fresh()
	var record := ObjectLayer.place(data, "house", Vector2i(4, 3), ObjectLayer.DEFAULT_LAYER, 0, 1)

	var flat := func(_cell: Vector2i) -> float: return 0.0
	if not is_equal_approx(ObjectLayer.anchorHeight(record, flat), 0.0):
		_fail("on flat ground the anchor is %f, expected 0" % ObjectLayer.anchorHeight(record, flat))
		return
	if not is_equal_approx(ObjectLayer.worldPosition(data, record, flat).y, 0.0):
		_fail("world position y is not 0 on flat ground")
		return

	# Raise ONE cell of the footprint -- a neighbour, not the anchor -- and the object must rise
	# with it. Taking the maximum is what makes that true; a mean or the anchor cell alone would
	# leave terrain poking through the building's floor.
	var raised := func(cell: Vector2i) -> float:
		return 3.0 if cell == Vector2i(5, 3) else 0.0
	var lifted := ObjectLayer.anchorHeight(record, raised)
	if not is_equal_approx(lifted, 3.0):
		_fail("raising one footprint cell to 3.0 gave an anchor of %f" % lifted)
		return
	if not is_equal_approx(ObjectLayer.worldPosition(data, record, raised).y, 3.0):
		_fail("world position did not follow the anchor")
		return

	# A cell OUTSIDE the footprint must not move it.
	var elsewhere := func(cell: Vector2i) -> float:
		return 9.0 if cell == Vector2i(0, 0) else 0.0
	if not is_equal_approx(ObjectLayer.anchorHeight(record, elsewhere), 0.0):
		_fail("terrain outside the footprint moved the object")
		return

	# A fixed-anchor object ignores terrain entirely.
	var pinned := ObjectLayer.place(
		data, "airship", Vector2i(4, 3), ObjectLayer.DEFAULT_LAYER, 0, 1,
		ObjectLayer.ANCHOR_FIXED, 12.0
	)
	if not is_equal_approx(ObjectLayer.anchorHeight(pinned, raised), 12.0):
		_fail("a fixed anchor followed the terrain")
		return
	print("  ok    rises with its footprint's highest cell; ignores terrain elsewhere and when fixed")


func _checkObjectsSurviveExport() -> void:
	print("-- objects survive export, findable by their own id --")
	var data := MapData.loadFrom(MapData.pathFor("temp2_authored"))
	if data == null:
		_fail("could not load temp2_authored")
		return
	var placed := {
		str(ObjectLayer.place(data, "house", Vector2i(2, 3))[ObjectLayer.K_ID]): Vector2i(2, 3),
		str(ObjectLayer.place(data, "tower", Vector2i(9, 6), ObjectLayer.DEFAULT_LAYER, 3)[ObjectLayer.K_ID]): Vector2i(9, 6),
	}
	var result := SceneExport.exportScene(
		data, FramingCatalog.framingFor(FramingCatalog.TILE_EXACT), EXPORTED
	)
	if not bool(result.get("ok", false)):
		_fail("export refused: %s" % str(result.get("error", "?")))
		return
	var packed := ResourceLoader.load(EXPORTED, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	var holder := instance.get_node_or_null("Objects")
	if holder == null:
		_fail("the exported scene has no Objects node")
		instance.free()
		return
	for id in placed:
		var node := holder.get_node_or_null(NodePath(str(id))) as Node3D
		if node == null:
			_fail("'%s' is not in the exported scene" % id)
			instance.free()
			return
		# Positioned where the record says, not merely present.
		var expected := ObjectLayer.worldPosition(data, ObjectLayer.find(data, str(id)))
		if not node.position.is_equal_approx(expected):
			_fail("'%s' exported at %s, the record says %s" % [id, node.position, expected])
			instance.free()
			return
	instance.free()
	print("  ok    %d objects exported, each findable by id and at its record's position" % placed.size())


## WMH-12's own words: deck height is AUTHORED, not derived -- that is the whole difference
## between a bridge and a road. `placeBridge` bakes in `ANCHOR_FIXED`; this checks that baking-in
## actually holds against a terrain sampler that would move an `ANCHOR_TERRAIN` object, both
## directly (a sampler that reports the deck should be buried) and unfavourably (one that reports
## it should float away) -- the deck must not move either way.
func _checkBridgeDeckIsAuthoredNotDerived() -> void:
	print("-- a bridge's deck stays at its authored height when the terrain beneath changes --")
	var data := _fresh()
	var bridge := ObjectLayer.placeBridge(data, "bridge", Vector2i(4, 3), 2.5, ObjectLayer.DEFAULT_LAYER, 0, 1)
	if str(bridge[ObjectLayer.K_ANCHOR]) != ObjectLayer.ANCHOR_FIXED:
		_fail("placeBridge recorded ANCHOR '%s', expected fixed" % bridge[ObjectLayer.K_ANCHOR])
		return
	if not is_equal_approx(float(bridge[ObjectLayer.K_HEIGHT]), 2.5):
		_fail("placeBridge recorded HEIGHT %s, expected 2.5" % bridge[ObjectLayer.K_HEIGHT])
		return

	var flat := func(_cell: Vector2i) -> float: return 0.0
	if not is_equal_approx(ObjectLayer.anchorHeight(bridge, flat), 2.5):
		_fail("on flat terrain the deck reads %f, expected 2.5" % ObjectLayer.anchorHeight(bridge, flat))
		return

	# Terrain that riases to swallow the deck -- an ANCHOR_TERRAIN object would rise with it.
	var risen := func(_cell: Vector2i) -> float: return 6.0
	if not is_equal_approx(ObjectLayer.anchorHeight(bridge, risen), 2.5):
		_fail("terrain rising to 6.0 moved the deck to %f" % ObjectLayer.anchorHeight(bridge, risen))
		return

	# Terrain that drops away -- an ANCHOR_TERRAIN object would fall with it.
	var dropped := func(_cell: Vector2i) -> float: return -6.0
	if not is_equal_approx(ObjectLayer.anchorHeight(bridge, dropped), 2.5):
		_fail("terrain dropping to -6.0 moved the deck to %f" % ObjectLayer.anchorHeight(bridge, dropped))
		return
	print("  ok    the deck reads 2.5 regardless of what the sampler under it reports")


## Deliberately built so the worst clearance comes from WATER, not the lower terrain beneath it --
## the failure mode the class note names: a deck that clears the riverbed by a wide margin but
## sits at or below the water surface above it is a bridge sitting IN the river.
func _checkClearanceReportsTheWorstSurface() -> void:
	print("-- clearance checks every footprint cell against both terrain and water, and reports the worst --")
	var data := _fresh()
	var centre := Vector2i(4, 3)
	var bridge := ObjectLayer.placeBridge(data, "bridge", centre, 1.0, ObjectLayer.DEFAULT_LAYER, 0, 1)
	var footprint := ObjectLayer.footprintCells(bridge)
	if footprint.size() != 7:
		_fail("test setup: expected a 7-cell footprint, got %d" % footprint.size())
		return
	var farCell: Vector2i = footprint[footprint.size() - 1]

	# Riverbed is deep everywhere (-5.0) except one cell the water sits shallow over (0.8) --
	# high enough that a 1.0-deck barely clears it.
	var terrain := func(cell: Vector2i) -> float: return -5.0
	var water := func(cell: Vector2i):
		return 0.8 if cell == farCell else null

	var report := ObjectLayer.clearance(bridge, terrain, water)
	if str(report["surface"]) != "water":
		_fail("worst surface reported as '%s', expected 'water'" % report["surface"])
		return
	if report["cell"] != farCell:
		_fail("worst cell reported as %s, expected %s" % [report["cell"], farCell])
		return
	if not is_equal_approx(float(report["clearance"]), 0.2):
		_fail("clearance reported as %f, expected 0.2 (1.0 deck - 0.8 water)" % report["clearance"])
		return
	print("  ok    the shallow water cell (0.2 clearance) outranks the deep riverbed (6.0) everywhere else")


## `waterSampler` returning `null` for a dry cell must be excluded outright, not read as a height
## of 0.0 -- the distinction WMH-11 built the water layer around. A bridge on dry land at deck
## height 0.05, checked with a water sampler that is null everywhere, must report against the
## TERRAIN only; if a dry null were treated as 0.0, this would report a bogus near-miss against
## phantom water.
func _checkClearanceSkipsDryCells() -> void:
	print("-- a null water sampler (a dry cell) is excluded, not read as height 0.0 --")
	var data := _fresh()
	var bridge := ObjectLayer.placeBridge(data, "bridge", Vector2i(4, 3), 0.05, ObjectLayer.DEFAULT_LAYER, 0, 0)
	var terrain := func(_cell: Vector2i) -> float: return -2.0
	var alwaysDry := func(_cell: Vector2i): return null

	var withDryWater := ObjectLayer.clearance(bridge, terrain, alwaysDry)
	var withNoWater := ObjectLayer.clearance(bridge, terrain)
	if str(withDryWater["surface"]) != "terrain":
		_fail("a dry water sampler still reported the worst surface as '%s'" % withDryWater["surface"])
		return
	if not is_equal_approx(float(withDryWater["clearance"]), float(withNoWater["clearance"])):
		_fail("passing an always-dry water sampler changed the result (%f vs %f)"
			% [withDryWater["clearance"], withNoWater["clearance"]])
		return
	print("  ok    an always-dry water sampler reports identically to no water sampler at all")
