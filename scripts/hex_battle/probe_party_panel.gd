extends SceneTree

const HexPartyPanelScript = preload("res://src/presentation/battle/ui/HexPartyPanel.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const HEADER_INDEX := 0
const KNIGHT_INDEX := 1
const MAGE_INDEX := 2
const CLERIC_INDEX := 3
const END_PARTY_INDEX := 4

var failures: Array[String] = []

## Bypasses this probe's own capture of the panel's row_built signal --
## the panel connects itself once in _init(), and this second, independent
## listener lets the probe read back what got built without adding any
## test-only API to HexPartyPanel itself.
var _capturedRows: Dictionary = {}  ## full_index -> Control

var _memberSelections: Array[int] = []
var _endPartyCount := 0

## Held past _init() so the panel is not garbage-collected before its
## deferred _ready() runs -- see the note on the process_frame wait below.
var _panel: HexPartyPanel


func _init() -> void:
	_panel = HexPartyPanelScript.new()
	root.add_child(_panel)
	# A node's _ready() is not synchronous with add_child() this early in a
	# --script SceneTree's life; it is queued and only runs once the engine
	# actually reaches a process frame. NoggWindow builds its whole _content
	# tree in _ready(), so anything here that calls updateModel() has to wait
	# for that frame first, or add_row() finds _content still null.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var panel := _panel
	# HexPartyPanel's public contract is only updateModel() and its two
	# signals; reaching into its NoggWindow directly is how this probe reads
	# back what got built (row text, colour overrides, and a place to fire
	# gui_input for the click checks) without adding test-only API to it.
	var window: NoggWindow = panel._window
	window.row_built.connect(_on_row_built)
	panel.member_selected.connect(func(monsterID: int): _memberSelections.append(monsterID))
	panel.end_party_requested.connect(func(): _endPartyCount += 1)

	_checkEmptyModelClearsPanel(panel, window)
	_checkActiveModel(panel, window)
	_checkFullyDisabledModel(panel, window)
	_checkClicksAndNoDuplication(panel, window)

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_PARTY_PANEL_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_PARTY_PANEL_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _on_row_built(row: Control, full_index: int) -> void:
	_capturedRows[full_index] = row


func _memberModel() -> Dictionary:
	return {
		"party_id": 7,
		"label": "Vanguard",
		"input_enabled": true,
		"can_end_party": true,
		"members": [
			{
				"id": 101, "label": "Knight", "commander": true,
				"eligible": true, "active": true, "spent": false,
			},
			{
				"id": 102, "label": "Mage", "commander": false,
				"eligible": true, "active": false, "spent": false,
			},
			{
				"id": 103, "label": "Cleric", "commander": false,
				"eligible": false, "active": false, "spent": true,
			},
		],
	}


func _checkEmptyModelClearsPanel(_panel: HexPartyPanel, window: NoggWindow) -> void:
	_capturedRows.clear()
	window.set_full_rows([{"label": "stale", "value": "", "disabled": false}])
	_panel.updateModel({})
	_require(window.row_count() == 0,
		"empty model left %d rows behind" % window.row_count())


func _checkActiveModel(panel: HexPartyPanel, window: NoggWindow) -> void:
	_capturedRows.clear()
	panel.updateModel(_memberModel())

	_require(window.row_count() == 5,
		"active model built %d rows, expected 5 (header + 3 members + end party)" %
		window.row_count())

	_require(_labelText(_capturedRows.get(HEADER_INDEX)) == "Vanguard",
		"header row did not show the party label")

	_require(_labelText(_capturedRows.get(KNIGHT_INDEX)) == "Knight",
		"member 0 was not rendered first -- supplied order was not preserved")
	_require(_valueText(_capturedRows.get(KNIGHT_INDEX)) == "CMD ACTIVE",
		"commander+active member did not show 'CMD ACTIVE'")
	_require(_isRowEnabledLooking(_capturedRows.get(KNIGHT_INDEX)),
		"eligible member under input_enabled rendered as disabled")

	_require(_labelText(_capturedRows.get(MAGE_INDEX)) == "Mage",
		"member 1 was not rendered second -- supplied order was not preserved")
	_require(_valueText(_capturedRows.get(MAGE_INDEX)) == "",
		"a plain member showed a status value")
	_require(_isRowEnabledLooking(_capturedRows.get(MAGE_INDEX)),
		"eligible member under input_enabled rendered as disabled")

	_require(_labelText(_capturedRows.get(CLERIC_INDEX)) == "Cleric",
		"member 2 was not rendered third -- supplied order was not preserved")
	_require(_valueText(_capturedRows.get(CLERIC_INDEX)) == "DONE",
		"a spent member did not show 'DONE'")
	_require(not _isRowEnabledLooking(_capturedRows.get(CLERIC_INDEX)),
		"an ineligible member rendered as enabled")

	_require(_labelText(_capturedRows.get(END_PARTY_INDEX)) == "End Party",
		"end party row missing or out of position")
	_require(_isRowEnabledLooking(_capturedRows.get(END_PARTY_INDEX)),
		"end party rendered as disabled when input_enabled and can_end_party were both true")


## input_enabled=false must disable every member and End Party regardless of
## their own eligible/can_end_party flags -- interactivity is gated by both.
func _checkFullyDisabledModel(panel: HexPartyPanel, window: NoggWindow) -> void:
	_capturedRows.clear()
	var model := _memberModel()
	model["input_enabled"] = false
	panel.updateModel(model)

	_require(not _isRowEnabledLooking(_capturedRows.get(KNIGHT_INDEX)),
		"an eligible member rendered as enabled while input_enabled was false")
	_require(not _isRowEnabledLooking(_capturedRows.get(MAGE_INDEX)),
		"an eligible member rendered as enabled while input_enabled was false")
	_require(not _isRowEnabledLooking(_capturedRows.get(END_PARTY_INDEX)),
		"end party rendered as enabled while input_enabled was false")


func _checkClicksAndNoDuplication(panel: HexPartyPanel, window: NoggWindow) -> void:
	_capturedRows.clear()
	_memberSelections.clear()
	_endPartyCount = 0
	panel.updateModel(_memberModel())

	# A disabled row was never wired in _on_row_built(), so emitting on it
	# must be a silent no-op.
	_clickRow(_capturedRows.get(CLERIC_INDEX))
	_require(_memberSelections.is_empty(),
		"clicking a disabled member emitted member_selected anyway")

	_clickRow(_capturedRows.get(KNIGHT_INDEX))
	_require(_memberSelections == [101],
		"clicking the Knight row emitted %s, expected [101]" % [_memberSelections])

	_clickRow(_capturedRows.get(END_PARTY_INDEX))
	_require(_endPartyCount == 1,
		"clicking End Party emitted end_party_requested %d times, expected 1" %
		_endPartyCount)

	# Rebuilding with equivalent data must not accumulate a second internal
	# connection on top of the first -- one click, one emission, even after
	# repeated updateModel() calls.
	_memberSelections.clear()
	panel.updateModel(_memberModel())
	panel.updateModel(_memberModel())
	_clickRow(_capturedRows.get(KNIGHT_INDEX))
	_require(_memberSelections == [101],
		"a rebuilt row emitted member_selected %s after one click, expected exactly [101]" %
		[_memberSelections])


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


## A row's label carries a TEXT_DIM override only when add_row() built it
## disabled; an enabled row's label is left at the theme default. Reading
## this back, rather than re-deriving "enabled" from the model, is what
## actually proves the panel told NoggWindow the right thing.
func _isRowEnabledLooking(row: Control) -> bool:
	if row == null:
		return false
	var clip := row.get_child(0)
	var label := clip.get_child(0) as Label
	if not label.has_theme_color_override("font_color"):
		return true
	return label.get_theme_color("font_color") != NoggThemeScript.TEXT_DIM
