## The one playback every cube placeholder profile runs on.
##
## A profile is a `CubePlaceholderComposition` (the choreography); this owns
## everything a composition should not have to: the `VfxPlayback` lifecycle,
## the timeline and its range warp, the anchors a spell's spec asks for, the
## palettes, and the renderer.
##
## RENDERING. Every cube of a playback is one instance of one `MultiMesh`: a
## unit quad billboarded in the shader, textured from a nearest-filtered atlas
## of twelve quarter-turn frames across and one palette row per element down.
## One node, one draw call, however many cubes, elements or anchors. Cubes are
## opaque with an alpha cut, so depth sorts them against each other and the
## world with no alpha ordering to get wrong; the rare faded cube is dithered.
## Several elements cost nothing extra because a cube picks its palette row per
## instance. This is why the substrate's budget (four nodes, four draw calls)
## is a ceiling it never approaches rather than a target.
##
## RESOURCES ARE PER PLAYBACK. The shader, material, atlas, quad and multimesh
## are built for each playback and freed with it. A static cache would save a
## few milliseconds per cast and cost what `VfxTextures`' unreleased static
## cache costs today: a crash at engine exit that keeps a probe from gating.
##
## PREPARATION IS SEPARATE FROM SAMPLING. Everything that allocates — atlas,
## multimesh, frames, pose buffer — happens in `_prepare()`, which runs on
## `play()` (and on a seek before any play) once cast context, footprint, spec
## and facing are known. Sampling then only writes into what exists.
##
## TIME. Compositions are authored on the sketch's 0-1 timeline. A spec with
## `RANGE_SCALING: travel` stretches the composition's travel beats by the
## range factor; the playback's normalized time is warped onto sketch time
## piecewise-linearly, so at the reference distance the warp is the identity
## and every beat boundary is exactly the sketch's.

class_name CubePlaceholderEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Atlas = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderAtlas.gd")
const Frame = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderFrame.gd")
const PoseBuffer = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderPoseBuffer.gd")
const Composition = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")

## Floats per multimesh instance: a 3x4 transform, then four custom channels.
const _FLOATS_PER_INSTANCE := 16
const _RENDER_AABB := AABB(Vector3(-64.0, -16.0, -64.0), Vector3(128.0, 64.0, 128.0))
## Billboarded, unshaded, alpha-cut pixel cube. Custom channels: frame, palette
## row, opacity (dithered), each encoded so an 8-bit channel decodes it too.
const _SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float frame_count = 12.0;
uniform float palette_rows = 1.0;

varying vec2 atlas_uv;
varying float fade;

const float BAYER[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

void vertex() {
	float edge = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(edge, 0.0, 0.0, 0.0), vec4(0.0, edge, 0.0, 0.0),
		vec4(0.0, 0.0, edge, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float frame = floor(INSTANCE_CUSTOM.r * frame_count);
	float row = floor(INSTANCE_CUSTOM.g * palette_rows);
	atlas_uv = vec2((UV.x + frame) / frame_count, (UV.y + row) / palette_rows);
	fade = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec4 texel = texture(atlas, atlas_uv);
	if (texel.a < 0.5) {
		discard;
	}
	if (fade < 0.999) {
		int ix = int(mod(FRAGCOORD.x, 4.0));
		int iy = int(mod(FRAGCOORD.y, 4.0));
		if (fade < (BAYER[ix + iy * 4] + 0.5) / 16.0) {
			discard;
		}
	}
	ALBEDO = texel.rgb;
}
"""

var _composition: Composition
var _elementColor := Color.WHITE
var _context: VfxCastContext = null
var _footprint: HexVfxFootprint = null
var _spec: Spec = null
var _sourceFront := Vector3.ZERO
var _targetFronts: Array[Vector3] = []

var _frames: Array = []
var _buffer: PoseBuffer = PoseBuffer.new()
var _roleVisible: Array[bool] = []
var _paletteKeys: Array[String] = []
var _paletteCount := 1
var _capacity := 0
var _instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _atlasTexture: ImageTexture
var _floats := PackedFloat32Array()
var _written := 0
var _dirty := true

## Travel stretch this playback prepared with, and its warp: `_sketchBreaks[i]`
## maps to `_warpBreaks[i]` (both 0-1), linear in between.
var _rangeStretch := 1.0
var _sketchBreaks := PackedFloat32Array([0.0, 1.0])
var _warpBreaks := PackedFloat32Array([0.0, 1.0])

var _elapsedTime := 0.0
var _baseDuration := 0.0
var _totalDuration := 0.0
var _playbackScale := 1.0
var _activeSeed := 0
var _activeMode := MODE_BATTLE
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false


## The generic factory every catalog row binds its composition script to:
## `Callable(CubePlaceholderEffect, "create").bind(CompositionScript)`.
static func create(
		parent: Node3D,
		worldPosition: Vector3,
		elementColor: Color,
		overrides: Dictionary,
		compositionScript: Script) -> CubePlaceholderEffect:
	var playback := CubePlaceholderEffect.new()
	playback._composition = compositionScript.new()
	playback.name = "Cube_%s" % playback._composition.profileID()
	playback._elementColor = elementColor
	playback._totalDuration = playback._composition.battleDurationSeconds()
	for _role: String in playback._composition.roles():
		playback._roleVisible.append(true)
	parent.add_child(playback)
	playback.global_position = worldPosition
	playback.set_tunable_overrides(overrides)
	return playback


func configure_cast_context(context: VfxCastContext) -> void:
	_context = context
	_dirty = true


## The battle's resolved cells, empty ones included. Same signature
## `HexBattleVfxBridge.createPlayback` and the debug scene call.
func setHexFootprint(footprint: HexVfxFootprint, _groundSpan: float = 0.0, _areaShape: String = "") -> void:
	_footprint = footprint
	_dirty = true


## The spell's presentation spec. Without one the playback plays the profile's
## own defaults with the palette of the colour it was created with.
func configure_spell_spec(spec: Spec) -> void:
	_spec = spec
	_dirty = true


## Derived fronts, from `SpellVfxSpec.frontToward`: the caster's, and one per
## cast-context target for an `each_target` spread. Units have no facing, so
## without this the substrate faces each anchor along its source direction.
func configure_facing(sourceFront: Vector3, targetFronts: Array[Vector3] = []) -> void:
	_sourceFront = sourceFront
	_targetFronts = targetFronts.duplicate()
	_dirty = true


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed cube placeholder.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_activeMode = mode
	_dirty = true
	_prepare()
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyProgress(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	if _dirty:
		_prepare()
	var progress := clampf(time, 0.0, 1.0)
	_elapsedTime = progress * _totalDuration
	_finished = progress >= 1.0
	if _finished:
		_playing = false
	_applyProgress(progress)


func skip_to_settle() -> void:
	seek_normalized(normalizedAtSketchTime(_composition.settleTime()))


func get_normalized_time() -> float:
	return clampf(_elapsedTime / maxf(_totalDuration, 0.001), 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return _totalDuration


func is_finished() -> bool:
	return _finished


## Seconds from the start of play until the composition's impact beat, after
## the range warp. A battle caller holds the action queue this long so the hit
## lands on the impact whatever the distance.
func get_action_hold_seconds() -> float:
	if _dirty:
		_prepare()
	return normalizedAtSketchTime(_composition.impactTime()) * _totalDuration


func get_layer_names() -> Array[String]:
	return _composition.roles()


func set_layer_visible(layerName: String, visible: bool) -> void:
	var index := _composition.roles().find(layerName)
	if index < 0:
		push_warning("Unknown cube placeholder layer: %s" % layerName)
		return
	_roleVisible[index] = visible
	if not _dirty:
		_applyProgress(get_normalized_time())


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	return _written


func get_live_node_count() -> int:
	return 0 if _disposed else _countNodes(self)


func get_live_draw_call_count() -> int:
	return 1 if _instance != null and _written > 0 else 0


func is_particle_seek_exact() -> bool:
	return true


func get_active_seed() -> int:
	return _activeSeed


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_playing = false
	set_process(false)
	if is_queued_for_deletion():
		return
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		call_deferred("free")


## --- inspection, for probes and the families' own checks ------------------

func get_composition() -> Composition:
	return _composition


func get_pose_buffer() -> PoseBuffer:
	return _buffer


func get_frames() -> Array:
	return _frames


func get_capacity() -> int:
	return _capacity


func get_palette_keys() -> Array[String]:
	return _paletteKeys.duplicate()


func get_range_stretch() -> float:
	return _rangeStretch


## Nodes that issue draws: the one multimesh instance.
func get_render_node_count() -> int:
	return 0 if _instance == null else 1


## Sketch-normalized time shown at playback-normalized `progress`.
func sketchTimeAt(progress: float) -> float:
	return _mapBreaks(clampf(progress, 0.0, 1.0), _warpBreaks, _sketchBreaks)


## Playback-normalized time at which sketch time `t` is shown.
func normalizedAtSketchTime(t: float) -> float:
	return _mapBreaks(clampf(t, 0.0, 1.0), _sketchBreaks, _warpBreaks)


## Builds the piecewise-linear warp for a travel stretch. Static and pure, so
## the probe can check it without a playback. Returns
## `{"sketch": breaks, "warped": breaks, "factor": total length multiplier}`.
static func buildWarp(beats: Array[Dictionary], stretch: float) -> Dictionary:
	var sketch := PackedFloat32Array([0.0])
	var lengths := PackedFloat32Array()
	var cursor := 0.0
	var ordered := beats.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["start"]) < float(b["start"]))
	for beat: Dictionary in ordered:
		var start := clampf(float(beat["start"]), 0.0, 1.0)
		var finish := clampf(float(beat["end"]), 0.0, 1.0)
		if start > cursor + 0.00001:
			sketch.append(start)
			lengths.append(start - cursor)
			cursor = start
		if finish > cursor + 0.00001:
			sketch.append(finish)
			var span := finish - cursor
			lengths.append(span * (stretch if bool(beat.get("travel", false)) else 1.0))
			cursor = finish
	if cursor < 1.0 - 0.00001:
		sketch.append(1.0)
		lengths.append(1.0 - cursor)
	var total := 0.0
	for value: float in lengths:
		total += value
	var warped := PackedFloat32Array([0.0])
	var running := 0.0
	for value: float in lengths:
		running += value
		warped.append(running / total)
	warped[warped.size() - 1] = 1.0
	sketch[sketch.size() - 1] = 1.0
	return {"sketch": sketch, "warped": warped, "factor": total}


static func _mapBreaks(value: float, from: PackedFloat32Array, to: PackedFloat32Array) -> float:
	for index: int in range(1, from.size()):
		if value <= from[index] or index == from.size() - 1:
			var span := from[index] - from[index - 1]
			if span <= 0.0000001:
				return to[index]
			var local := (value - from[index - 1]) / span
			return lerpf(to[index - 1], to[index], clampf(local, 0.0, 1.0))
	return value


## --- preparation (allocates) -----------------------------------------------

func _prepare() -> void:
	_dirty = false
	var spec := _spec if _spec != null else Spec.defaults(_composition.profileID())
	_preparePalettes(spec)
	_prepareFrames(spec)
	_composition.prepare(_frames)
	var perAnchor := maxi(_composition.peakCubes(), Profile.MIN_CAPACITY_PER_COMPOSITION)
	_ensureCapacity(perAnchor * maxi(_frames.size(), 1))
	var rangeMode := spec.resolvedRangeScaling(_composition.defaultRangeScaling())
	_rangeStretch = 1.0
	if rangeMode == Spec.RANGE_TRAVEL and _composition.hasTravelBeats():
		_rangeStretch = Profile.rangeStretch(_castDistance())
	var warp := buildWarp(_composition.beats(), _rangeStretch)
	_sketchBreaks = warp["sketch"]
	_warpBreaks = warp["warped"]
	_baseDuration = (
		_composition.referenceDurationSeconds()
		if _activeMode == MODE_REFERENCE
		else _composition.battleDurationSeconds()
	)
	_totalDuration = _baseDuration * float(warp["factor"])


## Explicit elements name their palettes; a spec with no element (or no spec)
## falls back to the colour the playback was created with, which is what a
## Color-only caller such as the debug element picker supplies.
func _preparePalettes(spec: Spec) -> void:
	var keys: Array[String] = []
	var palettes: Array = []
	var names := spec.elements()
	if names.is_empty() or (names.size() == 1 and names[0] == "none" and _spec == null):
		keys.append("color:%s" % _elementColor.to_html())
		palettes.append(Profile.paletteForColor(_elementColor))
	else:
		for elementName: String in names:
			keys.append(elementName)
			palettes.append(Profile.paletteForElement(elementName))
	if keys == _paletteKeys and _atlasTexture != null:
		return
	_paletteKeys = keys
	_paletteCount = keys.size()
	_atlasTexture = Atlas.build(palettes)
	if _material != null:
		_material.set_shader_parameter("atlas", _atlasTexture)
		_material.set_shader_parameter("palette_rows", float(_paletteCount))


func _ensureCapacity(capacity: int) -> void:
	_buffer.reserve(capacity)
	if _instance != null and capacity <= _capacity:
		return
	_capacity = capacity
	if _instance == null:
		var shader := Shader.new()
		shader.code = _SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("frame_count", float(Profile.SPRITE_ROTATION_FRAMES))
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = _material
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_custom_data = true
		_multimesh.mesh = quad
		_multimesh.custom_aabb = _RENDER_AABB
		_instance = MultiMeshInstance3D.new()
		_instance.name = "Cubes"
		_instance.multimesh = _multimesh
		_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_instance.extra_cull_margin = 8.0
		add_child(_instance)
	_material.set_shader_parameter("atlas", _atlasTexture)
	_material.set_shader_parameter("palette_rows", float(_paletteCount))
	_multimesh.instance_count = _capacity
	_multimesh.visible_instance_count = 0
	_floats.resize(_capacity * _FLOATS_PER_INSTANCE)
	_floats.fill(0.0)
	assert(
		_countNodes(self) - 1 <= Profile.MAX_RENDER_NODES,
		"Cube placeholder exceeded its render-node ceiling."
	)


## One frame per anchor. Which anchors exist is the spec's decision:
## `caster_front` puts one a cell in front of the caster; `each_target` puts
## one on every target; otherwise there is one, on the cast centre.
func _prepareFrames(spec: Spec) -> void:
	_frames.clear()
	var source := global_position
	var impact := global_position
	var targetPositions: Array[Vector3] = []
	var targetBounds: Array[AABB] = []
	if _context != null:
		source = _context.source_world_position
		impact = _context.impact_world_position
		targetPositions.assign(_context.target_world_positions)
		targetBounds.assign(_context.target_body_bounds)
	else:
		source = impact - Vector3(Profile.REFERENCE_DISTANCE_U, 0.0, 0.0)
	var castDirection := _flat(impact - source)
	var sourceFront := (
		_flat(_sourceFront).normalized() if _flat(_sourceFront).length() > 0.001
		else (castDirection.normalized() if castDirection.length() > 0.001 else Vector3.RIGHT)
	)

	var anchors: Array[Vector3] = []
	var bodies: Array[AABB] = []
	var fronts: Array[Vector3] = []
	var hasBodies: Array[bool] = []
	if spec.anchor() == Spec.ANCHOR_CASTER_FRONT:
		anchors.append(source + sourceFront * Profile.CELL_PITCH_U)
		bodies.append(VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS)
		fronts.append(sourceFront)
		hasBodies.append(false)
	elif spec.spread() == Spec.SPREAD_EACH_TARGET and not targetPositions.is_empty():
		for index: int in range(targetPositions.size()):
			anchors.append(targetPositions[index])
			bodies.append(
				targetBounds[index] if index < targetBounds.size()
				else VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
			)
			fronts.append(
				_flat(_targetFronts[index]).normalized()
				if index < _targetFronts.size() and _flat(_targetFronts[index]).length() > 0.001
				else sourceFront
			)
			hasBodies.append(true)
	else:
		var bodyIndex := _targetAt(impact, targetPositions)
		anchors.append(impact)
		bodies.append(
			targetBounds[bodyIndex] if bodyIndex >= 0 and bodyIndex < targetBounds.size()
			else VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
		)
		fronts.append(
			_flat(_targetFronts[bodyIndex]).normalized()
			if bodyIndex >= 0 and bodyIndex < _targetFronts.size()
				and _flat(_targetFronts[bodyIndex]).length() > 0.001
			else sourceFront
		)
		hasBodies.append(bodyIndex >= 0)

	var areaMode := spec.resolvedAreaScaling(_composition.defaultAreaScaling())
	var seedShift := 0.0 if _activeSeed == 0 else fposmod(float(_activeSeed) * 0.6180339887, 1.0) * 97.0
	for index: int in range(anchors.size()):
		var frame := Frame.new()
		frame.anchorIndex = index
		frame.source = source
		frame.target = anchors[index]
		var toward := _flat(frame.target - source)
		frame.distance = toward.length()
		frame.front = fronts[index]
		frame.forward = toward.normalized() if frame.distance > 0.001 else frame.front
		frame.side = frame.forward.cross(Vector3.UP).normalized()
		frame.bodyBounds = bodies[index]
		frame.hasBody = hasBodies[index]
		frame.bodyScale = _bodyScale(bodies[index]) if _composition.isBodyBound() else 1.0
		frame.footprint = _footprint
		frame.areaScale = 1.0
		if areaMode == Spec.AREA_SPREAD:
			frame.areaScale = _areaScale(frame)
		frame.seedShift = seedShift
		frame.buffer = _buffer
		_frames.append(frame)


## Uniform: a cage around a wide body grows until it encloses the width, a cage
## around a tall one until it clears the head, and a cube stays a cube.
static func _bodyScale(bounds: AABB) -> float:
	var horizontal := maxf(bounds.size.x, bounds.size.z) / Profile.STANDARD_BODY_WIDTH_U
	var vertical := (bounds.position.y + bounds.size.y) / Profile.STANDARD_BODY_TOP_U
	return maxf(horizontal, vertical)


## How far the composition's authored area must spread to reach the edge of
## the affected cells around this anchor: never less than 1, so a footprint
## smaller than the study's own area leaves the study exactly as authored.
func _areaScale(frame: Frame) -> float:
	var reference := _composition.areaReferenceRadius()
	if _footprint == null or _footprint.isEmpty() or reference <= 0.0:
		return 1.0
	var reach := 0.0
	for centre: Vector3 in _footprint.world_positions:
		reach = maxf(reach, _flat(centre - frame.target).length())
	reach += _footprint.cell_height * 0.5
	return maxf(1.0, reach / (reference * frame.unit * frame.bodyScale))


func _castDistance() -> float:
	if _context == null:
		return Profile.REFERENCE_DISTANCE_U
	return _flat(_context.impact_world_position - _context.source_world_position).length()


static func _targetAt(point: Vector3, positions: Array[Vector3]) -> int:
	var best := -1
	var bestDistance := Profile.CELL_PITCH_U * 0.25
	for index: int in range(positions.size()):
		var distance := _flat(positions[index] - point).length()
		if distance <= bestDistance:
			bestDistance = distance
			best = index
	return best


static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


## --- sampling (allocates nothing) ------------------------------------------

func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	var progress := get_normalized_time()
	if _elapsedTime >= _totalDuration:
		_elapsedTime = _totalDuration
		progress = 1.0
		_playing = false
		_finished = true
	_applyProgress(progress)
	if _finished and _autoDispose:
		dispose()


func _applyProgress(progress: float) -> void:
	if _instance == null:
		return
	var t := sketchTimeAt(progress)
	_buffer.clear()
	for frame: Frame in _frames:
		_composition.sample(t, frame)
	if _buffer.overflow > 0:
		push_error("Cube placeholder %s emitted %d cubes past its declared peak." % [
			_composition.profileID(), _buffer.overflow
		])
	_writeInstances()


func _writeInstances() -> void:
	var origin := global_position
	var frameCount := float(Profile.SPRITE_ROTATION_FRAMES)
	var rows := float(_paletteCount)
	var written := 0
	for index: int in range(_buffer.count):
		var role := _buffer.roles[index]
		if role >= 0 and role < _roleVisible.size() and not _roleVisible[role]:
			continue
		var quad := _buffer.sizes[index] * Profile.QUAD_PER_EDGE
		var local := _buffer.positions[index] - origin
		var base := written * _FLOATS_PER_INSTANCE
		_floats[base] = quad
		_floats[base + 1] = 0.0
		_floats[base + 2] = 0.0
		_floats[base + 3] = local.x
		_floats[base + 4] = 0.0
		_floats[base + 5] = quad
		_floats[base + 6] = 0.0
		_floats[base + 7] = local.y
		_floats[base + 8] = 0.0
		_floats[base + 9] = 0.0
		_floats[base + 10] = quad
		_floats[base + 11] = local.z
		var frameIndex := Atlas.frameForYaw(_buffer.yaws[index])
		var paletteRow := posmod(_buffer.ids[index], _paletteCount)
		_floats[base + 12] = (float(frameIndex) + 0.5) / frameCount
		_floats[base + 13] = (float(paletteRow) + 0.5) / rows
		_floats[base + 14] = _buffer.opacities[index]
		_floats[base + 15] = 0.0
		written += 1
	_written = written
	_multimesh.buffer = _floats
	_multimesh.visible_instance_count = written


static func _countNodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _countNodes(child)
	return total
