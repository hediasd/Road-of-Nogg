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
##
## The number is thrown rather than stamped: it leaves the unit at
## `RISE_SPEED`, decelerates under `FALL_ACCELERATION`, crests, and is already
## descending when it drops its outline and flashes out. See
## `docs/plans/battle-damage-number-arc.md` for the measured reference figures
## this timeline implements.

class_name DamageNumberBillboard
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const SPAWN_HEIGHT := 0.85

## The arc's parts, in glyph heights and glyph heights per second, so the throw
## keeps its proportions against the number that is doing the travelling at
## every `NoggTheme.ui_scale`. A figure in device pixels would make the arc
## shrink relative to the glyph as the UI grew.
##
## These are the timeline's parts, not a subdivision of a chosen total: per
## `docs/VFX_DESIGN.md` §4 the lifetime below falls out of them. Moving
## `OUTLINED_DURATION` earlier ends the number earlier rather than stretching
## what follows it.
const RISE_SPEED := 23.1
const FALL_ACCELERATION := 55.4
const DRIFT_SPEED := 4.2

## The reference drifts left on both of its sampled hits, which share an
## attacker, so this is the observed direction rather than a demonstrated rule.
## Kept as a signed constant because that is the whole of the change if stacked
## numbers ever read as mechanical.
const DRIFT_DIRECTION := -1.0

const OUTLINED_DURATION := 0.46
const FLASH_DURATION := 0.12

## The exit is not this glyph going transparent. The outline is dropped
## outright and the fill lightens, so the number blooms off the unit instead of
## dimming into the background. Derived from the front colour rather than
## authored, so the heal tint flashes as its own colour.
const FLASH_LIGHTEN := 0.25

const DAMAGE_VISIBLE_DURATION := OUTLINED_DURATION + FLASH_DURATION
const HEAL_VISIBLE_DURATION := DAMAGE_VISIBLE_DURATION

## Published for the probe: both fall out of the two motion constants, and
## restating them anywhere else would let the assertion drift from the arc.
const CREST_TIME := RISE_SPEED / FALL_ACCELERATION
const CREST_HEIGHT := RISE_SPEED * RISE_SPEED / (2.0 * FALL_ACCELERATION)

## This only matters when a queue tween is skipped or the tree is torn down
## while the animation is running. The normal tween callback frees the node.
const CLEANUP_MARGIN := 0.5

## The number is drawn on its own coarse grid, not on the device's.
##
## The reference's glyph stands 8 art pixels tall, wears an outline exactly one
## art pixel thick, and steps one art pixel at a time. Measured against its
## capture: the outline is 13% of the glyph's height and the motion quantum is
## an eighth of it. Drawn on the device grid instead, our outline was a 1 pixel
## hairline (4% of a 24 px glyph) and the motion stepped in 24ths -- which is
## why the number read as finely drawn and too smooth beside the source.
##
## So one art pixel is a share of the glyph, and both the outline and the
## motion are measured in it. This deliberately reverses `docs/UI_DESIGN.md`
## §3's "resolution-independent chrome" rule for this one element: a hit number
## is pixel art wearing a font, not window chrome, and chrome's hairline is the
## wrong family for it. Everything else on screen keeps the hairline rule.
const ART_PIXELS_PER_GLYPH := 8.0

## The smallest size Nogg Terminal still rasterises. Below this it returns a
## zero-sized glyph and the number renders as nothing at all, which is a silent
## failure rather than a small one -- hence a floor rather than a comment.
const MIN_FONT_STRIKE := 6

static var _outline_cache: Dictionary = {}


## Device pixels per art pixel, at the current `NoggTheme.ui_scale`.
##
## Rounded to a whole number, and that is the whole point of the function.
## `FONT_SIZE_BODY` is `12 * ui_scale`, so dividing it by `ART_PIXELS_PER_GLYPH`
## gives 1.5 at x1 and 4.5 at x3 -- both shipping scales. A fractional art pixel
## blows the glyph up by a fraction, and its edges stop landing on device
## pixels: some art pixels render three device pixels wide and their neighbours
## four, which is exactly the ragged, soft-looking number this whole grid exists
## to prevent. `NoggTheme._scaled` rounds its tokens for the same reason and
## says why: whole device pixels have to be a property of the token, not a hope
## at each draw site.
static func art_pixel() -> float:
	return float(maxi(
		1, roundi(float(NoggThemeScript.FONT_SIZE_BODY) / ART_PIXELS_PER_GLYPH)
	))


## A filled disc rather than the four cardinals: at a one pixel radius those are
## the same ring, but at three they leave the diagonals open and the glyph
## bleeds through its own outline at every corner.
static func outline_offsets(radius: int) -> Array:
	if _outline_cache.has(radius):
		return _outline_cache[radius]
	var offsets: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			if dx * dx + dy * dy <= radius * radius:
				offsets.append(Vector2(dx, dy))
	_outline_cache[radius] = offsets
	return offsets

static var _font: Font = null

var _anchor := Vector2.ZERO
var _glyph_height := 1.0


## A single digit owns its five direct draw passes, so the outline can be
## dropped for the flash without Label layout padding or per-label centering
## drift entering the number's geometry.
class DamageGlyph:
	extends Control

	var font: Font
	var glyph: String = ""
	var glyph_width: int = 1
	var font_size: int = 24
	var front_color := Color.WHITE
	var outlined := true
	var outline_ring: Array = []
	var pixel_scale := 1.0

	func configure(
			font_value: Font,
			glyph_value: String,
			width_value: int,
			size_value: int,
			color_value: Color,
			pixel_value: float) -> void:
		font = font_value
		glyph = glyph_value
		glyph_width = width_value
		font_size = size_value
		front_color = color_value
		pixel_scale = pixel_value
		# One art pixel, in the small space the glyph is rasterised in. The disc
		# at radius 1 is the four cardinals, which is the reference's outline
		# exactly; the blow-up below is what makes it read as thick.
		outline_ring = DamageNumberBillboard.outline_offsets(1)
		size = Vector2(glyph_width, font_size) * pixel_scale
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	## Compares before assigning so a tween seeking backwards restores the
	## outlined form as readily as playing forwards drops it.
	func setFlashing(flashing: bool, color_value: Color) -> void:
		if outlined == (not flashing) and front_color.is_equal_approx(color_value):
			return
		outlined = not flashing
		front_color = color_value
		queue_redraw()

	## The glyph is rasterised small and blown up by a whole number with nearest
	## filtering, rather than rasterised at full size. That is the difference
	## between pixel art and text: the reference's digit is about six art pixels
	## tall and every edge in it lands on that grid, where a glyph rasterised at
	## 24 px carries detail finer than any pixel the scene has.
	func _draw() -> void:
		if font == null or glyph.is_empty():
			return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(pixel_scale, pixel_scale))
		var baseline := Vector2(0, font.get_ascent(font_size))
		if outlined:
			for offset in outline_ring:
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
		var billboardRef: WeakRef = weakref(billboard)
		tree.create_timer(visible_duration(is_heal) * 5.0 + CLEANUP_MARGIN).timeout.connect(
			_cleanupBillboard.bind(billboardRef),
			CONNECT_ONE_SHOT
		)
	return animation


static func _cleanupBillboard(billboardRef: WeakRef) -> void:
	var billboard := billboardRef.get_ref() as DamageNumberBillboard
	if billboard != null and is_instance_valid(billboard):
		billboard.queue_free()


static func visible_duration(is_heal: bool) -> float:
	return HEAL_VISIBLE_DURATION if is_heal else DAMAGE_VISIBLE_DURATION


## The number's offset from its spawn anchor at `seconds`, in device pixels.
##
## Closed form, per `docs/VFX_DESIGN.md` §3: the vertical term is the integral
## of a decelerating rise written out rather than a value advanced by `delta`,
## so seeking to an instant and playing to it land on the same pixel.
static func offset_at(seconds: float, glyph_height: float) -> Vector2:
	return Vector2(
		DRIFT_DIRECTION * DRIFT_SPEED * glyph_height * seconds,
		(
			-RISE_SPEED * glyph_height * seconds
			+ 0.5 * FALL_ACCELERATION * glyph_height * seconds * seconds
		)
	)


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
	# Everything below is laid out in art pixels and multiplied up at the end,
	# so kerning lands on the same grid the glyph and its motion do. Measuring
	# advances at the full size and dividing would put digits at fractions of an
	# art pixel and undo the blow-up.
	var pixel := art_pixel()
	# Nogg Terminal is a bitmap font with fixed strikes, not a scalable one: it
	# renders the same 12 px strike for every requested size from 6 to 16, a
	# doubled strike at 24, and *nothing at all* below 6. So the size asked for
	# here is the design strike itself rather than a figure derived from the art
	# grid -- a derived one would silently render the same glyph while claiming
	# a smaller one, and a small enough one would render an invisible number.
	# The blow-up below is what sets the size on screen.
	var art_font_size := maxi(
		MIN_FONT_STRIKE, int(NoggThemeScript.FONT_SIZE_BODY_UNITS)
	)
	var advances: Array[int] = []
	var total_width := 0
	for index in range(text.length()):
		var glyph := text.substr(index, 1)
		var advance := maxi(
			1,
			ceili(_font.get_string_size(
				glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, art_font_size
			).x)
		)
		advances.append(advance)
		total_width += advance

	# The arc's unit is the glyph the art grid describes -- ART_PIXELS_PER_GLYPH
	# art pixels, which comes back to FONT_SIZE_BODY on screen -- not the font
	# strike's line box. The strike is 12 art pixels tall where its ink is 8, so
	# measuring the arc against it would throw the number half again as far.
	_glyph_height = ART_PIXELS_PER_GLYPH * pixel
	size = Vector2(float(total_width), float(art_font_size)) * pixel
	_anchor = (screen_position.round() - size * 0.5).round()
	position = _anchor

	var x := 0
	for index in range(text.length()):
		var digit := DamageGlyph.new()
		digit.name = "Digit_%d" % index
		digit.position = Vector2(float(x) * pixel, 0.0)
		digit.configure(
			_font,
			text.substr(index, 1),
			advances[index],
			art_font_size,
			front_color,
			pixel
		)
		add_child(digit)
		x += advances[index]

	return _animate(front_color)


## One linear tween over the number's own clock. Every visible property is a
## function of that clock rather than a separate tweened track, so the arc, the
## outline drop and the fade cannot fall out of step with each other.
func _animate(front_color: Color) -> Tween:
	var total := DAMAGE_VISIBLE_DURATION
	var flash_color := front_color.lightened(FLASH_LIGHTEN)
	var tween := create_tween()
	tween.tween_method(
		func(seconds: float) -> void: _applyClock(seconds, front_color, flash_color),
		0.0,
		total,
		total
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)
	return tween


## Snapped to whole art pixels before it reaches `position`. Rounding to device
## pixels was not enough: at 24 device pixels per glyph the number moved in
## 24ths of its own height, which is a glide, where the reference moves in
## eighths and visibly steps. The arc underneath is unchanged and still
## continuous -- only what is drawn from it is quantised, so the closed form
## and its probe stay exactly as they were.
func _applyClock(seconds: float, front_color: Color, flash_color: Color) -> void:
	var art := art_pixel()
	var offset := offset_at(seconds, _glyph_height)
	position = (_anchor + Vector2(
		roundf(offset.x / art) * art,
		roundf(offset.y / art) * art
	)).round()

	var flashing := seconds >= OUTLINED_DURATION
	var color := flash_color if flashing else front_color
	for child in get_children():
		var digit := child as DamageGlyph
		if digit != null:
			digit.setFlashing(flashing, color)

	if flashing:
		modulate.a = clampf(1.0 - (seconds - OUTLINED_DURATION) / FLASH_DURATION, 0.0, 1.0)
	else:
		modulate.a = 1.0
