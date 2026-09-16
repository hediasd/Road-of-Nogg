## The command rail on its own, driven from a supplied model: plates in order, disabled plates that
## explain themselves, the spell window opening inward and handing back focus, the STATUS plate
## staying presentation-only, and a rebuilt rail never double-wiring a click.
extends SceneTree

const HexCommandMenuScript = preload("res://src/presentation/battle/ui/HexCommandMenu.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const REJECTED_LABELS := ["Details", "MOVE ready", "ACTION ready"]

var failures: Array[String] = []
var _rows: Dictionary = {}
var _chosen: Array[String] = []
var _local: Array[String] = []
var _menu: HexCommandMenu


func _init() -> void:
	var host := Control.new()
	host.theme = NoggThemeScript.build_game_theme()
	root.add_child(host)
	_menu = HexCommandMenuScript.new()
	host.add_child(_menu)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_menu.row_built.connect(func(row: Control, index: int): _rows[index] = row)
	_menu.command_chosen.connect(func(commandID: String): _chosen.append(commandID))
	_menu.local_requested.connect(func(commandID: String): _local.append(commandID))
	_menu.visible = true

	_checkEmptyModelClearsRail()
	_checkPlatesFollowTheModel()
	_checkInputGate()
	_checkDisabledPlatesExplainAndRefuse()
	_checkKeyboardAndSpellWindow()
	_checkLocalPlate()
	_checkRebuildDoesNotDoubleWire()

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


func _model(inputEnabled := true) -> Dictionary:
	return {
		"input_enabled": inputEnabled,
		"commands": [
			{"id": "move", "label": "Move", "icon": "move", "enabled": true,
				"hint": "Walk up to 3 cells.", "reason": ""},
			{"id": "attack", "label": "Attack", "icon": "attack", "enabled": false,
				"hint": "Strike a unit within reach.", "reason": "Already acted this turn."},
			{"id": "magic", "label": "Magic", "icon": "magic", "enabled": true,
				"hint": "Cast one of 2 spells.", "reason": "", "children": [
					{"id": "spell:0:0", "label": "Ember", "detail": "Rng 2", "enabled": false,
						"reason": "Ready in 2 turns."},
					{"id": "spell:0:1", "label": "Frost", "detail": "Rng 3", "enabled": true,
						"hint": "Ice. Range 3."},
				]},
			{"id": "status", "label": "Status", "icon": "status", "enabled": true, "local": true,
				"hint": "Open the selected unit's full status.", "reason": ""},
			{"id": "end", "label": "End turn", "icon": "pass", "enabled": true,
				"hint": "Finish the turn.", "reason": ""},
		],
	}


func _checkEmptyModelClearsRail() -> void:
	_menu.updateModel(_model())
	_menu.updateModel({})
	_require(_menu.plateCount() == 0, "empty model left %d plates behind" % _menu.plateCount())


func _checkPlatesFollowTheModel() -> void:
	_rows.clear()
	_menu.updateModel(_model())
	_require(_menu.plateCount() == 5, "model built %d plates, expected 5" % _menu.plateCount())
	var expected := ["Move", "Attack", "Magic", "Status", "End turn"]
	for index in range(expected.size()):
		_require(_labelText(_rows.get(index)) == expected[index],
			"plate %d read '%s', expected '%s'" % [index, _labelText(_rows.get(index)), expected[index]])
	_require(_looksEnabled(_rows.get(0)), "enabled Move rendered disabled")
	_require(not _looksEnabled(_rows.get(1)), "disabled Attack rendered enabled")
	_require(_menu.focusedID() == "move", "rail opened focused on '%s', not Move" % _menu.focusedID())
	_require(_menu.hintText() == "Walk up to 3 cells.", "focused Move did not show its hint")
	# Every plate sits inside the rail's own rect, and the column leans left on the way down.
	var railSize := _menu.windowSize()
	var previousX := INF
	for index in range(_menu.plateCount()):
		var plate: HexCommandPlate = _menu.plateWithLabel(expected[index])
		_require(
			plate.position.x >= 0.0 and plate.position.x + plate.plateSize().x <= railSize.x + 0.5,
			"plate '%s' falls outside the rail's own %s rect" % [expected[index], railSize])
		_require(plate.position.x <= previousX,
			"plate '%s' does not lean with the rail" % expected[index])
		previousX = plate.position.x
	for label in REJECTED_LABELS:
		_require(_menu.plateWithLabel(label) == null, "rail shows the rejected label '%s'" % label)


func _checkInputGate() -> void:
	_rows.clear()
	_menu.updateModel(_model(false))
	for index in range(5):
		_require(not _looksEnabled(_rows.get(index)), "input gate left plate %d enabled" % index)
	_chosen.clear()
	_click(_rows.get(0))
	_require(_chosen.is_empty(), "a gated rail still emitted %s" % [_chosen])


func _checkDisabledPlatesExplainAndRefuse() -> void:
	_rows.clear()
	_chosen.clear()
	_menu.updateModel(_model())
	_click(_rows.get(1))
	_require(_chosen.is_empty(), "clicking disabled Attack emitted %s" % [_chosen])
	_require(_menu.focusedID() == "attack", "clicking disabled Attack did not focus it")
	_require(_menu.hintText() == "Already acted this turn.",
		"focused disabled Attack explained '%s' instead of its reason" % _menu.hintText())
	_click(_rows.get(0))
	_require(_chosen == ["move"], "clicking Move emitted %s, expected [move]" % [_chosen])


func _checkKeyboardAndSpellWindow() -> void:
	_rows.clear()
	_chosen.clear()
	_menu.updateModel(_model())
	_key(KEY_DOWN)
	_require(_menu.focusedID() == "attack", "Down from Move focused '%s'" % _menu.focusedID())
	_key(KEY_DOWN)
	_require(_menu.focusedID() == "magic", "Down from Attack focused '%s'" % _menu.focusedID())
	_key(KEY_UP)
	_key(KEY_DOWN)
	_key(KEY_ENTER)
	_require(_menu.isSpellWindowOpen(), "Enter on Magic did not open the spell window")
	_require(_chosen.is_empty(), "opening Magic reached the controller as %s" % [_chosen])
	_require(_labelText(_rows.get(HexCommandMenu.SPELL_ROW_INDEX_BASE)) == "Ember",
		"spell window's first row was not Ember")
	_require(not _looksEnabled(_rows.get(HexCommandMenu.SPELL_ROW_INDEX_BASE)),
		"cooling-down Ember rendered castable")
	_key(KEY_ESCAPE)
	_require(not _menu.isSpellWindowOpen(), "Escape did not close the spell window")
	_require(_menu.focusedID() == "magic", "closing the spell window lost Magic's focus")

	# The window opens on the first castable spell, not on a row that would refuse the confirm.
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	_require(_chosen == ["spell:0:1"], "Enter on Frost emitted %s, expected [spell:0:1]" % [_chosen])
	_require(not _menu.isSpellWindowOpen(), "casting left the spell window open")

	_chosen.clear()
	_key(KEY_ENTER)
	_click(_rows.get(HexCommandMenu.SPELL_ROW_INDEX_BASE))
	_require(_chosen.is_empty(), "clicking cooling-down Ember emitted %s" % [_chosen])
	_menu.cancel()


func _checkLocalPlate() -> void:
	_rows.clear()
	_chosen.clear()
	_local.clear()
	_menu.updateModel(_model())
	_click(_rows.get(3))
	_require(_local == ["status"], "clicking Status requested %s, expected [status]" % [_local])
	_require(_chosen.is_empty(), "Status reached the controller as a command: %s" % [_chosen])


func _checkRebuildDoesNotDoubleWire() -> void:
	_chosen.clear()
	_menu.updateModel(_model())
	_menu.updateModel(_model())
	_rows.clear()
	_menu.updateModel(_model())
	_click(_rows.get(0))
	_require(_chosen == ["move"], "rebuilt Move emitted %s after one click" % [_chosen])


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_menu.handleKey(event)


func _click(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		failures.append("attempted to click a row that was never captured")
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)


func _labelText(row: Control) -> String:
	if row == null or not is_instance_valid(row):
		return ""
	var clip := row.get_child(0)
	if clip == null or clip.get_child_count() == 0:
		return ""
	return str((clip.get_child(0) as Label).text)


func _looksEnabled(row: Control) -> bool:
	if row == null or not is_instance_valid(row):
		return false
	var label := row.get_child(0).get_child(0) as Label
	if not label.has_theme_color_override("font_color"):
		return true
	return label.get_theme_color("font_color") != NoggThemeScript.TEXT_DIM
