## BattleCursorController — Owns the tactical cursor's mode and discrete
## grid intent. The cursor never interpolates between cells.

class_name BattleCursorController
extends RefCounted

enum Mode {
	HIDDEN,
	TURN_INDICATOR,
	MOVEMENT_TARGET,
	PLAYER_SELECTION,
	TARGETING
}

const CURSOR_HEIGHT := 0.21

var mode: Mode = Mode.HIDDEN
var grid_position := Vector2i(-1, -1)

var _cursor: MeshInstance3D


func _init(cursor: MeshInstance3D) -> void:
	_cursor = cursor
	_cursor.visible = false


func focusTurn(coord: Vector2i) -> void:
	showAt(coord, Mode.TURN_INDICATOR)


func focusMovementDestination(coord: Vector2i) -> void:
	showAt(coord, Mode.MOVEMENT_TARGET)


func focusPlayerSelection(coord: Vector2i) -> void:
	showAt(coord, Mode.PLAYER_SELECTION)


func focusTarget(coord: Vector2i) -> void:
	showAt(coord, Mode.TARGETING)


func showAt(coord: Vector2i, nextMode: Mode) -> void:
	mode = nextMode
	grid_position = coord
	_cursor.position = _worldPosition(coord)
	_cursor.visible = true


func hide() -> void:
	mode = Mode.HIDDEN
	grid_position = Vector2i(-1, -1)
	_cursor.visible = false


func _worldPosition(coord: Vector2i) -> Vector3:
	return Vector3(coord.x, CURSOR_HEIGHT, coord.y)
