## Gold selection cursor: a filled triangle drawn in code (no art asset
## exists or is required — see docs/UI_DESIGN.md §3), always bobbing, tweened
## between rows. See docs/UI_DESIGN.md §5.
##
## Parent it to the window itself (the frame gutter), a sibling of the row
## list, never a child of any row — selection is this node's position, not
## anything drawn by a row.
##
## Set `position.x` to the gutter offset BEFORE calling `add_child()` on this
## node. The idle bob starts in `_ready()` per spec and captures whatever
## `position.x` already is as its centre; setting it afterward only fights
## the bob's next step back toward the wrong origin.

class_name MenuCursor
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Sourced from NoggTheme, not redeclared: NoggWindow reserves the gutter
## from the same numbers, and a local copy here would let the two drift.
##
## Read through accessors rather than captured in a `const`, because the cursor
## tokens now scale with `NoggTheme.ui_scale` — a const would freeze whatever
## the scale happened to be when this script was first parsed, and the gutter
## agreement NoggWindow depends on would silently break at any other scale.
static func _width() -> float:
	return NoggThemeScript.CURSOR_WIDTH


static func _height() -> float:
	return NoggThemeScript.CURSOR_HEIGHT

var _bob_tween: Tween
## Move and bob animate different sub-properties of the same `position`
## (:x for bob, :y for move), so they run simultaneously without conflict —
## killing the move tween on a new move_to_row() never touches the bob.
var _move_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_width(), _height())
	size = custom_minimum_size
	_start_bob()


func _draw() -> void:
	# Right-pointing triangle, matching the "›" direction the old text-prefix
	# cursor used and the pager arrows in §7.
	var points := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(_width(), _height() / 2.0),
		Vector2(0.0, _height()),
	])
	draw_colored_polygon(points, NoggThemeScript.CURSOR)


## Tweens position.y to the target row's vertical centre over
## TWEEN_CURSOR_MOVE. Any in-flight move is killed first, not queued — held
## arrow keys must track continuously, not drain a queue.
func move_to_row(rect: Rect2) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	var target_y := rect.position.y + rect.size.y / 2.0 - size.y / 2.0
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position:y", target_y, NoggThemeScript.TWEEN_CURSOR_MOVE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## No-animation placement, for a window that just opened or just turned a
## page — there is nothing to tween from.
func snap_to_row(rect: Rect2) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	position.y = rect.position.y + rect.size.y / 2.0 - size.y / 2.0


## Hands focus to a child window: hide this cursor without stopping its bob,
## so it is ready to reappear mid-cycle rather than snapping back to centre.
func set_visible_cursor(cursor_visible: bool) -> void:
	visible = cursor_visible


func _start_bob() -> void:
	if _bob_tween and _bob_tween.is_valid():
		_bob_tween.kill()
	var base_x := position.x
	var half_period := NoggThemeScript.CURSOR_BOB_PERIOD / 2.0
	_bob_tween = create_tween()
	_bob_tween.set_loops()
	_bob_tween.tween_property(
		self, "position:x", base_x + NoggThemeScript.CURSOR_BOB_PIXELS, half_period
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(
		self, "position:x", base_x - NoggThemeScript.CURSOR_BOB_PIXELS, half_period
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
