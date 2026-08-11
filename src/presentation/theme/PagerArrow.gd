## Filled triangle button for a NoggWindow page footer (docs/UI_DESIGN.md §7a,
## pagination). Same size and colour as MenuCursor's triangle, mirrored horizontally
## for the "previous page" direction — "Draw the arrows with `_draw()`... Mirror
## MenuCursor's triangle so pager and cursor read as one family."
##
## `◀`/`▶` are absent from the shipping font and silently fall back to a
## system font (§3), which is why this exists instead of a typed Label.

class_name PagerArrow
extends Control

signal pressed

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Sized identically to MenuCursor's own triangle, not merely shape-matched —
## the strongest reading of "read as one family".
##
## Accessors rather than consts: the cursor tokens scale with
## `NoggTheme.ui_scale`, and a const would freeze the parse-time value and let
## the arrow drift out of family with the cursor at any other scale.
static func width() -> float:
	return NoggThemeScript.CURSOR_WIDTH


static func height() -> float:
	return NoggThemeScript.CURSOR_HEIGHT

var _points_right: bool = true


func _init(points_right: bool = true) -> void:
	_points_right = points_right


func _ready() -> void:
	custom_minimum_size = Vector2(width(), height())
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var points := (
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(width(), height() / 2.0), Vector2(0.0, height())])
		if _points_right else
		PackedVector2Array([Vector2(width(), 0.0), Vector2(0.0, height() / 2.0), Vector2(width(), height())])
	)
	draw_colored_polygon(points, NoggThemeScript.TEXT_ACCENT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
