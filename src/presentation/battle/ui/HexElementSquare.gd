## An element as a square: the element's placeholder colour with its two-letter catalog code on it.
##
## The colour is `BattleMeshFactory.elementColor`, the same one the unit's body is tinted with, and
## the code is `data/elements.json`'s own `CODE`, so neither is a second definition. Both are
## placeholders the plan expects authored element art to replace.

class_name HexElementSquare
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

var _code := "??"
var _color := Color(0.5, 0.5, 0.5)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `element` is one entry of `HexUnitFacts.elementFacts`: name, code, color.
func setElement(element: Dictionary) -> void:
	_code = str(element.get("code", "??"))
	_color = element.get("color", _color)
	# Two cells wide: the code is two glyphs, and a square one glyph wide clipped it.
	size = Vector2(NoggThemeScript.HEX_ELEMENT_CELL * 2.0, NoggThemeScript.HEX_ELEMENT_CELL)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color)
	draw_rect(Rect2(Vector2.ZERO, size), NoggThemeScript.OUTLINE, false, 1.0)
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var fontSize := NoggThemeScript.FONT_SIZE_BODY
	var textSize := font.get_string_size(_code, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize)
	# Dark ink on light elements, light ink on dark ones, by perceived brightness.
	var ink := NoggThemeScript.OUTLINE if _color.get_luminance() > 0.55 else NoggThemeScript.TEXT_PRIMARY
	var baseline := floorf((size.y - textSize.y) / 2.0 + font.get_ascent(fontSize))
	draw_string(
		font, Vector2(floorf((size.x - textSize.x) / 2.0), baseline), _code,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize, ink
	)
