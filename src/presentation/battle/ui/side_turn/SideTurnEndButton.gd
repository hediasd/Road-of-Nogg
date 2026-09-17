class_name SideTurnEndButton
extends Control

signal end_requested()

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## The widest text the button ever shows, measured in the game font. A fixed pixel width clipped
## "End turn?" once the button wore the real face instead of the default sans.
const WIDEST_LABEL := "End turn?"
const WIDEST_VALUE := "Yes"
const WIDEST_COUNT := "00 ready"

var _window: NoggWindow
var _button: Button
var _readyCount := 0
var _confirming := false


func _init() -> void:
	_window = NoggWindowScript.new()
	_window.set_row_capacity(2)
	add_child(_window)
	_button = Button.new()
	_button.flat = true
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_onPressed)
	add_child(_button)


func _ready() -> void:
	_window.size.x = _contentWidth()
	size = _window.size
	_button.size = size
	_render()


func _contentWidth() -> float:
	var font := get_theme_default_font()
	var fontSize := NoggThemeScript.FONT_SIZE_BODY
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
	var question := font.get_string_size(WIDEST_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x \
		+ space * 2.0 + font.get_string_size(WIDEST_VALUE, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
	var count := font.get_string_size(WIDEST_COUNT, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x
	return ceilf(maxf(question, count)) + float(NoggThemeScript.CONTENT_INSET) * 2.0


func setReadyCount(count: int) -> void:
	_readyCount = maxi(0, count)
	_confirming = false
	_render()


func setConfirming(confirming: bool) -> void:
	_confirming = confirming
	_render()


func isConfirming() -> bool:
	return _confirming


func readyCount() -> int:
	return _readyCount


func _onPressed() -> void:
	if _readyCount > 0 and not _confirming:
		_confirming = true
		_render()
		return
	end_requested.emit()


func _render() -> void:
	if _window == null:
		return
	# The answer shares the question's row. On the count's row, "Confirm" ran into "3 ready" at
	# this width and read as "3 rea Confirm".
	_window.set_full_rows([
		{"label": "End turn?" if _confirming else "End turn", "value": "Yes" if _confirming else ""},
		{"label": "%d ready" % _readyCount, "value": ""},
	])
	_window.set_active(_confirming)
