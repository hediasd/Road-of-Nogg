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


## An "L" silhouette read as leg-plus-foot: the plainest shape that still
## reads as footwear rather than as a generic block.
static func _draw_boot(image: Image, color: Color) -> void:
	_fill_rect(image, 6, 2, 4, 7, color)
	_fill_rect(image, 3, 8, 2, 4, color)
	_fill_rect(image, 5, 9, 8, 3, color)


## A diagonal blade with a crossguard and hilt — the same construction
## `StatusEffectIcons._draw_sword` uses for `atk_buff`/`atk_debuff`, redrawn
## here rather than shared: the two files answer different questions (status
## vs. command) and neither should import the other over one shape.
static func _draw_sword(image: Image, color: Color) -> void:
	for offset in range(7):
		image.set_pixel(4 + offset, 10 - offset, color)
		image.set_pixel(5 + offset, 10 - offset, color)
	_fill_rect(image, 3, 10, 4, 2, color)
	_fill_rect(image, 2, 12, 3, 2, color)


## An eight-point sparkle: a cross plus four short diagonal ticks. Distinct
## from `StatusEffectIcons`'s plain plus and its `focus` glyph (a plus over a
## dark punch-out) by the diagonal ticks alone.
static func _draw_sparkle(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 3, 2, 10, color)
	_fill_rect(image, 3, 7, 10, 2, color)
	for offset in range(3):
		image.set_pixel(5 + offset, 5 + offset, color)
		image.set_pixel(10 - offset, 5 + offset, color)
		image.set_pixel(5 + offset, 10 - offset, color)
		image.set_pixel(10 - offset, 10 - offset, color)


## Two triangles narrowing to a shared neck, built as one horizontal strip per
## row rather than a filled diamond, so the waist actually pinches instead of
## reading as a bowtie.
static func _draw_hourglass(image: Image, color: Color) -> void:
	_fill_rect(image, 3, 2, 10, 1, color)
	_fill_rect(image, 4, 3, 8, 1, color)
	_fill_rect(image, 5, 4, 6, 1, color)
	_fill_rect(image, 6, 5, 4, 1, color)
	_fill_rect(image, 7, 6, 2, 1, color)
	_fill_rect(image, 7, 7, 2, 1, color)
	_fill_rect(image, 7, 8, 2, 1, color)
	_fill_rect(image, 6, 9, 4, 1, color)
	_fill_rect(image, 5, 10, 6, 1, color)
	_fill_rect(image, 4, 11, 8, 1, color)
	_fill_rect(image, 3, 12, 10, 1, color)
	_fill_rect(image, 3, 13, 10, 1, color)


## An open ring with an arrowhead at the gap — the standard "rewind" shape,
## traced as an arc of points rather than fill_rects: every other shape here is
## rectilinear, and a ring is the one silhouette a stack of rectangles cannot
## approximate without reading as a gear.
static func _draw_rewind(image: Image, color: Color) -> void:
	var center := Vector2(8.0, 8.5)
	var radius := 5.0
	# Sweep clockwise from the arrowhead's gap, stopping short of a full
	# circle so the two ends are visibly open, not just adjacent.
	for degrees in range(35, 300, 8):
		var rad := deg_to_rad(float(degrees))
		var x := int(round(center.x + cos(rad) * radius))
		var y := int(round(center.y + sin(rad) * radius))
		if x >= 1 and x < ICON_SIZE - 1 and y >= 1 and y < ICON_SIZE - 1:
			image.set_pixel(x, y, color)
			image.set_pixel(x, y - 1, color)
	# Arrowhead at the sweep's start (~35 degrees), pointing back along the arc.
	_fill_rect(image, 10, 2, 3, 2, color)
	_fill_rect(image, 12, 3, 2, 3, color)


static func _draw_plus(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 4, 2, 8, color)
	_fill_rect(image, 4, 7, 8, 2, color)
