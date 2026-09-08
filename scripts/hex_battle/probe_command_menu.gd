extends SceneTree

const HexCommandMenuScript = preload("res://src/presentation/battle/ui/HexCommandMenu.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const HEADER_INDEX := 0
const MOVE_INDEX := 1
const ATTACK_INDEX := 2
const WAIT_INDEX := 3
const CANCEL_INDEX := 4

var failures: Array[String] = []
var _capturedRows: Dictionary = {}
var _chosen: Array[String] = []
var _cancelCount := 0
var _menu: HexCommandMenu


func _init() -> void:
	_menu = HexCommandMenuScript.new()
	root.add_child(_menu)
	# NoggWindow creates its content in _ready(), which only runs once this
	# script SceneTree reaches a process frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var menu := _menu
	var window: NoggWindow = menu._window
	window.row_built.connect(_on_row_built)
	menu.command_chosen.connect(func(commandID: String): _chosen.append(commandID))
	menu.cancelled.connect(func(): _cancelCount += 1)

	_checkEmptyModelClearsMenu(menu, window)
	_checkEnabledAndOrderedModel(menu, window)
	_checkInputGate(menu, window)
	_checkSpentModel(menu, window)
	_checkClicksAndNoDuplication(menu, window)

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_MENU_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_MENU_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _on_row_built(row: Control, full_index: int) -> void:
	_capturedRows[full_index] = row


func _commandModel() -> Dictionary:
	return {
		"input_enabled": true,
		"title": "Knight commands",
		"commands": [
			{"id": "move", "label": "Move", "enabled": true, "detail": "3", "spent": false},
			{"id": "attack", "label": "Attack", "enabled": false, "detail": "1", "spent": false},
			{"id": "wait", "label": "Wait", "enabled": true, "detail": "", "spent": false},
		],
	}


func _checkEmptyModelClearsMenu(menu: HexCommandMenu, window: NoggWindow) -> void:
	_capturedRows.clear()
	window.set_full_rows([{"label": "stale", "value": "", "disabled": false}])
	menu.updateModel({})
	_require(window.row_count() == 0, "empty model left %d rows behind" % window.row_count())


func _checkEnabledAndOrderedModel(menu: HexCommandMenu, window: NoggWindow) -> void:
	_capturedRows.clear()
	menu.updateModel(_commandModel())
	_require(window.row_count() == 5, "command model built %d rows, expected 5" % window.row_count())
	_require(_labelText(_capturedRows.get(HEADER_INDEX)) == "Knight commands", "header did not show title")
	_require(_labelText(_capturedRows.get(MOVE_INDEX)) == "Move", "first supplied command was not rendered first")
	_require(_valueText(_capturedRows.get(MOVE_INDEX)) == "3", "Move detail was not rendered")
	_require(_isRowEnabledLooking(_capturedRows.get(MOVE_INDEX)), "enabled Move rendered disabled")
	_require(_labelText(_capturedRows.get(ATTACK_INDEX)) == "Attack", "second supplied command was not rendered second")
	_require(not _isRowEnabledLooking(_capturedRows.get(ATTACK_INDEX)), "disabled Attack rendered enabled")
	_require(_labelText(_capturedRows.get(WAIT_INDEX)) == "Wait", "third supplied command was not rendered third")
	_require(_labelText(_capturedRows.get(CANCEL_INDEX)) == "Cancel", "Cancel row missing or out of position")
	_require(_isRowEnabledLooking(_capturedRows.get(CANCEL_INDEX)), "Cancel rendered disabled while input was enabled")


func _checkInputGate(menu: HexCommandMenu, _window: NoggWindow) -> void:
	_capturedRows.clear()
	var model := _commandModel()
	model["input_enabled"] = false
	menu.updateModel(model)
	_require(not _isRowEnabledLooking(_capturedRows.get(MOVE_INDEX)), "input gate left Move enabled")
	_require(not _isRowEnabledLooking(_capturedRows.get(WAIT_INDEX)), "input gate left Wait enabled")
	_require(not _isRowEnabledLooking(_capturedRows.get(CANCEL_INDEX)), "input gate left Cancel enabled")


func _checkSpentModel(menu: HexCommandMenu, _window: NoggWindow) -> void:
	_capturedRows.clear()
	var model := _commandModel()
	var commands: Array = model["commands"]
	var spent: Dictionary = commands[0]
	spent["spent"] = true
	spent["enabled"] = false
	commands[0] = spent
	menu.updateModel(model)
	_require(not _isRowEnabledLooking(_capturedRows.get(MOVE_INDEX)), "spent command's supplied disabled state was ignored")
	_require(_labelText(_capturedRows.get(MOVE_INDEX)) == "Move", "spent command was dropped or reordered")


func _checkClicksAndNoDuplication(menu: HexCommandMenu, _window: NoggWindow) -> void:
	_capturedRows.clear()
	_chosen.clear()
	_cancelCount = 0
	menu.updateModel(_commandModel())
	_clickRow(_capturedRows.get(ATTACK_INDEX))
	_require(_chosen.is_empty(), "clicking disabled Attack emitted command_chosen")
	_clickRow(_capturedRows.get(MOVE_INDEX))
	_require(_chosen == ["move"], "clicking Move emitted %s, expected [move]" % [_chosen])
	_clickRow(_capturedRows.get(CANCEL_INDEX))
	_require(_cancelCount == 1, "clicking Cancel emitted cancelled %d times" % _cancelCount)

	_chosen.clear()
	menu.updateModel(_commandModel())
	menu.updateModel(_commandModel())
	_clickRow(_capturedRows.get(MOVE_INDEX))
	_require(_chosen == ["move"], "rebuilt Move row emitted %s after one click" % [_chosen])


func _clickRow(row: Control) -> void:
	if row == null:
		failures.append("attempted to click a row that was never captured")
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)


func _labelText(row: Control) -> String:
	if row == null:
		return ""
	var clip := row.get_child(0)
	if clip == null or clip.get_child_count() == 0:
		return ""
	return str((clip.get_child(0) as Label).text)


func _valueText(row: Control) -> String:
	if row == null or row.get_child_count() < 2:
		return ""
	return str((row.get_child(1) as Label).text)


func _isRowEnabledLooking(row: Control) -> bool:
	if row == null:
		return false
	var clip := row.get_child(0)
	var label := clip.get_child(0) as Label
	if not label.has_theme_color_override("font_color"):
		return true
	return label.get_theme_color("font_color") != NoggThemeScript.TEXT_DIM
