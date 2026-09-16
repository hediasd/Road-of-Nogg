## The STATUS sheet: the whole of one unit on four tabs -- profile, effects, skills, gear -- beside a
## portrait placeholder, with an explanation box for whichever row is focused.
##
## MODAL. While it is open the board takes no input; the HUD routes keys and clicks here first,
## and a click outside the sheet closes it. It reads nothing itself -- it renders a
## `HexUnitFacts` dictionary -- so a unit that dies with the sheet open is noticed by the HUD, which
## closes it, rather than by this node discovering a stale `Monster`.
##
## PLACEHOLDERS SAY THEY ARE PLACEHOLDERS. The portrait is an initial in a dim square, and the three
## gear slots read `Empty` with an explanation that equipment is not a battle rule yet. Neither
## invents content the game does not have.

class_name HexCharacterStatus
extends Control

signal closed()

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const MenuCursorScript = preload("res://src/presentation/theme/MenuCursor.gd")
const HexTextBoxScript = preload("res://src/presentation/battle/ui/HexTextBox.gd")
const HexHpBarScript = preload("res://src/presentation/battle/ui/HexHpBar.gd")
const HexElementSquareScript = preload("res://src/presentation/battle/ui/HexElementSquare.gd")

const TABS := ["PROFILE", "EFFECTS", "SKILLS", "GEAR"]
const TAB_PROFILE := 0
const TAB_EFFECTS := 1
const TAB_SKILLS := 2
const TAB_GEAR := 3
const PORTRAIT_ROWS := 4
const GEAR_NOTE := "Equipment is not in battle yet. These slots are where it will go."

var _facts: Dictionary = {}
var _tab := TAB_PROFILE
var _open := false

var _tabsWindow: NoggWindow
var _tabLabels: Array[Label] = []
var _portraitWindow: NoggWindow
var _portraitInitial: Label
var _body: NoggWindow
var _bodyOverlay: Control
var _cursor: MenuCursor
var _info: HexTextBox

## Per full-row index of the current tab: {selectable: bool, text: String, title: String}.
var _rowMeta: Array[Dictionary] = []
var _focus := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_portraitWindow = NoggWindowScript.new()
	_portraitWindow.name = "Portrait"
	_portraitWindow.set_input_transparent(true)
	add_child(_portraitWindow)

	_tabsWindow = NoggWindowScript.new()
	_tabsWindow.name = "Tabs"
	_tabsWindow.set_input_transparent(true)
	add_child(_tabsWindow)

	_body = NoggWindowScript.new()
	_body.name = "Body"
	_body.row_built.connect(_onRowBuilt)
	add_child(_body)
	_bodyOverlay = Control.new()
	_bodyOverlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_bodyOverlay)

	_cursor = MenuCursorScript.new()
	_info = HexTextBoxScript.new()
	add_child(_info)


func _ready() -> void:
	var gap := NoggThemeScript.HEX_PLATE_GAP * 2.0
	var portraitWidth := NoggThemeScript.HEX_PORTRAIT + float(NoggThemeScript.CONTENT_INSET) * 2.0
	_portraitWindow.size.x = portraitWidth
	_portraitWindow.set_row_capacity(PORTRAIT_ROWS)

	var column := portraitWidth + gap
	_tabsWindow.size.x = NoggThemeScript.HEX_SHEET_WIDTH
	_tabsWindow.set_row_capacity(1)
	_tabsWindow.position = Vector2(column, 0.0)

	_body.size.x = NoggThemeScript.HEX_SHEET_WIDTH
	_body.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)
	_body.set_row_capacity(NoggThemeScript.HEX_SHEET_CAPACITY)
	_body.position = Vector2(column, _tabsWindow.size.y + gap)
	# The overlay was added before the window built its chrome, so it sits under the body; the HP
	# bar and element squares have to draw over the rows.
	_body.move_child(_bodyOverlay, _body.get_child_count() - 1)
	_cursor.position.x = NoggThemeScript.CURSOR_INSET
	_body.add_child(_cursor)

	_info.setWidth(NoggThemeScript.HEX_SHEET_WIDTH)
	_info.position = Vector2(column, _body.position.y + _body.size.y + gap)

	var placeholder := ColorRect.new()
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.color = NoggThemeScript.HEX_PORTRAIT_FILL
	placeholder.position = Vector2(
		float(NoggThemeScript.CONTENT_INSET),
		floorf((_portraitWindow.size.y - NoggThemeScript.HEX_PORTRAIT) / 2.0)
	)
	placeholder.size = Vector2(NoggThemeScript.HEX_PORTRAIT, NoggThemeScript.HEX_PORTRAIT)
	_portraitWindow.add_child(placeholder)
	_portraitInitial = Label.new()
	_portraitInitial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portraitInitial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portraitInitial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portraitInitial.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	_portraitInitial.position = placeholder.position
	_portraitInitial.size = placeholder.size
	_portraitWindow.add_child(_portraitInitial)

	var tabRect := Rect2(
		Vector2(float(NoggThemeScript.CONTENT_INSET), float(NoggThemeScript.CONTENT_INSET)),
		Vector2(_tabsWindow.size.x, float(NoggThemeScript.ROW_HEIGHT))
	)
	var x := tabRect.position.x
	for index in range(TABS.size()):
		var label := Label.new()
		label.text = TABS[index]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.size = label.get_minimum_size()
		label.position = Vector2(x, tabRect.position.y + floorf((tabRect.size.y - label.size.y) / 2.0))
		label.gui_input.connect(_onTabInput.bind(index))
		_tabsWindow.add_child(label)
		_tabLabels.append(label)
		x += label.size.x + _spaceWidth() * 2.0

	size = Vector2(column + NoggThemeScript.HEX_SHEET_WIDTH, _info.position.y)


func sheetSize() -> Vector2:
	return size


func isOpen() -> bool:
	return _open


func unitID() -> int:
	return int(_facts.get("id", -1))


func currentTab() -> int:
	return _tab


func openFor(facts: Dictionary) -> void:
	if facts.is_empty():
		return
	_facts = facts
	_tab = TAB_PROFILE
	_focus = -1
	_open = true
	visible = true
	_render()
	for window in [_portraitWindow, _tabsWindow, _body]:
		window.open()


## New facts for the unit already shown -- HP ticking down while the sheet is open -- without
## losing the tab or the focused row.
func refresh(facts: Dictionary) -> void:
	if not _open or facts.is_empty():
		return
	_facts = facts
	var keep := _focus
	var page := _body.page()
	_render()
	if page > 0 and page < _body.page_count():
		_body.focus_index(_body.page_start_index(page))
	if keep >= 0 and keep < _rowMeta.size():
		_setFocus(keep, false)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_info.hideBox()
	closed.emit()


func setTab(tab: int) -> void:
	_tab = posmod(tab, TABS.size())
	_focus = -1
	_render()


func handleKey(event: InputEventKey) -> bool:
	if not _open or not event.pressed:
		return false
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_LEFT, KEY_A, KEY_Q:
			setTab(_tab - 1)
		KEY_RIGHT, KEY_D, KEY_E, KEY_TAB:
			setTab(_tab + 1)
		KEY_UP, KEY_W:
			_stepFocus(-1)
		KEY_DOWN, KEY_S:
			_stepFocus(1)
	# Modal: every key is the sheet's while it is open, so nothing leaks to the camera or the rail.
	return true


## Board-level mouse while open. A left click that reached the board landed outside the sheet's
## input-taking boxes, so it closes the sheet; a right click always does.
func handleUnhandledMouse(event: InputEventMouseButton) -> bool:
	if not _open or not event.pressed:
		return false
	if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		close()
	return true


func _render() -> void:
	for index in range(_tabLabels.size()):
		_tabLabels[index].add_theme_color_override(
			"font_color", NoggThemeScript.TEXT_ACCENT if index == _tab else NoggThemeScript.TEXT_DIM
		)
	var unitName := str(_facts.get("name", "?"))
	_portraitInitial.text = unitName.substr(0, 1).to_upper()
	for child in _bodyOverlay.get_children():
		_bodyOverlay.remove_child(child)
		child.queue_free()

	var rows: Array = []
	_rowMeta.clear()
	match _tab:
		TAB_PROFILE:
			_profileRows(rows)
		TAB_EFFECTS:
			_effectRows(rows)
		TAB_SKILLS:
			_skillRows(rows)
		TAB_GEAR:
			_gearRows(rows)
	_body.set_full_rows(rows)
	if _tab == TAB_PROFILE:
		_decorateProfile()
	var first := _firstSelectable()
	if first == -1:
		_focus = -1
		_cursor.visible = false
		_info.hideBox()
	else:
		_setFocus(first if _focus == -1 else _focus, false)


func _add(rows: Array, label: String, value: String, meta: Dictionary, disabled := false) -> void:
	rows.append({"label": label, "value": value, "disabled": disabled})
	_rowMeta.append(meta)


func _profileRows(rows: Array) -> void:
	var level := "Lv %d" % int(_facts.get("level", 1))
	if bool(_facts.get("commander", false)):
		level = "CMD " + level
	_add(rows, str(_facts.get("name", "")), level, {})
	_add(rows, "HP", "%d/%d" % [int(_facts.get("hp", 0)), int(_facts.get("max_hp", 1))], {})
	_add(rows, "Elements", "", {})
	# One taxonomy row, not three: the sheet pages at six rows, and a profile that paged would
	# leave the HP bar and element squares drawn over the wrong page.
	var kinds: Array[String] = []
	for key in ["race", "family", "species"]:
		var value := _word(str(_facts.get(key, "none")))
		if value != "-" and not kinds.has(value):
			kinds.append(value)
	_add(rows, "Kind", " ".join(kinds) if not kinds.is_empty() else "-", {})
	var stats: Dictionary = _facts.get("stats", {})
	_add(rows, "ATK %d   DEF %d" % [int(stats.get("ATK", 0)), int(stats.get("DEF", 0))],
		"SPD %d" % int(stats.get("SPD", 0)), {})
	_add(rows, "MOV %d   JMP %d" % [int(stats.get("MOV", 0)), int(stats.get("JMP", 0))],
		"LUK %d" % int(stats.get("LUK", 0)), {})


func _effectRows(rows: Array) -> void:
	var effects: Array = _facts.get("effects", [])
	if effects.is_empty():
		_add(rows, "No active effects", "", {}, true)
		return
	for fact in effects:
		var turns := int(fact.get("turns", 0))
		_add(rows, str(fact.get("label", "")), "%d turn%s" % [turns, "" if turns == 1 else "s"], {
			"selectable": true, "title": str(fact.get("label", "")), "text": str(fact.get("text", "")),
		})


func _skillRows(rows: Array) -> void:
	_add(rows, "SPELLS", "", {}, true)
	var spells: Array = _facts.get("spells", [])
	if spells.is_empty():
		_add(rows, "None", "", {}, true)
	for spell in spells:
		var cooldown := int(spell.get("cooldown_left", 0))
		var value := "CD %d" % cooldown if cooldown > 0 else "Rng %d" % int(spell.get("range", 0))
		_add(rows, str(spell.get("name", "")), value, {
			"selectable": true, "title": str(spell.get("name", "")), "text": str(spell.get("text", "")),
		})
	_add(rows, "PASSIVES", "", {}, true)
	var passives: Array = _facts.get("passives", [])
	if passives.is_empty():
		_add(rows, "None", "", {}, true)
	for passive in passives:
		_add(rows, str(passive.get("name", "")), "", {
			"selectable": true, "title": str(passive.get("name", "")),
			"text": str(passive.get("text", "")),
		})


func _gearRows(rows: Array) -> void:
	for slot in _facts.get("equipment", []):
		_add(rows, "Slot %d" % (int(slot.get("slot", 0)) + 1), "Empty", {
			"selectable": true, "title": "Slot %d" % (int(slot.get("slot", 0)) + 1), "text": GEAR_NOTE,
		}, true)


## The HP bar and element squares are drawn over their rows. Profile never pages -- it has fewer
## rows than the smallest sheet capacity -- so page-0 row rects are the rows' real rects.
func _decorateProfile() -> void:
	var hpRect := _body.row_rect(1)
	var bar: HexHpBar = HexHpBarScript.new()
	bar.setValues(int(_facts.get("hp", 0)), int(_facts.get("max_hp", 1)))
	bar.size = Vector2(NoggThemeScript.HEX_HP_BAR_WIDTH * 1.5, NoggThemeScript.HEX_HP_BAR_HEIGHT)
	bar.position = Vector2(
		hpRect.position.x + _textWidth("HP  "),
		hpRect.position.y + floorf((hpRect.size.y - bar.size.y) / 2.0)
	)
	_bodyOverlay.add_child(bar)

	var elementRect := _body.row_rect(2)
	var elements: Array = _facts.get("elements", [])
	var x := elementRect.position.x + elementRect.size.x
	for index in range(elements.size() - 1, -1, -1):
		var square: HexElementSquare = HexElementSquareScript.new()
		square.setElement(elements[index])
		x -= square.size.x
		square.position = Vector2(
			x, elementRect.position.y + floorf((elementRect.size.y - square.size.y) / 2.0)
		)
		_bodyOverlay.add_child(square)
		x -= NoggThemeScript.HEX_PLATE_GAP


func _onRowBuilt(row: Control, fullIndex: int) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	# The rows take the mouse, so a right click on one never reaches the board handler that closes
	# the sheet; answer it here too.
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed 				and event.button_index == MOUSE_BUTTON_RIGHT:
			close()
			accept_event())
	if fullIndex >= _rowMeta.size() or not bool(_rowMeta[fullIndex].get("selectable", false)):
		return
	row.mouse_entered.connect(func():
		if _open and fullIndex != _focus:
			_setFocus(fullIndex, true))


func _onTabInput(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		setTab(index)
		accept_event()


func _stepFocus(direction: int) -> void:
	if _rowMeta.is_empty():
		return
	var index := _focus
	for _attempt in range(_rowMeta.size()):
		index = posmod(index + direction, _rowMeta.size())
		if bool(_rowMeta[index].get("selectable", false)):
			_setFocus(index, true)
			return


func _setFocus(index: int, animate: bool) -> void:
	if index < 0 or index >= _rowMeta.size() or not bool(_rowMeta[index].get("selectable", false)):
		return
	_focus = index
	var focus := _body.focus_index(index)
	_cursor.visible = true
	if animate and not bool(focus["turned"]):
		_cursor.move_to_row(focus["rect"])
	else:
		_cursor.snap_to_row(focus["rect"])
	var meta := _rowMeta[index]
	_info.showText(str(meta.get("text", "")), str(meta.get("title", "")), "", 3)


func _firstSelectable() -> int:
	for index in range(_rowMeta.size()):
		if bool(_rowMeta[index].get("selectable", false)):
			return index
	return -1


func _word(value: String) -> String:
	return "-" if value == "" or value == "none" else value.capitalize()


func _spaceWidth() -> float:
	return _textWidth(" ")


func _textWidth(text: String) -> float:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, NoggThemeScript.FONT_SIZE_BODY
	).x
