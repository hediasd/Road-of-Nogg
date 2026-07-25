## BattleCursorController — Owns the tactical cursor's mode, grid position,
## and single active animation.

class_name BattleCursorController
extends RefCounted

enum Mode {
	HIDDEN,
	TURN_INDICATOR,
	PLAYER_SELECTION,
	TARGETING
}

const CURSOR_HEIGHT := 0.21
const PATH_STEP_DURATION := 0.2

var mode: Mode = Mode.HIDDEN
var grid_position := Vector2i(-1, -1)

var _cursor: MeshInstance3D
var _movement_tween: Tween
var _animation_generation := 0


func _init(cursor: MeshInstance3D) -> void:
	_cursor = cursor
	_cursor.visible = false


func focusTurn(coord: Vector2i) -> void:
	showAt(coord, Mode.TURN_INDICATOR)


func focusPlayerSelection(coord: Vector2i) -> void:
	showAt(coord, Mode.PLAYER_SELECTION)


func focusTarget(coord: Vector2i) -> void:
	showAt(coord, Mode.TARGETING)


func showAt(coord: Vector2i, nextMode: Mode) -> void:
	cancelAnimation()
	mode = nextMode
	grid_position = coord
	_cursor.position = _worldPosition(coord)
	_cursor.visible = true


func animateTurnPath(path: Array, authoritativeDestination: Vector2i) -> void:
	cancelAnimation()
	mode = Mode.TURN_INDICATOR
	_cursor.visible = true

	if path.is_empty():
		grid_position = authoritativeDestination
		_cursor.position = _worldPosition(authoritativeDestination)
		return

	var generation = _animation_generation
	var tween = _cursor.create_tween()
	_movement_tween = tween

	for value in path:
		var coord: Vector2i = value
		tween.tween_property(_cursor, "position", _worldPosition(coord), PATH_STEP_DURATION)

	tween.finished.connect(func():
		if generation != _animation_generation:
			return
		_movement_tween = null
		grid_position = authoritativeDestination
		_cursor.position = _worldPosition(authoritativeDestination)
	)


func cancelAnimation() -> void:
	_animation_generation += 1
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	_movement_tween = null


func hide() -> void:
	cancelAnimation()
	mode = Mode.HIDDEN
	grid_position = Vector2i(-1, -1)
	_cursor.visible = false


func _worldPosition(coord: Vector2i) -> Vector3:
	return Vector3(coord.x, CURSOR_HEIGHT, coord.y)
