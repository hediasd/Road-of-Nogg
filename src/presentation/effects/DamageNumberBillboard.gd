## DamageNumberBillboard — a pixel-perfect, screen-space number anchored above
## the unit that was hit.
##
## The number is deliberately not a Label3D. World-space text inherits camera
## scale and depth ordering, which made the old value look oversized and let it
## compete with the battlefield. This Control is placed in a dedicated
## CanvasLayer instead: its position is projected from the hit unit once, its
## size is the same as menu text, and UI CanvasLayers remain above it.
##
## Every digit owns five Labels: four opaque black copies shifted by one pixel in
## the cardinal directions, then one white copy at the centre. The digit roots
## pump independently, so a multi-digit value still reads as separate chunky
## glyphs rather than one large transforming string.

class_name DamageNumberBillboard
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const SPAWN_HEIGHT := 0.85
const PUMP_SCALE := 1.25
const PUMP_UP_DURATION := 0.08
const PUMP_DOWN_DURATION := 0.13
const HOLD_DURATION := 0.16
const DISAPPEAR_DURATION := 0.12

const DAMAGE_VISIBLE_DURATION := (
	PUMP_UP_DURATION + PUMP_DOWN_DURATION + HOLD_DURATION + DISAPPEAR_DURATION
)
const HEAL_VISIBLE_DURATION := DAMAGE_VISIBLE_DURATION

## This only matters when a queue tween is skipped or the tree is torn down
## while the animation is running. The normal tween callback frees the node.
const CLEANUP_MARGIN := 0.5

const OUTLINE_OFFSETS := [
	Vector2(-1, 0),
	Vector2(1, 0),
	Vector2(0, -1),
	Vector2(0, 1)
]

static var _font: Font = null


## `screen_position` is in the host viewport's native screen coordinates, not
## the low-resolution battle SubViewport. That keeps the menu-sized glyphs
## crisp even when the battlefield is rendered at 320x240 or 480x360.
static func spawn(
		parent: Control,
		screen_position: Vector2,
		amount: int,
		is_heal: bool = false) -> Tween:
	if parent == null or not is_instance_valid(parent):
		return null
	_ensure_font()

	var billboard := DamageNumberBillboard.new()
	billboard.name = "DamageNumber"
	billboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	billboard.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(billboard)
	var animation := billboard._build(screen_position, amount, is_heal)

	var tree := billboard.get_tree()
	if tree != null:
		tree.create_timer(visible_duration(is_heal) * 5.0 + CLEANUP_MARGIN).timeout.connect(
			func() -> void:
				if is_instance_valid(billboard):
					billboard.queue_free()
		)
	return animation


static func visible_duration(is_heal: bool) -> float:
	return HEAL_VISIBLE_DURATION if is_heal else DAMAGE_VISIBLE_DURATION


static func _ensure_font() -> void:
	if _font == null:
		_font = NoggThemeScript.build_game_theme().default_font


func _build(screen_position: Vector2, amount: int, is_heal: bool) -> Tween:
	var text := "+%d" % amount if is_heal else str(amount)
	var front_color: Color = (
		NoggThemeScript.TEXT_HEAL
		if is_heal else
		NoggThemeScript.TEXT_PRIMARY
	)
	var advances: Array[int] = []
	var total_width := 0
	for index in range(text.length()):
		var glyph := text.substr(index, 1)
		var advance := maxi(
			1,
			ceili(_font.get_string_size(
				glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NoggThemeScript.FONT_SIZE_BODY
			).x)
		)
		advances.append(advance)
		total_width += advance

	size = Vector2(total_width, NoggThemeScript.FONT_SIZE_BODY)
	position = (screen_position.round() - size * 0.5).round()

	var x := 0
	for index in range(text.length()):
		var digit := Control.new()
		digit.name = "Digit_%d" % index
		digit.position = Vector2(x, 0)
		digit.size = Vector2(advances[index], NoggThemeScript.FONT_SIZE_BODY)
		digit.pivot_offset = digit.size * 0.5
		digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		digit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for offset in OUTLINE_OFFSETS:
			digit.add_child(_build_label(
				text.substr(index, 1),
				digit.size,
				offset,
				NoggThemeScript.OUTLINE,
				0
			))
		digit.add_child(_build_label(
			text.substr(index, 1),
				digit.size,
			Vector2.ZERO,
			front_color,
			1
		))
		add_child(digit)
		x += advances[index]

	return _animate()


func _build_label(
		glyph: String,
		glyph_size: Vector2,
		offset: Vector2,
		color: Color,
		draw_order: int) -> Label:
	var label := Label.new()
	label.text = glyph
	label.position = offset
	label.size = glyph_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", NoggThemeScript.FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", color)
	label.z_index = draw_order
	return label


func _animate() -> Tween:
	var tween := create_tween()
	tween.set_parallel(true)
	for digit in get_children():
		tween.tween_property(digit, "scale", Vector2.ONE * PUMP_SCALE, PUMP_UP_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	# Keep this phase boundary explicit. Godot's parallel tween groups have
	# previously dropped elapsed time when a group changed mode without a
	# callback between them.
	tween.tween_callback(func() -> void: pass)
	tween.set_parallel(true)
	for digit in get_children():
		tween.tween_property(digit, "scale", Vector2.ONE, PUMP_DOWN_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: pass)
	tween.tween_interval(HOLD_DURATION)
	tween.set_parallel(true)
	for digit in get_children():
		tween.tween_property(digit, "modulate:a", 0.0, DISAPPEAR_DURATION) \
			.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)
	return tween
