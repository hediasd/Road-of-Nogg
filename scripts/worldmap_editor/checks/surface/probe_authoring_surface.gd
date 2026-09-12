extends SceneTree

## The three things an author reported about the hex editor's own 3D stage, each asserted as a
## property of the running editor rather than as a screenshot somebody looked at once.
##
## NOT HEADLESS. Every claim here needs a real buffer: the plane's mesh, the viewport's size, and
## a bake that actually updates. Run it through the real renderer, like the workspace probes.
##
## 1. THE PLANE IS THE DOCUMENT. A shipping ground extends one fog length past the region so the
##    haze can close before the art runs out; on an authoring surface that skirt was a region's
##    sea colour stretched nine map-widths in every direction, with the map a small dark square in
##    the middle of it. An authoring surface stops at the document's own edge.
## 2. THE BUFFER IS NATIVE. The explorer's 0.4 render scale drew the editor's overlay into a
##    buffer with less than half a pixel per grid line and nearest-upscaled the result.
## 3. A HELD DRAG PAINTS AS IT MOVES. The bake, not just the document, has to advance on every
##    pointer sample -- the defect was that it advanced only when the button came up, so a drag
##    showed nothing at all until it ended.

const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Any populated frame of the starter sheet. `t000` is its first, and the probe only needs A tile.
const STARTER_TILE := "t000"

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	for i in range(6):
		await process_frame
	editor.call("_newDocument", Vector2i(19, 14), "AuthoringSurfaceProbe", "temp2_hex32_starter")
	for i in range(10):
		await process_frame

	var ground := editor.get_node("World/FoundationMap/Ground") as WorldMapGround
	var viewport := editor.get_node("World") as SubViewport
	var display := editor.get_node("Display") as TextureRect

	_require(ground.authoring_surface, "the editor's ground is not marked as an authoring surface")

	var region: Rect2 = ground.regionRect()
	var plane: AABB = ground.get_aabb()
	_require(
		is_equal_approx(plane.size.x, region.size.x) and is_equal_approx(plane.size.z, region.size.y),
		"the plane is not the document: %s against a %s region" % [plane.size, region.size]
	)

	# The same framing on an ORDINARY ground still gets its skirt. Without this the first check
	# would pass just as well if the margin had been removed for everything, including exports.
	var shipping := WorldMapGround.new()
	var framing: Dictionary = editor.get("_framing")
	var margin := shipping.planeMargin(framing, Color.BLACK, Color.BLACK)
	_require(
		margin > 0.0 and is_equal_approx(margin, float(Uniforms.complete(framing)[Uniforms.K_FOG_END])),
		"a shipping ground lost its fog skirt: margin %f" % margin
	)
	shipping.free()

	_require(
		viewport.size == Vector2i(display.get_rect().size),
		"the editor buffer is not native: %s against a %s display" % [viewport.size, display.get_rect().size]
	)

	var hud = editor.get("_editorHud")
	editor.call("setActiveLayerID", "ground")
	editor.call("setActiveToolID", "paint")
	hud.selectTileID(STARTER_TILE)
	await process_frame
	_require(not hud.requiresTileSelection(), "could not select a starter tile to paint with")

	var baker = editor.get("_baker")
	var beforePress: PackedByteArray = baker.texture().get_image().get_data()

	var rect := display.get_global_rect()
	var start := rect.position + rect.size * 0.5
	editor.call("_beginToolGesture", start)
	await process_frame
	_require(bool(editor.get("_strokeOpen")), "paint did not open a stroke")
	var afterPress: PackedByteArray = baker.texture().get_image().get_data()
	_require(afterPress != beforePress, "the press itself did not reach the bake")

	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(0.0, rect.size.y * 0.12)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor.call("_applyPointerMotion", motion)
	await process_frame
	_require(bool(editor.get("_strokeOpen")), "the drag closed the stroke early")
	var afterDrag: PackedByteArray = baker.texture().get_image().get_data()
	_require(afterDrag != afterPress, "the held drag did not reach the bake before release")

	editor.call("_endToolGesture", motion.position)
	await process_frame
	_require(not bool(editor.get("_strokeOpen")), "release left the stroke open")
	# The other half of the same claim: if release still changed the bake, the drag had been
	# accumulating unshown work after all.
	_require(
		baker.texture().get_image().get_data() == afterDrag,
		"release changed the bake, so the drag was not already current"
	)

	editor.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			printerr("HXF_SURFACE_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX EDITOR SURFACE OK")
	quit(0)
