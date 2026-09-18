## Source-bound elemental-cube channeling used as the generic spell fallback.
##
## The two catalog profiles share one carrier because they have the same layer,
## mesh, material, palette and lifecycle; only their analytic choreography
## differs. Motion is evaluated directly from normalized playback time, so
## pause, scrub, replay and reverse seeking all reproduce the same frame.

class_name ElementalCubeRitualEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const Profile = preload("res://src/presentation/effects/ElementalCubeRitualProfile.gd")
const _CUBE_SHADER = preload("res://assets/shaders/effects/elemental_cube_ritual.gdshader")

const STYLE_CROWNBURST := "crownburst"
const STYLE_SPIRAL := "spiral"
const LAYER_CUBES := "elemental_cubes"

var _style := STYLE_CROWNBURST
var _elementColor := Color.WHITE
var _cubeInstances: Array[MeshInstance3D] = []
var _cubeMesh: ArrayMesh
var _cubeMaterial: ShaderMaterial
var _elapsedTime := 0.0
var _totalDuration := Profile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 0
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _orbitTurns := Profile.ORBIT_TURNS
var _spinTurns := Profile.SPIN_TURNS
var _acceleration := Profile.ACCELERATION
var _dissipation := Profile.DISSIPATION


static func createCrownburst(
		parent: Node3D,
		worldPosition: Vector3,
		elementColor: Color,
		overrides: Dictionary = {}) -> ElementalCubeRitualEffect:
	return _create(STYLE_CROWNBURST, parent, worldPosition, elementColor, overrides)


static func createSpiral(
		parent: Node3D,
		worldPosition: Vector3,
		elementColor: Color,
		overrides: Dictionary = {}) -> ElementalCubeRitualEffect:
	return _create(STYLE_SPIRAL, parent, worldPosition, elementColor, overrides)


static func _create(
		style: String,
		parent: Node3D,
		worldPosition: Vector3,
		elementColor: Color,
		overrides: Dictionary) -> ElementalCubeRitualEffect:
	var playback := ElementalCubeRitualEffect.new()
	playback.name = "ElementalCubeCrownburst" if style == STYLE_CROWNBURST \
		else "ElementalCubeSpiral"
	playback._style = style
	playback._elementColor = elementColor
	parent.add_child(playback)
	playback.global_position = worldPosition
	playback.set_tunable_overrides(overrides)
	playback._resolveTuning()
	playback._buildLayers()
	return playback


static func tunables() -> Array[Dictionary]:
	return [
		{
			"id": "ORBIT_TURNS", "label": "Orbit turns", "group": "Motion",
			"min": 0.7, "max": 2.4, "step": 0.05,
			"default": Profile.ORBIT_TURNS, "rebuild": false,
		},
		{
			"id": "SPIN_TURNS", "label": "Self-spin turns", "group": "Motion",
			"min": 0.2, "max": 3.2, "step": 0.05,
			"default": Profile.SPIN_TURNS, "rebuild": false,
		},
		{
			"id": "ACCELERATION", "label": "Acceleration", "group": "Motion",
			"min": 0.7, "max": 2.8, "step": 0.05,
			"default": Profile.ACCELERATION, "rebuild": false,
		},
		{
			"id": "DISSIPATION", "label": "Dissipation", "group": "Motion",
			"min": 0.65, "max": 2.4, "step": 0.05,
			"default": Profile.DISSIPATION, "rebuild": false,
		},
	]


func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	global_position = context.source_world_position


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed elemental cube ritual.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_totalDuration = (
		Profile.REFERENCE_DURATION_SECONDS
		if mode == MODE_REFERENCE
		else Profile.BATTLE_DURATION_SECONDS
	)
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
	var progress := clampf(time, 0.0, 1.0)
	_elapsedTime = progress * _totalDuration
	_finished = progress >= 1.0
	if _finished:
		_playing = false
	_applyProgress(progress)


func skip_to_settle() -> void:
	seek_normalized(Profile.SETTLE_NORMALIZED_TIME)


func get_normalized_time() -> float:
	return clampf(_elapsedTime / maxf(_totalDuration, 0.001), 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return _totalDuration


func is_finished() -> bool:
	return _finished


func get_layer_names() -> Array[String]:
	return [LAYER_CUBES]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if layerName != LAYER_CUBES:
		push_warning("Unknown elemental cube ritual layer: %s" % layerName)
		return
	for cube: MeshInstance3D in _cubeInstances:
		cube.set_meta("layer_enabled", visible)
		cube.visible = visible and bool(cube.get_meta("timeline_visible", false))


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	var total := 0
	for cube: MeshInstance3D in _cubeInstances:
		if cube.visible:
			total += 1
	return total


func get_live_node_count() -> int:
	return 0 if _disposed else _countNodes(self)


func get_live_draw_call_count() -> int:
	return get_live_instance_count()


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


func _on_tunables_applied() -> void:
	_resolveTuning()
	_applyProgress(get_normalized_time())


func _resolveTuning() -> void:
	_orbitTurns = maxf(0.0, tunable("ORBIT_TURNS", Profile.ORBIT_TURNS))
	_spinTurns = maxf(0.0, tunable("SPIN_TURNS", Profile.SPIN_TURNS))
	_acceleration = maxf(0.01, tunable("ACCELERATION", Profile.ACCELERATION))
	_dissipation = maxf(0.01, tunable("DISSIPATION", Profile.DISSIPATION))


func _buildLayers() -> void:
	_cubeMesh = _buildBeveledCubeMesh()
	_cubeMaterial = ShaderMaterial.new()
	_cubeMaterial.shader = _CUBE_SHADER
	var palette: Array[Color] = Profile.paletteFor(_elementColor)
	_cubeMaterial.set_shader_parameter("direct_color", palette[0])
	_cubeMaterial.set_shader_parameter("mid_color", palette[1])
	_cubeMaterial.set_shader_parameter("shadow_color", palette[2])
	_cubeMaterial.set_shader_parameter("light_direction_world", Profile.LIGHT_DIRECTION_WORLD)
	_cubeMaterial.set_shader_parameter("shadow_stop", Profile.SHADOW_STOP)
	_cubeMaterial.set_shader_parameter("mid_stop", Profile.MID_STOP)
	_cubeMaterial.set_shader_parameter("direct_stop", Profile.DIRECT_STOP)
	_cubeMaterial.set_shader_parameter("edge_polish", Profile.EDGE_POLISH)

	for index in range(Profile.CUBE_COUNT):
		var cube := MeshInstance3D.new()
		cube.name = "Cube%02d" % index
		cube.mesh = _cubeMesh
		cube.material_override = _cubeMaterial
		cube.extra_cull_margin = 3.0
		cube.set_meta("layer_enabled", true)
		cube.set_meta("timeline_visible", false)
		cube.visible = false
		add_child(cube)
		_cubeInstances.append(cube)

	assert(
		_countNodes(self) <= Profile.MAX_EFFECT_NODES,
		"Elemental cube ritual exceeded its authored node ceiling."
	)
	assert(
		_cubeInstances.size() <= Profile.MAX_GEOMETRY_INSTANCES,
		"Elemental cube ritual exceeded its geometry-instance ceiling."
	)
	assert(
		_cubeInstances.size() <= Profile.MAX_DRAW_CALLS,
		"Elemental cube ritual exceeded its draw-call ceiling."
	)


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
	if _cubeInstances.is_empty():
		return
	var orbit := _orbitProgress(progress, 0.3 / _acceleration)
	if _style == STYLE_SPIRAL:
		_applySpiral(orbit)
	else:
		_applyCrownburst(progress, orbit)


func _applyCrownburst(progress: float, orbit: float) -> void:
	var manifest := _range(Profile.CROWN_MANIFEST_START, Profile.CROWN_MANIFEST_END, progress)
	var arrival := _range(Profile.CROWN_ARRIVAL_START, Profile.CROWN_ARRIVAL_END, progress)
	var releaseEnd := minf(
		0.98,
		Profile.CROWN_RELEASE_START
			+ (Profile.CROWN_RELEASE_END - Profile.CROWN_RELEASE_START) / _dissipation
	)
	var dissolveEnd := minf(
		0.98,
		Profile.CROWN_DISSOLVE_START
			+ (Profile.CROWN_DISSOLVE_END - Profile.CROWN_DISSOLVE_START) / _dissipation
	)
	var release := _range(Profile.CROWN_RELEASE_START, releaseEnd, progress)
	var dissolve := _range(Profile.CROWN_DISSOLVE_START, dissolveEnd, progress)
	var life := manifest * (1.0 - dissolve)
	var spin := orbit * TAU * _spinTurns
	for index in range(_cubeInstances.size()):
		var phase := float(index) / float(Profile.CUBE_COUNT) * TAU
		var angle := phase + orbit * TAU * _orbitTurns
		var radius := lerpf(Profile.CROWN_INNER_RADIUS_U, Profile.CROWN_RADIUS_U, arrival) \
			+ release * Profile.CROWN_RELEASE_DISTANCE_U
		var position := Vector3(
			cos(angle) * radius,
			lerpf(Profile.CROWN_START_HEIGHT_U, Profile.CROWN_HEIGHT_U, arrival)
				+ sin(orbit * TAU) * Profile.CROWN_BREATH_U
				- release * Profile.CROWN_FALL_DISTANCE_U,
			sin(angle) * radius
		)
		_setCubeTransform(index, position, spin, life * (1.0 - release * 0.35))


func _applySpiral(orbit: float) -> void:
	var lineGap := Profile.SPIRAL_LINE_GAP
	var exitWindow := Profile.SPIRAL_EXIT_WINDOW / _dissipation
	var lineSpan := lineGap * float(Profile.CUBE_COUNT - 1)
	var travel := orbit * (1.0 + lineSpan + exitWindow)
	var spin := orbit * TAU * _spinTurns
	for index in range(_cubeInstances.size()):
		var pathProgress := travel - float(Profile.CUBE_COUNT - 1 - index) * lineGap
		var rise := clampf(pathProgress, 0.0, 1.0)
		var manifest := _range(0.0, Profile.SPIRAL_MANIFEST_WINDOW, pathProgress)
		var exit := _range(1.0, 1.0 + exitWindow, pathProgress)
		var angle := pathProgress * TAU * _orbitTurns
		var radius := lerpf(
			Profile.SPIRAL_INNER_RADIUS_U,
			Profile.SPIRAL_RADIUS_U,
			_range(0.0, Profile.SPIRAL_RADIUS_SETTLE_PROGRESS, pathProgress)
		)
		var position := Vector3(
			cos(angle) * radius,
			Profile.SPIRAL_BASE_HEIGHT_U + rise * Profile.SPIRAL_HEIGHT_U,
			sin(angle) * radius
		)
		_setCubeTransform(index, position, spin, manifest * (1.0 - exit))


func _setCubeTransform(index: int, position: Vector3, spin: float, scaleAmount: float) -> void:
	var cube := _cubeInstances[index]
	var timelineVisible := scaleAmount > 0.002
	cube.set_meta("timeline_visible", timelineVisible)
	cube.visible = timelineVisible and bool(cube.get_meta("layer_enabled", true))
	cube.position = position
	cube.rotation = Vector3(0.0, spin, 0.0)
	var safeScale := maxf(scaleAmount, 0.001)
	cube.scale = Vector3.ONE * safeScale


static func _orbitProgress(value: float, ramp: float) -> float:
	var time := clampf(value, 0.0, 1.0)
	var safeRamp := clampf(ramp, 0.01, 0.9)
	var distance: float
	if time < safeRamp:
		var local := time / safeRamp
		distance = safeRamp * (local * local * local - 0.5 * pow(local, 4.0))
	else:
		distance = time - safeRamp * 0.5
	return distance / (1.0 - safeRamp * 0.5)


static func _range(start: float, finish: float, value: float) -> float:
	if is_equal_approx(start, finish):
		return 1.0 if value >= finish else 0.0
	var normalized := clampf((value - start) / (finish - start), 0.0, 1.0)
	return normalized * normalized * (3.0 - 2.0 * normalized)


static func _buildBeveledCubeMesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Profile.CUBE_SIZE_U * 0.5
	var inner := half - Profile.BEVEL_RADIUS_U
	var coordinates: Array[float] = [-half, -inner, 0.0, inner, half]
	var faces := [
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	]
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var axisU: Vector3 = face[1]
		var axisV: Vector3 = face[2]
		for row in range(coordinates.size() - 1):
			for column in range(coordinates.size() - 1):
				var raw00: Vector3 = normal * half + axisU * coordinates[column] \
					+ axisV * coordinates[row]
				var raw10: Vector3 = normal * half + axisU * coordinates[column + 1] \
					+ axisV * coordinates[row]
				var raw11: Vector3 = normal * half + axisU * coordinates[column + 1] \
					+ axisV * coordinates[row + 1]
				var raw01: Vector3 = normal * half + axisU * coordinates[column] \
					+ axisV * coordinates[row + 1]
				_addRoundedTriangle(surface, raw00, raw10, raw11, inner)
				_addRoundedTriangle(surface, raw00, raw11, raw01, inner)
	return surface.commit()


static func _addRoundedTriangle(
		surface: SurfaceTool,
		rawA: Vector3,
		rawB: Vector3,
		rawC: Vector3,
		inner: float) -> void:
	for raw: Vector3 in [rawA, rawB, rawC]:
		var core := Vector3(
			clampf(raw.x, -inner, inner),
			clampf(raw.y, -inner, inner),
			clampf(raw.z, -inner, inner)
		)
		var offset := raw - core
		var normal := offset.normalized()
		surface.set_normal(normal)
		surface.add_vertex(core + normal * Profile.BEVEL_RADIUS_U)


static func _countNodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _countNodes(child)
	return total
