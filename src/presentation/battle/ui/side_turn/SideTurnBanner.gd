class_name SideTurnBanner
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## The longest text the banner shows. Its frame is measured from this in the banner face, so
## the text keeps the window's content inset at every UI scale.
const WIDEST_TEXT := "Enemy turn"
const ENTER_OFFSET := 18.0
const ENTER_SECONDS := 0.22

var _window: NoggWindow
var _label: Label
var _restPosition := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.set_input_transparent(true)
	add_child(_window)
	_label = NoggThemeScript.make_banner_label()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	var font := _label.get_theme_font("font")
	var fontSize := _label.get_theme_font_size("font_size")
	var inset := float(NoggThemeScript.CONTENT_INSET)
	var text := font.get_string_size(WIDEST_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize)
	_window.custom_minimum_size = Vector2(ceilf(text.x), font.get_height(fontSize)) + Vector2.ONE * inset * 2.0
	_window.size = _window.custom_minimum_size
	size = _window.size
	_label.size = size


## Where the banner settles. Owned by the layout rather than read back from `position`, which a
## turn change arriving mid-entrance would have caught part-way up.
func setRestPosition(rest: Vector2) -> void:
	_restPosition = rest
	if _tween == null or not _tween.is_valid():
		position = rest


func showTurn(text: String, friendly: bool) -> void:
	_label.text = text
	_label.add_theme_color_override(
		"font_color", NoggThemeScript.TEXT_ACCENT if friendly else Color("ff8066"))
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position = Vector2(_restPosition.x, _restPosition.y - ENTER_OFFSET)
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	var tween := _tween
	tween.tween_property(self, "position:y", _restPosition.y, ENTER_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, ENTER_SECONDS)
