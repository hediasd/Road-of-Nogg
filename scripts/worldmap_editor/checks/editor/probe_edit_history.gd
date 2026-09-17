## WME-7's self-contained validation: undo/redo round-trip exactly, at stroke granularity, and
## nothing in the history captures a reference it should have copied.
##
## THE FUZZ IS THE REAL TEST. Any hand-picked sequence of edits can pass by accident -- a shared-
## reference bug shows up only when two strokes happen to touch overlapping state in a way a
## human wouldn't think to construct. So the headline check runs a hundred randomised strokes
## against a real WorldMapTileData, undoes every one of them, and asserts the data lands back on
## its EXACT starting `toDictionary()` -- not "looks right", byte-for-byte structural equality.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const History = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const ObjectLayer = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")

const TILE_IDS := ["t000", "t001", "t002", "t003", "t004", "-"]

var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 20260906

	_checkCoalescing()
	_checkMultiWriteWithinStrokeCollapses()
	_checkNoNetChangeIsNotPushed()
	_checkUndoRedoSymmetry()
	_checkRedoStackClearsOnNewStroke()
	_checkDepthBound()
	_checkTouchedCellsReported()
	_checkPaintWithoutOpenStrokeRefused()
	_checkFuzzRoundTrip()
	_checkMixedKindStrokeRefused()
	_checkHeightUndoRedo()
	_checkHeightFloatToleranceNoOp()
	_checkObjectUndoRedo()
	_checkFuzzRoundTripAllKinds()

	print("")
	print("probe_edit_history: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP EDIT HISTORY OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _freshData() -> WorldMapTileData:
	var data: WorldMapTileData = MapData.create("probe", Vector2i(6, 6))
	return data


func _checkCoalescing() -> void:
	print("-- a drag across many cells is one undo entry --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	for x in 5:
		history.paintCell(data, Vector2i(x, 0), "t001")
	if not history.endStroke():
		_fail("a 5-cell stroke reported nothing to push")
		return
	if history.undoCount() != 1:
		_fail("5 painted cells produced %d undo entries, expected 1" % history.undoCount())
		return
	history.undo(data)
	for x in 5:
		if data.getCell("ground", Vector2i(x, 0)) != MapData.EMPTY:
			_fail("cell (%d, 0) did not revert on a single undo" % x)
			return
	print("  ok    5 cells painted, 1 undo entry, 1 undo reverts all 5")


func _checkMultiWriteWithinStrokeCollapses() -> void:
	print("-- repainting the same cell within a stroke keeps the ORIGINAL before --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(2, 2), "t001")
	history.paintCell(data, Vector2i(2, 2), "t002")
	history.paintCell(data, Vector2i(2, 2), "t003")
	history.endStroke()
	history.undo(data)
	var reverted := data.getCell("ground", Vector2i(2, 2))
	if reverted != MapData.EMPTY:
		_fail("undo landed on '%s', expected the pre-stroke EMPTY, not an intermediate value" % reverted)
		return
	print("  ok    3 writes to one cell in one stroke; undo reaches the pre-stroke value")


func _checkNoNetChangeIsNotPushed() -> void:
	print("-- a stroke that nets to nothing is not pushed --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(1, 1), "t001")
	history.paintCell(data, Vector2i(1, 1), MapData.EMPTY)
	var pushed := history.endStroke()
	if pushed:
		_fail("a paint-then-revert-to-original stroke was pushed anyway")
		return
	if history.canUndo():
		_fail("canUndo() is true after a net-zero stroke")
		return
	print("  ok    paint-then-revert nets to nothing; endStroke reports false, nothing pushed")

	# A stroke touching several cells where only SOME net to a real change keeps only those.
	var data2 := _freshData()
	var history2 := History.new()
	history2.beginStroke("ground")
	history2.paintCell(data2, Vector2i(0, 0), "t001")
	history2.paintCell(data2, Vector2i(0, 0), MapData.EMPTY)  # nets to nothing
	history2.paintCell(data2, Vector2i(1, 0), "t002")  # a real change
	history2.endStroke()
	history2.undo(data2)
	if data2.getCell("ground", Vector2i(1, 0)) != MapData.EMPTY:
		_fail("the real change in a mixed stroke did not undo")
		return
	print("  ok    a mixed stroke keeps only the cells with a net effect")


func _checkUndoRedoSymmetry() -> void:
	print("-- redo re-applies exactly what undo removed --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(3, 3), "t004")
	history.endStroke()
	var beforeUndo := data.toDictionary()
	history.undo(data)
	if data.getCell("ground", Vector2i(3, 3)) != MapData.EMPTY:
		_fail("undo did not clear the cell")
		return
	history.redo(data)
	if data.toDictionary() != beforeUndo:
		_fail("redo did not reproduce the pre-undo state exactly")
		return
	print("  ok    undo then redo reproduces the state exactly")


func _checkRedoStackClearsOnNewStroke() -> void:
	print("-- a new stroke after an undo clears the redo stack --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(0, 0), "t001")
	history.endStroke()
	history.undo(data)
	if not history.canRedo():
		_fail("expected something redoable after one undo")
		return
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(5, 5), "t002")
	history.endStroke()
	if history.canRedo():
		_fail("redo stack survived a new stroke")
		return
	print("  ok    redo stack cleared the moment a new stroke was pushed")


func _checkDepthBound() -> void:
	print("-- undo depth is bounded --")
	var data := _freshData()
	var history := History.new()
	history.maxDepth = 3
	for i in 5:
		history.beginStroke("ground")
		history.paintCell(data, Vector2i(i % 6, 0), "t00%d" % (i % 5))
		history.endStroke()
	if history.undoCount() != 3:
		_fail("maxDepth 3 after 5 strokes left %d entries" % history.undoCount())
		return
	print("  ok    5 strokes, maxDepth 3, undo stack holds exactly 3")


func _checkTouchedCellsReported() -> void:
	print("-- undo/redo report exactly the cells they touched --")
	var data := _freshData()
	var history := History.new()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(0, 0), "t001")
	history.paintCell(data, Vector2i(4, 4), "t002")
	history.endStroke()
	var touched: Dictionary = history.undo(data)
	if str(touched.get("layerID", "")) != "ground":
		_fail("undo reported layerID '%s'" % touched.get("layerID", ""))
		return
	var cells: Array = touched.get("cells", [])
	if cells.size() != 2 or not cells.has(Vector2i(0, 0)) or not cells.has(Vector2i(4, 4)):
		_fail("undo reported cells %s, expected exactly (0,0) and (4,4)" % [cells])
		return
	var redoTouched: Dictionary = history.redo(data)
	if redoTouched.get("cells", []) != cells:
		_fail("redo reported a different cell set than undo: %s vs %s" % [
			redoTouched.get("cells", []), cells
		])
		return
	print("  ok    undo and redo both report the exact 2 touched cells")


func _checkPaintWithoutOpenStrokeRefused() -> void:
	print("-- paintCell without an open stroke is refused, not silently applied --")
	var data := _freshData()
	var history := History.new()
	var result := history.paintCell(data, Vector2i(0, 0), "t001")
	if result:
		_fail("paintCell succeeded with no open stroke")
		return
	if data.getCell("ground", Vector2i(0, 0)) != MapData.EMPTY:
		_fail("data was mutated despite paintCell refusing")
		return
	print("  ok    refused, and the data was not touched")


## The headline check -- see the class note. A hundred randomised strokes of random size against
## random cells with random tile ids (including erasing to EMPTY), interleaved with occasional
## undos, all eventually undone back to the start.
func _checkFuzzRoundTrip() -> void:
	print("-- 100 randomised strokes, undone, reproduce the exact starting state --")
	var data := _freshData()
	var history := History.new()
	history.maxDepth = 1000  # unbounded for this check -- every stroke must be undoable
	var startState := data.toDictionary()

	var strokeCount := 0
	for _i in 100:
		history.beginStroke("ground")
		var strokeSize := _rng.randi_range(1, 8)
		for _j in strokeSize:
			var cell := Vector2i(_rng.randi_range(0, 5), _rng.randi_range(0, 5))
			var tileID: String = TILE_IDS[_rng.randi_range(0, TILE_IDS.size() - 1)]
			history.paintCell(data, cell, tileID)
		if history.endStroke():
			strokeCount += 1

	var postFuzzState := data.toDictionary()
	if postFuzzState == startState:
		_fail("100 strokes left the data unchanged; the fuzz did not exercise anything")
		return

	var undone := 0
	while history.canUndo():
		history.undo(data)
		undone += 1
	if undone != strokeCount:
		_fail("pushed %d strokes but undid %d" % [strokeCount, undone])
		return
	if data.toDictionary() != startState:
		_fail("after undoing every stroke, data does not match its exact starting state")
		return
	print("  ok    %d net-nonzero strokes pushed and fully undone; exact byte match" % strokeCount)

	# And redoing everything reaches the POST-FUZZ state again, exactly -- not just "some" state.
	var redone := 0
	while history.canRedo():
		history.redo(data)
		redone += 1
	if redone != strokeCount:
		_fail("undid %d strokes but redid %d" % [strokeCount, redone])
		return
	if data.toDictionary() != postFuzzState:
		_fail("after redoing every stroke, data does not match the exact post-fuzz state")
		return
	print("  ok    redoing every stroke reproduces the post-fuzz state exactly")


func _freshHexData() -> WorldMapTileData:
	var data: WorldMapTileData = MapData.create("probe_hex", Vector2i(6, 6), MapData.LAYOUT_HEX_FLAT)
	HeightField.ensureLayer(data)
	ObjectLayer.ensureLayer(data)
	return data


## WMH-9's own claim: a stroke is homogeneous. A tile write claims "tile" for the stroke; a
## height write inside that same stroke must be refused outright, not silently folded in, and
## the refusal must not have mutated the data it refused to touch.
func _checkMixedKindStrokeRefused() -> void:
	print("-- mixing edit kinds within one stroke is refused, not silently mixed --")
	var data := _freshHexData()
	var history := History.new()
	history.beginStroke("ground")
	if not history.paintCell(data, Vector2i(1, 1), "t001"):
		_fail("the first (tile) write in the stroke was refused")
		return
	if history.paintHeight(data, Vector3i(1, 1, 0), 2.0):
		_fail("a height write inside an open tile stroke was accepted")
		return
	if not is_zero_approx(HeightField.heightAt(data, Vector3i(1, 1, 0))):
		_fail("the refused height write still mutated the data")
		return
	history.endStroke()
	print("  ok    a height write inside an open tile stroke is refused and leaves data alone")


## A sculpt undoes and redoes exactly like a paint stroke -- the whole point of widening the same
## stack rather than building a second one.
func _checkHeightUndoRedo() -> void:
	print("-- a sculpt undoes and redoes like any other stroke --")
	var data := _freshHexData()
	var history := History.new()
	var vertex := Vector3i(2, 3, 1)

	history.beginStroke("heights")
	if not history.paintHeight(data, vertex, 4.5):
		_fail("paintHeight reported no change on a fresh vertex")
		return
	if not history.endStroke():
		_fail("a real height edit was not pushed")
		return
	if not is_equal_approx(HeightField.heightAt(data, vertex), 4.5):
		_fail("the sculpt did not take")
		return

	history.undo(data)
	if not is_zero_approx(HeightField.heightAt(data, vertex)):
		_fail("undoing the sculpt left it at %f, expected 0" % HeightField.heightAt(data, vertex))
		return
	history.redo(data)
	if not is_equal_approx(HeightField.heightAt(data, vertex), 4.5):
		_fail("redoing the sculpt did not restore 4.5")
		return
	print("  ok    Ctrl+Z after a sculpt undoes the sculpt, and redo reapplies it")


## WMH-9's own risk, made concrete: two writes within one stroke, each a real change against its
## own immediately-prior value (so neither is caught by `WorldMapHeightField.setHeightAt`'s own
## per-write tolerance check), whose STROKE-LEVEL net effect is float-close to the value the
## vertex already held but not bit-identical to it. An exact `!=` at `endStroke()` would push
## this as a real edit; `_valuesEqual`'s tolerance must not.
func _checkHeightFloatToleranceNoOp() -> void:
	print("-- a stroke whose net effect is float-tolerance-equal to its start is not pushed --")
	var data := _freshHexData()
	var history := History.new()
	var vertex := Vector3i(3, 3, 0)

	history.beginStroke("heights")
	history.paintHeight(data, vertex, 1.0)
	history.endStroke()
	var depthAfterFirst := history.undoCount()

	history.beginStroke("heights")
	if not history.paintHeight(data, vertex, 1.5):
		_fail("the first write of the second stroke did not register as a change")
		return
	if not history.paintHeight(data, vertex, 1.0 + 1e-7):
		_fail("the second write of the second stroke did not register as a change")
		return
	var pushed := history.endStroke()
	if pushed:
		_fail("a stroke whose net effect is float-tolerance-equal to its start was pushed")
		return
	if history.undoCount() != depthAfterFirst:
		_fail("undo depth changed even though endStroke reported no push")
		return
	print("  ok    net-zero-within-tolerance sculpt is not pushed as a real edit")


## Placement, move, rotation and removal -- every mutator WorldMapObjectLayer exposes -- each
## undo and redo through the same stack a tile edit uses. The id itself is the thing worth
## checking hardest: undoing a REMOVAL must restore the exact same id, not a fresh one, since
## that id is exactly what a quest or a save file would still be holding.
func _checkObjectUndoRedo() -> void:
	print("-- object placement, move, facing and removal all undo and redo --")
	var data := _freshHexData()
	var history := History.new()

	history.beginStroke("objects")
	var record := history.placeObject(data, "house", Vector2i(2, 2))
	if not history.endStroke():
		_fail("placing an object was not pushed as an edit")
		return
	var id := str(record[ObjectLayer.K_ID])
	if ObjectLayer.find(data, id).is_empty():
		_fail("placeObject did not actually place the object")
		return

	history.undo(data)
	if not ObjectLayer.find(data, id).is_empty():
		_fail("undoing a placement left the object behind")
		return
	history.redo(data)
	var restored := ObjectLayer.find(data, id)
	if restored.is_empty() or str(restored[ObjectLayer.K_ID]) != id:
		_fail("redoing a placement did not restore the object under the same id")
		return

	history.beginStroke("objects")
	if not history.moveObject(data, id, Vector2i(4, 4)):
		_fail("moveObject reported failure")
		return
	history.endStroke()
	if ObjectLayer.cellOf(ObjectLayer.find(data, id)) != Vector2i(4, 4):
		_fail("the move did not take")
		return
	history.undo(data)
	if ObjectLayer.cellOf(ObjectLayer.find(data, id)) != Vector2i(2, 2):
		_fail("undoing the move did not restore the original cell")
		return
	history.redo(data)
	if ObjectLayer.cellOf(ObjectLayer.find(data, id)) != Vector2i(4, 4):
		_fail("redoing the move did not reapply it")
		return

	history.beginStroke("objects")
	history.setObjectFacing(data, id, 3)
	history.endStroke()
	history.undo(data)
	if int(ObjectLayer.find(data, id)[ObjectLayer.K_FACING]) != 0:
		_fail("undoing the facing change did not restore facing 0")
		return
	history.redo(data)
	if int(ObjectLayer.find(data, id)[ObjectLayer.K_FACING]) != 3:
		_fail("redoing the facing change did not reapply facing 3")
		return

	history.beginStroke("objects")
	if not history.removeObject(data, id):
		_fail("removeObject reported failure")
		return
	history.endStroke()
	if not ObjectLayer.find(data, id).is_empty():
		_fail("the object survived removal")
		return
	history.undo(data)
	var revived := ObjectLayer.find(data, id)
	if revived.is_empty():
		_fail("undoing a removal did not restore the object")
		return
	if str(revived[ObjectLayer.K_ID]) != id:
		_fail("undoing a removal restored the object under a different id -- exactly the failure a quest reference cannot survive")
		return
	print("  ok    place, move, rotate and remove all undo and redo; ids never change")


## `toDictionary()` with every list layer's `NEXT_ID` zeroed out. `NEXT_ID` is deliberately NOT
## rewound by undo -- an id must never be reissued, full stop (WorldMapObjectLayer's own class
## note), so undoing a placement removes the object but leaves the allocator exactly where it
## was. That makes `NEXT_ID` the one field in the whole document that is EXPECTED to differ
## between the start of a fuzz run and its own full undo, and comparing it away here is what
## keeps this test honest about what WMH-9 actually promises rather than accidentally asserting
## something WMH-7 deliberately does not do.
func _stateIgnoringAllocators(data: WorldMapTileData) -> Dictionary:
	var state := data.toDictionary()
	for layer in state["LAYERS"]:
		if str((layer as Dictionary).get("KIND", "")) == MapData.KIND_LIST:
			(layer as Dictionary)["NEXT_ID"] = 0
	return state


func _allocatorTotal(data: WorldMapTileData) -> int:
	var total := 0
	for layer in data.toDictionary()["LAYERS"]:
		if str((layer as Dictionary).get("KIND", "")) == MapData.KIND_LIST:
			total += int((layer as Dictionary).get("NEXT_ID", 0))
	return total


## The extended fuzz the item's own validation asks for: tile, height and object strokes
## interleaved at random, all undone, reproducing the exact starting state -- modulo the
## allocator caveat above, which is checked separately (monotonic, never decreasing) rather than
## folded into a byte-equality check it would only ever fail.
func _checkFuzzRoundTripAllKinds() -> void:
	print("-- 100 randomised strokes interleaving tile, height and object edits, all undone --")
	var data := _freshHexData()
	var history := History.new()
	history.maxDepth = 1000
	var startState := _stateIgnoringAllocators(data)
	var allocatorBefore := _allocatorTotal(data)

	var placedIDs: Array[String] = []
	var strokeCount := 0
	for _i in 100:
		var kind := _rng.randi_range(0, 2)
		if kind == 0:
			history.beginStroke("ground")
			for _j in _rng.randi_range(1, 5):
				var cell := Vector2i(_rng.randi_range(0, 5), _rng.randi_range(0, 5))
				history.paintCell(data, cell, TILE_IDS[_rng.randi_range(0, TILE_IDS.size() - 1)])
			if history.endStroke():
				strokeCount += 1
		elif kind == 1:
			history.beginStroke("heights")
			for _j in _rng.randi_range(1, 5):
				var vertex := Vector3i(
					_rng.randi_range(0, 5), _rng.randi_range(0, 5), _rng.randi_range(0, 1)
				)
				history.paintHeight(data, vertex, _rng.randf_range(-5.0, 5.0))
			if history.endStroke():
				strokeCount += 1
		else:
			history.beginStroke("objects")
			var action := _rng.randi_range(0, 3) if not placedIDs.is_empty() else 0
			if action == 0:
				var cell := Vector2i(_rng.randi_range(0, 5), _rng.randi_range(0, 5))
				var placed := history.placeObject(data, "house", cell)
				if not placed.is_empty():
					placedIDs.append(str(placed[ObjectLayer.K_ID]))
			elif action == 1:
				var moveID: String = placedIDs[_rng.randi_range(0, placedIDs.size() - 1)]
				history.moveObject(
					data, moveID, Vector2i(_rng.randi_range(0, 5), _rng.randi_range(0, 5))
				)
			elif action == 2:
				var faceID: String = placedIDs[_rng.randi_range(0, placedIDs.size() - 1)]
				history.setObjectFacing(data, faceID, _rng.randi_range(0, 5))
			else:
				var removeID: String = placedIDs[_rng.randi_range(0, placedIDs.size() - 1)]
				if history.removeObject(data, removeID):
					placedIDs.erase(removeID)
			if history.endStroke():
				strokeCount += 1

	var postFuzzState := _stateIgnoringAllocators(data)
	if postFuzzState == startState:
		_fail("100 mixed strokes left the data unchanged; the fuzz did not exercise anything")
		return

	var undone := 0
	while history.canUndo():
		history.undo(data)
		undone += 1
	if undone != strokeCount:
		_fail("pushed %d mixed strokes but undid %d" % [strokeCount, undone])
		return
	if _stateIgnoringAllocators(data) != startState:
		_fail("after undoing every mixed stroke, data does not match its exact starting state")
		return
	if _allocatorTotal(data) < allocatorBefore:
		_fail("an object id allocator went BACKWARDS after undo, which means an id could be reissued")
		return
	print("  ok    %d net-nonzero mixed strokes pushed and fully undone; exact match modulo allocators" % strokeCount)

	var redone := 0
	while history.canRedo():
		history.redo(data)
		redone += 1
	if redone != strokeCount:
		_fail("undid %d mixed strokes but redid %d" % [strokeCount, redone])
		return
	if _stateIgnoringAllocators(data) != postFuzzState:
		_fail("after redoing every mixed stroke, data does not match the exact post-fuzz state")
		return
	print("  ok    redoing every mixed stroke reproduces the post-fuzz state exactly")
