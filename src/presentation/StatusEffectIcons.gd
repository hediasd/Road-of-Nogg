## Drawn placeholder icons for status effects, used until authored art lands in
## `StatusIconRegistry`.
##
## **Texture source only.** Row layout, positioning and hover live in
## `StatusBadgeRow`; this file answers one question — what does effect X look
## like — and nothing else.
##
## Every icon is emitted at `StatusIconRegistry.SOURCE_PX` square so a drawn
## placeholder and an authored icon are interchangeable at the same size. Shapes
## are still authored on the original 16-pixel grid and scaled up with nearest
## filtering, because the shape vocabulary was tuned at that size and rewriting
## every coordinate would risk it for no gain.
##
## **Each of the five negative effects has its own silhouette.** Previously
## `burn`, `poison`, `petrify` and `chill` all rendered as one down arrow, and
## the shield served `guard`, `def_buff` and `def_debuff` alike — four effects
## with entirely different consequences looked identical, and colour separated
## only buff from debuff. Shape is now the primary channel and the buff/debuff
## colour split is the redundant one, which is the correct way round: colour
## alone fails for a colour-blind player and fails again over a bright board.

class_name StatusEffectIcons
extends RefCounted

const StatusIconRegistryScript = preload("res://src/presentation/StatusIconRegistry.gd")

const ICON_SIZE := 16
const BUFF_BACKGROUND := Color(0.05, 0.19, 0.34, 0.94)
const BUFF_FOREGROUND := Color(0.42, 0.78, 1.0, 1.0)
const DEBUFF_BACKGROUND := Color(0.35, 0.04, 0.13, 0.94)
const DEBUFF_FOREGROUND := Color(1.0, 0.38, 0.54, 1.0)
const OVERFLOW_BACKGROUND := Color(0.11, 0.11, 0.16, 0.94)
const OVERFLOW_FOREGROUND := Color(0.92, 0.92, 0.98, 1.0)

## Cached per shape/colour combination. A row rebuild is cheap only if it is not
## rasterising the same handful of icons every time an effect ticks.
static var _cache: Dictionary = {}


## The icon for an effect: authored art when registered, a drawn placeholder
## otherwise. Callers do not need to know which they got.
static func texture_for(effect: Dictionary) -> Texture2D:
	var effect_name := str(effect.get("name", ""))
	var authored := StatusIconRegistryScript.texture_for(effect_name)
	if authored != null:
		return authored
	return placeholder_for(effect_name, bool(effect.get("negative", false)))


static func overflow_texture() -> Texture2D:
	return _cached("overflow", OVERFLOW_BACKGROUND, OVERFLOW_FOREGROUND)


static func placeholder_for(effect_name: String, negative_hint: bool) -> Texture2D:
	var info := _style_for(effect_name, negative_hint)
	return _cached(str(info["shape"]), info["background"], info["foreground"])


static func _cached(shape: String, background: Color, foreground: Color) -> Texture2D:
	var key := "%s|%s|%s" % [shape, background, foreground]
	if _cache.has(key):
		return _cache[key]
	var texture := _render(shape, background, foreground)
	_cache[key] = texture
	return texture


static func _render(shape: String, background: Color, foreground: Color) -> ImageTexture:
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(background)
	_draw_border(image, foreground)
	match shape:
		"shield": _draw_shield(image, foreground)
		"focus": _draw_focus(image, foreground)
		"up": _draw_arrow(image, foreground, true)
		"down": _draw_arrow(image, foreground, false)
		"speed": _draw_speed(image, foreground)
		"move": _draw_move(image, foreground)
		"sword": _draw_sword(image, foreground)
		"flame": _draw_flame(image, foreground)
		"droplet": _draw_droplet(image, foreground)
		"crack": _draw_crack(image, foreground)
		"snowflake": _draw_snowflake(image, foreground)
		_: _draw_plus(image, foreground)
	# Nearest, not bilinear: these are hard-edged pixel shapes and any smoothing
	# turns a one-pixel stroke into grey mush at this size.
	image.resize(
		StatusIconRegistryScript.SOURCE_PX,
		StatusIconRegistryScript.SOURCE_PX,
		Image.INTERPOLATE_NEAREST
	)
	return ImageTexture.create_from_image(image)


## Effects in display order: most urgent first, ties broken by name so a row
## never reorders itself between frames for no reason.
static func sorted_effects(effects: Array) -> Array:
	var ordered: Array = []
	for effect in effects:
		if effect is Dictionary:
			ordered.append(effect)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a = _priority(a)
		var priority_b = _priority(b)
		if priority_a == priority_b:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return priority_a > priority_b
	)
	return ordered


static func _priority(effect: Dictionary) -> int:
	var effect_name = str(effect.get("name", "")).to_lower()
	if bool(effect.get("negative", false)) or effect_name in ["burn", "poison", "petrify", "chill", "spd_debuff"]:
		return 30
	if effect_name in ["guard", "focus"]:
		return 20
	return 10


static func _style_for(effect_name: String, negative_hint: bool) -> Dictionary:
	match effect_name.to_lower():
		"guard": return _buff("shield")
		"focus": return _buff("focus")
		"atk_buff": return _buff("sword")
		"def_buff": return _buff("up")
		"spd_buff": return _buff("speed")
		"move_buff": return _buff("move")
		"atk_debuff": return _debuff("sword")
		"def_debuff": return _debuff("down")
		"spd_debuff": return _debuff("speed")
		"move_debuff": return _debuff("move")
		"burn": return _debuff("flame")
		"poison": return _debuff("droplet")
		"petrify": return _debuff("crack")
		"chill": return _debuff("snowflake")
		_: return _debuff("down") if negative_hint else _buff("plus")


static func _buff(shape: String) -> Dictionary:
	return {"shape": shape, "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}


static func _debuff(shape: String) -> Dictionary:
	return {"shape": shape, "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}


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


static func _draw_shield(image: Image, color: Color) -> void:
	_fill_rect(image, 5, 3, 6, 7, color)
	_fill_rect(image, 6, 10, 4, 2, color)
	_fill_rect(image, 7, 12, 2, 1, color)


static func _draw_focus(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 3, 2, 10, color)
	_fill_rect(image, 3, 7, 10, 2, color)
	_fill_rect(image, 6, 6, 4, 4, Color(0.05, 0.05, 0.05, 0.94))
	_fill_rect(image, 7, 7, 2, 2, color)


static func _draw_arrow(image: Image, color: Color, upwards: bool) -> void:
	if upwards:
		_fill_rect(image, 7, 3, 2, 10, color)
		_fill_rect(image, 5, 5, 6, 2, color)
		_fill_rect(image, 6, 4, 4, 2, color)
	else:
		_fill_rect(image, 7, 3, 2, 10, color)
		_fill_rect(image, 5, 9, 6, 2, color)
		_fill_rect(image, 6, 10, 4, 2, color)


static func _draw_speed(image: Image, color: Color) -> void:
	_fill_rect(image, 3, 4, 7, 2, color)
	_fill_rect(image, 5, 7, 7, 2, color)
	_fill_rect(image, 3, 10, 7, 2, color)
	_fill_rect(image, 10, 6, 2, 4, color)


static func _draw_move(image: Image, color: Color) -> void:
	_fill_rect(image, 4, 8, 7, 2, color)
	_fill_rect(image, 9, 6, 2, 6, color)
	_fill_rect(image, 10, 7, 2, 4, color)


static func _draw_sword(image: Image, color: Color) -> void:
	for offset in range(7):
		image.set_pixel(4 + offset, 10 - offset, color)
		image.set_pixel(5 + offset, 10 - offset, color)
	_fill_rect(image, 3, 10, 4, 2, color)
	_fill_rect(image, 2, 12, 3, 2, color)


static func _draw_plus(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 4, 2, 8, color)
	_fill_rect(image, 4, 7, 8, 2, color)


## Tapered body with a notched top, so it reads as fire rather than as a leaf.
static func _draw_flame(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 3, 2, 3, color)
	_fill_rect(image, 6, 5, 4, 3, color)
	_fill_rect(image, 5, 8, 6, 4, color)
	_fill_rect(image, 6, 12, 4, 1, color)
	_fill_rect(image, 7, 8, 2, 3, image.get_pixel(1, 1))


## Round-bottomed drop with a pointed top — deliberately the inverse taper of
## the flame, so the two never read as the same silhouette.
static func _draw_droplet(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 3, 2, 2, color)
	_fill_rect(image, 6, 5, 4, 2, color)
	_fill_rect(image, 5, 7, 6, 4, color)
	_fill_rect(image, 6, 11, 4, 1, color)


## A solid block split by a jagged seam.
static func _draw_crack(image: Image, color: Color) -> void:
	_fill_rect(image, 4, 4, 8, 8, color)
	var seam := image.get_pixel(1, 1)
	_fill_rect(image, 7, 4, 1, 2, seam)
	_fill_rect(image, 8, 6, 1, 2, seam)
	_fill_rect(image, 7, 8, 1, 2, seam)
	_fill_rect(image, 8, 10, 1, 2, seam)


## Three crossed axes. Sparse on purpose: at 16 pixels a six-armed flake with
## barbs fills in solid and stops being a flake at all.
static func _draw_snowflake(image: Image, color: Color) -> void:
	_fill_rect(image, 7, 3, 2, 10, color)
	_fill_rect(image, 3, 7, 10, 2, color)
	for offset in range(5):
		image.set_pixel(4 + offset, 4 + offset, color)
		image.set_pixel(11 - offset, 4 + offset, color)
