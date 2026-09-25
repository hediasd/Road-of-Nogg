## The hex battle's own camera: an oblique 2.5D view of the board, orbitable and zoomable.
##
## SEPARATE FROM `BattleCameraController` ON PURPOSE. That one frames a square board from its own
## dimensions and is shared with the debug scenes and the square reference; retuning it to suit a
## hex lattice would move a camera the frozen reference still depends on. This item's instruction
## is explicit -- camera changes stay in the new implementation -- so this file owns the hex
## framing and touches nothing shared.
##
## THE ORBIT IS WHY THE CURSOR PROJECTS. `HexBattleCursor` resolves direction in screen space
## against wherever this camera currently sits, so rotating the board does not leave the player
## pressing "up-left" to go somewhere that is now down-right. That coupling is the reason orbit is
## offered at all: a fixed camera would have made a fixed axial-to-key table workable and much
## less useful.

class_name HexBattleCamera
extends Node3D

enum DragMode { NONE, ORBIT, PAN }

## Oblique rather than top-down: the retro 2.5D direction this cycle keeps means reading height
## off the board, and a plan view flattens every plateau to nothing.
const DEFAULT_YAW_DEGREES := 30.0
const DEFAULT_PITCH_DEGREES := -42.0
const MIN_PITCH_DEGREES := -70.0
const MAX_PITCH_DEGREES := -12.0

## Sixty degrees is one hex neighbour, so a detent lands the board back on an orientation where
## the six directions sit exactly where they did one detent ago.
const YAW_DETENT_DEGREES := 60.0

const MIN_ORTHOGRAPHIC_SIZE := 8.0
const MAX_ORTHOGRAPHIC_SIZE := 48.0
const ZOOM_STEP := 1.5
## Orthographic zoom is controlled by `Camera3D.size`, not physical distance. Keeping that camera
## well behind the entire rotating board prevents a zoomed-in corner from crossing its near plane
## without changing how large the board looks.
const ORTHOGRAPHIC_CAMERA_DISTANCE := 100.0
## Opening size is derived directly in orthographic world units. At 1280x720 this
## puts the standard 20x10 field across roughly two-thirds of the usable width.
const FRAME_SPAN_FACTOR := 0.76
const FRAME_MARGIN := 2.5
## The raised rim extends roughly one world unit beyond each side of the valid-cell span.
const FRAME_BOARD_PADDING := 2.0

const ORBIT_SENSITIVITY := 0.22
const PITCH_SENSITIVITY := 0.18
const PAN_SENSITIVITY := 1.6
const CAMERA_EASE_SECONDS := 0.22

var camera: Camera3D
var _pivot: Node3D
var _yaw := DEFAULT_YAW_DEGREES
var _pitch := DEFAULT_PITCH_DEGREES
var _orthographicSize := 18.0
var _focus := Vector3.ZERO
var _screenConverter := Callable()
var _dragMode: DragMode = DragMode.NONE
var _cameraTween: Tween
var _defaultYaw := DEFAULT_YAW_DEGREES
var _defaultPitch := DEFAULT_PITCH_DEGREES
var _defaultOrthographicSize := 18.0
var _defaultFocus := Vector3.ZERO
## High-polling mice can deliver many motion events between rendered frames. Accumulate them and
## mutate the SubViewport camera once per frame; rebuilding its visibility state for every raw
## event made an otherwise simple drag feel dramatically slower than the square battle camera.
var _pendingOrbitMotion := Vector2.ZERO
var _pendingPanMotion := Vector2.ZERO
var _pendingPanViewportHeight := 1.0


func _init() -> void:
	name = "HexBattleCamera"
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	_pivot.add_child(camera)


func _process(_delta: float) -> void:
	if not _pendingOrbitMotion.is_zero_approx():
		_yaw = fmod(_yaw - _pendingOrbitMotion.x * ORBIT_SENSITIVITY, 360.0)
		_pitch = clampf(
			_pitch + _pendingOrbitMotion.y * PITCH_SENSITIVITY,
			MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
		_pendingOrbitMotion = Vector2.ZERO
		_apply()
	elif not _pendingPanMotion.is_zero_approx():
		var motion := _pendingPanMotion
		_pendingPanMotion = Vector2.ZERO
		_panByScreenDelta(motion, _pendingPanViewportHeight)


## Frames the whole board, from the map's own extent rather than a constant -- a 20x10 lattice and
## a 7x5 one need very different distances and there is no single number that suits both.
func frameMap(map: BattleMapDefinition, layout: HexBattleLayout) -> void:
	if map == null or layout == null:
		return
	var cells := map.validCells()
	if cells.is_empty():
		return
	var bounds := AABB(layout.cellCenter(cells[0]), Vector3.ZERO)
	for cell: Vector2i in cells:
		bounds = bounds.expand(layout.cellCenter(cell))
	_focus = bounds.position + bounds.size * 0.5
	# Distance from the larger horizontal span. Close enough that the board fills the space between
	# the HUD columns and a unit reads at a glance; at 1.15x span the board sat in the middle third
	# of the window with units about 16 px tall at 1280x720, too small to follow a fight. The near
	# rows may pass under the bottom windows, which the wheel undoes.
	var span := maxf(bounds.size.x, bounds.size.z) + FRAME_BOARD_PADDING
	_yaw = DEFAULT_YAW_DEGREES
	_pitch = DEFAULT_PITCH_DEGREES
	_orthographicSize = clampf(
		span * FRAME_SPAN_FACTOR + FRAME_MARGIN,
		MIN_ORTHOGRAPHIC_SIZE, MAX_ORTHOGRAPHIC_SIZE)
	_defaultYaw = _yaw
	_defaultPitch = _pitch
	_defaultOrthographicSize = _orthographicSize
	_defaultFocus = _focus
	_apply()


func focusOn(worldPosition: Vector3) -> void:
	_cancelCameraTween()
	_focus = worldPosition
	_apply()


func orbit(degrees: float) -> void:
	_cancelCameraTween()
	_yaw = fmod(_yaw + degrees, 360.0)
	_apply()


## Eases by one sixty-degree detent. The final angle is still exact, so cursor projection and the
## lattice agree when the motion stops, but the board no longer snaps like a debug view.
func orbitDetent(steps: int) -> void:
	_cancelCameraTween()
	var target := _yaw + YAW_DETENT_DEGREES * float(steps)
	_cameraTween = create_tween()
	_cameraTween.tween_method(_setYaw, _yaw, target, CAMERA_EASE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func pitch(degrees: float) -> void:
	_cancelCameraTween()
	_pitch = clampf(_pitch + degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
	_apply()


func zoom(steps: float) -> void:
	_cancelCameraTween()
	_orthographicSize = clampf(
		_orthographicSize + ZOOM_STEP * steps,
		MIN_ORTHOGRAPHIC_SIZE, MAX_ORTHOGRAPHIC_SIZE)
	_apply()


func yaw() -> float:
	return _yaw


func orthographicSize() -> float:
	return _orthographicSize


func pitchDegrees() -> float:
	return _pitch


func focus() -> Vector3:
	return _focus


## The square battle's mouse contract, implemented with this camera's orbit state:
## middle drag orbits and pitches, right drag pans, wheel zooms, and double middle resets. Returns
## true for every owned press, release and drag motion so tactical hover/aim never fires beneath it.
func handleInput(event: InputEvent, viewportHeight: float) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom(-1.0)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom(1.0)
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed and event.double_click:
			cancelDrag()
			resetView()
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_cancelCameraTween()
				_discardPendingMotion()
				_dragMode = DragMode.ORBIT
			elif _dragMode == DragMode.ORBIT:
				_dragMode = DragMode.NONE
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_cancelCameraTween()
				_discardPendingMotion()
				_dragMode = DragMode.PAN
			elif _dragMode == DragMode.PAN:
				_dragMode = DragMode.NONE
			return true
	elif event is InputEventMouseMotion:
		if _dragMode == DragMode.ORBIT:
			_pendingOrbitMotion += event.relative
			return true
		if _dragMode == DragMode.PAN:
			_pendingPanMotion += event.relative
			_pendingPanViewportHeight = viewportHeight
			return true
	return false


func isDragging() -> bool:
	return _dragMode != DragMode.NONE


func cancelDrag() -> void:
	_dragMode = DragMode.NONE


## Returns to the map framing captured by `frameMap`, preserving the same brief ease used by key
## detents. A reset is authored camera motion, so any drag or older settle is cancelled first.
func resetView() -> void:
	cancelDrag()
	_discardPendingMotion()
	_cancelCameraTween()
	var targetYaw := _nearestEquivalentYaw(_defaultYaw)
	_cameraTween = create_tween().set_parallel(true)
	_cameraTween.tween_method(_setYaw, _yaw, targetYaw, CAMERA_EASE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_cameraTween.tween_method(_setPitch, _pitch, _defaultPitch, CAMERA_EASE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_cameraTween.tween_method(
		_setOrthographicSize, _orthographicSize, _defaultOrthographicSize,
		CAMERA_EASE_SECONDS
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_cameraTween.tween_method(_setFocus, _focus, _defaultFocus, CAMERA_EASE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _panByScreenDelta(relative: Vector2, viewportHeight: float) -> void:
	if camera == null or viewportHeight <= 0.0:
		return
	var factor := _orthographicSize / viewportHeight * PAN_SENSITIVITY
	var right := camera.global_transform.basis.x
	right.y = 0.0
	var up := camera.global_transform.basis.y
	up.y = 0.0
	if not right.is_zero_approx():
		right = right.normalized()
	if not up.is_zero_approx():
		up = up.normalized()
	_focus -= right * relative.x * factor
	_focus += up * relative.y * factor
	_apply()


func _setYaw(value: float) -> void:
	_yaw = value
	_apply()


func _setPitch(value: float) -> void:
	_pitch = value
	_apply()


func _setOrthographicSize(value: float) -> void:
	_orthographicSize = value
	_apply()


func _setFocus(value: Vector3) -> void:
	_focus = value
	_apply()


func _nearestEquivalentYaw(target: float) -> float:
	var result := target
	while result - _yaw > 180.0:
		result -= 360.0
	while result - _yaw < -180.0:
		result += 360.0
	return result


func _cancelCameraTween() -> void:
	if _cameraTween != null and _cameraTween.is_valid():
		_cameraTween.kill()
	_cameraTween = null


func _discardPendingMotion() -> void:
	_pendingOrbitMotion = Vector2.ZERO
	_pendingPanMotion = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancelDrag()
		_discardPendingMotion()


## Projects a world point to host-screen coordinates, or reports that it is behind the camera.
##
## What `HexBattleCursor` is handed. The stage-supplied conversion is the sole letterbox/render
## scaling boundary. A negative point keeps an off-camera neighbour from becoming valid input.
func setScreenConverter(converter: Callable) -> void:
	_screenConverter = converter


func projectToRenderViewport(worldPosition: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2(-1.0, -1.0)
	if camera.is_position_behind(worldPosition):
		return Vector2(-1.0, -1.0)
	return camera.unproject_position(worldPosition)


func projectToScreen(worldPosition: Vector3) -> Vector2:
	var renderPoint := projectToRenderViewport(worldPosition)
	if renderPoint.x < 0.0:
		return renderPoint
	if _screenConverter.is_valid():
		return _screenConverter.call(renderPoint)
	return renderPoint


func _apply() -> void:
	if _pivot == null or camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _orthographicSize
	var placementDistance := ORTHOGRAPHIC_CAMERA_DISTANCE
	_pivot.position = _focus
	_pivot.rotation_degrees = Vector3(0.0, _yaw, 0.0)
	# Orbit is around the focus, so the camera sits back along its own local Z and is then tilted;
	# the pivot's yaw carries it around. Composing it this way keeps pitch independent of yaw,
	# which a single look_at would not.
	camera.position = Vector3(
		0.0,
		-sin(deg_to_rad(_pitch)) * placementDistance,
		cos(deg_to_rad(_pitch)) * placementDistance
	)
	camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)
