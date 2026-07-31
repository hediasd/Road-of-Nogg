## Player command surface: stacked sibling `NoggWindow`s driven by a gutter
## `MenuCursor`. See docs/UI_DESIGN.md §5 (the cursor), §6 (the input model),
## and §8 (window taxonomy).
##
## **The rule this file exists to enforce (§5):** content changes rebuild rows,
## selection changes move the cursor, and neither path calls the other. The
## previous implementation encoded selection in each row's *text*
## (`("› " if selected else "  ") + label`), so every arrow keypress ran a full
## `queue_free()`-and-rebuild of every row. Nothing could be animated across
## that, which is why the cursor could not exist until this was untangled.
##
## Selection state therefore lives in `_root_index` / `_spell_index` — indices
## into the row-metadata arrays — and the cursor's position is derived from
## them. `moveSelection()` must never call a `_rebuild_*` function.
##
## This node renders the controller's data-only menu models and owns no rules
## about what a command means; `PlayerTurnController` still owns all of that.

class_name PlayerCommandMenu
extends Control

signal entry_activated(entry_id: String)
signal spell_activated(set_index: int, spell_index: int)

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const MenuCursorScript = preload("res://src/presentation/theme/MenuCursor.gd")

const ROOT := "root"
const SPELLS := "spells"
const BACK_ID := "__back"

# Widths from docs/UI_DESIGN.md §8 — measured against the shipping font at
# size 24, not chosen. Do not tune without rerunning debug/preview_theme.gd.
## Sized to the longest command label plus the cursor gutter. With `Undo Move`
## shortened to `Undo`, the longest is now `ATTACK` at 144 + 56 overhead = 200,
## so 220 leaves comfortable slack. Dropping the long label is what let this
## come down from 300. A typical spell row needs 644 of 680.
const COMMAND_WIDTH := 220.0
const SPELL_WIDTH := 680.0
const PROMPT_WIDTH := 620.0
const FORECAST_WIDTH := 460.0

## The command list's true maximum: Move / Undo / Attack / Spell / Pass.
## It can never page, so reserving `ROW_CAPACITY_DEFAULT` (8) here just bought
## four rows of dead space — half the window — for a list that will never grow
## into it. Capacity should be a menu's real ceiling, not a shared constant.
const COMMAND_CAPACITY := 5
## The spell list *can* page, so it keeps a ceiling; but it is sized to its
## actual contents on open (see `_rebuild_spell_rows`) rather than always
## reserving the maximum.
const SPELL_MAX_CAPACITY := 8

## Uppercase is applied to command labels at render time, never to the model.
## `PlayerTurnController.menuEntries()` keeps returning "Undo" — that
## string is also what logs and harness output read, and the id layer is
## case-sensitive. Flip this to false to revert the look in one line.
const UPPERCASE_COMMANDS := true

# The cursor's resting x and the row indent that keeps clear of it both come
# from NoggTheme (CURSOR_INSET / CURSOR_GUTTER_WIDTH) so the two cannot drift.

var _prompt_window: NoggWindow
var _forecast_window: NoggWindow
var _command_window: NoggWindow
var _spell_window: NoggWindow
var _command_cursor: MenuCursor
var _spell_cursor: MenuCursor

var _entries: Array = []
var _spells: Array = []
## Row metadata parallel to the rows added to each window, in display order.
## Each entry is {"id": String, "enabled": bool} plus, for spells, the
## set/spell indices needed to emit `spell_activated`.
var _root_rows: Array = []
var _spell_rows: Array = []
var _root_index := -1
var _spell_index := -1
var _mode := ROOT
var _prompt_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_prompt_window = _build_window(PROMPT_WIDTH, 1)
	_forecast_window = _build_window(FORECAST_WIDTH, 2)
	_forecast_window.visible = false
	_command_window = _build_window(COMMAND_WIDTH, COMMAND_CAPACITY)
	_spell_window = _build_window(SPELL_WIDTH, SPELL_MAX_CAPACITY)
	_spell_window.visible = false
	# Only the two cursor-driven windows reserve the gutter. The prompt and
	# forecast have no cursor, so indenting them would just look misaligned.
	_command_window.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)
	_spell_window.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)

	_command_cursor = _build_cursor(_command_window)
	_spell_cursor = _build_cursor(_spell_window)
	_spell_cursor.set_visible_cursor(false)

	_command_window.gui_input.connect(_on_window_gui_input.bind(ROOT))
	_spell_window.gui_input.connect(_on_window_gui_input.bind(SPELLS))

	resized.connect(_layout_windows)
	_layout_windows()
	_rebuild_root_rows()


# --- public API (unchanged shape; BattlePresentationController calls these) --

func setStatus(text: String) -> void:
	_prompt_text = text
	_refresh_prompt()


func setForecast(text: String) -> void:
	_forecast_window.clear_rows()
	if text.is_empty():
		_forecast_window.visible = false
		return
	# The forecast is two short lines at most; split on newline so each is its
	# own row rather than one wrapped label (trait 4 forbids wrapping).
	for line in text.split("\n", false):
		var row := _forecast_window.add_row(line)
		_tint_row_label(row, NoggThemeScript.TEXT_FORECAST)
	_forecast_window.visible = true


func showRoot(entries: Array) -> void:
	_mode = ROOT
	_entries = entries.duplicate(true)
	_command_window.visible = true
	_command_cursor.set_visible_cursor(true)
	_command_window.set_active(true)
	_rebuild_root_rows()
	_refresh_prompt()


## Phase left the menu (a destination or target is being aimed). The windows
## go away but the prompt stays, because the prompt is what tells the player
## what they are aiming at.
func showPromptOnly() -> void:
	_mode = ROOT
	_command_window.visible = false
	_spell_window.visible = false
	_command_cursor.set_visible_cursor(false)
	_spell_cursor.set_visible_cursor(false)
	_refresh_prompt()


func openSpells(spells: Array) -> void:
	_mode = SPELLS
	_spells = spells.duplicate(true)
	_rebuild_spell_rows()
	# The parent stays on screen, dimmed — it does not hide, move, or resize.
	_command_window.set_active(false)
	_command_cursor.set_visible_cursor(false)
	_spell_window.open()
	_spell_cursor.set_visible_cursor(true)
	# Snap, never tween: the cursor does not fly between windows (§5).
	_select(_first_selectable(_spell_rows), false)
	_refresh_prompt()


func closeSpells() -> bool:
	if _mode != SPELLS:
		return false
	_mode = ROOT
	_spell_cursor.set_visible_cursor(false)
	_spell_window.close()
	_command_window.set_active(true)
	_command_cursor.set_visible_cursor(true)
	# Deliberately no rebuild and no cursor move: the command window's content
	# did not change, so its selection is exactly where the player left it.
	_refresh_prompt()
	return true


func isShowingSpells() -> bool:
	return _mode == SPELLS


# --- read-only selection observation ---------------------------------------
#
# Exists so harnesses (debug/drive_battle.gd) can assert on what is selected
# without reaching into private state. Selection used to be a `_root_selected_id`
# String that a harness could read directly; it is now a cursor index, and
# these keep that observability without re-exposing the representation.

## Id of the row the command cursor is on, or "" when nothing is selectable.
func selectedEntryId() -> String:
	return _id_at(_root_rows, _root_index)


## Ids of the enabled command rows, in display order. Disabled rows are
## excluded because keyboard movement skips them.
func selectableEntryIds() -> Array:
	var ids: Array = []
	for row in _root_rows:
		if row["enabled"]:
			ids.append(str(row["id"]))
	return ids


## Id of the row the spell cursor is on: "spell:<set>:<index>", BACK_ID, or "".
func selectedSpellId() -> String:
	return _id_at(_spell_rows, _spell_index)


## Selection-only path. Must not rebuild rows — see the note at the top.
func moveSelection(direction: int) -> void:
	var rows := _spell_rows if _mode == SPELLS else _root_rows
	var selectable := _selectable_indices(rows)
	if selectable.is_empty():
		return
	var current := _spell_index if _mode == SPELLS else _root_index
	var at := selectable.find(current)
	at = 0 if at < 0 else posmod(at + direction, selectable.size())
	_select(selectable[at], true)


func acceptSelection() -> void:
	if _mode == SPELLS:
		_activate_spell_row(_spell_index)
	else:
		_activate_root_row(_root_index)


# --- rows -------------------------------------------------------------------

func _rebuild_root_rows() -> void:
	var preserved := _id_at(_root_rows, _root_index)
	_command_window.clear_rows()
	_root_rows.clear()
	for entry in _entries:
		if not entry["visible"]:
			continue
		var enabled := bool(entry["enabled"])
		var row := _command_window.add_row(_display(str(entry["label"])), "", not enabled)
		_root_rows.append({"id": str(entry["id"]), "enabled": enabled})
		_wire_row(row, ROOT, _root_rows.size() - 1, enabled)
	# Restore the player's selection by id where the row survived the rebuild;
	# snap rather than tween, because this is a content change, not a move.
	var restored := _index_of_id(_root_rows, preserved)
	if restored == -1 or not _root_rows[restored]["enabled"]:
		restored = _first_selectable(_root_rows)
	_root_index = restored
	_select(restored, false)


func _rebuild_spell_rows() -> void:
	_spell_window.clear_rows()
	_spell_rows.clear()
	# Size to content, capped at the page size: a 1-spell monster should not
	# get an 8-row window with seven empty rows. Sized here, on open, and then
	# held for the lifetime of the opening — paging must never resize a window
	# mid-navigation, but sizing it as it appears is free.
	_spell_window.set_row_capacity(
		clampi(_spells.size() + 1, 1, SPELL_MAX_CAPACITY)
	)
	for spell in _spells:
		var ready := bool(spell["ready"])
		var row := _spell_window.add_row(
			str(spell["name"]), _spell_value(spell), not ready
		)
		_spell_rows.append({
			"id": _spell_id(spell),
			"enabled": ready,
			"set_index": int(spell["set_index"]),
			"spell_index": int(spell["spell_index"])
		})
		_wire_row(row, SPELLS, _spell_rows.size() - 1, ready)
	var back := _spell_window.add_row(_display("< Back"))
	_spell_rows.append({"id": BACK_ID, "enabled": true})
	_wire_row(back, SPELLS, _spell_rows.size() - 1, true)


## Cooldown is shown rather than hidden so the player can see what is coming
## back. Range only matters for a spell that can actually be cast now.
func _spell_value(spell: Dictionary) -> String:
	if bool(spell["ready"]):
		return "Rng %d" % int(spell["range"])
	return "CD %d" % int(spell["cooldown_remaining"])


func _spell_id(spell: Dictionary) -> String:
	return "spell:%d:%d" % [int(spell["set_index"]), int(spell["spell_index"])]


# --- selection --------------------------------------------------------------

## The single place cursor position is written. `animate` distinguishes a
## selection move (tween) from a content rebuild or a window handover (snap).
func _select(index: int, animate: bool) -> void:
	if index < 0:
		return
	var window := _spell_window if _mode == SPELLS else _command_window
	var cursor := _spell_cursor if _mode == SPELLS else _command_cursor
	if _mode == SPELLS:
		_spell_index = index
	else:
		_root_index = index
	if animate:
		cursor.move_to_row(window.row_rect(index))
	else:
		cursor.snap_to_row(window.row_rect(index))


func _selectable_indices(rows: Array) -> Array:
	var out: Array = []
	for i in rows.size():
		if rows[i]["enabled"]:
			out.append(i)
	return out


func _first_selectable(rows: Array) -> int:
	for i in rows.size():
		if rows[i]["enabled"]:
			return i
	return -1


func _index_of_id(rows: Array, id: String) -> int:
	if id.is_empty():
		return -1
	for i in rows.size():
		if rows[i]["id"] == id:
			return i
	return -1


func _id_at(rows: Array, index: int) -> String:
	if index < 0 or index >= rows.size():
		return ""
	return str(rows[index]["id"])


# --- activation -------------------------------------------------------------

func _activate_root_row(index: int) -> void:
	if index < 0 or index >= _root_rows.size():
		return
	if not _root_rows[index]["enabled"]:
		return
	entry_activated.emit(str(_root_rows[index]["id"]))


func _activate_spell_row(index: int) -> void:
	if index < 0 or index >= _spell_rows.size():
		return
	var row: Dictionary = _spell_rows[index]
	if row["id"] == BACK_ID:
		closeSpells()
		return
	if not row["enabled"]:
		return
	spell_activated.emit(int(row["set_index"]), int(row["spell_index"]))


# --- mouse (§6) -------------------------------------------------------------
#
# The cursor position is the only selection truth, so hover *moves the cursor*
# rather than previewing a second highlight. That is what keeps mouse and
# keyboard from ever disagreeing about what is selected.

func _wire_row(row: Control, which: String, index: int, enabled: bool) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if not enabled:
		# Disabled rows stay visible and dim, but are inert to hover and click.
		# They still consume the event so a click does not fall through to the
		# battle grid underneath.
		return
	row.mouse_entered.connect(_on_row_hover.bind(which, index))
	row.gui_input.connect(_on_row_gui_input.bind(which, index))


func _on_row_hover(which: String, index: int) -> void:
	if which != _mode:
		return
	_select(index, true)


func _on_row_gui_input(event: InputEvent, which: String, index: int) -> void:
	if which != _mode or not (event is InputEventMouseButton) or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_select(index, true)
			if _mode == SPELLS:
				_activate_spell_row(index)
			else:
				_activate_root_row(index)
			accept_event()
		MOUSE_BUTTON_WHEEL_UP:
			moveSelection(-1)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			moveSelection(1)
			accept_event()


## Wheel over the window's empty area, below the last row. Rows handle the
## wheel themselves; this covers the rest of a fixed-capacity window, which is
## mostly empty whenever the list is shorter than its capacity.
func _on_window_gui_input(event: InputEvent, which: String) -> void:
	if which != _mode or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		moveSelection(-1)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		moveSelection(1)
		accept_event()


# --- construction and layout ------------------------------------------------

func _build_window(width: float, capacity: int) -> NoggWindow:
	var window := NoggWindowScript.new()
	add_child(window)
	window.set_row_capacity(capacity)
	window.size = Vector2(width, NoggThemeScript.window_height(capacity))
	return window


func _build_cursor(window: NoggWindow) -> MenuCursor:
	var cursor := MenuCursorScript.new()
	# Set before add_child(): MenuCursor's idle bob starts in _ready() and
	# captures position.x as its centre, so a later assignment would be
	# dragged back — see the contract note at the top of MenuCursor.gd.
	cursor.position.x = NoggThemeScript.CURSOR_INSET
	window.add_child(cursor)
	return cursor


## Docks per §8. The command and spell windows are siblings, not parent and
## child: the spell window opens to the *right* of the command window, and the
## command window neither moves nor resizes when it does.
func _layout_windows() -> void:
	var screen := size
	if screen.x <= 0.0:
		screen = get_viewport_rect().size

	var command_height := NoggThemeScript.window_height(COMMAND_CAPACITY)
	var command_y := floorf((screen.y - command_height) * 0.5)
	var left := 20.0

	_command_window.position = Vector2(left, command_y)
	_spell_window.position = Vector2(
		left + COMMAND_WIDTH + NoggThemeScript.WINDOW_STACK_GAP, command_y
	)

	# Directly above the command window and left-aligned with it. §8 asks for
	# right-aligned, which cannot hold at this font size: the forecast needs
	# ~460px and the command window's right edge is at x=300, so right-aligning
	# would push it off the left of the screen. Recorded in the UI-5 notes.
	var forecast_height := NoggThemeScript.window_height(2)
	_forecast_window.position = Vector2(left, command_y - forecast_height - 8.0)

	_prompt_window.position = Vector2(
		floorf((screen.x - PROMPT_WIDTH) * 0.5), 24.0
	)


func _refresh_prompt() -> void:
	_prompt_window.clear_rows()
	if _prompt_text.is_empty():
		_prompt_window.visible = false
		return
	_prompt_window.add_row(_prompt_text)
	_prompt_window.visible = true


## Command labels and menu chrome render in caps; proper nouns do not. Spell
## and monster names stay mixed-case because all-caps strips the word-shape
## cues that make an unfamiliar name scannable, and they are the strings most
## likely to be long and truncated. The font is monospace, so this costs
## nothing in width either way — measured 2026-07-31, every command label is
## byte-for-byte the same pixel width in both cases.
func _display(text: String) -> String:
	return text.to_upper() if UPPERCASE_COMMANDS else text


func _tint_row_label(row: Control, colour: Color) -> void:
	for child in row.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", colour)
			return
