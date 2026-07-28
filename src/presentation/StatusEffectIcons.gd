## Compact, billboarded status badges used by the Godot battle presentation.
## Gameplay owns effect data; this class only translates the current data into
## small readable visuals that follow each monster model.

class_name StatusEffectIcons
extends RefCounted

const ROW_NAME := "StatusEffectIcons"
const StatusEffectBillboardScript = preload("res://src/presentation/StatusEffectBillboard.gd")
const MAX_VISIBLE_ICONS := 4
const ICON_SIZE := 16
const BADGE_PIXEL_SIZE := 0.019
const BADGE_SPACING := 0.35
const BUFF_BACKGROUND := Color(0.05, 0.19, 0.34, 0.94)
const BUFF_FOREGROUND := Color(0.42, 0.78, 1.0, 1.0)
const DEBUFF_BACKGROUND := Color(0.35, 0.04, 0.13, 0.94)
const DEBUFF_FOREGROUND := Color(1.0, 0.38, 0.54, 1.0)

static func create_or_update(container: Node3D, effects: Array, anchor_y: float) -> void:
	var row = container.get_node_or_null(NodePath(ROW_NAME)) as Node3D
	if row == null:
		row = StatusEffectBillboardScript.new()
		row.name = ROW_NAME
		container.add_child(row)
	row.position = Vector3(0.0, anchor_y, 0.0)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var has_overflow = effects.size() > MAX_VISIBLE_ICONS
	var display_count = MAX_VISIBLE_ICONS - 1 if has_overflow else MAX_VISIBLE_ICONS
	var display_effects = _display_effects(effects, display_count)
	var slot_count = MAX_VISIBLE_ICONS if has_overflow else display_effects.size()
	for index in range(display_effects.size()):
		var effect: Dictionary = display_effects[index]
		var badge = _make_badge(effect, false)
		badge.position.x = (float(index) - (float(slot_count - 1) * 0.5)) * BADGE_SPACING
		row.add_child(badge)
	if has_overflow:
		var hidden_count = effects.size() - display_effects.size()
		var overflow = _make_badge({"name": "overflow", "remainingTurns": hidden_count}, true)
		overflow.position.x = (float(slot_count - 1) - (float(slot_count - 1) * 0.5)) * BADGE_SPACING
		row.add_child(overflow)


static func clear(container: Node3D) -> void:
	var row = container.get_node_or_null(NodePath(ROW_NAME))
	if row != null:
		row.queue_free()


static func _display_effects(effects: Array, maximum: int) -> Array:
	var sorted_effects: Array = []
	for effect in effects:
		if effect is Dictionary:
			sorted_effects.append(effect)
	sorted_effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a = _priority(a)
		var priority_b = _priority(b)
		if priority_a == priority_b:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return priority_a > priority_b
	)
	return sorted_effects.slice(0, maximum)


static func _priority(effect: Dictionary) -> int:
	var effect_name = str(effect.get("name", "")).to_lower()
	if bool(effect.get("negative", false)) or effect_name in ["burn", "poison", "petrify", "chill", "spd_debuff"]:
		return 30
	if effect_name in ["guard", "focus"]:
		return 20
	return 10


static func _make_badge(effect: Dictionary, is_overflow: bool) -> Node3D:
	var badge = Node3D.new()
	badge.name = "Badge_%s" % str(effect.get("name", "unknown"))
	var sprite = Sprite3D.new()
	sprite.name = "Icon"
	sprite.texture = _texture_for(effect, is_overflow)
	sprite.pixel_size = BADGE_PIXEL_SIZE
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# The parent row billboards the complete badge group. Child planes inherit one shared orientation.
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.render_priority = 1
	badge.add_child(sprite)
	var duration = int(effect.get("remainingTurns", 0))
	if duration > 0:
		var label = Label3D.new()
		label.name = "Duration"
		label.text = str(duration)
		label.font_size = 34
		label.outline_size = 5
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0.03, 0.03, 0.05, 1.0)
		label.pixel_size = 0.0038
		label.position = Vector3(0.105, -0.09, 0.005)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.render_priority = 2
		badge.add_child(label)
	return badge


static func _texture_for(effect: Dictionary, is_overflow: bool) -> ImageTexture:
	var image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var info = _style_for(effect, is_overflow)
	var background: Color = info["background"]
	var foreground: Color = info["foreground"]
	image.fill(background)
	_draw_border(image, foreground)
	match str(info["shape"]):
		"shield": _draw_shield(image, foreground)
		"focus": _draw_focus(image, foreground)
		"up": _draw_arrow(image, foreground, true)
		"down": _draw_arrow(image, foreground, false)
		"speed": _draw_speed(image, foreground)
		"move": _draw_move(image, foreground)
		"sword": _draw_sword(image, foreground)
		_: _draw_plus(image, foreground)
	return ImageTexture.create_from_image(image)


static func _style_for(effect: Dictionary, is_overflow: bool) -> Dictionary:
	if is_overflow:
		return {"shape": "plus", "background": Color(0.11, 0.11, 0.16, 0.94), "foreground": Color(0.92, 0.92, 0.98, 1.0)}
	var effect_name = str(effect.get("name", "")).to_lower()
	match effect_name:
		"guard": return {"shape": "shield", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"focus": return {"shape": "focus", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"atk_buff": return {"shape": "sword", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"def_buff": return {"shape": "shield", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"spd_buff": return {"shape": "speed", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"move_buff": return {"shape": "move", "background": BUFF_BACKGROUND, "foreground": BUFF_FOREGROUND}
		"atk_debuff": return {"shape": "sword", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}
		"def_debuff": return {"shape": "shield", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}
		"spd_debuff": return {"shape": "speed", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}
		"move_debuff": return {"shape": "move", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}
		"burn", "poison", "petrify", "chill": return {"shape": "down", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}
		_: return {"shape": "down", "background": DEBUFF_BACKGROUND, "foreground": DEBUFF_FOREGROUND}

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
