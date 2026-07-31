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

var _content: VBoxContainer
var _frame: NinePatchRect
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


func _ready() -> void:
	# Root is a plain Control, NOT a PanelContainer — see docs/UI_DESIGN.md
	# §4. A Container force-fits the frame into its content rect and the ring
	# ends up covering the first and last glyph of every row.
	var body := NoggThemeScript.build_window_body()
	add_child(body)

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
	_frame = NoggThemeScript.build_window_frame()
	add_child(_frame)

	set_row_capacity(_row_capacity)


## Tweens the frame tint AND the content tint between their active and
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
		_frame, "self_modulate", frame_target, NoggThemeScript.TWEEN_FOCUS
	)
	_active_tween.tween_property(
		_content, "modulate", content_target, NoggThemeScript.TWEEN_FOCUS
	)


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
## The value is given its natural width by the container's own minimum-size
## pass before the label's SIZE_EXPAND_FILL claims what's left, which is what
## keeps a long label from running straight into its value with no gap.
func add_row(label_text: String, value_text: String = "", disabled: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = NoggThemeScript.ROW_HEIGHT
	_content.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Hard cut, not ellipsis: the shipping font has no ellipsis glyph (§3).
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	label.clip_text = true
	if disabled:
		label.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	row.add_child(label)

	if not value_text.is_empty():
		var value := Label.new()
		value.text = value_text
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override(
			"font_color",
			NoggThemeScript.TEXT_DIM if disabled else NoggThemeScript.TEXT_ACCENT
		)
		row.add_child(value)

	_rows.append(row)
	return row


## Removes every row added so far. Pairs with add_row() to satisfy the §5
## rule: content changes rebuild rows; they never touch cursor position.
##
## `remove_child` before `queue_free`: queue_free alone defers the actual
## removal to the end of the frame, so a clear_rows()/add_row() pair in the
## same call would leave the VBoxContainer briefly holding both the stale and
## the new rows — and any row_rect() taken in between would be measured
## against that doubled list.
func clear_rows() -> void:
	for row in _rows:
		_content.remove_child(row)
		row.queue_free()
	_rows.clear()


func row_count() -> int:
	return _rows.size()


## A row's rect in this window's own coordinate space, for MenuCursor
## positioning (UI-4) without reaching into the row's children.
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
