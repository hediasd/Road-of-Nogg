## WMH-10B's self-contained validation: the three layers the editor could not reach are reachable
## with a mouse, and every edit made that way is one undo away from gone.
##
## DRIVEN THROUGH `_beginToolGesture` / `_endToolGesture`, the controller's own gesture entry
## points, never by calling `WorldMapHeightField`, `WorldMapObjectLayer` or `WorldMapBrushes`
## underneath. That distinction is the whole point of this file: Gate 3 found a data model that
## worked perfectly and an editor that could not drive it, and a probe that called the modules
## directly would have passed happily throughout.
##
## Screen positions are computed by PROJECTING a known world point back through the same camera
## and letterbox arithmetic `_viewportPoint` uses, rather than guessed. A guessed position that
## misses the map makes every assertion below pass for the wrong reason -- the trap
## `probe_editor_input_dispatch.gd` names in its own header, in a different form.
##
## WRITES TO THE REAL `data/worldmap/authored/`, like `probe_document_loop.gd` and for the same
## reason. `_cleanup()` removes everything before and after the run.

extends SceneTree

const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")
const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")

const TEST_NAME := "_probe_editor_tools_test"
const LATTICE := Vector2i(11, 8)

var _failures := 0
var _scene: Node
var _hud: WorldMapEditorHud


func _initialize() -> void:
	_cleanup()
	# Headless gives the root window no size of its own, so the editor's `Display` TextureRect
	# lays out to zero width and every screen-to-map pick correctly refuses. Sized here to the
	# same 1152x648 the scene is authored against -- the picks under test are pure arithmetic
	# over that rect, so a stated size is as honest as a real window and does not need one.
	_scene = EditorScene.instantiate()
	root.add_child(_scene)
	await process_frame
	root.size = Vector2i(1152, 648)
	for i in 8:
		await process_frame
	_hud = _scene.get("_editorHud")

	_scene.call("requestNewDocument", LATTICE, TEST_NAME)
	for i in 2:
		await process_frame

	_checkLayerRows()
	_checkValueRowPerKind()
	_checkTrianglePick()
	_checkSculpt()
	_checkSculptSharesVerticesOnce()
	_checkPlaceTurnRemove()
	_checkDetailPaint()
	_checkMismatchedToolSaysSo()

	_cleanup()
	print("")
	print("probe_editor_tools: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP EDITOR TOOLS OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _cleanup() -> void:
	for path in [MapData.pathFor(TEST_NAME), Baker.generatedPathFor(TEST_NAME)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _document() -> WorldMapTileData:
	return _scene.call("openDocument")


func _history() -> WorldMapEditHistory:
	return _scene.get("_history")


## The screen position that looks at a region-local point on the drawn surface. The inverse of
## `_viewportPoint`, composed with the camera's own projection, so a click can be aimed at a
## known cell instead of hoped at one.
func _screenFor(local: Vector2) -> Vector2:
	var ground: WorldMapGround = _scene.get("_ground")
	var camera: WorldMapEditorCamera = _scene.get("_editorCamera")
	var display: TextureRect = _scene.get("_display")
	var viewport: SubViewport = _scene.get("_viewport")
	var region := ground.regionRect()
	var height := WorldMapHeightField.sample(_document(), local)
	var world := Vector3(region.position.x + local.x, height, region.position.y + local.y)
	var viewportPoint := camera.unproject_position(world)
	var displayRect := display.get_global_rect()
	var bufferSize := Vector2(viewport.size)
	var scale := minf(displayRect.size.x / bufferSize.x, displayRect.size.y / bufferSize.y)
	var drawnOrigin := displayRect.position + (displayRect.size - bufferSize * scale) * 0.5
	return drawnOrigin + viewportPoint * scale


func _clickAt(local: Vector2) -> void:
	var screen := _screenFor(local)
	_scene.call("_beginToolGesture", screen)
	_scene.call("_endToolGesture", screen)


func _use(layerID: String, toolID: String, value: String) -> void:
	_scene.call("setActiveLayerID", layerID)
	_scene.call("setActiveToolID", toolID)
	_hud.selectTileID(value)


func _checkLayerRows() -> void:
	print("-- the layer selector lists every layer a hex map can carry --")
	var ids: Array[String] = []
	for layer in _scene.get("LAYERS"):
		ids.append(str((layer as Dictionary)["id"]))
	for wanted in ["ground", "overlay", "heights", "objects", "detail"]:
		if not ids.has(wanted):
			_fail("the layer table has no '%s' row" % wanted)
			return
	for wanted in ["heights", "objects", "detail"]:
		if not bool(_scene.call("layerIsEditable", wanted)):
			_fail("'%s' is not editable on a fresh hex document" % wanted)
			return
	# Reachable and empty at once: a fresh document has none of the three, and the rows must say
	# so rather than claiming content that is not there.
	var doc := _document()
	for absent in ["heights", "objects", "detail"]:
		if doc.layers.has(absent):
			_fail("a fresh document already carries a '%s' layer" % absent)
			return
	_ok("5 rows; heights/objects/detail all reachable and all still empty")


func _checkValueRowPerKind() -> void:
	print("-- the value row offers what the active layer's tool takes --")
	_scene.call("setActiveLayerID", "heights")
	if _hud.selectedValue().is_empty() or _hud.tileLabel.text != "Sculpt":
		_fail("the height layer's value row reads '%s' offering '%s'"
			% [_hud.tileLabel.text, _hud.selectedValue()])
		return
	var sculptValue := _hud.selectedValue()
	if not (sculptValue == "flatten" or absf(float(sculptValue)) > 0.0):
		_fail("the height row offers '%s', which is neither a step nor flatten" % sculptValue)
		return

	_scene.call("setActiveLayerID", "objects")
	if _hud.tileLabel.text != "Object":
		_fail("the object layer's value row reads '%s'" % _hud.tileLabel.text)
		return
	_hud.selectTileID("remove")
	if _hud.selectedValue() != "remove":
		_fail("the object row has no Remove entry")
		return

	_scene.call("setActiveLayerID", "ground")
	if _hud.tileLabel.text != "Tile" or not _hud.selectedValue().begins_with("t"):
		_fail("the ground layer's value row reads '%s' offering '%s'"
			% [_hud.tileLabel.text, _hud.selectedValue()])
		return
	_ok("Sculpt over heights, Object over objects, Tile over ground")


## The decisive one for sub-triangle authoring: two points inside the SAME hex, in different
## sixths, must resolve to different slots. A pick that only resolved the cell would return the
## same answer for both and every detail edit would land in slot 0.
func _checkTrianglePick() -> void:
	print("-- a click resolves the triangle it landed in, not merely the cell --")
	var cell := Vector2i(5, 4)
	var centre := WorldMapHexGrid.cellCentre(cell)
	var seen := {}
	for slot in WorldMapTileData.DETAIL_SLOTS_PER_CELL:
		var a: Vector2 = WorldMapHeightField.CORNER_OFFSETS[slot]
		var b: Vector2 = WorldMapHeightField.CORNER_OFFSETS[
			(slot + 1) % WorldMapTileData.DETAIL_SLOTS_PER_CELL
		]
		# Well inside the triangle: the centroid of (centre, a, b), pulled off every edge.
		var probe := centre + (a + b) / 3.0
		var picked = _scene.call("_pickTriangle", _screenFor(probe))
		if picked == null:
			_fail("slot %d's own interior point picked nothing" % slot)
			return
		var target := picked as Vector3i
		if Vector2i(target.x, target.y) != cell:
			_fail("slot %d's interior point picked cell %s, expected %s"
				% [slot, Vector2i(target.x, target.y), cell])
			return
		if target.z != slot:
			_fail("a point inside slot %d picked slot %d" % [slot, target.z])
			return
		seen[target.z] = true
	if seen.size() != WorldMapTileData.DETAIL_SLOTS_PER_CELL:
		_fail("six interior points resolved to %d distinct slots" % seen.size())
		return
	_ok("six points in one hex resolve to its six distinct slots")


func _checkSculpt() -> void:
	print("-- sculpt raises the terrain under the pointer, and one undo puts it back --")
	_use("heights", "sculpt", "1.0")
	var cell := Vector2i(4, 3)
	var doc := _document()
	var before := WorldMapHeightField.centreHeight(doc, cell)
	var depth := _history().undoCount()
	_clickAt(WorldMapHexGrid.cellCentre(cell))
	var after := WorldMapHeightField.centreHeight(doc, cell)
	if not is_equal_approx(after, before + 1.0):
		_fail("a +1.00 sculpt moved %s from %.3f to %.3f" % [cell, before, after])
		return
	if _history().undoCount() != depth + 1:
		_fail("the sculpt did not land as exactly one undo entry")
		return
	_history().undo(doc)
	if not is_equal_approx(WorldMapHeightField.centreHeight(doc, cell), before):
		_fail("undoing the sculpt did not restore %.3f" % before)
		return
	_history().redo(doc)
	if not is_equal_approx(WorldMapHeightField.centreHeight(doc, cell), after):
		_fail("redoing the sculpt did not restore %.3f" % after)
		return
	# The named risk of this item, checked rather than assumed: a sculpt that changes the document
	# and not the screen. A flat map's ground is a PlaneMesh; a sculpted one is the ArrayMesh
	# `WorldMapHeightField.buildSurfaceMesh` returns, and the editor only swaps it in if
	# `_afterHeightsEdited` actually ran with a texture to hand.
	var ground: WorldMapGround = _scene.get("_ground")
	if not (ground.mesh is ArrayMesh):
		_fail("after a sculpt the editor's ground is still a %s" % ground.mesh.get_class())
		return
	_ok("+1.00 at %s, one entry, undone and redone exactly; the preview surface is a real mesh"
		% cell)


## Three hexes share every vertex on this lattice, so a drag across neighbours must not raise the
## shared ones twice -- a ridge along the drag is what that bug looks like on screen.
func _checkSculptSharesVerticesOnce() -> void:
	print("-- a drag across neighbours raises each shared vertex once --")
	var doc := _document()
	var first := Vector2i(6, 5)
	var second := Vector2i(6, 6)
	_use("heights", "sculpt", "1.0")
	var screen := _screenFor(WorldMapHexGrid.cellCentre(first))
	_scene.call("_beginToolGesture", screen)
	_scene.call("_sculptCell", second)
	_scene.call("_endToolGesture", _screenFor(WorldMapHexGrid.cellCentre(second)))

	var shared: Array[Vector3i] = []
	for vertex in WorldMapHeightField.cellVertices(first):
		if WorldMapHeightField.cellVertices(second).has(vertex):
			shared.append(vertex)
	if shared.is_empty():
		_fail("test setup: %s and %s share no vertex" % [first, second])
		return
	for vertex in shared:
		var height := WorldMapHeightField.heightAt(doc, vertex)
		if not is_equal_approx(height, 1.0):
			_fail("shared vertex %s rose to %.3f, expected 1.00" % [vertex, height])
			return
	_history().undo(doc)
	_ok("%d shared vertices each rose exactly 1.00, not 2.00" % shared.size())


func _checkPlaceTurnRemove() -> void:
	print("-- place, turn and remove, all from one tool --")
	var doc := _document()
	var cell := Vector2i(3, 5)
	var centre := WorldMapHexGrid.cellCentre(cell)
	_use("objects", "place", "house")
	var depth := _history().undoCount()
	_clickAt(centre)
	if WorldMapObjectLayer.count(doc) != 1:
		_fail("a click on the object layer placed %d objects" % WorldMapObjectLayer.count(doc))
		return
	var record: Dictionary = WorldMapObjectLayer.items(doc)[0]
	var id := str(record[WorldMapObjectLayer.K_ID])
	if WorldMapObjectLayer.cellOf(record) != cell:
		_fail("the object landed at %s, expected %s"
			% [WorldMapObjectLayer.cellOf(record), cell])
		return

	# A second click on the same cell turns it rather than stacking a second building there.
	var facing := int(record[WorldMapObjectLayer.K_FACING])
	_clickAt(centre)
	if WorldMapObjectLayer.count(doc) != 1:
		_fail("clicking an occupied cell placed a second object")
		return
	var turned := int(WorldMapObjectLayer.find(doc, id)[WorldMapObjectLayer.K_FACING])
	if turned == facing:
		_fail("clicking an occupied cell left the facing at %d" % facing)
		return

	# The preview is what makes a placement visible; without it the tool edits an invisible layer.
	var preview: Node3D = _scene.get("_objectsPreview")
	if preview == null or preview.get_child_count() == 0:
		_fail("no object preview was built for a placed object")
		return

	_use("objects", "place", "remove")
	_clickAt(centre)
	if WorldMapObjectLayer.count(doc) != 0:
		_fail("Remove left %d objects" % WorldMapObjectLayer.count(doc))
		return

	if _history().undoCount() != depth + 3:
		_fail("place, turn and remove landed as %d entries, expected 3"
			% (_history().undoCount() - depth))
		return
	_history().undo(doc)
	if WorldMapObjectLayer.count(doc) != 1:
		_fail("undoing the removal did not bring the object back")
		return
	if str((WorldMapObjectLayer.items(doc)[0] as Dictionary)[WorldMapObjectLayer.K_ID]) != id:
		_fail("undoing the removal brought back a different id")
		return
	_history().undo(doc)
	_history().undo(doc)
	_ok("placed as %s, turned %d -> %d, removed, and every step undone" % [id, facing, turned])


## The item's second named risk, checked directly: `WorldMapTileData.setCell` refuses a non-grid
## layer by returning false, so a tile tool aimed at the height layer does nothing at all. Nothing
## corrupts -- the danger is the SILENCE, which is the same shape as Gate 1's picker refusing a
## click without a word.
func _checkMismatchedToolSaysSo() -> void:
	print("-- a tool aimed at the wrong layer kind says so --")
	var doc := _document()
	var cell := Vector2i(2, 2)
	var before := doc.getCell("ground", cell)
	_use("heights", "paint", "1.0")
	_clickAt(WorldMapHexGrid.cellCentre(cell))
	if doc.getCell("ground", cell) != before:
		_fail("a paint aimed at the height layer changed the ground")
		return
	var said := _hud.status.text
	if not (said.to_lower().contains("tile") and said.to_lower().contains("height")):
		_fail("painting on the height layer reported '%s'" % said)
		return
	_use("ground", "sculpt", "1.0")
	_clickAt(WorldMapHexGrid.cellCentre(cell))
	if not _hud.status.text.to_lower().contains("terrain height"):
		_fail("sculpting on the ground layer reported '%s'" % _hud.status.text)
		return
	_ok("both mismatches refused with a message naming the tool and the layer")


func _checkDetailPaint() -> void:
	print("-- a triangle paint lands in the slot clicked, and undoes as one edit --")
	var doc := _document()
	var cell := Vector2i(7, 3)
	var slot := 2
	var centre := WorldMapHexGrid.cellCentre(cell)
	var a: Vector2 = WorldMapHeightField.CORNER_OFFSETS[slot]
	var b: Vector2 = WorldMapHeightField.CORNER_OFFSETS[(slot + 1) % 6]
	var target := centre + (a + b) / 3.0

	_scene.call("setActiveLayerID", "detail")
	_scene.call("setActiveToolID", "paintTriangle")
	var tileID := _hud.selectedValue()
	if not tileID.begins_with("t"):
		_fail("the detail layer's value row offers '%s', not a tile" % tileID)
		return
	var depth := _history().undoCount()
	_clickAt(target)

	if not doc.layers.has("detail"):
		_fail("painting a triangle did not create the detail layer")
		return
	if doc.getDetail("detail", cell, slot) != tileID:
		_fail("slot %d of %s holds '%s', expected '%s'"
			% [slot, cell, doc.getDetail("detail", cell, slot), tileID])
		return
	for other in 6:
		if other == slot:
			continue
		if doc.getDetail("detail", cell, other) != WorldMapTileData.EMPTY:
			_fail("painting slot %d also filled slot %d" % [slot, other])
			return
	if _history().undoCount() != depth + 1:
		_fail("the triangle paint did not land as exactly one undo entry")
		return
	_history().undo(doc)
	if doc.getDetail("detail", cell, slot) != WorldMapTileData.EMPTY:
		_fail("undoing the triangle paint left '%s' in place"
			% doc.getDetail("detail", cell, slot))
		return
	_ok("slot %d of %s took '%s' alone, and one undo cleared it" % [slot, cell, tileID])
