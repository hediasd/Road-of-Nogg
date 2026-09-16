## The command rail: a stable column of plates on the right edge, a spell window that opens inward
## from it, and a hint box that says what the focused choice does or why it cannot.
##
## OWNS NEITHER AVAILABILITY NOR MEANING. The caller supplies both in the model -- `enabled`,
## `hint`, `reason` -- and this node reports a chosen command id, a presentation-only request
## (`local_requested`, for STATUS), or a cancel. The spell rows are the `children` of the `magic`
## entry; opening them is navigation, not a command, so no controller ever hears about it.
##
## ONE FOCUS, TWO DEVICES. Hovering a plate focuses it, exactly like an arrow key does, and a click
## is focus-then-activate (UI_DESIGN §6: the selection is the only selection truth). Disabled
## plates are focusable, which departs from §6's skip rule on purpose: the plan this rail was built
## to asks that an unavailable action explain itself, and a plate the cursor can never land on has
## no way to. They are still inert to activation.
##
## THE RAIL NEVER MOVES. It is anchored top-right for the whole battle and does not follow the
## acting unit or the pointer. Only its content changes.

class_name HexCommandMenu
extends Control

signal command_chosen(commandID: String)
## A plate that means something only to the HUD, such as `status`.
signal local_requested(commandID: String)
signal cancelled()
## Every plate row and every spell row as it is built, with a rail-wide index. Plates come first
## in model order; spell rows follow. For probes and anything else that needs the real Controls.
signal row_built(row: Control, index: int)

const HexCommandPlateScript = preload("res://src/presentation/battle/ui/HexCommandPlate.gd")
const HexTextBoxScript = preload("res://src/presentation/battle/ui/HexTextBox.gd")
const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const MenuCursorScript = preload("res://src/presentation/theme/MenuCursor.gd")

const MAGIC_GROUP := "magic"
## Rows the spell window pages at. Six is the compact layout's own ceiling (HudLayoutCatalog).
const SPELL_ROWS_MAX := 6
const SPELL_ROW_INDEX_BASE := 100

var _inputEnabled := false
var _commands: Array = []
var _plates: Array[HexCommandPlate] = []
var _focusID := ""

var _cursor: MenuCursor
var _hint: HexTextBox

var _spellWindow: NoggWindow
var _spellCursor: MenuCursor
var _spells: Array = []
var _spellFocus := 0
var _spellOpen := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cursor = MenuCursorScript.new()
	_cursor.name = "RailCursor"

	_spellWindow = NoggWindowScript.new()
	_spellWindow.name = "SpellWindow"
	_spellWindow.visible = false
	_spellWindow.row_built.connect(_onSpellRowBuilt)
	_spellWindow.page_arrow_pressed.connect(_onSpellPageArrow)
	add_child(_spellWindow)

	_spellCursor = MenuCursorScript.new()
	_spellCursor.name = "SpellCursor"

	_hint = HexTextBoxScript.new()
	_hint.name = "Hint"
	add_child(_hint)


func _ready() -> void:
	_spellWindow.size.x = NoggThemeScript.HEX_SPELL_WIDTH
	_spellWindow.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)
	_spellCursor.position.x = NoggThemeScript.CURSOR_INSET
	_spellWindow.add_child(_spellCursor)
	_cursor.position.x = -NoggThemeScript.CURSOR_WIDTH - NoggThemeScript.HEX_PLATE_GAP
	add_child(_cursor)
	_cursor.visible = false
	_hint.setWidth(NoggThemeScript.HEX_HINT_WIDTH)


## `model` keys: input_enabled (bool), commands (Array of Dictionaries with id, label, icon,
## enabled, hint, reason, and `children` for the magic group). Plates are rebuilt; focus is kept by
## id when the rebuilt rail still has that plate, so returning from an aim lands where the player
## left.
func updateModel(model: Dictionary) -> void:
	_commands = model.get("commands", [])
	_inputEnabled = bool(model.get("input_enabled", false))
	for plate in _plates:
		remove_child(plate)
		plate.queue_free()
	_plates.clear()
	_closeSpells()

	if _commands.is_empty():
		_cursor.visible = false
		_hint.hideBox()
		return

	var y := 0.0
	for index in range(_commands.size()):
		var entry: Dictionary = _commands[index]
		var plate: HexCommandPlate = HexCommandPlateScript.new()
		plate.name = "Plate_%s" % str(entry.get("id", index))
		plate.configure(entry, _inputEnabled)
		plate.row_built.connect(_onPlateRowBuilt.bind(index))
		add_child(plate)
		# Each plate steps left of the one above, so the column leans the way the reference's plates
		# are cut without the frame art itself being skewed. Offsets are measured from this node's
		# own top-left, like every other window, so `windowSize()` and the rail's rect agree.
		plate.position = Vector2(
			NoggThemeScript.HEX_PLATE_LEAN * float(_commands.size() - 1 - index), y
		)
		y += plate.plateSize().y + NoggThemeScript.HEX_PLATE_GAP
		_plates.append(plate)
	move_child(_cursor, get_child_count() - 1)
	move_child(_hint, get_child_count() - 1)
	size = Vector2(railWidth(_commands.size()), maxf(y - NoggThemeScript.HEX_PLATE_GAP, 0.0))

	if _indexOf(_focusID) == -1:
		_focusID = _firstEnabledID()
	_applyFocus(false)


# --- queries (probes and the HUD) -------------------------------------------

func plateCount() -> int:
	return _plates.size()


## The rail's footprint, as `HexPartyPanel.windowSize()` reports one: the plates plus the lean the
## column picks up on the way down. Zero while no rail is up.
func windowSize() -> Vector2:
	if _plates.is_empty():
		return Vector2.ZERO
	var last := _plates[_plates.size() - 1]
	return Vector2(railWidth(_plates.size()), last.position.y + last.plateSize().y)


## How wide a rail of `count` plates is, before it is built.
static func railWidth(count: int) -> float:
	return NoggThemeScript.HEX_PLATE_WIDTH \
		+ NoggThemeScript.HEX_PLATE_LEAN * float(maxi(count - 1, 0))


func focusedID() -> String:
	return _focusID


func isSpellWindowOpen() -> bool:
	return _spellOpen


func plateWithLabel(label: String) -> HexCommandPlate:
	for plate in _plates:
		if plate.labelText() == label:
			return plate
	return null


func hintText() -> String:
	var entry := _focusedEntry()
	if entry.is_empty():
		return ""
	return _textFor(entry)


# --- input --------------------------------------------------------------------

## Keyboard entry point. Returns whether the event was the rail's. All four directions are
## consumed while the rail is up, whether or not they moved anything (UI_DESIGN §6).
func handleKey(event: InputEventKey) -> bool:
	if not visible or _plates.is_empty() or not event.pressed:
		return false
	match event.keycode:
		KEY_UP, KEY_W:
			_step(-1)
			return true
		KEY_DOWN, KEY_S:
			_step(1)
			return true
		KEY_LEFT, KEY_A:
			if _spellOpen:
				_spellWindow.prev_page()
				_focusSpell(_spellWindow.page_start_index(_spellWindow.page()), true)
			return true
		KEY_RIGHT, KEY_D:
			if _spellOpen:
				_spellWindow.next_page()
				_focusSpell(_spellWindow.page_start_index(_spellWindow.page()), true)
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _spellOpen:
				_activateSpell(_spellFocus)
			else:
				activate(_focusID)
			return true
		KEY_ESCAPE, KEY_BACKSPACE:
			return cancel()
	return false


## Right click and Escape. Closes the spell window if it is open; at the rail there is nothing to
## back out of -- a member turn ends by acting or waiting (HexBattleMemberInput.cancel).
func cancel() -> bool:
	if _spellOpen:
		_closeSpells()
		_applyFocus(true)
		return true
	cancelled.emit()
	return false


## Focus a plate by id and, if it can, carry it out.
func activate(commandID: String) -> bool:
	var index := _indexOf(commandID)
	if index == -1:
		return false
	_focusID = commandID
	_applyFocus(true)
	var entry: Dictionary = _commands[index]
	if not _inputEnabled or not bool(entry.get("enabled", false)):
		return false
	if commandID == MAGIC_GROUP:
		_openSpells(entry)
		return true
	if bool(entry.get("local", false)):
		local_requested.emit(commandID)
		return true
	command_chosen.emit(commandID)
	return true


# --- rail focus -----------------------------------------------------------------

func _step(direction: int) -> void:
	if _spellOpen:
		var count := _spells.size()
		if count == 0:
			return
		_focusSpell(posmod(_spellFocus + direction, count), true)
		return
	var index := _indexOf(_focusID)
	if index == -1:
		index = 0
	else:
		index = posmod(index + direction, _commands.size())
	_focusID = str(_commands[index].get("id", ""))
	_applyFocus(true)


func _applyFocus(animate: bool) -> void:
	var index := _indexOf(_focusID)
	for plateIndex in range(_plates.size()):
		_plates[plateIndex].setFocused(plateIndex == index and not _spellOpen)
	if index == -1:
		_cursor.visible = false
		_hint.hideBox()
		return
	var plate := _plates[index]
	var rect := Rect2(Vector2(plate.position.x, plate.position.y), plate.plateSize())
	_cursor.visible = not _spellOpen
	_cursor.reposition_gutter(rect.position.x - NoggThemeScript.CURSOR_WIDTH - NoggThemeScript.HEX_PLATE_GAP)
	if animate:
		_cursor.move_to_row(rect)
	else:
		_cursor.snap_to_row(rect)
	if not _spellOpen:
		_showHint(_commands[index], rect)


func _showHint(entry: Dictionary, anchor: Rect2) -> void:
	var text := _textFor(entry)
	_hint.showText(text, "", "", 2)
	if not _hint.isShown():
		return
	# Left of the plate it explains, top-aligned with it, clear of the cursor.
	_hint.position = Vector2(
		anchor.position.x - NoggThemeScript.CURSOR_WIDTH - NoggThemeScript.HEX_PLATE_GAP * 2.0
			- _hint.boxSize().x,
		anchor.position.y
	)


func _textFor(entry: Dictionary) -> String:
	var reason := str(entry.get("reason", ""))
	if not _inputEnabled:
		return ""
	if not bool(entry.get("enabled", false)) and not reason.is_empty():
		return reason
	return str(entry.get("hint", ""))


func _indexOf(commandID: String) -> int:
	for index in range(_commands.size()):
		if str(_commands[index].get("id", "")) == commandID:
			return index
	return -1


func _firstEnabledID() -> String:
	for entry in _commands:
		if bool(entry.get("enabled", false)):
			return str(entry.get("id", ""))
	return str(_commands[0].get("id", "")) if not _commands.is_empty() else ""


func _focusedEntry() -> Dictionary:
	var index := _indexOf(_focusID)
	return _commands[index] if index != -1 else {}


func _onPlateRowBuilt(built: Control, index: int) -> void:
	built.mouse_filter = Control.MOUSE_FILTER_STOP
	built.mouse_entered.connect(_onPlateHovered.bind(index))
	built.gui_input.connect(_onPlateGuiInput.bind(index))
	row_built.emit(built, index)


func _onPlateHovered(index: int) -> void:
	if _spellOpen or index >= _commands.size():
		return
	var commandID := str(_commands[index].get("id", ""))
	if commandID == _focusID:
		return
	_focusID = commandID
	_applyFocus(true)


func _onPlateGuiInput(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if index >= _commands.size():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _spellOpen:
			_closeSpells()
		activate(str(_commands[index].get("id", "")))
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		accept_event()


# --- spell window ---------------------------------------------------------------

func _openSpells(entry: Dictionary) -> void:
	_spells = entry.get("children", [])
	if _spells.is_empty():
		return
	var index := _indexOf(MAGIC_GROUP)
	var plate := _plates[index]
	var descriptors: Array = []
	for spell in _spells:
		descriptors.append({
			"label": str(spell.get("label", "")),
			"value": str(spell.get("detail", "")),
			"disabled": not (_inputEnabled and bool(spell.get("enabled", false))),
		})
	_spellWindow.set_row_capacity(mini(_spells.size(), SPELL_ROWS_MAX))
	_spellWindow.position = Vector2(
		plate.position.x - NoggThemeScript.HEX_PLATE_GAP * 2.0 - _spellWindow.size.x,
		plate.position.y
	)
	_spellOpen = true
	_spellWindow.visible = true
	_spellWindow.set_full_rows(descriptors)
	_spellWindow.open()
	for plateIndex in range(_plates.size()):
		_plates[plateIndex].setFocused(false)
	_cursor.visible = false
	var first := 0
	for spellIndex in range(_spells.size()):
		if bool(_spells[spellIndex].get("enabled", false)):
			first = spellIndex
			break
	_focusSpell(first, false)


func _closeSpells() -> void:
	if not _spellOpen:
		return
	_spellOpen = false
	_spellWindow.visible = false
	_spellWindow.set_full_rows([])
	_spells = []


func _focusSpell(index: int, animate: bool) -> void:
	if index < 0 or index >= _spells.size():
		return
	_spellFocus = index
	var focus := _spellWindow.focus_index(index)
	var rect: Rect2 = focus["rect"]
	if animate and not bool(focus["turned"]):
		_spellCursor.move_to_row(rect)
	else:
		_spellCursor.snap_to_row(rect)
	var spell: Dictionary = _spells[index]
	_hint.showText(_textFor(spell), str(spell.get("label", "")), "", 3)
	# Under the spell window and flush with its left edge, which keeps it clear of the plates: the
	# rail leans left as it descends, so a box flush right would slide under the lower plates.
	_hint.position = Vector2(
		_spellWindow.position.x,
		_spellWindow.position.y + _spellWindow.size.y + NoggThemeScript.HEX_PLATE_GAP * 2.0
	)


func _activateSpell(index: int) -> void:
	if index < 0 or index >= _spells.size():
		return
	_focusSpell(index, true)
	var spell: Dictionary = _spells[index]
	if not _inputEnabled or not bool(spell.get("enabled", false)):
		return
	var spellID := str(spell.get("id", ""))
	_closeSpells()
	command_chosen.emit(spellID)


func _onSpellRowBuilt(built: Control, fullIndex: int) -> void:
	built.mouse_filter = Control.MOUSE_FILTER_STOP
	built.mouse_entered.connect(func():
		if _spellOpen and fullIndex != _spellFocus:
			_focusSpell(fullIndex, true))
	built.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton) or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_activateSpell(fullIndex)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			accept_event())
	row_built.emit(built, SPELL_ROW_INDEX_BASE + fullIndex)


func _onSpellPageArrow(direction: int) -> void:
	if direction < 0:
		_spellWindow.prev_page()
	else:
		_spellWindow.next_page()
	_focusSpell(_spellWindow.page_start_index(_spellWindow.page()), false)
