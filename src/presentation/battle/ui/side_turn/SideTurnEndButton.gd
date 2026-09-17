class_name SideTurnEndButton
extends Control

signal end_requested()

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const WIDTH := 152.0

var _window: NoggWindow
var _button: Button
var _readyCount := 0
var _confirming := false


func _init() -> void:
	_window = NoggWindowScript.new()
	_window.size.x = WIDTH
	_window.set_row_capacity(2)
	add_child(_window)
	_button = Button.new()
	_button.flat = true
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(_onPressed)
	add_child(_button)


func _ready() -> void:
	size = _window.size
	_button.size = size
	_render()


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
