## The battle's session controls: pause, speed, skip, and at the end the result, restart and
## return to setup.
##
## THE SQUARE BATTLE'S CONTROLS, IN THE HEX HUD'S LANGUAGE. The square battle had a Play/Pause
## button, an animation speed slider, skip on accept, and a New Battle button, all in a developer
## tool row. Here they are rows in one `NoggWindow`, like the party panel: each row says what it
## does now ("Pause" or "Resume", "Speed 2x"), and its value column carries the key that does the
## same thing. That is the input help: it sits on the control it describes.
##
## RENDERS A MODEL, DECIDES NOTHING. `HexBattleHud.sessionModel` builds the rows; this node draws
## them and reports which enabled row was clicked. Rows rebuild only when the model changes.

class_name HexBattleSessionPanel
extends Control

signal command_chosen(commandID: String)

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const PAUSE := "pause"
const SPEED := "speed"
const SKIP := "skip"
const RESTART := "restart"
const SETUP := "setup"

const KIND_HEADER := "header"
const KIND_ROW := "row"

var _window: NoggWindow
var _rowMeta: Array[Dictionary] = []
var _drawn = null


func _init() -> void:
	name = "SessionPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.size.x = NoggThemeScript.STATUS_WINDOW_WIDTH
	add_child(_window)
	_window.row_built.connect(_on_row_built)


## `model` keys: title (String), rows (Array of Dictionaries with id, label, value, enabled). A row
## with an empty id is information only. An empty model clears the panel.
func updateModel(model: Dictionary) -> void:
	if _drawn != null and _drawn == model:
		return
	# NoggWindow builds its content in _ready. Not recorded as drawn, so the next refresh retries.
	if not _window.is_node_ready():
		return
	_drawn = model.duplicate(true)
	var rows: Array = model.get("rows", [])
	if rows.is_empty():
		_rowMeta = []
		_window.set_row_capacity(1)
		_window.set_full_rows([])
		_window.visible = false
		return
	var descriptors: Array = []
	var meta: Array[Dictionary] = []
	descriptors.append({"label": str(model.get("title", "")), "value": "", "disabled": true})
	meta.append({"kind": KIND_HEADER, "enabled": false})
	for entry in rows:
		var row: Dictionary = entry
		var id := str(row.get("id", ""))
		var enabled := bool(row.get("enabled", false)) and not id.is_empty()
		descriptors.append({
			"label": str(row.get("label", "")),
			"value": str(row.get("value", "")),
			"disabled": not enabled,
		})
		meta.append({"kind": KIND_ROW, "id": id, "enabled": enabled})
	_rowMeta = meta
	_window.visible = true
	_window.set_row_capacity(descriptors.size())
	_window.set_full_rows(descriptors)


func windowSize() -> Vector2:
	if _rowMeta.is_empty():
		return Vector2.ZERO
	return Vector2(_window.size.x, NoggThemeScript.window_height(_rowMeta.size()))


func drawnModel():
	return _drawn


## Rows rebuild fresh on every model change, so nothing here can double-wire. Disabled rows still
## stop the click, so it never falls through to the board.
func _on_row_built(row: Control, full_index: int) -> void:
	if full_index < 0 or full_index >= _rowMeta.size():
		return
	var entry: Dictionary = _rowMeta[full_index]
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if not bool(entry.get("enabled", false)):
		return
	row.gui_input.connect(_on_row_gui_input.bind(full_index))


func _on_row_gui_input(event: InputEvent, full_index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if full_index < 0 or full_index >= _rowMeta.size():
		return
	command_chosen.emit(str(_rowMeta[full_index].get("id", "")))
