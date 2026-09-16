class_name SideTurnBanner
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const WIDTH := 220.0
const ENTER_OFFSET := 18.0
const ENTER_SECONDS := 0.22

var _window: NoggWindow
var _label: Label
var _restPosition := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.set_input_transparent(true)
	_window.size.x = WIDTH
	_window.set_row_capacity(1)
	add_child(_window)
	_label = NoggThemeScript.make_banner_label()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	size = _window.size
	_label.size = size


func showTurn(text: String, friendly: bool) -> void:
	_label.text = text
	_label.add_theme_color_override(
		"font_color", NoggThemeScript.TEXT_ACCENT if friendly else Color("ff8066"))
	visible = true
	_restPosition = position
	position.y = _restPosition.y - ENTER_OFFSET
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", _restPosition.y, ENTER_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, ENTER_SECONDS)
