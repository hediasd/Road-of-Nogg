class_name SideTurnPreviewBox
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const ENTER_OFFSET := 10.0
const ENTER_SECONDS := 0.14

var _window: NoggWindow
var targetID := -1
var worldAnchor := Vector3.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.set_input_transparent(true)
	_window.set_row_capacity(3)
	add_child(_window)


func _ready() -> void:
	size = _window.size


## As wide as its widest row plus the content inset on both sides. A fixed width clipped longer
## unit names once the box wore the game font.
func _fitWidth(rows: Array[Dictionary]) -> void:
	var font := get_theme_default_font()
	var fontSize := NoggThemeScript.FONT_SIZE_BODY
	var gap := font.get_string_size("  ", HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
	var widest := 0.0
	for row in rows:
		var width := font.get_string_size(str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
		if not str(row["value"]).is_empty():
			width += gap + font.get_string_size(
				str(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
		widest = maxf(widest, width)
	_window.size.x = ceilf(widest) + float(NoggThemeScript.CONTENT_INSET) * 2.0
	size = _window.size


func configure(monsterID: int, name: String, anchor: Vector3, forecast: Dictionary) -> void:
	targetID = monsterID
	worldAnchor = anchor
	var minimum := int(forecast.get("minimum", 0))
	var maximum := int(forecast.get("maximum", minimum))
	var exact := bool(forecast.get("exact", minimum == maximum))
	var damage := "%d dmg" % minimum if exact else "%d dmg, %d crit (%d%%)" % [
		minimum, maximum, roundi(float(forecast.get("critical_chance", 0.0)) * 100.0)]
	var hp := int(forecast.get("target_hitpoints", 0))
	var rows: Array[Dictionary] = [
		{"label": name, "value": "KO" if bool(forecast.get("lethal", false)) else ""},
		{"label": damage, "value": ""},
		{"label": "HP", "value": "%d -> %d" % [hp, maxi(0, hp - minimum)]},
	]
	_fitWidth(rows)
	_window.set_full_rows(rows)
	visible = true
	modulate.a = 0.0
	position.y -= ENTER_OFFSET
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y + ENTER_OFFSET, ENTER_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, ENTER_SECONDS)


func forecastRows() -> Array[Dictionary]:
	return _window._full_rows.duplicate(true)
