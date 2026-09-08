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

## Oblique rather than top-down: the retro 2.5D direction this cycle keeps means reading height
## off the board, and a plan view flattens every plateau to nothing.
const DEFAULT_PITCH_DEGREES := -38.0
const MIN_PITCH_DEGREES := -70.0
const MAX_PITCH_DEGREES := -12.0

## Sixty degrees is one hex neighbour, so a detent lands the board back on an orientation where
## the six directions sit exactly where they did one detent ago.
const YAW_DETENT_DEGREES := 60.0

const MIN_DISTANCE := 6.0
const MAX_DISTANCE := 60.0
const ZOOM_STEP := 2.0

var camera: Camera3D
var _pivot: Node3D
var _yaw := 0.0
var _pitch := DEFAULT_PITCH_DEGREES
var _distance := 18.0
var _focus := Vector3.ZERO


func _init() -> void:
	name = "HexBattleCamera"
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	_pivot.add_child(camera)


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
	# Distance from the larger horizontal span, with room around the edge so the outermost cells
	# are not flush against the viewport border.
	var span := maxf(bounds.size.x, bounds.size.z)
	_distance = clampf(span * 1.15 + 6.0, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func focusOn(worldPosition: Vector3) -> void:
	_focus = worldPosition
	_apply()


func orbit(degrees: float) -> void:
	_yaw = fmod(_yaw + degrees, 360.0)
	_apply()


## Snaps to the nearest sixty-degree detent -- see the constant's note on why sixty.
func orbitDetent(steps: int) -> void:
	_yaw = fmod(_yaw + YAW_DETENT_DEGREES * float(steps), 360.0)
	_apply()


func pitch(degrees: float) -> void:
	_pitch = clampf(_pitch + degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
	_apply()


func zoom(steps: float) -> void:
	_distance = clampf(_distance + ZOOM_STEP * steps, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func yaw() -> float:
	return _yaw


func distance() -> float:
	return _distance


## Projects a world point to viewport coordinates, or reports that it is behind the camera.
##
## What `HexBattleCursor` is handed. Returning the origin for a point behind the camera rather
## than a wrapped coordinate keeps a neighbour that is off-screen from reading as a valid
## direction.
func projectToScreen(worldPosition: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	if camera.is_position_behind(worldPosition):
		return Vector2.ZERO
	return camera.unproject_position(worldPosition)


func _apply() -> void:
	if _pivot == null or camera == null:
		return
	_pivot.position = _focus
	_pivot.rotation_degrees = Vector3(0.0, _yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, _distance)
	camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)
	# Orbit is around the focus, so the camera sits back along its own local Z and is then tilted;
	# the pivot's yaw carries it around. Composing it this way keeps pitch independent of yaw,
	# which a single look_at would not.
	camera.position = Vector3(
		0.0, -sin(deg_to_rad(_pitch)) * _distance, cos(deg_to_rad(_pitch)) * _distance
	)
	camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)
