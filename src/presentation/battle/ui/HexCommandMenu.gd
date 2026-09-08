## Bounded command display: one NoggWindow rendering the supplied view model.
## This node owns neither command availability nor command meaning; its caller
## supplies both and this node reports a selected command id or cancellation.

class_name HexCommandMenu
extends Control

signal command_chosen(commandID: String)
signal cancelled()

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")

const CANCEL_LABEL := "Cancel"

const KIND_HEADER := "header"
const KIND_COMMAND := "command"
const KIND_CANCEL := "cancel"

var _window: NoggWindow

## Parallel to the descriptors handed to set_full_rows(). Keeping the command
## id and enabled state here makes row_built() use the rendered row's index,
## instead of trying to infer behaviour from its visible text.
var _rowMeta: Array[Dictionary] = []


func _init() -> void:
	_window = NoggWindowScript.new()
	add_child(_window)
	_window.row_built.connect(_on_row_built)


## `model` keys: input_enabled (bool), title (String), commands (Array of
## Dictionaries with id, label, enabled, detail, spent). Commands remain in
## supplied order. `spent` is retained with the row metadata for callers that
## need to distinguish a spent command from another disabled command; this
## view does not infer enabled state from it.
func updateModel(model: Dictionary) -> void:
	var commands: Array = model.get("commands", [])
	if commands.is_empty():
		_rowMeta = []
		_window.set_row_capacity(1)
		_window.set_full_rows([])
		return

	var inputEnabled := bool(model.get("input_enabled", false))
	var descriptors: Array = []
	var meta: Array[Dictionary] = []

	descriptors.append({"label": str(model.get("title", "")), "value": "", "disabled": true})
	meta.append({"kind": KIND_HEADER, "enabled": false})

	for entry in commands:
		var command: Dictionary = entry as Dictionary
		var commandID := str(command.get("id", ""))
		if commandID.is_empty():
			push_error("HexCommandMenu: every command requires a non-empty id")
			_rowMeta = []
			_window.set_row_capacity(1)
			_window.set_full_rows([])
			return
		var enabled := bool(command.get("enabled", false))
		var interactive := inputEnabled and enabled
		descriptors.append({
			"label": str(command.get("label", "")),
			"value": str(command.get("detail", "")),
			"disabled": not interactive,
		})
		meta.append({
			"kind": KIND_COMMAND,
			"id": commandID,
			"enabled": interactive,
			"spent": bool(command.get("spent", false)),
		})

	descriptors.append({"label": CANCEL_LABEL, "value": "", "disabled": not inputEnabled})
	meta.append({"kind": KIND_CANCEL, "enabled": inputEnabled})

	_rowMeta = meta
	_window.set_row_capacity(descriptors.size())
	_window.set_full_rows(descriptors)


## Wired once for each newly built row. set_full_rows() replaces the previous
## rows, so no stale row survives to accumulate another connection.
func _on_row_built(row: Control, full_index: int) -> void:
	if full_index < 0 or full_index >= _rowMeta.size():
		return
	var entry: Dictionary = _rowMeta[full_index]
	if str(entry.get("kind", "")) == KIND_HEADER:
		return
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
	var entry: Dictionary = _rowMeta[full_index]
	match str(entry.get("kind", "")):
		KIND_COMMAND:
			command_chosen.emit(str(entry.get("id", "")))
		KIND_CANCEL:
			cancelled.emit()
