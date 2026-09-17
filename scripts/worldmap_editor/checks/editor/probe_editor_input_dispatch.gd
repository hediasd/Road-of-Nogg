## Regression guard for a defect neither `probe_editor_camera.gd` nor `probe_editor_shell.gd`
## could catch: `WorldMapEditorCamera` originally read mouse/keyboard input in its OWN
## `_unhandled_input`, but that node lives inside `WorldMapEditorController`'s "World"
## `SubViewport`, which the scene displays through a plain `TextureRect` rather than a
## `SubViewportContainer` -- so it never received a real, engine-dispatched event at all. Every
## existing probe drove the camera by calling its methods directly (`orbitBy()`,
## `_unhandled_input(event)` called BY NAME), which exercises the maths correctly and says
## nothing about whether a real mouse drag or keypress ever reaches it. Both probes passed
## while every navigation control in a live window did nothing.
##
## This probe is the difference: it pushes events through `Input.parse_input_event()`, which
## takes the same dispatch path a real OS event does, and never calls a handler by name.
##
## Click and drag positions are deliberately kept away from (0, 0) -- the scene's left-docked
## editor panel starts there, and a Control's default `MOUSE_FILTER_STOP` swallows a button
## press over it regardless of which button, before the SceneTree ever sees it as "unhandled".
## The first version of this probe used the default `Vector2.ZERO` position and every assertion
## below would have reported PASS for the wrong reason if it had not been caught by hand.

extends SceneTree

const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")
const EditorCameraScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorCamera.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")

## Comfortably inside the centre of a 1152x648 window and clear of both docked panels (440 px
## on the right, 280 on the left).
const CLEAR_POS := Vector2(640.0, 360.0)

var _failures := 0
var _scene: Node
var _camera: WorldMapEditorCamera


func _initialize() -> void:
	_scene = EditorScene.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	await process_frame
	_camera = _scene.get("_camera")

	await _checkOrbit()
	await _checkPan()
	await _checkDolly()
	await _checkTab()
	await _checkSpace()
	await _checkShiftSnap()
	await _checkFrameRegionFit()
	await _checkShortcutsIgnoreFocusedControl()

	print("")
	print("probe_editor_input_dispatch: %s" % (
		"PASS" if _failures == 0 else "%d FAILURE(S)" % _failures
	))
	if _failures == 0:
		print("WORLD MAP EDITOR INPUT DISPATCH OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _mouseButton(index: int, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = pos
	return event


func _mouseMotion(relative: Vector2, pos: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = pos
	return event


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _checkOrbit() -> void:
	print("-- real middle-drag reaches orbit --")
	var yawBefore: float = _camera.yaw
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, true, CLEAR_POS))
	await process_frame
	Input.parse_input_event(_mouseMotion(Vector2(120.0, 0.0), CLEAR_POS + Vector2(120, 0)))
	await process_frame
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, false, CLEAR_POS + Vector2(120, 0)))
	await process_frame
	if is_equal_approx(_camera.yaw, yawBefore):
		_fail("a dispatched middle-drag did not move yaw at all")
	else:
		print("  ok    yaw moved from %.2f to %.2f" % [yawBefore, _camera.yaw])


func _checkPan() -> void:
	print("-- real right-drag reaches pan --")
	var focusBefore: Vector2 = _camera.focus
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_RIGHT, true, CLEAR_POS))
	await process_frame
	Input.parse_input_event(_mouseMotion(Vector2(60.0, -40.0), CLEAR_POS + Vector2(60, -40)))
	await process_frame
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_RIGHT, false, CLEAR_POS + Vector2(60, -40)))
	await process_frame
	if _camera.focus.is_equal_approx(focusBefore):
		_fail("a dispatched right-drag did not move the focus at all")
	else:
		print("  ok    focus moved from %s to %s" % [focusBefore, _camera.focus])


func _checkDolly() -> void:
	print("-- real wheel reaches dolly --")
	var distBefore: float = _camera.distance
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_WHEEL_UP, true, CLEAR_POS))
	await process_frame
	if is_equal_approx(_camera.distance, distBefore):
		_fail("a dispatched wheel notch did not change distance")
	else:
		print("  ok    distance moved from %.2f to %.2f" % [distBefore, _camera.distance])


func _checkTab() -> void:
	print("-- real Tab reaches ortho toggle --")
	var modeBefore: int = _camera.mode
	Input.parse_input_event(_key(KEY_TAB))
	await process_frame
	if _camera.mode == modeBefore:
		_fail("a dispatched Tab did not change mode")
	elif _camera.mode != WorldMapEditorCamera.Mode.ORTHO:
		_fail("Tab changed mode but not to ORTHO")
	else:
		print("  ok    entered ORTHO")
	Input.parse_input_event(_key(KEY_TAB))
	await process_frame


func _checkSpace() -> void:
	print("-- real Space reaches snap-to-contract --")
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, true, CLEAR_POS))
	await process_frame
	Input.parse_input_event(_mouseMotion(Vector2(50.0, 20.0), CLEAR_POS + Vector2(50, 20)))
	await process_frame
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, false, CLEAR_POS + Vector2(50, 20)))
	await process_frame
	if _camera.offContractReason().is_empty():
		_fail("setup drag did not leave the camera off-contract; Space would pass vacuously")
		return
	Input.parse_input_event(_key(KEY_SPACE))
	await process_frame
	if _camera.mode != WorldMapEditorCamera.Mode.CONTRACT or not _camera.offContractReason().is_empty():
		_fail("a dispatched Space did not restore contract mode")
	else:
		print("  ok    restored to CONTRACT, reports on-contract")


## Shift held during a middle-button release snaps yaw to the nearest 45 degrees -- exercised
## separately because it reads a SECOND input source (`Input.is_key_pressed`) at the moment the
## drag ends, which is a different path than the drag itself.
func _checkShiftSnap() -> void:
	print("-- Shift-release snaps yaw to 45 degrees --")
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, true, CLEAR_POS))
	await process_frame
	Input.parse_input_event(_mouseMotion(Vector2(37.0, 0.0), CLEAR_POS + Vector2(37, 0)))
	await process_frame
	var shift := _key(KEY_SHIFT)
	Input.parse_input_event(shift)
	await process_frame
	Input.parse_input_event(_mouseButton(MOUSE_BUTTON_MIDDLE, false, CLEAR_POS + Vector2(37, 0)))
	await process_frame
	var remainder := fmod(absf(_camera.yaw), 45.0)
	if remainder > 0.01 and remainder < 44.99:
		_fail("Shift-release left yaw at %.3f, not a multiple of 45" % _camera.yaw)
	else:
		print("  ok    yaw snapped to %.1f" % _camera.yaw)
	var shiftUp := _key(KEY_SHIFT)
	shiftUp.pressed = false
	Input.parse_input_event(shiftUp)
	await process_frame


## WMH-1's own regression guard: `frameRegion` fits BOTH axes, at any orientation and aspect,
## rather than the larger of two world-space numbers with no aspect at all -- the bug that
## cropped a portrait-shaped viewport. Built on its own SubViewport of an EXPLICIT pixel size
## rather than the editor scene's window-driven display, because the actual OS window is not
## controllable under `--headless` (it stays a fixed 64x64 stub regardless of any size set on
## `root` -- confirmed while building this probe), while a child `SubViewport`'s own size is
## fully respected there. That keeps the check deterministic and fast, and it is the right
## boundary anyway: fitting is a pure function of the region, the aspect, the mode, and the
## camera's own orientation, and needs no live window to test.
func _checkFrameRegionFit() -> void:
	print("-- frameRegion fits all four region corners, at three aspects, both projections --")
	var vp := SubViewport.new()
	vp.own_world_3d = true
	root.add_child(vp)
	var camera: WorldMapEditorCamera = EditorCameraScript.new()
	vp.add_child(camera)
	camera.current = true
	var framing: Dictionary = FramingCatalog.framingFor(FramingCatalog.OVERLAND)
	camera.snapToContract()
	camera.applyFraming(framing)
	await process_frame

	# A region with unequal width and height, so an aspect fit that only checks one axis (the
	# original bug) is caught rather than accidentally hidden by a square region.
	var region := Rect2(Vector2.ZERO, Vector2(23.0, 15.0))
	var pixelSizes := {
		"portrait": Vector2i(600, 1000),
		"square": Vector2i(800, 800),
		"landscape": Vector2i(1600, 900),
	}
	var yaws := [0.0, -60.0, 120.0]
	var tested := 0
	for label in pixelSizes:
		var pixels: Vector2i = pixelSizes[label]
		vp.size = pixels
		var aspect := float(pixels.x) / float(pixels.y)
		for yaw in yaws:
			for orthoMode in [false, true]:
				camera.snapToContract()
				camera.applyFraming(framing)
				if orthoMode:
					camera.toggleOrtho()
				if absf(yaw) > 0.001:
					camera.setFree()
					camera.orbitBy(yaw, 0.0)
				camera.frameRegion(region, aspect)
				await process_frame
				tested += 1
				var escaped := _worstCornerEscape(camera, region, pixels)
				if escaped > 0.0:
					_fail("%-9s yaw=%-6s ortho=%s: a region corner is %.1f px outside the frame" % [
						label, yaw, orthoMode, escaped
					])
					return
	print("  ok    %d configurations (3 aspects x 3 yaws x 2 projections), no corner escapes" % tested)
	vp.queue_free()


## How far outside the viewport rect the worst-projecting corner lands, in pixels; 0 or less
## means every corner is safely inside (a fit is expected to have margin, not sit exactly on the
## edge). A corner behind the camera is treated as maximally outside rather than silently passed.
func _worstCornerEscape(camera: Camera3D, region: Rect2, pixels: Vector2i) -> float:
	var worst := -INF
	for corner in [region.position, region.position + Vector2(region.size.x, 0.0),
			region.position + region.size, region.position + Vector2(0.0, region.size.y)]:
		var world := Vector3(corner.x, 0.0, corner.y)
		if not camera.is_position_in_frustum(world):
			worst = maxf(worst, 1.0e6)
			continue
		var screen := camera.unproject_position(world)
		var escape := maxf(
			maxf(-screen.x, screen.x - float(pixels.x)),
			maxf(-screen.y, screen.y - float(pixels.y))
		)
		worst = maxf(worst, escape)
	return worst


## The playtest's exact repro: focus the tile-grid checkbox (the control it happened to land on),
## then press Space. Before the fix that both reset the camera AND toggled the checkbox in one
## keypress. `WorldMapEditorController._neutralizeDebugHudFocus()` is the half asserted here --
## it should mean the checkbox never becomes the viewport's focus owner in the first place, which
## this checks directly rather than inferring from side effects alone.
func _checkShortcutsIgnoreFocusedControl() -> void:
	print("-- Tab/Space/F ignore a HUD control the user just clicked --")
	var hud = _scene.get("_hud")
	if hud == null:
		_fail("scene has no _hud to test focus against")
		return
	var toggle: CheckButton = hud.tileGridToggle
	var before := toggle.button_pressed

	toggle.grab_focus()
	await process_frame
	var owner := root.gui_get_focus_owner()
	if owner == toggle:
		_fail("the tile-grid checkbox still accepts keyboard focus")
		return

	var camera = _scene.get("_camera")
	var modeBefore: int = camera.mode

	Input.parse_input_event(_key(KEY_SPACE))
	await process_frame
	if toggle.button_pressed != before:
		_fail("Space toggled the checkbox it could not focus -- the exact playtest defect")
		return

	Input.parse_input_event(_key(KEY_TAB))
	await process_frame
	if camera.mode == modeBefore:
		_fail("Tab reached the SceneTree but did not change camera mode")
		return
	if toggle.button_pressed != before:
		_fail("Tab toggled the checkbox")
		return

	Input.parse_input_event(_key(KEY_F))
	await process_frame
	if toggle.button_pressed != before:
		_fail("F toggled the checkbox")
		return

	print("  ok    checkbox never gained focus; Space, Tab and F all reached the camera cleanly")
