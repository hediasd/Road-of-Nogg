## DamageNumberBillboard - a compact JRPG-style screen-space hit number.
##
## The number is deliberately not a Label3D. World-space text inherits camera
## scale and depth ordering, which made the old value look oversized and let it
## compete with the battlefield. This Control is placed in a dedicated
## CanvasLayer instead: its position is projected from the hit unit once, its
## size is the same as menu text, and UI CanvasLayers remain above it.
##
## Each digit is drawn directly as five pixel passes: four opaque black copies
## shifted by one pixel in the cardinal directions, then one white copy in the
## centre. Drawing the glyphs directly keeps the number tightly kerned instead
## of making it look like several centered UI labels placed side by side.

class_name DamageNumberBillboard
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const SPAWN_HEIGHT := 0.85
const PUMP_SCALE := 1.15
const PUMP_UP_DURATION := 0.07
const PUMP_DOWN_DURATION := 0.12
const DIGIT_STAGGER := 0.025
const HOLD_DURATION := 0.18
const DISAPPEAR_DURATION := 0.14

const DAMAGE_VISIBLE_DURATION := (
	PUMP_UP_DURATION + PUMP_DOWN_DURATION + DIGIT_STAGGER * 2.0
	+ HOLD_DURATION + DISAPPEAR_DURATION
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


## A single digit owns its five direct draw passes, so scaling it for the one
## pump does not introduce Label layout padding or per-label centering drift.
class DamageGlyph:
	extends Control

	var font: Font
	var glyph: String = ""
	var glyph_width: int = 1
	var font_size: int = 24
	var front_color := Color.WHITE

	func configure(
			font_value: Font,
			glyph_value: String,
			width_value: int,
			size_value: int,
			color_value: Color) -> void:
		font = font_value
		glyph = glyph_value
		glyph_width = width_value
		font_size = size_value
		front_color = color_value
		size = Vector2(glyph_width, font_size)
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	func _draw() -> void:
		if font == null or glyph.is_empty():
			return
		var baseline := Vector2(0, font.get_ascent(font_size))
		for offset in DamageNumberBillboard.OUTLINE_OFFSETS:
			draw_string(
				font,
				baseline + offset,
				glyph,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				NoggThemeScript.OUTLINE
			)
		draw_string(
			font,
			baseline,
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			front_color
		)


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
		var digit := DamageGlyph.new()
		digit.name = "Digit_%d" % index
		digit.position = Vector2(x, 0)
		digit.configure(
			_font,
			text.substr(index, 1),
			advances[index],
			NoggThemeScript.FONT_SIZE_BODY,
			front_color
		)
		add_child(digit)
		x += advances[index]

	return _animate()


func _animate() -> Tween:
	var tween := create_tween()
	var digits := get_children()

	# A tiny left-to-right wave makes the value feel struck into the scene while
	# keeping the whole number readable as one compact object.
	tween.set_parallel(true)
	for index in range(digits.size()):
		tween.tween_property(
			digits[index], "scale", Vector2.ONE * PUMP_SCALE, PUMP_UP_DURATION
		).set_delay(index * DIGIT_STAGGER) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: pass)

	# Return in the opposite order: the last digit settles first, giving the
	# number the compact arcade/JRPG hit cadence without moving its anchor.
	tween.set_parallel(true)
	for index in range(digits.size()):
		var reverse_delay := (digits.size() - 1 - index) * DIGIT_STAGGER
		tween.tween_property(
			digits[index], "scale", Vector2.ONE, PUMP_DOWN_DURATION
		).set_delay(reverse_delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: pass)
	tween.tween_interval(HOLD_DURATION)

	tween.set_parallel(true)
	for digit in digits:
		tween.tween_property(digit, "modulate:a", 0.0, DISAPPEAR_DURATION) \
			.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)
	return tween
