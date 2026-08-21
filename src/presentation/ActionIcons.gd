## Drawn placeholder icons for player commands, used until authored art lands
## in `ActionIconRegistry`.
##
## **Texture source only** — mirrors `StatusEffectIcons`'s split: this file
## answers one question, what does command X look like, and nothing else.
## Layout, hover, and enabled/disabled dimming belong to whatever widget draws
## the action ring; a disabled command is drawn the same texture, modulated,
## not a second texture.
##
## Every icon is emitted at `ActionIconRegistry.SOURCE_PX` square so a drawn
## placeholder and an authored icon are interchangeable at the same size, and
## authored here on a 16-pixel grid, scaled up with nearest filtering, exactly
## like `StatusEffectIcons` — the shape vocabulary reads at 16px and rewriting
## every coordinate for a bigger canvas would risk it for no gain.
##
## One shape per command, not a shared glyph tinted differently: `move`,
## `attack`, `magic`, and `pass` must stay tellable apart at a glance, the same
## reasoning `StatusEffectIcons` gives for why its five negative effects no
## longer share one down arrow. `undo_move` gets its own shape too rather than
## reusing `move`'s rotated — the two can be on screen in the same ring slot
## at different times, never at once, so there is no cost to a second shape and
## a real one reads faster than a mirrored one.

class_name ActionIcons
extends RefCounted

const ActionIconRegistryScript = preload("res://src/presentation/ActionIconRegistry.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const ICON_SIZE := 16

## Reuses the shipped window body and accent tokens rather than inventing a
## new hue: the ring sits over the board, not inside a window, but it should
## still read as part of the same chrome language.
const BACKGROUND := Color(0.004, 0.004, 0.008, 0.94)
const FOREGROUND := Color(1.0, 0.843, 0.400)

## Cached per action id. Five shapes total; nothing here changes per monster
## or per turn, so rasterising them more than once is pure waste.
static var _cache: Dictionary = {}


## The icon for a command: authored art when registered, a drawn placeholder
## otherwise. Callers do not need to know which they got.
static func texture_for(action_id: String) -> Texture2D:
	var authored := ActionIconRegistryScript.texture_for(action_id)
	if authored != null:
		return authored
	return placeholder_for(action_id)


static func placeholder_for(action_id: String) -> Texture2D:
	var key := action_id.to_lower()
	if _cache.has(key):
		return _cache[key]
	var texture := _render(key)
	_cache[key] = texture
	return texture


static func _render(action_id: String) -> ImageTexture:
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(BACKGROUND)
	_draw_border(image, FOREGROUND)
	match action_id:
		"move": _draw_boot(image, FOREGROUND)
		"undo_move": _draw_rewind(image, FOREGROUND)
		"attack": _draw_sword(image, FOREGROUND)
		"magic": _draw_sparkle(image, FOREGROUND)
		"pass": _draw_hourglass(image, FOREGROUND)
		_: _draw_plus(image, FOREGROUND)
	# Nearest, not bilinear: hard-edged pixel shapes, and any smoothing turns a
	# one-pixel stroke into grey mush at this size.
	image.resize(
		ActionIconRegistryScript.SOURCE_PX,
		ActionIconRegistryScript.SOURCE_PX,
		Image.INTERPOLATE_NEAREST
	)
	return ImageTexture.create_from_image(image)


static func _draw_border(image: Image, color: Color) -> void:
	for pixel in range(ICON_SIZE):
		image.set_pixel(pixel, 0, color)
		image.set_pixel(pixel, ICON_SIZE - 1, color)
		image.set_pixel(0, pixel, color)
		image.set_pixel(ICON_SIZE - 1, pixel, color)


static func _fill_rect(image: Image, left: int, top: int, width: int, height: int, color: Color) -> void:
	for y in range(top, top + height):
		for x in range(left, left + width):
			if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
				image.set_pixel(x, y, color)


## A boot in profile, facing right: a narrow shaft with the foot extending to
## one side only.
##
## The asymmetry is the entire read. A vertical bar centred on a horizontal one
## is a hammer, and a bar with a wide cap at both ends is an anvil -- the first
## two drafts were each of those in turn. Shaft flush with the heel, toe
## overhanging forward, one corner clipped so the toe is not a square.
static func _draw_boot(image: Image, color: Color) -> void:
	_fill_rect(image, 4, 2, 4, 9, color)
	_fill_rect(image, 4, 11, 9, 3, color)
	# Clip the toe's upper corner so the foot tapers instead of ending square.
	image.set_pixel(12, 11, BACKGROUND)
	# Cuff seam. Without it the silhouette is exactly the letter L; one dark
	# row across the shaft is the cheapest thing that makes it read as footwear.
	_fill_rect(image, 4, 4, 4, 1, BACKGROUND)


## A blade on the up-right diagonal with a crossguard perpendicular to it, a
## short grip, and a pommel.
##
## The guard runs down-right specifically because it must cross the blade at a
## right angle: drawn axis-aligned it reads as a bracket stuck to the side of a
## line. It is kept short -- four pixels -- because a long one reads as a
## second blade and turns the glyph into a pair of scissors.
##
## Diagonal is also the point of the silhouette: it is the only shape here that
## is neither a box nor built on the centre cross, so it cannot be confused
## with the magic star at a glance.
static func _draw_sword(image: Image, color: Color) -> void:
	# Stepped 2x2 blocks, not a one-pixel trace: at 45 degrees a single-pixel
	# line is only ~0.7px thick perpendicular, which survives the 4x zoom but
	# disappears into a scratch at the native 32px the ring actually draws.
	for offset in range(9):
		_fill_rect(image, 3 + offset, 10 - offset, 2, 2, color)
	# Guard: two pixels thick, or it reads as a check mark rather than a bar.
	for offset in range(5):
		image.set_pixel(3 + offset, 7 + offset, color)
		image.set_pixel(3 + offset, 8 + offset, color)
	# Pommel, on the blade axis below the guard, joined to it by the grip.
	_fill_rect(image, 1, 12, 3, 2, color)


## A four-point star with concave flanks.
##
## Concave is the whole difference from a plus: each arm tapers to two pixels
## instead of ending square, which is what separates this from
## `StatusEffectIcons`'s `plus` and `focus` glyphs. Both axes taper through the
## same width ladder, so the star is balanced -- an earlier draft tapered only
## the vertical and read as a horizontal bar with a stub on top.
static func _draw_sparkle(image: Image, color: Color) -> void:
	var widths := [2, 2, 4, 4, 6, 12, 12, 6, 4, 4, 2, 2]
	for index in range(widths.size()):
		var width: int = widths[index]
		_fill_rect(image, 8 - width / 2, 2 + index, width, 1, color)


## An open ring with a triangular head at the gap.
##
## Filled as an annulus -- a distance test per pixel -- rather than traced as a
## parametric arc. Tracing a circle this small lands successive points on the
## same pixel and then skips one, so the stroke comes out visibly dotted no
## matter how fine the angular step; testing every pixel against a radius band
## gives a solid stroke by construction.
##
## The head is a real triangle. Two overlapping rectangles read as a lump
## welded to the ring, and an arrowhead is the only thing distinguishing "undo"
## from a letter C.
static func _draw_rewind(image: Image, color: Color) -> void:
	var center := Vector2(7.5, 8.5)
	for y in range(1, ICON_SIZE - 1):
		for x in range(1, ICON_SIZE - 1):
			var offset := Vector2(float(x), float(y)) - center
			var distance := offset.length()
			if distance < 3.2 or distance > 5.4:
				continue
			# Leave the upper-left quadrant open for the head.
			if offset.x < 0.0 and offset.y < 0.0:
				continue
			image.set_pixel(x, y, color)
	# Head at the ring's top end, pointing LEFT along the tangent. Direction is
	# not decoration: an arrow sweeping clockwise is the redo glyph, and this
	# slot is undo.
	var head := [2, 3, 4, 3, 2]
	for index in range(head.size()):
		_fill_rect(image, 8 - head[index], 2 + index, head[index], 1, color)


## Two triangles narrowing to a shared neck, one horizontal strip per row so
## the waist actually pinches instead of reading as a bowtie. Symmetric top to
## bottom -- the first draft carried an extra row on the bottom cap, which
## tilted the whole glyph.
static func _draw_hourglass(image: Image, color: Color) -> void:
	var widths := [10, 8, 6, 4, 2, 2, 4, 6, 8, 10]
	for index in range(widths.size()):
		var width: int = widths[index]
		_fill_rect(image, 8 - width / 2, 3 + index, width, 1, color)
	# Caps, overhanging the sand so the glyph reads as a framed vessel.
	_fill_rect(image, 2, 2, 12, 1, color)
	_fill_rect(image, 2, 13, 12, 1, color)


static func _draw_plus(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 4, 2, 8, color)
	_fill_rect(image, 4, 7, 8, 2, color)
