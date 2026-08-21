## The four command icons carried around the acting unit.
##
## Replaces the docked command window as the player's root command surface. It
## renders `PlayerTurnController.menuEntries()` and owns no rules about what a
## command means or when it is available — same contract `PlayerCommandMenu`
## already keeps, and for the same reason.
##
## **Slots are keyed by action id, not by list order.** A command's position on
## the ring is fixed for the whole battle: Move north, Attack east, Pass south,
## Spell west. Laying the entries out in the order `menuEntries()` returns them
## would let a command move because a *different* command became unavailable —
## the exact failure a four-direction control cannot absorb, since the player's
## hand is already committed to a direction before the icon is read. Fixed
## slots are also what make the ring worth having over a list: after a few
## turns "attack" is a direction, not a menu lookup.
##
## **Move and Undo share the north slot.** They are mutually exclusive by
## construction — `menuEntries()` marks Undo visible only when a move has
## happened and no action has, which is exactly when Move itself is spent — so
## the slot shows whichever of the two is live. This is what keeps the ring at
## four directions while preserving the undo safety net that movement's lack of
## a confirm step depends on.
##
## **A forbidden command dims; it never leaves.** The four slots are fixed
## positions, so hiding one would leave a hole that reads as a missing feature
## rather than as a spent phase, and would teach nothing. See
## `NoggTheme.ACTION_RING_DISABLED_ALPHA`.
##
## **Projected, not parented into the world.** Positioning is the caller's job
## (`BattlePresentationController` runs the same `unproject_position` ->
## `RetroRenderController.world_to_screen` chain it already uses for damage
## numbers and status badges) because this widget has no access to the camera.
## The battle world renders into a SubViewport that some presets drop to
## 320x240; anything parented in there would be downsampled with it, so the
## ring lives on the native-resolution game canvas and is *placed* per frame.

class_name ActionRing
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const ActionIconsScript = preload("res://src/presentation/ActionIcons.gd")

## Screen-space slot directions, and which action id each holds.
##
## `alt_id` is the contextual replacement described in the header: when an
## entry with that id is visible, it takes the slot instead of `id`. Only the
## north slot uses it today.
##
## Order is north, east, south, west — the order `_slot_for_direction()`
## indexes with, so an input layer can map an arrow key to a slot without
## restating the geometry.
const SLOTS := [
	{"id": "move", "alt_id": "undo_move", "direction": Vector2(0.0, -1.0)},
	{"id": "attack", "alt_id": "", "direction": Vector2(1.0, 0.0)},
	{"id": "pass", "alt_id": "", "direction": Vector2(0.0, 1.0)},
	{"id": "magic", "alt_id": "", "direction": Vector2(-1.0, 0.0)},
]

## Resolved slot contents, parallel to `SLOTS`. Each is either an empty
## Dictionary (nothing live in that slot) or the `menuEntries()` entry itself,
## carried whole so `enabled` and `label` stay the controller's words.
var _slots: Array = []
## Index into `SLOTS` of the focused slot, or -1.
var _focus: int = -1
## Per-slot growth toward `ACTION_RING_FOCUS_SCALE`, tweened rather than
## snapped so focus reads as movement between slots.
var _scales: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
				"ActionRing: no slot for command '%s'; it will not be reachable." % entry_id
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


## The slot lying in `direction` (any of the four unit vectors in `SLOTS`), or
## -1. Lets an input layer turn an arrow key into a slot without duplicating
## the geometry this file owns.
func slot_for_direction(direction: Vector2) -> int:
	for index in range(SLOTS.size()):
		if SLOTS[index]["direction"].is_equal_approx(direction):
			return index
	return -1


## The first slot that can currently be activated, or -1 when none can. Used to
## seed focus when the ring opens, so the player never starts on a dead slot.
func first_activatable_slot() -> int:
	for index in range(SLOTS.size()):
		if _is_activatable(index):
			return index
	return -1


func is_slot_activatable(slot: int) -> bool:
	return _is_activatable(slot)


## Advances the focus growth tween. Driven by the caller's frame loop rather
## than an internal `_process`, matching `StatusBadgeRow.advance()` so every
## projected icon surface has one update path.
func advance(delta: float) -> bool:
	var changed := false
	var rate := delta / maxf(NoggThemeScript.ACTION_RING_FOCUS_TWEEN, 0.0001)
	for index in range(_scales.size()):
		var target := (
			NoggThemeScript.ACTION_RING_FOCUS_SCALE if index == _focus else 1.0
		)
		var current: float = _scales[index]
		if is_equal_approx(current, target):
			continue
		_scales[index] = move_toward(
			current, target, absf(NoggThemeScript.ACTION_RING_FOCUS_SCALE - 1.0) * rate
		)
		changed = true
	if changed:
		queue_redraw()
	return changed


## Total extent, so the caller can clamp the ring inside the display rect
## without knowing its internals. Square, and measured from the widest slot
## icon at its focused size — the ring must not overhang the screen edge on the
## frame a slot happens to be grown.
func extent() -> float:
	var grown := NoggThemeScript.ACTION_RING_ICON * NoggThemeScript.ACTION_RING_FOCUS_SCALE
	return NoggThemeScript.ACTION_RING_RADIUS * 2.0 + grown


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
	var centre := size * 0.5
	for index in range(SLOTS.size()):
		var entry: Dictionary = _slots[index]
		if entry.is_empty():
			continue
		var texture := ActionIconsScript.texture_for(str(entry.get("id", "")))
		if texture == null:
			continue
		var scale: float = _scales[index]
		var drawn := NoggThemeScript.ACTION_RING_ICON * scale
		var slot_centre: Vector2 = (
			centre + SLOTS[index]["direction"] * NoggThemeScript.ACTION_RING_RADIUS
		)
		# Rounded so a tweening icon lands on whole device pixels rather than
		# resampling its own hard edges every frame.
		var rect := Rect2(
			(slot_centre - Vector2(drawn, drawn) * 0.5).round(), Vector2(drawn, drawn)
		)
		var tint := Color.WHITE
		if not bool(entry.get("enabled", false)):
			tint.a = NoggThemeScript.ACTION_RING_DISABLED_ALPHA
		draw_texture_rect(texture, rect, false, tint)

	_draw_focus_label(centre)


## The focused command's name, centred under the ring's south slot.
##
## Placeholder icons are not self-explanatory, and this is the only thing that
## makes them learnable — which is also why it replaced the prompt window's
## "Choose a command." rather than joining it.
func _draw_focus_label(centre: Vector2) -> void:
	var label := focused_label()
	if label.is_empty():
		return
	var font := get_theme_font("font")
	if font == null:
		return
	var font_size := NoggThemeScript.FONT_SIZE_BODY
	var text_size := font.get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var baseline := (
		centre.y
		+ NoggThemeScript.ACTION_RING_RADIUS
		+ NoggThemeScript.ACTION_RING_ICON * 0.5
		+ NoggThemeScript.ACTION_RING_LABEL_GAP
		+ font.get_ascent(font_size)
	)
	var origin := Vector2(centre.x - text_size.x * 0.5, baseline).round()
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
