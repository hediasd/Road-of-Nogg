## Debug-only polygonal technique-charge aura playback.
##
## Authored fresh under docs/VFX_DESIGN.md's isolation rule. Solar Storm is a
## process reference only: this effect owns its mesh construction, materials,
## texture, profile, and lifecycle implementation.

class_name TechniqueChargeAuraEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _AURA_SHADER = preload(
	"res://assets/shaders/effects/technique_charge_aura.gdshader"
)
const _AURA_MASK = preload(
	"res://assets/vfx/technique_charge_aura/aura_panel.png"
)

const LAYER_GROUND := "ground_circle"
const LAYER_WALL := "polygonal_wall"

var _groundInstance: MeshInstance3D
var _wallInstance: MeshInstance3D
var _groundMaterial: ShaderMaterial
var _wallMaterial: ShaderMaterial
var _elapsedTime := 0.0
var _playbackScale := 1.0
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _seedOffset := 0.0

## Live-class authored values, resolved once at build time and again whenever
## the debug panel pushes an override. Read through `tunable()` there rather
## than per frame: a dictionary lookup inside the per-frame path would cost
## real performance in the one tool used to judge performance.
var _igniteEnd := TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED
var _releaseStart := TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED
var _noiseScaleCoarse := TechniqueChargeAuraProfile.NOISE_SCALE_COARSE
var _noiseScaleFine := TechniqueChargeAuraProfile.NOISE_SCALE_FINE
var _noiseRiseSpeed := TechniqueChargeAuraProfile.NOISE_RISE_SPEED
var _flickerAmount := TechniqueChargeAuraProfile.FLICKER_AMOUNT
var _displacement := TechniqueChargeAuraProfile.DISPLACEMENT_U
var _wallBottomStrength := TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH
var _groundSpillAlpha := TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA
var _groundSpillOuter := TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV


## Live-authoring roster. `rebuild: true` marks the values consumed while the
## mesh is assembled — the panel replays the effect for those rather than
## nudging a uniform that nothing would re-read.
static func tunables() -> Array[Dictionary]:
	return [
		{
			"id": "WALL_SIDES", "label": "Sides", "group": "Dimensions",
			"min": 3.0, "max": 16.0, "step": 1.0,
			"default": float(TechniqueChargeAuraProfile.WALL_SIDES),
			"rebuild": true,
		},
		{
			"id": "WALL_RADIUS_U", "label": "Radius", "group": "Dimensions",
			"min": 0.2, "max": 2.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_RADIUS_U,
			"rebuild": true,
		},
		{
			"id": "WALL_HEIGHT_U", "label": "Height", "group": "Dimensions",
			"min": 0.4, "max": 4.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_HEIGHT_U,
			"rebuild": true,
		},
		{
			"id": "GROUND_DIAMETER_U", "label": "Ground size",
			"group": "Dimensions",
			"min": 0.5, "max": 5.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.GROUND_DIAMETER_U,
			"rebuild": true,
		},
		{
			"id": "WALL_BOTTOM_STRENGTH", "label": "Bottom strength",
			"group": "Wall",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH,
			"rebuild": false,
		},
		{
			"id": "NOISE_SCALE_COARSE", "label": "Noise coarse", "group": "Noise",
			"min": 0.5, "max": 12.0, "step": 0.1,
			"default": TechniqueChargeAuraProfile.NOISE_SCALE_COARSE,
			"rebuild": false,
		},
		{
			"id": "NOISE_SCALE_FINE", "label": "Noise fine", "group": "Noise",
			"min": 2.0, "max": 40.0, "step": 0.5,
			"default": TechniqueChargeAuraProfile.NOISE_SCALE_FINE,
			"rebuild": false,
		},
		{
			"id": "NOISE_RISE_SPEED", "label": "Rise speed", "group": "Noise",
			"min": 0.0, "max": 3.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.NOISE_RISE_SPEED,
			"rebuild": false,
		},
		{
			"id": "FLICKER_AMOUNT", "label": "Flicker", "group": "Motion",
			"min": 0.0, "max": 0.6, "step": 0.01,
			"default": TechniqueChargeAuraProfile.FLICKER_AMOUNT,
			"rebuild": false,
		},
		{
			"id": "DISPLACEMENT_U", "label": "Height flutter", "group": "Motion",
			"min": 0.0, "max": 0.3, "step": 0.005,
			"default": TechniqueChargeAuraProfile.DISPLACEMENT_U,
			"rebuild": false,
		},
		{
			"id": "IGNITE_END_NORMALIZED", "label": "Ignite end", "group": "Fade",
			"min": 0.02, "max": 0.6, "step": 0.01,
			"default": TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED,
			"rebuild": false,
		},
		{
			"id": "RELEASE_START_NORMALIZED", "label": "Release start",
			"group": "Fade",
			"min": 0.4, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED,
			"rebuild": false,
		},
		{
			"id": "GROUND_SPILL_ALPHA", "label": "Spill strength",
			"group": "Circle",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA,
			"rebuild": false,
		},
		{
			"id": "GROUND_SPILL_OUTER_UV", "label": "Spill reach",
			"group": "Circle",
			"min": 0.2, "max": 0.5, "step": 0.005,
			"default": TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV,
			"rebuild": false,
		},
	]


static func createPlayback(
		parent: Node3D,
		world_position: Vector3,
		_element_color: Color,
		overrides: Dictionary = {}) -> TechniqueChargeAuraEffect:
	var playback := TechniqueChargeAuraEffect.new()
	playback.name = "TechniqueChargeAuraEffect"
	playback.position = world_position
	parent.add_child(playback)
	playback.set_tunable_overrides(overrides)
	playback._buildOwnedLayers()
	return playback


func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	context.assert_valid()
	position = context.source_world_position


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed TechniqueChargeAuraEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	# The seed only ever offsets the noise sample point, so two seeds are two
	# draws of the same authored material rather than two different looks.
	#
	# The offset must stay *small*. The shader's hash runs fract() on the sample
	# point scaled by ~123, so a large offset lands where float32 has no
	# fractional precision left and every seed collapses to an identical
	# pattern. A first version scaled a wrapped seed up to ~718 and did exactly
	# that; the seed-variation check reported no difference between two seeds.
	# The golden-ratio scramble is computed in GDScript's 64-bit float and
	# handed over already wrapped into a range the shader can resolve.
	_seedOffset = fmod(float(absi(seed)) * 0.61803398875, 16.0)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyTimeline()
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalized_time := clampf(time, 0.0, 1.0)
	_elapsedTime = normalized_time * TechniqueChargeAuraProfile.DURATION_SECONDS
	_finished = normalized_time >= 1.0
	_playing = not _finished
	if _finished:
		_applyVisibility(0.0)
	else:
		_applyTimeline()


func skip_to_settle() -> void:
	seek_normalized(TechniqueChargeAuraProfile.SETTLE_NORMALIZED_TIME)


func get_normalized_time() -> float:
	return clampf(
		_elapsedTime / TechniqueChargeAuraProfile.DURATION_SECONDS,
		0.0,
		1.0
	)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return TechniqueChargeAuraProfile.DURATION_SECONDS


func is_finished() -> bool:
	return _finished


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


func get_layer_names() -> Array[String]:
	return [LAYER_GROUND, LAYER_WALL]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_GROUND:
			if _groundInstance != null:
				_groundInstance.visible = visible
		LAYER_WALL:
			if _wallInstance != null:
				_wallInstance.visible = visible
		_:
			push_warning("Unknown TechniqueChargeAuraEffect layer: %s" % layer_name)


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _disposed or _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [_groundInstance, _wallInstance]:
		if instance != null and instance.visible:
			count += 1
	return count


func get_live_draw_call_count() -> int:
	return get_live_instance_count()


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return 1 + get_child_count()


func is_particle_seek_exact() -> bool:
	return true


func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	if _elapsedTime < TechniqueChargeAuraProfile.DURATION_SECONDS:
		_applyTimeline()
		return
	_elapsedTime = TechniqueChargeAuraProfile.DURATION_SECONDS
	_playing = false
	_finished = true
	_applyVisibility(0.0)
	if _autoDispose:
		dispose()


func _readLiveTunables() -> void:
	_igniteEnd = tunable(
		"IGNITE_END_NORMALIZED", TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED
	)
	_releaseStart = tunable(
		"RELEASE_START_NORMALIZED",
		TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED
	)
	_noiseScaleCoarse = tunable(
		"NOISE_SCALE_COARSE", TechniqueChargeAuraProfile.NOISE_SCALE_COARSE
	)
	_noiseScaleFine = tunable(
		"NOISE_SCALE_FINE", TechniqueChargeAuraProfile.NOISE_SCALE_FINE
	)
	_noiseRiseSpeed = tunable(
		"NOISE_RISE_SPEED", TechniqueChargeAuraProfile.NOISE_RISE_SPEED
	)
	_flickerAmount = tunable(
		"FLICKER_AMOUNT", TechniqueChargeAuraProfile.FLICKER_AMOUNT
	)
	_displacement = tunable(
		"DISPLACEMENT_U", TechniqueChargeAuraProfile.DISPLACEMENT_U
	)
	_wallBottomStrength = tunable(
		"WALL_BOTTOM_STRENGTH", TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH
	)
	_groundSpillAlpha = tunable(
		"GROUND_SPILL_ALPHA", TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA
	)
	_groundSpillOuter = tunable(
		"GROUND_SPILL_OUTER_UV", TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV
	)


func _pushLiveTunables() -> void:
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material == null:
			continue
		material.set_shader_parameter("noise_scale_coarse", _noiseScaleCoarse)
		material.set_shader_parameter("noise_scale_fine", _noiseScaleFine)
		material.set_shader_parameter("noise_rise_speed", _noiseRiseSpeed)
		material.set_shader_parameter("flicker_amount", _flickerAmount)
		material.set_shader_parameter("displacement_u", _displacement)
		material.set_shader_parameter("wall_bottom_strength", _wallBottomStrength)
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter(
			"ground_spill_alpha", _groundSpillAlpha
		)
		_groundMaterial.set_shader_parameter(
			"ground_spill_outer", _groundSpillOuter
		)


func _buildOwnedLayers() -> void:
	_readLiveTunables()
	_groundMaterial = _createOwnedMaterial(1)
	_groundMaterial.render_priority = TechniqueChargeAuraProfile.GROUND_RENDER_PRIORITY
	_groundMaterial.set_shader_parameter(
		"opacity", TechniqueChargeAuraProfile.GROUND_OPACITY
	)
	_groundMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.GROUND_EMISSION_ENERGY
	)
	_groundMaterial.set_shader_parameter(
		"ground_spill_inner", TechniqueChargeAuraProfile.GROUND_SPILL_INNER_UV
	)
	_groundMaterial.set_shader_parameter("ground_spill_outer", _groundSpillOuter)
	_groundMaterial.set_shader_parameter("ground_spill_alpha", _groundSpillAlpha)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2.ONE * tunable(
		"GROUND_DIAMETER_U", TechniqueChargeAuraProfile.GROUND_DIAMETER_U
	)
	_groundInstance = MeshInstance3D.new()
	_groundInstance.name = "GroundCircle"
	_groundInstance.mesh = ground_mesh
	_groundInstance.position.y = TechniqueChargeAuraProfile.GROUND_HEIGHT_U
	_groundInstance.material_override = _groundMaterial
	_groundInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_groundInstance)

	_wallMaterial = _createOwnedMaterial(0)
	_wallMaterial.render_priority = TechniqueChargeAuraProfile.WALL_RENDER_PRIORITY
	_wallMaterial.set_shader_parameter(
		"opacity", TechniqueChargeAuraProfile.WALL_OPACITY
	)
	_wallMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.WALL_EMISSION_ENERGY
	)

	_wallInstance = MeshInstance3D.new()
	_wallInstance.name = "PolygonalWall"
	_wallInstance.mesh = _createRepeatedFaceWall(
		tunable_int("WALL_SIDES", TechniqueChargeAuraProfile.WALL_SIDES),
		tunable("WALL_RADIUS_U", TechniqueChargeAuraProfile.WALL_RADIUS_U),
		tunable("WALL_HEIGHT_U", TechniqueChargeAuraProfile.WALL_HEIGHT_U)
	)
	_wallInstance.material_override = _wallMaterial
	_wallInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wallInstance)

	_pushLiveTunables()

	assert(
		get_child_count() + 1 <= TechniqueChargeAuraProfile.MAX_EFFECT_NODES,
		"Technique charge aura exceeded its authored node ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_GEOMETRY_INSTANCES,
		"Technique charge aura exceeded its authored geometry ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_DRAW_CALLS,
		"Technique charge aura exceeded its authored draw-call ceiling."
	)


func _createOwnedMaterial(layer_kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _AURA_SHADER
	material.set_shader_parameter("aura_mask", _AURA_MASK)
	material.set_shader_parameter("aura_color", TechniqueChargeAuraProfile.AURA_COLOR)
	material.set_shader_parameter("layer_kind", layer_kind)
	material.set_shader_parameter("lifecycle_visibility", 1.0)
	return material


func _applyVisibility(visibility: float) -> void:
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material != null:
			material.set_shader_parameter("lifecycle_visibility", visibility)


## Pushes the whole per-instant state: the envelope and the effect's own clock.
##
## The shader never reads `TIME`, so this is the only thing that advances it.
## That is what makes a normalized seek exact — the image is a pure function of
## `playback_time` and the seed — and it is why pause and speed need no special
## handling at all: a scale of zero simply stops changing the value pushed here.
func _applyTimeline() -> void:
	var normalized := get_normalized_time()
	var envelope := _envelopeAt(normalized)
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material != null:
			material.set_shader_parameter("lifecycle_visibility", envelope)
			material.set_shader_parameter("playback_time", normalized)
			material.set_shader_parameter("playback_seed", _seedOffset)


## Authored ignition / hold / release. Release begins at the settle point, so
## `skip_to_settle()` lands on the last fully-charged frame instead of inside
## the fade.
func _envelopeAt(normalized: float) -> float:
	var ignite_end: float = maxf(_igniteEnd, 0.0001)
	if normalized < ignite_end:
		return smoothstep(0.0, ignite_end, normalized)
	if normalized < _releaseStart:
		return 1.0
	return 1.0 - smoothstep(_releaseStart, 1.0, normalized)


## Live-class overrides only. Anything that shapes geometry is marked
## `rebuild: true` in the descriptor roster and reaches the effect through
## `set_tunable_overrides()` before `_buildOwnedLayers()` instead.
func _on_tunables_applied() -> void:
	if _disposed:
		return
	_readLiveTunables()
	_pushLiveTunables()
	_applyTimeline()


static func _createRepeatedFaceWall(sides: int, radius: float, height: float) -> ArrayMesh:
	assert(sides >= 3, "Technique charge aura wall needs at least three sides.")
	assert(radius > 0.0 and height > 0.0, "Aura wall dimensions must be positive.")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for side: int in range(sides):
		var angle_a := TAU * float(side) / float(sides)
		var angle_b := TAU * float(side + 1) / float(sides)
		var point_a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var point_b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		var outward_angle := (angle_a + angle_b) * 0.5
		var outward := Vector3(cos(outward_angle), 0.0, sin(outward_angle))
		var base := vertices.size()

		vertices.append_array(PackedVector3Array([
			point_a,
			point_b,
			point_a + Vector3.UP * height,
			point_b + Vector3.UP * height,
		]))
		normals.append_array(PackedVector3Array([outward, outward, outward, outward]))
		uvs.append_array(PackedVector2Array([
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
		]))
		indices.append_array(PackedInt32Array([
			base,
			base + 3,
			base + 2,
			base,
			base + 1,
			base + 3,
		]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
