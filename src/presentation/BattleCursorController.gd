## Owns the tactical cursor's discrete grid intent and input authority.

class_name BattleCursorController
extends RefCounted

enum Mode {
	HIDDEN,
	TURN_INDICATOR,
	MOVEMENT_TARGET,
	PLAYER_SELECTION,
	TARGETING
}

enum Owner {
	NONE,
	AI,
	PLAYER
}

const CURSOR_LIFT := 0.015
const DEFAULT_CURSOR_COLOR := Color(0.2, 0.6, 1.0, 0.5)
const TARGET_CURSOR_COLOR := Color(1.0, 0.82, 0.12, 0.78)

var mode: Mode = Mode.HIDDEN
var owner: Owner = Owner.NONE
var grid_position := Vector2i(-1, -1)
var _cursor: MeshInstance3D
var _getSurfaceY: Callable


func _init(cursor: MeshInstance3D, getSurfaceY: Callable = Callable()) -> void:
	_cursor = cursor
	_getSurfaceY = getSurfaceY
	_cursor.visible = false


func focusTurn(coord: Vector2i) -> void:
	_showAIIntent(coord, Mode.TURN_INDICATOR)


func focusMovementDestination(coord: Vector2i) -> void:
	_showAIIntent(coord, Mode.MOVEMENT_TARGET)


func focusTarget(coord: Vector2i) -> void:
	_showAIIntent(coord, Mode.TARGETING)


func focusPlayerSelection(coord: Vector2i) -> void:
	owner = Owner.PLAYER
	showAt(coord, Mode.PLAYER_SELECTION)


func focusPlayerTarget(coord: Vector2i) -> void:
	owner = Owner.PLAYER
	showAt(coord, Mode.TARGETING)


func releasePlayerOwnership() -> void:
	if owner == Owner.PLAYER:
		owner = Owner.NONE


func _showAIIntent(coord: Vector2i, nextMode: Mode) -> void:
	if owner == Owner.PLAYER:
		return
	owner = Owner.AI
	showAt(coord, nextMode)


func showAt(coord: Vector2i, nextMode: Mode) -> void:
	mode = nextMode
	grid_position = coord
	_setCursorColor(
		TARGET_CURSOR_COLOR if nextMode == Mode.TARGETING else DEFAULT_CURSOR_COLOR
	)
	_cursor.position = _worldPosition(coord)
	_cursor.visible = true


func _setCursorColor(color: Color) -> void:
	var material = _cursor.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("color_a", color)
	material.set_shader_parameter("color_b", color)


func hide(clearOwner: bool = true) -> void:
	mode = Mode.HIDDEN
	grid_position = Vector2i(-1, -1)
	_cursor.visible = false
	if clearOwner:
		owner = Owner.NONE


func _worldPosition(coord: Vector2i) -> Vector3:
	var surfaceY = 0.0
	if _getSurfaceY.is_valid():
		surfaceY = float(_getSurfaceY.call(coord))
	return Vector3(coord.x, surfaceY + CURSOR_LIFT, coord.y)
