## DamageNumberBillboard — A pixel-perfect, camera-facing number that appears
## directly above a unit when it takes damage or is healed.
##
## Two treatments, deliberately different in feel:
##
##   Damage — white on a hard black offset shadow. Appears instantly at full
##            size (no pop, no grow-in), holds a beat, then arcs away from the
##            camera while shrinking and fading, like it is thrown back over
##            the unit's shoulder.
##   Heal   — light green. Appears the same way, then simply drifts straight up
##            and fades out, slowly. No arc and no shrink: a heal should read as
##            calm where a hit reads as impact.
##
## The shadow is a second, displaced copy of the glyph, not `Label3D.outline_size`.
## An outline draws a border around the glyph's own edge, which is a different
## look entirely and softens the pixel edges this is trying to keep crisp.
##
## Pixel-perfect: `texture_filter` is NEAREST and the font size is an integer,
## per NoggTheme's rule that a pixel font at a fractional size smears.
##
## The container reuses StatusEffectBillboard for camera-facing rather than
## re-deriving it — that class's whole job is "stay oriented to the active
## camera every frame", which is exactly what this needs.
##
## `spawn()` returns its own Tween so a caller that needs the number to occupy
## the animation queue can hand the queue the real animation rather than a
## stand-in tween with nothing in it. A cleanup timer independent of that tween
## guarantees the node is freed even if the tween is killed mid-flight by a
## player-requested skip — the same belt-and-braces `SpellCastAura` uses.

class_name DamageNumberBillboard

const StatusEffectBillboardScript = preload("res://src/presentation/StatusEffectBillboard.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Damage: a beat at rest, then the arc away. Heal: one slow drift, no hold —
## it starts moving immediately because the motion itself is the soothing part.
const _DAMAGE_HOLD := 0.10
const _DAMAGE_ARC := 0.46
const _HEAL_DRIFT := 0.95

const DAMAGE_VISIBLE_DURATION := _DAMAGE_HOLD + _DAMAGE_ARC
const HEAL_VISIBLE_DURATION := _HEAL_DRIFT

## Margin past the animation before the fallback cleanup timer fires. Only ever
## reached when the tween was killed early (skip); on a normal run the tween's
## own final callback frees the node first and this finds nothing to do.
const _CLEANUP_MARGIN := 0.5

## Height above the unit's origin the number appears at — clear of the
## placeholder bodies' heads without floating free of them.
const _SPAWN_HEIGHT := 0.85

## Damage arc: up, and away from the camera, while shrinking.
const _DAMAGE_RISE := 0.30
const _DAMAGE_PUSH_BACK := 0.55
const _DAMAGE_END_SCALE := 0.45
## Heal drift: straight up, no horizontal motion, no shrink.
const _HEAL_RISE := 0.75

## Integer size per NoggTheme's pixel-font rule. Matches the UI body size
## rather than exceeding it: this sits over a model at gameplay camera
## distance, where oversized digits crowd the board they are annotating.
const _FONT_SIZE := 24
## World units per font pixel, with `fixed_size` on so this reads as a constant
## on-screen size rather than growing as the camera nears.
const _PIXEL_SIZE := 0.0065

const _DAMAGE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
## Light green, kept bright enough to stay legible against the board's own
## greens rather than sinking into them.
const _HEAL_COLOR := Color(0.62, 1.0, 0.65, 1.0)
const _SHADOW_COLOR := Color(0.03, 0.03, 0.05, 1.0)
## One pixel down-right at the shipping size, so the shadow reads as a hard
## offset rather than a blur.
const _SHADOW_OFFSET := Vector3(0.012, -0.012, -0.002)

static var _font: Font = null


## Returns the Tween driving the number, so a caller can let the animation
## queue track this animation directly. Safe to ignore.
static func spawn(
		parent: Node3D,
		world_pos: Vector3,
		amount: int,
		is_heal: bool = false) -> Tween:
	_ensure_font()

	var billboard := StatusEffectBillboardScript.new()
	billboard.name = "DamageNumber"
	billboard.position = world_pos + Vector3(0, _SPAWN_HEIGHT, 0)
	parent.add_child(billboard)

	var text := "+%d" % amount if is_heal else str(amount)
	var tint: Color = _HEAL_COLOR if is_heal else _DAMAGE_COLOR
	# Shadow first so the tinted copy draws over it.
	var shadow := _build_label(text, _SHADOW_COLOR, 0)
	shadow.position = _SHADOW_OFFSET
	billboard.add_child(shadow)
	var front := _build_label(text, tint, 1)
	billboard.add_child(front)

	var tween := (
		_animate_heal(billboard, [shadow, front]) if is_heal
		else _animate_damage(billboard, [shadow, front])
	)

	# Fallback cleanup, generous on purpose. The tween frees the node itself on
	# a normal run; this only matters when the tween was killed early. It must
	# never beat a tween that is merely running slowly — `_activateScaled`
	# speed-scales these, and the slowest setting is 0.25x, so the margin has to
	# clear four times the declared duration or the timer would free the node
	# out from under a healthy animation and strand whatever is waiting on it.
	var tree := billboard.get_tree()
	if tree != null:
		var lifetime := visible_duration(is_heal)
		tree.create_timer(lifetime * 5.0 + _CLEANUP_MARGIN).timeout.connect(
			func() -> void:
				if is_instance_valid(billboard):
					billboard.queue_free()
		)
	return tween


static func visible_duration(is_heal: bool) -> float:
	return HEAL_VISIBLE_DURATION if is_heal else DAMAGE_VISIBLE_DURATION


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
	label.fixed_size = true
	# NEAREST, not the default linear filter: this is a pixel font and any
	# smoothing on the glyph edges is exactly what "pixel-perfect" excludes.
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# The container billboards the whole group once per frame; a child
	# billboarding as well would rotate it twice. Same reasoning
	# StatusEffectIcons uses for its own Label3D children.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.render_priority = render_priority
	label.outline_size = 0
	label.no_depth_test = true
	return label


## Appears at rest, holds, then arcs away from the camera while shrinking and
## fading. The rise eases out and the push-back eases in, which is what bends
## the path into an arc rather than a straight diagonal.
static func _animate_damage(billboard: Node3D, labels: Array) -> Tween:
	var start := billboard.position
	var away := _away_from_camera(billboard)
	var apex := start + Vector3.UP * _DAMAGE_RISE + away * (_DAMAGE_PUSH_BACK * 0.45)
	var target := start + Vector3.UP * (_DAMAGE_RISE * 0.35) + away * _DAMAGE_PUSH_BACK

	var tween := billboard.create_tween()
	tween.tween_interval(_DAMAGE_HOLD)

	tween.set_parallel(true)
	tween.tween_property(billboard, "position", apex, _DAMAGE_ARC * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(billboard, "scale", Vector3.ONE * 0.8, _DAMAGE_ARC * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.set_parallel(false)
	tween.tween_property(billboard, "position", target, _DAMAGE_ARC * 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.set_parallel(true)
	tween.tween_property(billboard, "scale", Vector3.ONE * _DAMAGE_END_SCALE, _DAMAGE_ARC * 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for label in labels:
		tween.tween_property(label, "modulate:a", 0.0, _DAMAGE_ARC * 0.55) \
			.set_trans(Tween.TRANS_LINEAR)

	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(billboard):
			billboard.queue_free()
	)
	return tween


## Straight up, slowly, fading the whole way. No arc and no shrink — the point
## is that a heal reads as calm next to damage's impact.
static func _animate_heal(billboard: Node3D, labels: Array) -> Tween:
	var target := billboard.position + Vector3.UP * _HEAL_RISE

	var tween := billboard.create_tween()
	tween.set_parallel(true)
	tween.tween_property(billboard, "position", target, _HEAL_DRIFT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Fade held off until the drift is underway, so the number is readable
	# before it starts leaving rather than dimming from the first frame.
	for label in labels:
		tween.tween_property(label, "modulate:a", 0.0, _HEAL_DRIFT * 0.62) \
			.set_delay(_HEAL_DRIFT * 0.38).set_trans(Tween.TRANS_SINE)

	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(billboard):
			billboard.queue_free()
	)
	return tween


## Horizontal direction pointing away from the viewer, so the damage arc
## recedes rather than sliding sideways. Flattened to the ground plane: the
## rise is applied separately, and leaving the camera's pitch in would fight
## it. Falls back to a fixed direction when there is no camera (headless).
static func _away_from_camera(node: Node3D) -> Vector3:
	var viewport := node.get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return Vector3.FORWARD
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()
