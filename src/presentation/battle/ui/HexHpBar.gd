## A flat HP bar: a dark track and a fill that turns warning red at a quarter or below.
##
## Drawn, not a `ProgressBar`: a themed range control brings its own stylebox, and the bar has to
## read as part of the window's pixel chrome rather than as a default widget dropped into it.

class_name HexHpBar
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## At or below this share of max HP the fill switches to the warning colour.
const LOW_FRACTION := 0.25

var _hp := 0
var _maxHp := 1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setValues(hp: int, maxHp: int) -> void:
	_hp = maxi(hp, 0)
	_maxHp = maxi(maxHp, 1)
	queue_redraw()


func fraction() -> float:
	return clampf(float(_hp) / float(_maxHp), 0.0, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), NoggThemeScript.HEX_HP_BACK)
	var share := fraction()
	if share <= 0.0:
		return
	# Whole pixels, and never less than one while the unit is alive: a sliver of HP left must still
	# show as a sliver rather than as an empty bar.
	var width := maxf(1.0, floorf(size.x * share))
	var color := NoggThemeScript.HEX_HP_FILL_LOW if share <= LOW_FRACTION else NoggThemeScript.HEX_HP_FILL
	draw_rect(Rect2(Vector2.ZERO, Vector2(width, size.y)), color)
