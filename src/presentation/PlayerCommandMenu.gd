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
const CONFIRM := "confirm"
const BACK_ID := "__back"
## Emitted through the existing `entry_activated` signal rather than a new one,
## so the controller keeps a single activation path for every command surface.
## Prefixed like BACK_ID to stay clear of `PlayerTurnController`'s own entry ids.
const CONFIRM_ID := "__confirm"
const CANCEL_ID := "__cancel"

# Widths owned by NoggTheme (COMMAND_WIDTH / SPELL_WIDTH / PROMPT_WIDTH /
# FORECAST_WIDTH), not redeclared here — see the "Window widths" block
# in NoggTheme.gd for how each was measured and why PROMPT_WIDTH and
# FORECAST_WIDTH specifically were corrected rather than merely re-expressed.
# A local const of a literal number could never track `NoggTheme.ui_scale`,
# which is exactly the bug this migration exists to close.

## The command list's true maximum: Move / Undo / Attack / Spell / Pass.
## It can never page, so reserving `ROW_CAPACITY_DEFAULT` (8) here just bought
## four rows of dead space — half the window — for a list that will never grow
## into it. Capacity should be a menu's real ceiling, not a shared constant.
const COMMAND_CAPACITY := 5
## The spell list *can* page, so it keeps a ceiling; but it is sized to its
## actual contents on open (see `_rebuild_spell_rows`) rather than always
## reserving the maximum.
const SPELL_MAX_CAPACITY := 8
## CONFIRM / CANCEL, and it can never be anything else.
const CONFIRM_CAPACITY := 2

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
var _confirm_window: NoggWindow
var _command_cursor: MenuCursor
var _spell_cursor: MenuCursor
var _confirm_cursor: MenuCursor

var _entries: Array = []
var _spells: Array = []
## Row metadata parallel to the rows added to each window, in display order.
## Each entry is {"id": String, "enabled": bool} plus, for spells, the
## set/spell indices needed to emit `spell_activated`.
var _root_rows: Array = []
var _spell_rows: Array = []
var _confirm_rows: Array = []
var _root_index := -1
var _spell_index := -1
var _confirm_index := -1
var _mode := ROOT
var _prompt_text := ""
## Where the prompt window attaches, instead of `self` like every other window
## here. Set by `BattleUIBuilder` via `set_prompt_layer_root()` before this
## node enters the tree, so the prompt can live on `NoggTheme.PROMPT_LAYER` —
## above the dev bar — while the rest of this menu stays on the game layer.
## `null` (the default) falls back to `self`, so a caller that never sets this
## still gets a working, merely un-elevated, prompt.
var _prompt_layer_root: Control = null


## Must be called before this node enters the tree — `_ready()` reads it once,
## synchronously, to decide the prompt window's parent.
func set_prompt_layer_root(root: Control) -> void:
	_prompt_layer_root = root


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_prompt_window = _build_window(NoggThemeScript.PROMPT_WIDTH, 1, _prompt_layer_root)
	# Readout only, same as the actor/target status windows: nothing here ever
	# connects its gui_input. Left at the default STOP filter it would now
	# intercept clicks meant for the dev bar underneath it, since it renders
	# above DEV_LAYER on PROMPT_LAYER.
	_prompt_window.set_input_transparent(true)
	# Starts closed: `_refresh_prompt()` now drives open()/close() off whether
	# there is a real message, and the Control default of visible = true would
	# otherwise open() at construction just to close() again once the first
	# (likely empty) status arrives.
	_prompt_window.visible = false
	_forecast_window = _build_window(NoggThemeScript.FORECAST_WIDTH, 2)
	_forecast_window.visible = false
	_command_window = _build_window(NoggThemeScript.COMMAND_WIDTH, COMMAND_CAPACITY)
	_spell_window = _build_window(NoggThemeScript.SPELL_WIDTH, SPELL_MAX_CAPACITY)
	_spell_window.visible = false
	# Same width as the command window, and docked on top of it, so the cursor
	# does not travel when the phase changes (§5: the cursor snaps between
	# windows, it does not fly).
	_confirm_window = _build_window(NoggThemeScript.COMMAND_WIDTH, CONFIRM_CAPACITY)
	_confirm_window.visible = false
	# Only the cursor-driven windows reserve the gutter. The prompt and
	# forecast have no cursor, so indenting them would just look misaligned.
	_command_window.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)
	_spell_window.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)
	_confirm_window.set_content_indent(NoggThemeScript.CURSOR_GUTTER_WIDTH)

	_command_cursor = _build_cursor(_command_window)
	_spell_cursor = _build_cursor(_spell_window)
	_spell_cursor.set_visible_cursor(false)
	_confirm_cursor = _build_cursor(_confirm_window)
	_confirm_cursor.set_visible_cursor(false)

	_command_window.gui_input.connect(_on_window_gui_input.bind(ROOT))
	_spell_window.gui_input.connect(_on_window_gui_input.bind(SPELLS))
	_confirm_window.gui_input.connect(_on_window_gui_input.bind(CONFIRM))
	# Row construction lives inside NoggWindow for paging; it reports
	# each built Control back so wiring can still happen here, per row, exactly
	# as it did when this file built rows itself.
	_command_window.row_built.connect(_on_root_row_built)
	_spell_window.row_built.connect(_on_spell_row_built)
	_confirm_window.row_built.connect(_on_confirm_row_built)
	# Only the spell window can ever page (the command list's true maximum is
	# 5, under COMMAND_CAPACITY), but wiring both costs nothing and needs no
	# special-casing later if that ever changes.
	_command_window.page_arrow_pressed.connect(func(direction): pageSpells(direction))
	_spell_window.page_arrow_pressed.connect(func(direction): pageSpells(direction))

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
	# Unconditional rather than gated on `_mode == CONFIRM`: this and
	# `showPromptOnly()` are the two ways any phase other than confirm reaches
	# the screen, so hiding the confirm window in both makes it impossible to
	# strand one on a path nobody anticipated — a rejected action, a turn
	# ending early, or a phase transition added later.
	_hide_confirm_window()
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
	_hide_confirm_window()
	_command_window.visible = false
	_spell_window.visible = false
	_command_cursor.set_visible_cursor(false)
	_spell_cursor.set_visible_cursor(false)
	_refresh_prompt()


## Hides instantly rather than through `NoggWindow.close()`, unlike the spell
## column. Every caller is a phase transition that immediately shows a
## different window at this same origin, and cross-fading two windows over one
## another there reads as a smear; `close()`'s await would also let a stale
## hide land after the next phase had already opened. `open()` resets alpha and
## scale on the way back in, so an interrupted open self-heals.
func _hide_confirm_window() -> void:
	_confirm_window.visible = false
	_confirm_cursor.set_visible_cursor(false)


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


## The confirm phase's own surface. Unlike `openSpells()`, which leaves its
## parent on screen and dimmed, this *hides* the command and spell windows:
## confirm replaces the command list rather than descending from it, so leaving
## a dimmed parent behind would imply a hierarchy that is not there.
func openConfirm() -> void:
	if _mode == CONFIRM:
		return
	_mode = CONFIRM
	_command_window.visible = false
	_command_cursor.set_visible_cursor(false)
	_spell_window.visible = false
	_spell_cursor.set_visible_cursor(false)
	_rebuild_confirm_rows()
	_confirm_window.open()
	_confirm_cursor.set_visible_cursor(true)
	# Snap, never tween: the cursor does not fly between windows (§5).
	_select(_first_selectable(_confirm_rows), false)
	_refresh_prompt()


## Restores the command window exactly as the player left it. Deliberately no
## rebuild of its rows and no cursor move — its content did not change while
## the confirm window was up.
func closeConfirm() -> bool:
	if _mode != CONFIRM:
		return false
	_mode = ROOT
	_hide_confirm_window()
	_command_window.visible = true
	_command_window.set_active(true)
	_command_cursor.set_visible_cursor(true)
	_refresh_prompt()
	return true


func isShowingConfirm() -> bool:
	return _mode == CONFIRM


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


## Id of the row the confirm cursor is on: CONFIRM_ID, CANCEL_ID, or "".
func selectedConfirmId() -> String:
	return _id_at(_confirm_rows, _confirm_index)


## Selection-only path. Must not rebuild rows — see the note at the top.
func moveSelection(direction: int) -> void:
	var rows := _rows_for_mode()
	var selectable := _selectable_indices(rows)
	if selectable.is_empty():
		return
	var current := _index_for_mode()
	var at := selectable.find(current)
	at = 0 if at < 0 else posmod(at + direction, selectable.size())
	_select(selectable[at], true)


func acceptSelection() -> void:
	match _mode:
		SPELLS: _activate_spell_row(_spell_index)
		CONFIRM: _activate_confirm_row(_confirm_index)
		_: _activate_root_row(_root_index)


## The three cursor-driven surfaces differ only in which arrays they read, so
## every shared path (movement, selection, hover, click, wheel) goes through
## these rather than branching on `_mode` at each site.
func _rows_for_mode() -> Array:
	match _mode:
		SPELLS: return _spell_rows
		CONFIRM: return _confirm_rows
		_: return _root_rows


func _index_for_mode() -> int:
	match _mode:
		SPELLS: return _spell_index
		CONFIRM: return _confirm_index
		_: return _root_index


## Explicit page navigation (§7a, item 4): ui_left/ui_right and the footer's
## arrow buttons both call this, direction -1 or +1. Distinct from a cursor
## crossing a page boundary during moveSelection() — that case already lands
## on the correct row via the ordinary selectable-index cycle over the full
## list, and window.focus_index() turns the page as a side effect; this is an
## unconditional "show me the next/previous page" request with no target row
## in mind yet, so it picks one: the first enabled row on the page it lands on.
func pageSpells(direction: int) -> void:
	if _mode != SPELLS or _spell_window.page_count() <= 1:
		return
	if direction > 0:
		_spell_window.next_page()
	else:
		_spell_window.prev_page()
	var start := _spell_window.page_start_index(_spell_window.page())
	var end := _spell_window.page_end_index(_spell_window.page())
	var landing := start
	for i in range(start, end):
		if _spell_rows[i]["enabled"]:
			landing = i
			break
	_spell_index = landing
	# The window is already on the right page (next_page()/prev_page() above),
	# so focus_index() here only positions the cursor and the marquee — it does
	# not turn a page a second time.
	var focus: Dictionary = _spell_window.focus_index(landing)
	_spell_cursor.snap_to_row(focus["rect"])


# --- rows -------------------------------------------------------------------

func _rebuild_root_rows() -> void:
	var preserved := _id_at(_root_rows, _root_index)
	_root_rows.clear()
	var descriptors: Array = []
	for entry in _entries:
		if not entry["visible"]:
			continue
		var enabled := bool(entry["enabled"])
		descriptors.append({
			"label": _display(str(entry["label"])), "value": "", "disabled": not enabled
		})
		_root_rows.append({"id": str(entry["id"]), "enabled": enabled})
	# _root_rows must be complete before set_full_rows() renders — it fires
	# row_built synchronously per row, and _on_root_row_built reads _root_rows
	# by the same index.
	_command_window.set_full_rows(descriptors)
	# Restore the player's selection by id where the row survived the rebuild;
	# snap rather than tween, because this is a content change, not a move.
	var restored := _index_of_id(_root_rows, preserved)
	if restored == -1 or not _root_rows[restored]["enabled"]:
		restored = _first_selectable(_root_rows)
	_root_index = restored
	_select(restored, false)


func _rebuild_spell_rows() -> void:
	_spell_rows.clear()
	var descriptors: Array = []
	for spell in _spells:
		var ready := bool(spell["ready"])
		descriptors.append({
			"label": str(spell["name"]), "value": _spell_value(spell), "disabled": not ready
		})
		_spell_rows.append({
			"id": _spell_id(spell),
			"enabled": ready,
			"set_index": int(spell["set_index"]),
			"spell_index": int(spell["spell_index"])
		})
	descriptors.append({"label": _display("< Back"), "value": "", "disabled": false})
	_spell_rows.append({"id": BACK_ID, "enabled": true})

	# Size to content, capped at the page size: a 1-spell monster should not
	# get an 8-row window with seven empty rows, and a monster with more spells
	# than fit gets exactly one page's worth per screen. Capacity must
	# be set before set_full_rows(), which computes page_count from it — and
	# held for the lifetime of the opening: paging must never resize a window
	# mid-navigation, but sizing it as it appears is free.
	_spell_window.set_row_capacity(clampi(descriptors.size(), 1, SPELL_MAX_CAPACITY))
	_spell_window.set_full_rows(descriptors)


func _rebuild_confirm_rows() -> void:
	_confirm_rows.clear()
	var descriptors: Array = []
	for row in [
		{"id": CONFIRM_ID, "label": "Confirm"},
		{"id": CANCEL_ID, "label": "Cancel"}
	]:
		descriptors.append({
			"label": _display(str(row["label"])), "value": "", "disabled": false
		})
		_confirm_rows.append({"id": str(row["id"]), "enabled": true})
	_confirm_window.set_full_rows(descriptors)


func _on_root_row_built(row: Control, full_index: int) -> void:
	_wire_row(row, ROOT, full_index, bool(_root_rows[full_index]["enabled"]))


func _on_confirm_row_built(row: Control, full_index: int) -> void:
	_wire_row(row, CONFIRM, full_index, bool(_confirm_rows[full_index]["enabled"]))


func _on_spell_row_built(row: Control, full_index: int) -> void:
	_wire_row(row, SPELLS, full_index, bool(_spell_rows[full_index]["enabled"]))


## Cooldown is shown rather than hidden so the player can see what is coming
## back. Range only matters for a spell that can actually be cast now.
## `self_targeted` (not `range == 0`) picks the `Self` label — see the comment
## where `spellEntries()` sets that key.
func _spell_value(spell: Dictionary) -> String:
	if not bool(spell["ready"]):
		return "CD %d" % int(spell["cooldown_remaining"])
	if bool(spell.get("self_targeted", false)):
		return "Self"
	return "Rng %d" % int(spell["range"])


func _spell_id(spell: Dictionary) -> String:
	return "spell:%d:%d" % [int(spell["set_index"]), int(spell["spell_index"])]


# --- selection --------------------------------------------------------------

## The single place cursor position is written. `animate` distinguishes a
## selection move (tween) from a content rebuild or a window handover (snap).
##
## `index` is always a FULL-LIST index, spanning every page — window.focus_index()
## is what turns the page if `index` is not on the one currently shown, and
## reports that back so a page turn always snaps rather than tweens (§7a, item
## 3: "tweening across a page turn reads as a glitch"), even when the caller
## asked to animate.
func _select(index: int, animate: bool) -> void:
	if index < 0:
		return
	var window := _command_window
	var cursor := _command_cursor
	match _mode:
		SPELLS:
			window = _spell_window
			cursor = _spell_cursor
			_spell_index = index
		CONFIRM:
			window = _confirm_window
			cursor = _confirm_cursor
			_confirm_index = index
		_:
			_root_index = index
	# §7b: the row under the cursor marquees if its label overflows. Every
	# selection change goes through here (via focus_index()), so this is the
	# one place that needs to know about it.
	var focus: Dictionary = window.focus_index(index)
	if animate and not focus["turned"]:
		cursor.move_to_row(focus["rect"])
	else:
		cursor.snap_to_row(focus["rect"])


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


func _activate_confirm_row(index: int) -> void:
	if index < 0 or index >= _confirm_rows.size():
		return
	# Both rows are always enabled, and both leave the phase, so the controller
	# — not this node — decides what confirming or cancelling means.
	entry_activated.emit(str(_confirm_rows[index]["id"]))


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
			# Same dispatch as acceptSelection()'s, so a click and a keypress on
			# the same row can never mean two different things.
			match _mode:
				SPELLS: _activate_spell_row(index)
				CONFIRM: _activate_confirm_row(index)
				_: _activate_root_row(index)
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

## `parent` overrides where the window attaches; only the prompt window uses
## this (see `_prompt_layer_root`) — every other window keeps parenting under
## `self`, which is what passing `null` reproduces.
func _build_window(width: float, capacity: int, parent: Control = null) -> NoggWindow:
	var window := NoggWindowScript.new()
	(parent if parent != null else self).add_child(window)
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
		left + NoggThemeScript.COMMAND_WIDTH + NoggThemeScript.WINDOW_STACK_GAP, command_y
	)
	# Directly on top of the command window's own origin, not beside it: the
	# confirm window replaces the command list, so the cursor stays exactly
	# where the player last saw it instead of travelling across the screen.
	_confirm_window.position = Vector2(left, command_y)

	# Directly above the command window and left-aligned with it. §8 asks for
	# right-aligned, which cannot hold at this font size: the forecast needs
	# ~460px and the command window's right edge is at x=300, so right-aligning
	# would push it off the left of the screen. Recorded in the design notes.
	var forecast_height := NoggThemeScript.window_height(2)
	_forecast_window.position = Vector2(
		left, command_y - forecast_height - NoggThemeScript.FORECAST_GAP
	)

	_prompt_window.position = Vector2(
		floorf((screen.x - NoggThemeScript.PROMPT_WIDTH) * 0.5),
		NoggThemeScript.PROMPT_TOP
	)


## Audit finding: "Choose a command." said nothing the open command window
## did not already say, and a 940px bar saying nothing was the third-largest
## permanently-drawn element in the HUD. `PlayerTurnController._menuStatusText()`
## now returns "" for that baseline case, so this mostly closes rather than
## showing filler — matching the open()/close() treatment
## `BattlePresentationController._renderStatusWindow()` already gives the
## actor/target windows, for the same reason: nothing else reflows off this
## window's visibility, so there is no layout cost to hiding it, only a
## legibility gain.
func _refresh_prompt() -> void:
	_prompt_window.clear_rows()
	if _prompt_text.is_empty():
		if _prompt_window.visible:
			_prompt_window.close()
		return
	if not _prompt_window.visible:
		_prompt_window.open()
	_prompt_window.add_row(_prompt_text)


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
