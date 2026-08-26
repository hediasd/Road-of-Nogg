## Fixed-capacity translucent battle window: the shared frame every game
## window uses. See docs/UI_DESIGN.md §4.
##
## `custom_minimum_size.y` is set by `set_row_capacity()` from the theme's row
## metrics, so height is a function of declared capacity, not of how many rows
## are actually added (trait 6). Width is NOT set here — the caller sizes it
## from the measured table in docs/UI_DESIGN.md §8. A `NoggWindow` never sizes
## itself to its content.

class_name NoggWindow
extends Control

## Emitted when close()'s fade-and-shrink tween finishes and the window has
## gone invisible. Callers that need to sequence teardown may also just
## `await window.close()` directly; both are satisfied by the same call.
signal closed

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const PagerArrowScript = preload("res://src/presentation/theme/PagerArrow.gd")

var _content: VBoxContainer
## `null` under a skin with no halo. Tracked as a field, not a `_ready()`
## local, so `restyle()` can find and free it without guessing whether one
## exists.
var _halo: Panel
var _body: Panel
var _rim: Panel
var _rows: Array[Control] = []
var _row_capacity: int = NoggThemeScript.ROW_CAPACITY_DEFAULT
var _active_tween: Tween
var _open_tween: Tween
## Bumped by every open()/close(). A close() that is overtaken by an open()
## before its timer elapses must not go on to hide the window.
var _visibility_generation := 0
## Extra left padding for rows, reserved for a MenuCursor. Zero for windows
## that host no cursor (prompt, forecast, docked readouts).
var _content_indent := 0.0
## Whether this window is tinted for focus or for a parent-with-open-child.
## No caller sets this today -- set_active() has no callers in this
## codebase yet, so every window is nogg-default active in practice -- but
## restyle() still has to reapply *some* state to a freshly built _rim, and
## reading a tracked value beats assuming the answer is always true.
var _is_active := true

# --- Row overflow marquee (§7b) ---------------------------------------------
#
# Parallel to `_rows` rather than looked up from it: the label sits one level
# deeper now (inside a clip wrapper), and the available width a row's label
# gets is computed arithmetically at add_row() time, for the same reason
# row_rect() is arithmetic — Container sorting is deferred, so reading a live
# node's size back on the same frame it was built is stale.
var _row_labels: Array[Label] = []
var _row_available_widths: Array[float] = []
var _marquee_generation := 0
var _marquee_label: Label
var _marquee_tween: Tween

## Display-only windows must not eat mouse input. A `Control` defaults to
## `MOUSE_FILTER_STOP`, so a docked readout silently consumes every click
## landing in its rect — and Godot's GUI layer resolves that before
## `_unhandled_input()` ever runs, so the board underneath becomes unclickable
## rather than merely covered. The command menu is the opposite case and keeps
## the default, because its rows are the input surface.
var _input_transparent := false

# --- Paging (§7a) -------------------------------------------------------------
#
# Opt-in: only set_full_rows() engages this. A window built the old way, via
# direct add_row()/clear_rows() calls (the docked status windows, the prompt,
# the forecast), is completely unaffected — _page_count stays 1 and no footer
# is ever built. row_capacity is the page size, the same number that already
# governs window height (trait 6), so a page is always exactly the window's
# own height.

## Emitted once per row Control constructed — by set_full_rows() and by every
## page turn — so a caller needing per-row interactivity (PlayerCommandMenu)
## can wire hover/click using the FULL-LIST index, the id space its own
## selection state already lives in, regardless of which page produced the row.
signal row_built(row: Control, full_index: int)

## Emitted when a footer pager arrow is clicked; direction is -1 (previous) or
## +1 (next). Deliberately NOT auto-handled: paging changes selection too, and
## selection is the caller's job per this file's own rule at the top. This
## widget reports the input; it does not decide what it means.
signal page_arrow_pressed(direction: int)

## Owned by NoggTheme (PAGER_WIDTH / PAGER_ARROW_GAP), not redeclared here — a
## local const of a literal number could never track `NoggTheme.ui_scale`. Still
## provisional: nothing in the shipping catalog pages at all today, so there is
## no real content to measure against per docs/UI_DESIGN.md §8's usual rule.

var _full_rows: Array[Dictionary] = []
var _page := 0
var _page_count := 1
var _footer: NoggWindow
var _footer_label: Label


func _ready() -> void:
	clip_contents = false

	# Null under a skin with no halo, and then this window simply has no halo
	# child -- see NoggTheme.build_window_halo() for why that is a missing node
	# rather than a transparent one.
	_halo = NoggThemeScript.build_window_halo()
	if _halo != null:
		add_child(_halo)

	_body = NoggThemeScript.build_window_body()
	add_child(_body)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = NoggThemeScript.CONTENT_INSET
	_content.offset_top = NoggThemeScript.CONTENT_INSET
	_content.offset_right = -NoggThemeScript.CONTENT_INSET
	_content.offset_bottom = -NoggThemeScript.CONTENT_INSET
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	# Added last so it draws over the body and the rows.
	_rim = NoggThemeScript.build_window_frame()
	add_child(_rim)

	set_row_capacity(_row_capacity)
	set_input_transparent(_input_transparent)


## Marks this window as a readout that never takes mouse input, so clicks pass
## through to whatever is behind it — for the docked status windows that is the
## board, which they overlap heavily at the default resolution.
##
## Only the window root and the rows need changing: the body, frame, content
## container, and row clip are already IGNORE, and `Label` defaults to IGNORE.
## Safe to call before `_ready()`; the flag is re-applied there.
func set_input_transparent(transparent: bool) -> void:
	_input_transparent = transparent
	var filter := (
		Control.MOUSE_FILTER_IGNORE if transparent else Control.MOUSE_FILTER_STOP
	)
	mouse_filter = filter
	for row in _rows:
		row.mouse_filter = filter


## Tweens the rim tint AND the content tint between their active and
## inactive values. This is the only signal telling the player which window
## their arrow keys are driving — see docs/UI_DESIGN.md §4 "Behaviour". A
## window never moves to show focus.
##
## The content dims with the frame rather than the frame dimming alone: a
## fully-lit list inside a greyed border reads as a rendering glitch, not as
## "this window is not listening". Modulating the content container (rather
## than restyling each row) also means a disabled row inside an inactive
## window compounds correctly to the dimmest state, with no extra bookkeeping.
func set_active(active: bool) -> void:
	_is_active = active
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	var frame_target := NoggThemeScript.FRAME_ACTIVE if active else NoggThemeScript.FRAME_INACTIVE
	var content_target := (
		NoggThemeScript.CONTENT_ACTIVE_MODULATE if active
		else NoggThemeScript.CONTENT_INACTIVE_MODULATE
	)
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(
		_rim, "self_modulate", frame_target, NoggThemeScript.TWEEN_FOCUS
	)
	_active_tween.tween_property(
		_content, "modulate", content_target, NoggThemeScript.TWEEN_FOCUS
	)


## Repaints this window under the currently active skin, in place, without
## losing what it is showing.
##
## Rebuilds the halo, body and rim -- the same trio `_ready()` builds --
## because whether a halo exists at all is itself skin-dependent
## (`build_window_halo()` may now return `null` where it built a node before,
## not merely a re-tinted one) and every other chrome property is baked into a
## `StyleBoxFlat` at construction rather than read live at draw time.
##
## `_content` and its rows are deliberately NOT rebuilt: row labels carry their
## own colour overrides, and rebuilding would drop the marquee's in-flight
## state and the page a paged window is currently showing. The row height
## bookkeeping below is the one piece of row state that does have to move, so
## that `row_rect()`'s arithmetic keeps agreeing with what the container
## actually lays out (its own doc comment states that agreement as the reason
## it is arithmetic rather than read off the node).
##
## **The caller sizes width before calling this**, exactly as `_ready()`
## expects width sized before `add_child()` — see the class doc at the top of
## this file. This only ever derives height, via `set_row_capacity()`.
func restyle() -> void:
	# _active_tween targets _rim, which is about to be freed. A killed tween
	# never fires again regardless, but killing it before the free is what
	# keeps this from ever depending on tween/free ordering.
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	if _halo != null and is_instance_valid(_halo):
		remove_child(_halo)
		_halo.queue_free()
	_halo = null
	if _body != null and is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	if _rim != null and is_instance_valid(_rim):
		remove_child(_rim)
		_rim.queue_free()

	# Rebuilt in the same order `_ready()` uses, and re-established with
	# `move_child()`: `add_child()` always appends, so adding halo and body
	# again would stack them AFTER `_content`, drawing the body over the rows
	# instead of under them.
	_halo = NoggThemeScript.build_window_halo()
	if _halo != null:
		add_child(_halo)
		move_child(_halo, 0)

	_body = NoggThemeScript.build_window_body()
	add_child(_body)
	move_child(_body, 1 if _halo != null else 0)

	_content.offset_left = NoggThemeScript.CONTENT_INSET + _content_indent
	_content.offset_top = NoggThemeScript.CONTENT_INSET
	_content.offset_right = -NoggThemeScript.CONTENT_INSET
	_content.offset_bottom = -NoggThemeScript.CONTENT_INSET

	_rim = NoggThemeScript.build_window_frame()
	add_child(_rim)  # appended last: draws over the body and the rows.
	_rim.self_modulate = (
		NoggThemeScript.FRAME_ACTIVE if _is_active else NoggThemeScript.FRAME_INACTIVE
	)
	_content.modulate = (
		NoggThemeScript.CONTENT_ACTIVE_MODULATE if _is_active
		else NoggThemeScript.CONTENT_INACTIVE_MODULATE
	)

	set_row_capacity(_row_capacity)  # re-derives size.y from the new skin.

	# Existing rows were built under the old skin's ROW_HEIGHT and carry it as
	# their own cached `custom_minimum_size.y`. row_rect() reads the CURRENT
	# theme value, so a row that kept its old cached height would disagree
	# with the arithmetic the instant anything asks where it is — including
	# the cursor. Sub-row detail (a label's baked vertical centring, the label
	# clip wrapper's own height) is not chased here: it is a sub-pixel residue
	# at the scale these numbers move by, and fixing it needs the row rebuild
	# this function deliberately avoids. It self-heals on the next
	# add_row()/clear_rows() cycle, which every one of these windows goes
	# through routinely.
	for row in _rows:
		row.custom_minimum_size.y = NoggThemeScript.ROW_HEIGHT

	if _footer != null and is_instance_valid(_footer):
		_footer.size.x = NoggThemeScript.PAGER_WIDTH
		_footer.restyle()
		if _footer_label != null:
			_footer_label.add_theme_font_size_override(
				"font_size", NoggThemeScript.FONT_SIZE_FOOTER
			)
		_update_footer()


## Reserves extra left padding inside the window for a MenuCursor, so the
## arrow sits in clear space between the ring and the text instead of on top
## of the ring. Windows with no cursor leave this at zero.
func set_content_indent(pixels: float) -> void:
	_content_indent = pixels
	if _content:
		_content.offset_left = NoggThemeScript.CONTENT_INSET + _content_indent


## Scale 0.94 -> 1.0 and alpha 0 -> 1 over TWEEN_WINDOW_OPEN, EASE_OUT.
func open() -> void:
	_visibility_generation += 1
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	visible = true
	pivot_offset = size / 2.0
	scale = Vector2.ONE * NoggThemeScript.WINDOW_OPEN_SCALE
	modulate.a = 0.0
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(self, "scale", Vector2.ONE, NoggThemeScript.TWEEN_WINDOW_OPEN) \
		.set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(self, "modulate:a", 1.0, NoggThemeScript.TWEEN_WINDOW_OPEN) \
		.set_ease(Tween.EASE_OUT)


## Reverse of open() over TWEEN_WINDOW_CLOSE. Awaitable (the coroutine only
## returns once the window is actually invisible) AND emits `closed`, so a
## caller can use either without checking which this widget picked.
##
## Callers may fire-and-forget this. The wait is on a SceneTree timer, not on
## `_open_tween.finished`, for two reasons: a killed tween never emits
## `finished`, so awaiting it would strand the coroutine forever the moment an
## open() interrupts a close(); and the generation check below then cleanly
## drops the stale close instead of hiding a window that was just reopened.
func close() -> void:
	_visibility_generation += 1
	var generation := _visibility_generation
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	pivot_offset = size / 2.0
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(self, "scale", Vector2.ONE * NoggThemeScript.WINDOW_OPEN_SCALE, NoggThemeScript.TWEEN_WINDOW_CLOSE)
	_open_tween.tween_property(self, "modulate:a", 0.0, NoggThemeScript.TWEEN_WINDOW_CLOSE)
	await get_tree().create_timer(NoggThemeScript.TWEEN_WINDOW_CLOSE).timeout
	if generation != _visibility_generation:
		return
	visible = false
	closed.emit()


## Fixes height from the theme's row metrics, independent of how many rows are
## currently added. Width is the caller's responsibility.
##
## Assigns `size.y` outright rather than only growing it: these windows are
## free-floating Controls with no parent container to re-fit them, so a
## capacity that shrinks (a 2-spell list after an 8-spell one) has to be able
## to pull the window back in.
func set_row_capacity(rows: int) -> void:
	_row_capacity = rows
	custom_minimum_size.y = NoggThemeScript.window_height(rows)
	size.y = custom_minimum_size.y


## Two-column row: label left, value right in TEXT_ACCENT (TEXT_DIM if
## disabled). A plain HBoxContainer, never a Button — see docs/UI_DESIGN.md §5.
##
## The label lives inside a `clip_contents` wrapper rather than relying on
## `Label.clip_text`/`OVERRUN_TRIM_CHAR` alone: the wrapper clips visually
## regardless of the label's own size, which is what lets the label be sized
## to its FULL natural width and then have `position.x` tweened to reveal the
## hidden tail — the marquee (§7b). A row whose label fits looks identical to
## before; nothing here changes what a non-overflowing row renders.
##
## The value is given its natural width before the label's SIZE_EXPAND_FILL
## wrapper claims what's left, which is what keeps a long label from running
## straight into its value with no gap.
func add_row(label_text: String, value_text: String = "", disabled: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = NoggThemeScript.ROW_HEIGHT
	if _input_transparent:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(row)

	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size.y = NoggThemeScript.ROW_HEIGHT
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(clip)

	var label := Label.new()
	label.text = label_text
	if disabled:
		label.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	# Sized to its full natural width, not the clip's — the clip is what
	# truncates. get_minimum_size() is a pure function of font/text/theme, so
	# unlike a Container-assigned size it is correct immediately, before any
	# layout pass.
	label.size = label.get_minimum_size()
	label.position.y = (NoggThemeScript.ROW_HEIGHT - label.size.y) / 2.0
	clip.add_child(label)

	var value_width := 0.0
	if not value_text.is_empty():
		var value := Label.new()
		value.text = value_text
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override(
			"font_color",
			NoggThemeScript.TEXT_DIM if disabled else NoggThemeScript.TEXT_ACCENT
		)
		row.add_child(value)
		value_width = value.get_minimum_size().x

	_rows.append(row)
	_row_labels.append(label)
	var content_width: float = size.x - NoggThemeScript.CONTENT_INSET * 2.0 - _content_indent
	_row_available_widths.append(maxf(content_width - value_width, 0.0))
	return row


## Fixed-column cells for passive status readouts. The builder is deliberately
## separate from add_row(): list rows retain their two-column HBox and marquee
## contract, while a status row puts label/value units beside one another.
##
## Every cell has a String label and exactly one of `value` (a String) or
## `control` (a caller-supplied Control). The returned handles expose the created
## nodes so callers never depend on a child index for value tinting. An optional
## `column` selects one of the fixed offsets; otherwise input order is used.
func add_stat_row(cells: Array[Dictionary]) -> Array[Dictionary]:
	if cells.is_empty() or cells.size() > NoggThemeScript.STATUS_CELL_OFFSETS.size():
		push_error("NoggWindow: status row has an invalid cell count")
		return []
	var used_columns: Dictionary = {}
	for index in cells.size():
		var cell: Dictionary = cells[index]
		var has_label := cell.has("label") and cell["label"] is String
		var has_value := cell.has("value") and cell["value"] is String
		var has_control := cell.has("control") and cell["control"] is Control
		if not has_label or has_value == has_control:
			push_error("NoggWindow: status cells need a label and exactly one value/control")
			return []

		var column = cell.get("column", index)
		if not column is int or column < 0 or column >= NoggThemeScript.STATUS_CELL_OFFSETS.size() or used_columns.has(column):
			push_error("NoggWindow: status cell has an invalid or duplicate column")
			return []
		used_columns[column] = true
	var row := Control.new()
	row.custom_minimum_size.y = NoggThemeScript.ROW_HEIGHT
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _input_transparent:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(row)

	var handles: Array[Dictionary] = []
	for index in cells.size():
		var cell: Dictionary = cells[index]
		var cell_root := Control.new()
		var column: int = int(cell.get("column", index))
		cell_root.position.x = NoggThemeScript.STATUS_CELL_OFFSETS[column]
		cell_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cell_root)

		var label := Label.new()
		label.text = str(cell["label"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size = label.get_minimum_size()
		label.position.y = (NoggThemeScript.ROW_HEIGHT - label.size.y) / 2.0
		cell_root.add_child(label)

		var value: Control
		if cell.has("value"):
			var value_label := Label.new()
			value_label.text = str(cell["value"])
			value_label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
			value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			value_label.size = value_label.get_minimum_size()
			value = value_label
		else:
			value = cell["control"] as Control
			value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.position = Vector2(
			label.size.x + (
				NoggThemeScript.STATUS_CELL_TEXT_GAP if cell.has("value")
				else NoggThemeScript.STATUS_CELL_CONTROL_GAP
			),
			(NoggThemeScript.ROW_HEIGHT - value.get_combined_minimum_size().y) / 2.0
		)
		cell_root.add_child(value)
		handles.append({"cell": cell_root, "label": label, "value": value})

	_rows.append(row)
	return handles


## Removes every row added so far. Pairs with add_row() to satisfy the §5 rule:
## content changes rebuild rows; they never touch cursor position.
##
## `remove_child` before `queue_free`: queue_free alone defers the actual
## removal to the end of the frame, so a clear_rows()/add_row() pair in the
## same call would leave the VBoxContainer briefly holding both the stale and
## the new rows — and any row_rect() taken in between would be measured
## against that doubled list.
func clear_rows() -> void:
	# Stop any marquee and snap-reset first: the label it targets is about to
	# be freed, and set_focused_row(-1) is the one place that already knows
	# how to unwind that safely.
	set_focused_row(-1)
	for row in _rows:
		_content.remove_child(row)
		row.queue_free()
	_rows.clear()
	_row_labels.clear()
	_row_available_widths.clear()


func row_count() -> int:
	return _rows.size()


## Marks which row is "focused" for the overflow marquee (§7b) — driven by
## selection change in an interactive window, or set once by a caller that
## wants a specific row (e.g. a status window's Elements row, which has no
## cursor at all) to marquee unconditionally. `-1` clears focus.
##
## Resets whatever was scrolling IMMEDIATELY — no easing out, no finishing the
## cycle (rule 5): leaving the reset for later is what lets a superseding
## selection change and the old row's snap-back visibly fight.
func set_focused_row(index: int) -> void:
	_marquee_generation += 1
	# The scroll tween is independent of _runMarquee's own generation checks —
	# it keeps animating position.x on its own once created, regardless of
	# what the coroutine does next. Without this kill, the reset below is
	# overwritten on the very next frame by the tween still running toward
	# wherever it was headed — confirmed on screen: a row refocused away
	# mid-scroll stayed visibly scrolled instead of snapping back.
	if _marquee_tween and _marquee_tween.is_valid():
		_marquee_tween.kill()
	if _marquee_label:
		_marquee_label.position.x = 0.0
	_marquee_label = null
	if index < 0 or index >= _row_labels.size():
		return
	var label := _row_labels[index]
	var overflow: float = label.get_minimum_size().x - _row_available_widths[index]
	# Rule 6: a row whose label fits must never scroll and must never wait out
	# the delay. Compared against the clip width, not a character count.
	if overflow <= 0.0:
		return
	_marquee_label = label
	_runMarquee(label, overflow, _marquee_generation)


## Delay, scroll left at MARQUEE_SPEED, hold, snap, repeat — forever, until a
## later set_focused_row() bumps the generation and this loop notices and
## exits. Every wait is a SceneTree timer, not a tween signal: a killed tween
## never emits `finished` (see close()'s note above), and set_focused_row()
## does not go through this tween at all, so awaiting it here would strand
## the coroutine the moment a new row takes focus.
func _runMarquee(label: Label, distance: float, generation: int) -> void:
	while generation == _marquee_generation:
		await get_tree().create_timer(NoggThemeScript.MARQUEE_DELAY).timeout
		if generation != _marquee_generation:
			return
		_marquee_tween = create_tween()
		_marquee_tween.tween_property(
			label, "position:x", -distance, distance / NoggThemeScript.MARQUEE_SPEED
		).set_trans(Tween.TRANS_LINEAR)
		await get_tree().create_timer(distance / NoggThemeScript.MARQUEE_SPEED).timeout
		if generation != _marquee_generation:
			return
		await get_tree().create_timer(NoggThemeScript.MARQUEE_END_HOLD).timeout
		if generation != _marquee_generation:
			return
		label.position.x = 0.0


## A row's rect in this window's own coordinate space, for MenuCursor
## positioning without reaching into the row's children.
##
## Computed from ROW_HEIGHT and the index rather than read off the row node,
## deliberately. `Container` sorting is deferred in Godot, so a row's
## `position` is still stale on the same frame it was added — a cursor snapped
## from it right after a rebuild would land on the wrong row and, since
## nothing re-runs afterwards, silently stay there. Every row is exactly
## ROW_HEIGHT tall with zero separation (the theme sets `separation` to 0 and
## ROW_HEIGHT is >= the font height), so the arithmetic and the layout agree
## by construction.
func row_rect(index: int) -> Rect2:
	if index < 0 or index >= _rows.size():
		return Rect2()
	var inset := float(NoggThemeScript.CONTENT_INSET)
	return Rect2(
		Vector2(inset + _content_indent, inset + index * NoggThemeScript.ROW_HEIGHT),
		Vector2(
			maxf(size.x - inset * 2.0 - _content_indent, 0.0),
			float(NoggThemeScript.ROW_HEIGHT)
		)
	)


## Replaces the row set with `rows` (dictionaries with "label", optional
## "value", optional "disabled"), slices it into pages of `row_capacity`, and
## renders the first page. Always resets to page 0, even when reopening
## identical content — matching how every other rebuild in this codebase snaps
## rather than remembers (§5): a caller that wants to reopen mid-list has to
## say so explicitly via focus_index(), not get it for free here.
func set_full_rows(rows: Array) -> void:
	_full_rows.clear()
	for row in rows:
		_full_rows.append(row as Dictionary)
	_page = 0
	var capacity := maxi(_row_capacity, 1)
	_page_count = maxi(1, (_full_rows.size() + capacity - 1) / capacity)
	_render_page()


func page() -> int:
	return _page


func page_count() -> int:
	return _page_count


## First full-list index shown on `page_index`.
func page_start_index(page_index: int) -> int:
	return page_index * maxi(_row_capacity, 1)


## One-past-last full-list index shown on `page_index`.
func page_end_index(page_index: int) -> int:
	return mini(page_start_index(page_index) + maxi(_row_capacity, 1), _full_rows.size())


func next_page() -> void:
	if _page_count > 1:
		_go_to_page(posmod(_page + 1, _page_count))


func prev_page() -> void:
	if _page_count > 1:
		_go_to_page(posmod(_page - 1, _page_count))


## Brings `full_index`'s page on screen if it is not already (turning,
## rebuilding that page's rows and re-firing row_built), applies the overflow
## marquee to it (§7b), and returns its rect plus whether a page turn
## happened — the caller's signal to snap the cursor instead of tweening it.
## "Cursor movement past the last row of a page advances to the next page...
## tweening across a page turn reads as a glitch" (§7a, item 3).
func focus_index(full_index: int) -> Dictionary:
	var capacity := maxi(_row_capacity, 1)
	var target_page := clampi(full_index / capacity, 0, maxi(_page_count - 1, 0))
	var turned := target_page != _page
	if turned:
		_go_to_page(target_page)
	var relative := full_index - _page * capacity
	set_focused_row(relative)
	return {"rect": row_rect(relative), "turned": turned}


func _go_to_page(target: int) -> void:
	if target == _page:
		return
	_page = target
	_render_page()


func _render_page() -> void:
	clear_rows()
	var start := page_start_index(_page)
	var end := page_end_index(_page)
	for i in range(start, end):
		var d: Dictionary = _full_rows[i]
		var row := add_row(
			str(d.get("label", "")), str(d.get("value", "")), bool(d.get("disabled", false))
		)
		row_built.emit(row, i)
	_update_footer()


func _update_footer() -> void:
	if _page_count <= 1:
		if _footer:
			_footer.visible = false
		return
	if not _footer:
		_build_footer()
	_footer_label.text = "%d / %d" % [_page + 1, _page_count]
	_footer.position = Vector2(
		(size.x - NoggThemeScript.PAGER_WIDTH) / 2.0, size.y - NoggThemeScript.window_height(1) / 2.0
	)
	_footer.visible = true


## The footer is its own small NoggWindow, horizontally centred and
## overlapping the parent's bottom border by half its height (§7a) — built
## lazily, the first time a window actually needs to page, so a window that
## never pages carries no extra nodes for one it will never show.
func _build_footer() -> void:
	_footer = NoggWindow.new()
	add_child(_footer)  # after the rim, added in _ready() — draws on top of it
	_footer.set_row_capacity(1)
	_footer.size.x = NoggThemeScript.PAGER_WIDTH
	# Only the two arrows are clickable; everything else in the footer's rect
	# (including the label and the space around it) passes clicks through.
	_footer.set_input_transparent(true)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", NoggThemeScript.PAGER_ARROW_GAP)
	_footer._content.add_child(bar)

	var prev_arrow := PagerArrowScript.new(false)
	prev_arrow.pressed.connect(func(): page_arrow_pressed.emit(-1))
	bar.add_child(prev_arrow)

	_footer_label = Label.new()
	_footer_label.add_theme_font_size_override("font_size", NoggThemeScript.FONT_SIZE_FOOTER)
	_footer_label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	bar.add_child(_footer_label)

	var next_arrow := PagerArrowScript.new(true)
	next_arrow.pressed.connect(func(): page_arrow_pressed.emit(1))
	bar.add_child(next_arrow)
