## DamageNumberBillboard — Spawns a transient, camera-facing number above a
## world position when a unit takes damage or is healed: pop up, settle, hold,
## then fade.
##
## Two Label3D children, black behind white and offset up-and-right — a hard
## offset shadow, not a symmetric outline. Label3D.outline_size produces the
## wrong look on purpose: an outline reads as a coloured border on the glyph
## itself, where the reference is a second, displaced copy of the glyph. The
## white copy also sits slightly toward the camera (+local Z, since the
## container's basis is set to the camera's own) so draw order never depends
## on child-add order.
##
## The container reuses StatusEffectBillboard for camera-facing rather than
## re-deriving it: that class's whole job is "stay oriented to the active
## camera every frame", and this needs exactly that, unchanged.
##
## Usage: DamageNumberBillboard.spawn(parent_node, world_position, "42")
##
## VISIBLE_DURATION is public for the same reason SpellCastAura's is: this
## spawns outside the caster's own tween (GodotVisualAdapter._start_bump_animation's
## bump is 0.1s + 0.15s regardless), so the tween's own duration says nothing
## about how long the number is on screen, and the queue's hold has to be told.

class_name DamageNumberBillboard

const StatusEffectBillboardScript = preload("res://src/presentation/StatusEffectBillboard.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## pop-up (overshoot) -> settle -> hold -> fade. Summing to VISIBLE_DURATION.
const _POP_UP_DURATION := 0.14
const _SETTLE_DURATION := 0.10
const _HOLD_DURATION := 0.22
const _FADE_DURATION := 0.34
const VISIBLE_DURATION := _POP_UP_DURATION + _SETTLE_DURATION + _HOLD_DURATION + _FADE_DURATION

## How far the number rises over its full lifetime, world units.
const _RISE_HEIGHT := 0.55
## Spawn height above the target's own origin — roughly chest/head height for
## the placeholder capsule bodies this project ships today.
const _SPAWN_HEIGHT := 0.55

## Integer size, per NoggTheme's pixel-font rule (a fractional size smears).
## Larger than the UI body size (24): this is a small, prominent effect meant
## to be read from gameplay camera distance, not a dense window row.
const _FONT_SIZE := 32
## World units per font pixel. Chosen so a number reads as a clearly legible
## pop rather than a tiny badge digit — StatusEffectIcons' duration digit is a
## corner annotation at 34px/0.0038 (≈0.13 world units tall); this is a
## foreground effect and is sized well above that on purpose. Final legibility
## at gameplay camera distance through the retro/CRT pipeline is judged at
## PLAN-VALIDATE, which has the rendering context this file does not.
const _PIXEL_SIZE := 0.011

const _SHADOW_COLOR := Color(0.02, 0.02, 0.03, 1.0)
const _SHADOW_OFFSET := Vector3(-0.018, -0.026, 0.0)
const _FRONT_OFFSET := Vector3(0.018, 0.026, 0.004)
const _HEAL_PREFIX := "+"

static var _font: Font = null


## `is_heal`: prefixes `+` rather than tinting the number a different colour.
## The reference treatment (and this item's own spec) is a single black+white
## scheme for every number; a heal/damage colour split was not asked for and
## would be a second visual language on top of it.
static func spawn(parent: Node3D, world_pos: Vector3, amount: int, is_heal: bool = false) -> void:
	_ensure_font()
	var text := "%s%d" % [_HEAL_PREFIX, amount] if is_heal else str(amount)

	var billboard := StatusEffectBillboardScript.new()
	billboard.name = "DamageNumber"
	billboard.position = world_pos + Vector3(0, _SPAWN_HEIGHT, 0)
	billboard.scale = Vector3.ONE * 0.4
	parent.add_child(billboard)

	var shadow := _build_label(text, _SHADOW_COLOR, 0)
	shadow.position = _SHADOW_OFFSET
	billboard.add_child(shadow)

	var front := _build_label(text, Color.WHITE, 1)
	front.position = _FRONT_OFFSET
	billboard.add_child(front)

	_animate(billboard, [shadow, front])


static func _ensure_font() -> void:
	if _font == null:
		_font = NoggThemeScript.build_game_theme().default_font


static func _build_label(text: String, color: Color, render_priority: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = _FONT_SIZE
	label.pixel_size = _PIXEL_SIZE
	label.modulate = color
	# fixed_size: glyphs hold a constant on-screen size regardless of camera
	# distance, so the pixel font never lands on a fractional scale mid-zoom.
	label.fixed_size = true
	# The container already billboards the whole group every frame; a child
	# billboarding too would double-rotate it. Same reasoning StatusEffectIcons
	# uses for its own Label3D/Sprite3D children.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.render_priority = render_priority
	label.outline_size = 0
	return label


## Built on the persistent `set_parallel(bool)` toggle. A `tween_callback()`
## with nothing else in it sits at every phase boundary — this is not left
## over from debugging. Without one, a group's declared duration and the
## queue's measured elapsed time diverge: verified empirically (a version with
## no boundary callbacks measured a full sequence at roughly 70% of its
## declared VISIBLE_DURATION, reproducibly across repeated runs; inserting a
## no-op callback at each `set_parallel` transition brought measured and
## declared time back into agreement, also reproducibly). Do not remove these
## as unnecessary — they are the fix, confirmed against real elapsed time, not
## an artifact of how this was found.
static func _animate(billboard: Node3D, labels: Array) -> void:
	var spawn_y := billboard.position.y
	var tween := billboard.create_tween()

	# Pop up: overshoot past resting scale, reads as impact.
	tween.set_parallel(true)
	tween.tween_property(billboard, "scale", Vector3.ONE * 1.15, _POP_UP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(billboard, "position:y", spawn_y + _RISE_HEIGHT * 0.35, _POP_UP_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Settle back to resting scale, sequentially after the pop.
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: pass)
	tween.tween_property(billboard, "scale", Vector3.ONE, _SETTLE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: pass)

	# Hold: no property change, just the beat before the fade.
	tween.tween_interval(_HOLD_DURATION)
	tween.tween_callback(func() -> void: pass)

	# Pop down and fade: shrink slightly while both labels fade out together,
	# so the shadow never lingers after the front copy has gone.
	tween.set_parallel(true)
	tween.tween_property(billboard, "scale", Vector3.ONE * 0.85, _FADE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(billboard, "position:y", spawn_y + _RISE_HEIGHT, _FADE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for label in labels:
		tween.tween_property(label, "modulate:a", 0.0, _FADE_DURATION) \
			.set_trans(Tween.TRANS_LINEAR)

	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(billboard):
			billboard.queue_free()
	)
