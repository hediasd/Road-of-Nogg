## WMH-10's self-contained validation: 6 slots per hex resolve distinctly, painting detail leaves
## tile-grade layers untouched, and the bake composites detail over ground.
##
## NO REAL DETAIL ART EXISTS YET, so this reuses `temp2_hex32_ground` -- the only hex tileset in
## the catalog -- as placeholder art, exactly the bootstrap pattern WMH-2 and WMH-4 already used.
## What is being proven here is the MECHANISM: that six independently-addressed slots exist per
## hex, that painting one never touches another layer, and that the baker's mask actually confines
## each slot's pixels to its own fan triangle rather than covering the whole 32 px frame.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const TilesetCatalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")

const HEX_TILESET := "temp2_hex32_ground"

var _failures := 0

## WMH-10B routed detail through the history, so every paint here opens and closes a stroke.
## One stroke per call keeps each check's undo boundary exactly where it was when this file was
## written against the direct mutator.
var _history := WorldMapEditHistory.new()


func _paintTriangle(data: WorldMapTileData, cell: Vector2i, index: int, id: String) -> bool:
	_history.beginStroke("detail")
	var painted := Brushes.paintTriangle(data, _history, "detail", cell, index, id)
	_history.endStroke()
	return painted



func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_checkSixSlotsResolveDistinctly()
	_checkDetailIsAddedAsAFourthKind()
	_checkPaintingDetailLeavesGroundUntouched()
	_checkOutOfRangeIsRefused()
	_checkRoundTrip()
	_checkBakeCompositesDetailOverGround()
	_checkSlotsAreMaskedNotOverlapping()

	print("")
	print("probe_subtriangles: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP SUBTRIANGLES OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _freshHexData() -> WorldMapTileData:
	var data: WorldMapTileData = MapData.create("_probe_subtri", Vector2i(6, 6), MapData.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = HEX_TILESET
	data.addDetailLayer("detail", HEX_TILESET)
	return data


func _tileIDs() -> Array[String]:
	var ids: Array[String] = []
	for tile in TilesetCatalog.tilesetFor(HEX_TILESET)["TILES"]:
		ids.append(str((tile as Dictionary)["ID"]))
	return ids


func _checkSixSlotsResolveDistinctly() -> void:
	print("-- 6 slots per hex resolve distinctly --")
	var data := _freshHexData()
	var ids := _tileIDs()
	if ids.size() < 6:
		_fail("the hex tileset has too few tiles to give each slot a distinct id")
		return
	var cell := Vector2i(2, 2)
	for i in 6:
		if not _paintTriangle(data, cell, i, ids[i]):
			_fail("painting slot %d reported no change" % i)
			return
	for i in 6:
		var read := data.getDetail("detail", cell, i)
		if read != ids[i]:
			_fail("slot %d reads back '%s', expected '%s'" % [i, read, ids[i]])
			return
	# And a NEIGHBOURING cell's slot 0 is independent of this cell's slot 0.
	var neighbour := Vector2i(3, 2)
	_paintTriangle(data, neighbour, 0, ids[0])
	_paintTriangle(data, cell, 0, ids[1])
	if data.getDetail("detail", neighbour, 0) != ids[0]:
		_fail("a neighbouring cell's slot 0 was affected by this cell's own slot 0")
		return
	print("  ok    6 slots per hex, each independently addressable and readable")


func _checkDetailIsAddedAsAFourthKind() -> void:
	print("-- detail is its own storage kind, sized for the lattice --")
	var data := _freshHexData()
	if str(data.layers["detail"]["KIND"]) != MapData.KIND_DETAIL:
		_fail("detail layer KIND is '%s', expected '%s'" % [
			data.layers["detail"]["KIND"], MapData.KIND_DETAIL
		])
		return
	var expected := data.size_tiles.x * data.size_tiles.y * MapData.DETAIL_SLOTS_PER_CELL
	if data.detailValueCount() != expected:
		_fail("detailValueCount() is %d, expected %d" % [data.detailValueCount(), expected])
		return
	if (data.layers["detail"]["CELLS"] as PackedStringArray).size() != expected:
		_fail("the stored CELLS array is not sized for the full lattice")
		return
	print("  ok    KIND_DETAIL, sized cols x rows x 6 = %d" % expected)


## The item's own risk, made concrete: detail is art only, and painting it must never touch a
## tile-grade layer -- ground, most of all, since that is exactly what §9's "one record feeds
## every derived thing" lesson would be violated by if detail silently doubled as terrain.
func _checkPaintingDetailLeavesGroundUntouched() -> void:
	print("-- painting detail leaves tile-grade layers untouched --")
	var data := _freshHexData()
	var ids := _tileIDs()
	for col in data.size_tiles.x:
		for row in data.size_tiles.y:
			data.setCell("ground", Vector2i(col, row), ids[0])
	var groundBefore: Dictionary = data.toDictionary()["LAYERS"][0]

	for col in data.size_tiles.x:
		for row in data.size_tiles.y:
			for i in 6:
				_paintTriangle(data, Vector2i(col, row), i, ids[i % ids.size()])

	var groundAfter: Dictionary = data.toDictionary()["LAYERS"][0]
	if groundAfter != groundBefore:
		_fail("ground's own RLE changed after painting every detail slot on every cell")
		return
	print("  ok    every cell fully detailed; ground's own layer is byte-identical to before")


func _checkOutOfRangeIsRefused() -> void:
	print("-- an out-of-range cell or slot index is refused, not silently written --")
	var data := _freshHexData()
	var ids := _tileIDs()
	if _paintTriangle(data, Vector2i(-1, 0), 0, ids[0]):
		_fail("a negative cell was accepted")
		return
	if _paintTriangle(data, data.size_tiles, 0, ids[0]):
		_fail("a cell one past the lattice was accepted")
		return
	if _paintTriangle(data, Vector2i(2, 2), 6, ids[0]):
		_fail("slot index 6 (only 0-5 exist) was accepted")
		return
	if _paintTriangle(data, Vector2i(2, 2), -1, ids[0]):
		_fail("a negative slot index was accepted")
		return
	print("  ok    out-of-range cells and slot indices are all refused")


func _checkRoundTrip() -> void:
	print("-- a detailed map survives a save and reload --")
	var data := _freshHexData()
	var ids := _tileIDs()
	var painted := {}
	for col in data.size_tiles.x:
		for row in data.size_tiles.y:
			for i in 6:
				if (col + row + i) % 3 == 0:
					continue  # leave some slots empty, so EMPTY round-trips too
				var id: String = ids[(col + row + i) % ids.size()]
				_paintTriangle(data, Vector2i(col, row), i, id)
				painted[Vector3i(col, row, i)] = id

	var path := "user://probe_scratch/worldmap/_probe_subtri.json"
	if not data.saveTo(path):
		_fail("could not write the scratch document")
		return
	var reloaded := MapData.loadFrom(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if reloaded == null:
		_fail("could not read the scratch document back")
		return
	for key in painted:
		var v: Vector3i = key
		var back := reloaded.getDetail("detail", Vector2i(v.x, v.y), v.z)
		if back != painted[key]:
			_fail("slot %s came back as '%s', expected '%s'" % [v, back, painted[key]])
			return
	print("  ok    %d painted slots survive a round trip through disk" % painted.size())


## The bake composites detail OVER ground -- checked by painting ground one colour-bearing tile
## and detail a DIFFERENT one, then confirming the composed image shows the detail tile's own
## pixels somewhere inside the hex (not just the ground tile's), rather than being skipped.
func _checkBakeCompositesDetailOverGround() -> void:
	print("-- the bake composites detail over ground --")
	var ids := _tileIDs()
	if ids.size() < 2:
		_fail("need at least 2 distinct tiles to tell ground and detail apart")
		return
	var data := _freshHexData()
	for col in data.size_tiles.x:
		for row in data.size_tiles.y:
			data.setCell("ground", Vector2i(col, row), ids[0])
	var cell := Vector2i(3, 3)
	_paintTriangle(data, cell, 0, ids[1])

	var baker := Baker.new()
	if baker.bake(data) == null:
		_fail("bake produced no texture")
		return

	# Reference: the same detail tile's own art, masked to slot 0, as a standalone image --
	# exactly what _composeDetailLayer should have blended into the baked frame.
	var reference: Dictionary = TilesetCatalog.tilesetFor(HEX_TILESET)
	var sheet := TilesetCatalog.loadSheetImage(str(reference["SHEET"]))
	var framePx := int(reference["FRAME_PX"])
	var detailCellOnSheet: Vector2i = Vector2i.ZERO
	for tile in reference["TILES"]:
		if str((tile as Dictionary)["ID"]) == ids[1]:
			detailCellOnSheet = (tile as Dictionary)["CELL"]
			break
	var frameOrigin := Vector2i(
		int(round(WorldMapHexGrid.cellCentre(cell).x * 16.0 - framePx * 0.5)),
		int(round(WorldMapHexGrid.cellCentre(cell).y * 16.0 - framePx * 0.5))
	)

	var found := false
	for fy in framePx:
		for fx in framePx:
			var localUnits := (Vector2(fx, fy) + Vector2(0.5, 0.5) - Vector2(framePx * 0.5, framePx * 0.5)) / 16.0
			var a: Vector2 = HeightField.CORNER_OFFSETS[0]
			var b: Vector2 = HeightField.CORNER_OFFSETS[1]
			# Well inside slot 0, not near its edges, so this cannot be sensitive to the mask's
			# own boundary tolerance.
			var det := a.x * b.y - b.x * a.y
			var u := (localUnits.x * b.y - b.x * localUnits.y) / det
			var v := (a.x * localUnits.y - localUnits.x * a.y) / det
			if u < 0.2 or v < 0.2 or (1.0 - u - v) < 0.2:
				continue
			var srcColour := sheet.get_pixel(detailCellOnSheet.x * framePx + fx, detailCellOnSheet.y * framePx + fy)
			if srcColour.a <= 0.0:
				continue
			var bakedColour := baker.image().get_pixel(frameOrigin.x + fx, frameOrigin.y + fy)
			if not bakedColour.is_equal_approx(srcColour):
				_fail("inside slot 0 at frame pixel (%d,%d): baked %s, detail art %s" % [
					fx, fy, bakedColour, srcColour
				])
				return
			found = true
	if not found:
		_fail("found no well-inside, opaque pixel of slot 0 to compare -- the check proves nothing")
		return
	print("  ok    detail tile's own pixels appear in the bake, inside its painted slot")


## The mask's own job: a pixel belonging to slot 1 must NOT be overwritten by slot 4 (the
## opposite side of the hex) painted with a different tile afterward. If masking silently
## degraded to "the whole frame", the second paint would erase the first.
func _checkSlotsAreMaskedNotOverlapping() -> void:
	print("-- painting one slot does not overwrite a different slot's pixels in the bake --")
	var ids := _tileIDs()
	if ids.size() < 2:
		_fail("need at least 2 distinct tiles")
		return
	var data := _freshHexData()
	for col in data.size_tiles.x:
		for row in data.size_tiles.y:
			data.setCell("ground", Vector2i(col, row), MapData.EMPTY)
	var cell := Vector2i(3, 3)
	_paintTriangle(data, cell, 1, ids[0])

	var baker := Baker.new()
	baker.bake(data)
	var beforeImage := baker.image().get_region(Rect2i(Vector2i.ZERO, baker.image().get_size()))

	_paintTriangle(data, cell, 4, ids[1])
	baker.markCellsDirty(data, "detail", Rect2i(cell, Vector2i.ONE))
	baker.flush(data)

	var reference: Dictionary = TilesetCatalog.tilesetFor(HEX_TILESET)
	var framePx := int(reference["FRAME_PX"])
	var frameOrigin := Vector2i(
		int(round(WorldMapHexGrid.cellCentre(cell).x * 16.0 - framePx * 0.5)),
		int(round(WorldMapHexGrid.cellCentre(cell).y * 16.0 - framePx * 0.5))
	)
	var a: Vector2 = HeightField.CORNER_OFFSETS[0]
	var b: Vector2 = HeightField.CORNER_OFFSETS[1]
	var det := a.x * b.y - b.x * a.y
	var changedInsideSlot1 := 0
	var checkedInsideSlot1 := 0
	for fy in framePx:
		for fx in framePx:
			var localUnits := (Vector2(fx, fy) + Vector2(0.5, 0.5) - Vector2(framePx * 0.5, framePx * 0.5)) / 16.0
			var u := (localUnits.x * b.y - b.x * localUnits.y) / det
			var v := (a.x * localUnits.y - localUnits.x * a.y) / det
			if u < 0.25 or v < 0.25 or (1.0 - u - v) < 0.25:
				continue
			checkedInsideSlot1 += 1
			var before := beforeImage.get_pixel(frameOrigin.x + fx, frameOrigin.y + fy)
			var after := baker.image().get_pixel(frameOrigin.x + fx, frameOrigin.y + fy)
			if not before.is_equal_approx(after):
				changedInsideSlot1 += 1
	if checkedInsideSlot1 == 0:
		_fail("found no well-inside pixel of slot 0 to compare -- the check proves nothing")
		return
	if changedInsideSlot1 > 0:
		_fail("%d of %d well-inside slot 0 pixels changed when a DIFFERENT slot was painted" % [
			changedInsideSlot1, checkedInsideSlot1
		])
		return
	print("  ok    painting the opposite slot left slot 0's own pixels untouched (%d checked)" % checkedInsideSlot1)
