## The four command icons carried above the acting unit.
##
## Replaces the docked command window as the player's root command surface. It
## renders `PlayerTurnController.menuEntries()` and owns no rules about what a
## command means or when it is available — same contract `PlayerCommandMenu`
## already keeps, and for the same reason.
##
## **Slots are keyed by action id, not by list order.** A command's position in
## the row is fixed for the whole battle: Move, Attack, Spell, Pass, left to
## right. Laying the entries out in the order `menuEntries()` returns them
## would let a command shift because a *different* command became unavailable,
## and a surface whose whole value is "the second icon is always Attack" cannot
## afford that.
##
## **This was a diamond before, and the change cost something worth recording.**
## Four slots around the unit mapped one command to each arrow key, so a
## command was a *direction*. A horizontal row is navigated by stepping along
## it, which makes this a list again — laid out sideways, with fixed positions,
## but a list. Position memory survives; direction memory does not. The row was
## chosen for how it reads on the board, and this is the price.
##
## **Move and Undo share the first slot.** They are mutually exclusive by
## construction — `menuEntries()` marks Undo visible only when a move has
## happened and no action has, which is exactly when Move itself is spent — so
## the slot shows whichever of the two is live. Undo draws in its own colour
## (`ActionIcons`), because unlike every other slot this one changes what it
## means mid-turn, and a player who has stopped reading icons needs the change
## to catch their eye rather than to blend in.
##
## **A forbidden command dims; it never leaves.** The four slots are fixed
## positions, so hiding one would leave a hole that reads as a missing feature
## rather than as a spent phase, and would teach nothing. See
## `NoggTheme.ACTION_ROW_DISABLED_ALPHA`.
##
## **Projected, not parented into the world.** Positioning is the caller's job
## (`BattlePresentationController` runs the same `unproject_position` ->
## `RetroRenderController.world_to_screen` chain it already uses for damage
## numbers and status badges) because this widget has no access to the camera.
## The battle world renders into a SubViewport that some presets drop to
## 320x240; anything parented in there would be downsampled with it, so the row
## lives on the native-resolution game canvas and is *placed* per frame.

class_name ActionRow
extends Control

## A slot was clicked. Carries the command id rather than the slot index, so
## the listener never has to know the ring's geometry.
signal entry_activated(entry_id: String)
## The pointer moved onto a different activatable slot, or off all of them
## (-1). Focus itself is applied here; this reports it so a listener can keep
## a mirrored surface in step.
signal slot_focused(slot: int)

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const ActionIconsScript = preload("res://src/presentation/ActionIcons.gd")

## The row, left to right, and which action id each slot holds.
##
## `alt_id` is the contextual replacement described in the header: when an
## entry with that id is visible, it takes the slot instead of `id`. Only the
## first slot uses it today.
##
## Ordered to match the turn's own shape: Move spends the movement phase,
## Attack and Spell spend the action phase, and Pass ends the turn. Reading
## left to right is therefore reading the order a turn is usually played, and
## the one irreversible command sits at the far end rather than next to the
## slot the row opens focused on.
const SLOTS := [
	{"id": "move", "alt_id": "undo_move"},
	{"id": "attack", "alt_id": ""},
	{"id": "magic", "alt_id": ""},
	{"id": "pass", "alt_id": ""},
]

## Resolved slot contents, parallel to `SLOTS`. Each is either an empty
## Dictionary (nothing live in that slot) or the `menuEntries()` entry itself,
## carried whole so `enabled` and `label` stay the controller's words.
var _slots: Array = []
## Index into `SLOTS` of the focused slot, or -1.
var _focus: int = -1
## Per-slot growth toward `ACTION_ROW_FOCUS_SCALE`, tweened rather than
## snapped so focus reads as movement between slots.
var _scales: Array = []


func _init() -> void:
	# STOP, not IGNORE, so the icons are clickable -- but `_has_point()` below
	# narrows what "inside this Control" means to the four icon rects, so the
	# ring claims only those and every other pixel of its bounding box (the
	# centre where the unit stands most of all) still reaches the board.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The icons are hard-edged pixel art at exactly 1:1 with their source at the
	# shipping scale; any smoothing would undo that.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_slots.resize(SLOTS.size())
	_scales.resize(SLOTS.size())
	for index in range(SLOTS.size()):
		_slots[index] = {}
		_scales[index] = 1.0


## Fills the slots from a `menuEntries()` array. Returns whether anything
## changed, so a caller polling every frame redraws only on the frames where
## the menu actually moved — which is very few of them.
##
## An entry whose id matches no slot is dropped, with a warning: a fifth
## command is a design decision about what the ring's geometry becomes, and
## silently vanishing from the player's only command surface is the worst
## possible way to discover one was added.
func set_entries(entries: Array) -> bool:
	var built: Array = []
	built.resize(SLOTS.size())
	for index in range(SLOTS.size()):
		built[index] = {}

	for entry in entries:
		if not (entry is Dictionary):
			continue
		if not bool(entry.get("visible", true)):
			continue
		var entry_id := str(entry.get("id", ""))
		var slot := _slot_for_id(entry_id)
		if slot == -1:
			push_warning(
				"ActionRow: no slot for command '%s'; it will not be reachable." % entry_id
			)
			continue
		built[slot] = entry

	if not _slots_differ(built):
		return false
	_slots = built
	if _focus != -1 and _slots[_focus].is_empty():
		_focus = -1
	queue_redraw()
	return true


## Moves focus to a slot by index into `SLOTS`, or -1 for none. A slot holding
## nothing, or holding a command this phase forbids, refuses focus and leaves
## it where it was — the ring should not let the player rest on a command they
## cannot issue.
func set_focus_slot(slot: int) -> bool:
	if slot != -1:
		if slot < 0 or slot >= SLOTS.size():
			return false
		if not _is_activatable(slot):
			return false
	if slot == _focus:
		return false
	_focus = slot
	queue_redraw()
	return true


func focus_slot() -> int:
	return _focus


## The focused command's id, or "" when nothing is focused.
func focused_entry_id() -> String:
	if _focus == -1 or _slots[_focus].is_empty():
		return ""
	return str(_slots[_focus].get("id", ""))


## The focused command's label, or "" — what the caller draws under the ring.
func focused_label() -> String:
	if _focus == -1 or _slots[_focus].is_empty():
		return ""
	return str(_slots[_focus].get("label", ""))


## The next activatable slot `step` places along the row from the focused one,
## wrapping, or -1 when nothing can be focused at all.
##
## Skips unavailable slots rather than stopping on them: on a row the player
## navigates by stepping, so landing on a dead slot would make the same key
## press sometimes move and sometimes not. The diamond could stop dead, because
## there a direction addressed one specific slot and "nothing there" was an
## honest answer; stepping has no such excuse.
func step_slot(step: int) -> int:
	var live: Array = []
	for index in range(SLOTS.size()):
		if _is_activatable(index):
			live.append(index)
	if live.is_empty():
		return -1
	var at := live.find(_focus)
	if at == -1:
		return live[0] if step > 0 else live[live.size() - 1]
	return live[posmod(at + step, live.size())]


## The slot holding `entry_id`, or -1. Lets a caller address a command by name
## without knowing where it sits.
func slot_for_id(entry_id: String) -> int:
	return _slot_for_id(entry_id)


## The first slot that can currently be activated, or -1 when none can. Used to
## seed focus when the ring opens, so the player never starts on a dead slot.
func first_activatable_slot() -> int:
	for index in range(SLOTS.size()):
		if _is_activatable(index):
			return index
	return -1


func is_slot_activatable(slot: int) -> bool:
	return _is_activatable(slot)


## The command id held by a slot, or "" when the slot is empty.
func entry_id_at(slot: int) -> String:
	if slot < 0 or slot >= _slots.size() or _slots[slot].is_empty():
		return ""
	return str(_slots[slot].get("id", ""))


## Advances the focus growth tween. Driven by the caller's frame loop rather
## than an internal `_process`, matching `StatusBadgeRow.advance()` so every
## projected icon surface has one update path.
func advance(delta: float) -> bool:
	var changed := false
	var rate := delta / maxf(NoggThemeScript.ACTION_ROW_FOCUS_TWEEN, 0.0001)
	for index in range(_scales.size()):
		var target := (
			NoggThemeScript.ACTION_ROW_FOCUS_SCALE if index == _focus else 1.0
		)
		var current: float = _scales[index]
		if is_equal_approx(current, target):
			continue
		_scales[index] = move_toward(
			current, target, absf(NoggThemeScript.ACTION_ROW_FOCUS_SCALE - 1.0) * rate
		)
		changed = true
	if changed:
		queue_redraw()
	return changed


## Centre-to-centre distance between neighbouring slots.
func _pitch() -> float:
	return NoggThemeScript.ACTION_ROW_ICON + NoggThemeScript.ACTION_ROW_GAP


## The band the icons occupy, measured at a slot's *focused* size — the row
## must not overhang the screen edge on the frame a slot happens to be grown,
## and the end slots are exactly where that would show.
func icon_band() -> Vector2:
	var grown := NoggThemeScript.ACTION_ROW_ICON * NoggThemeScript.ACTION_ROW_FOCUS_SCALE
	return Vector2(float(SLOTS.size() - 1) * _pitch() + grown, grown)


## Height of the band under the icons that carries the focused command's name.
## `ROW_HEIGHT` is the theme's body-font line box plus air — exactly what a
## one-line label needs — so it is reused rather than re-derived from metrics.
func label_band() -> float:
	return NoggThemeScript.ACTION_ROW_LABEL_GAP + float(NoggThemeScript.ROW_HEIGHT)


## Full size of this Control: the icon band plus the label band beneath it.
##
## The label is inside these bounds deliberately. An earlier version sized the
## Control to the icons alone and drew the label past the bottom edge, which
## Godot permits — so the label rendered fine but sat outside everything that
## reasons about this widget's rectangle, and the caller's edge clamp could not
## see it. Anything drawn has to be measured.
func full_size() -> Vector2:
	var band := icon_band()
	return Vector2(band.x, band.y + label_band())


## Offset from this Control's top-left to the point it should be anchored by:
## bottom-centre, because the row hangs *above* the unit it belongs to.
##
## A diamond was centred on its unit and could use half the size. A row cannot:
## centred, its icons would sit on the unit's own sprite, which is the thing the
## player is deciding about.
func anchor_offset() -> Vector2:
	var size_now := full_size()
	return Vector2(size_now.x * 0.5, size_now.y)


## Narrows this Control's hit area to the icon rects.
##
## Without it the row would be a rectangle roughly 180px wide sitting over the
## board, swallowing clicks on several tiles including whichever ones happen to
## lie behind the gaps between icons. Only *activatable* slots take the
## pointer: a dimmed icon is a readout, and a click there should reach the tile
## behind it.
func _has_point(point: Vector2) -> bool:
	return slot_at_point(point) != -1


## The activatable slot whose icon contains `point` (this Control's own space),
## or -1. Hit-tested at the icon's resting size rather than its focused size,
## so a slot's clickable area does not breathe as the focus tween runs.
func slot_at_point(point: Vector2) -> int:
	for index in range(SLOTS.size()):
		if not _is_activatable(index):
			continue
		if _slot_rect(index, 1.0).has_point(point):
			return index
	return -1


## Where slot `index` draws, at `scale` times the resting icon size. Rounded so
## a tweening icon lands on whole device pixels rather than resampling its own
## hard edges every frame.
func _slot_rect(index: int, scale: float) -> Rect2:
	var band := icon_band()
	var drawn := NoggThemeScript.ACTION_ROW_ICON * scale
	var centre := Vector2(
		band.x * 0.5 + (float(index) - float(SLOTS.size() - 1) * 0.5) * _pitch(),
		band.y * 0.5
	)
	return Rect2((centre - Vector2(drawn, drawn) * 0.5).round(), Vector2(drawn, drawn))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := slot_at_point(event.position)
		if hovered != -1 and set_focus_slot(hovered):
			slot_focused.emit(hovered)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked := slot_at_point(event.position)
		if clicked == -1:
			return
		# Focus first, then activate: a click is also a selection, and a
		# listener reading `focused_entry_id()` from the activation handler
		# must see the slot that was actually clicked.
		if set_focus_slot(clicked):
			slot_focused.emit(clicked)
		accept_event()
		entry_activated.emit(str(_slots[clicked].get("id", "")))


func _slot_for_id(entry_id: String) -> int:
	for index in range(SLOTS.size()):
		if SLOTS[index]["id"] == entry_id or SLOTS[index]["alt_id"] == entry_id:
			return index
	return -1


func _is_activatable(slot: int) -> bool:
	if slot < 0 or slot >= _slots.size():
		return false
	var entry: Dictionary = _slots[slot]
	return not entry.is_empty() and bool(entry.get("enabled", false))


## Compares only the fields that change what is drawn. `menuEntries()` rebuilds
## its dictionaries every call, so comparing the arrays by identity would
## report a change on every single frame.
func _slots_differ(built: Array) -> bool:
	for index in range(SLOTS.size()):
		var before: Dictionary = _slots[index]
		var after: Dictionary = built[index]
		if before.is_empty() != after.is_empty():
			return true
		if before.is_empty():
			continue
		if before.get("id", "") != after.get("id", ""):
			return true
		if before.get("enabled", false) != after.get("enabled", false):
			return true
		if before.get("label", "") != after.get("label", ""):
			return true
	return false


func _draw() -> void:
	for index in range(SLOTS.size()):
		var entry: Dictionary = _slots[index]
		if entry.is_empty():
			continue
		var texture := ActionIconsScript.texture_for(str(entry.get("id", "")))
		if texture == null:
			continue
		var tint := Color.WHITE
		if not bool(entry.get("enabled", false)):
			tint.a = NoggThemeScript.ACTION_ROW_DISABLED_ALPHA
		draw_texture_rect(texture, _slot_rect(index, _scales[index]), false, tint)

	_draw_focus_label()


## The focused command's name, centred under the row.
##
## Placeholder icons are not self-explanatory, and this is the only thing that
## makes them learnable — which is also why it replaced the prompt window's
## "Choose a command." rather than joining it.
func _draw_focus_label() -> void:
	var label := focused_label()
	if label.is_empty():
		return
	var font := get_theme_font("font")
	if font == null:
		return
	var band := icon_band()
	var font_size := NoggThemeScript.FONT_SIZE_BODY
	var text_size := font.get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var baseline := (
		band.y + NoggThemeScript.ACTION_ROW_LABEL_GAP + font.get_ascent(font_size)
	)
	var origin := Vector2(band.x * 0.5 - text_size.x * 0.5, baseline).round()
	# Drawn shadow-then-text by hand rather than through a themed Label: this
	# widget draws its icons in `_draw()` already, and a child Label would need
	# its own position kept in sync with a ring whose radius scales. The shadow
	# reproduces what the game theme gives every Label — see NoggTheme's
	# "Shadow, not halo" note for why it is an offset shadow and not an outline.
	draw_string(
		font,
		origin + Vector2(NoggThemeScript.SHADOW_OFFSET, NoggThemeScript.SHADOW_OFFSET),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		NoggThemeScript.SHADOW_COLOR
	)
	draw_string(
		font,
		origin,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		NoggThemeScript.TEXT_PRIMARY
	)
