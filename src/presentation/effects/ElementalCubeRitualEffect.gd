## Source-bound elemental-cube channeling used as the generic spell fallback.
##
## The two catalog profiles share one carrier because they have the same layer,
## pixel atlas, sprite treatment, palette and lifecycle; only their analytic choreography
## differs. Motion is evaluated directly from normalized playback time, so
## pause, scrub, replay and reverse seeking all reproduce the same frame.

class_name ElementalCubeRitualEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const Profile = preload("res://src/presentation/effects/ElementalCubeRitualProfile.gd")

const STYLE_CROWNBURST := "crownburst"
const STYLE_SPIRAL := "spiral"
const LAYER_CUBES := "elemental_cubes"

var _style := STYLE_CROWNBURST
var _elementColor := Color.WHITE
var _cubeInstances: Array[Sprite3D] = []
var _cubeTexture: ImageTexture
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
	for cube: Sprite3D in _cubeInstances:
		cube.set_meta("layer_enabled", visible)
		cube.visible = visible and bool(cube.get_meta("timeline_visible", false))


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	var total := 0
	for cube: Sprite3D in _cubeInstances:
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
	var palette: Array[Color] = Profile.paletteFor(_elementColor)
	_cubeTexture = _buildPixelAtlas(palette)

	for index in range(Profile.CUBE_COUNT):
		var cube := Sprite3D.new()
		cube.name = "Cube%02d" % index
		cube.texture = _cubeTexture
		cube.hframes = Profile.SPRITE_ROTATION_FRAMES
		cube.pixel_size = Profile.SPRITE_PIXEL_SIZE_U
		cube.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cube.shaded = false
		cube.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		cube.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var cube: Sprite3D = _cubeInstances[index]
	var timelineVisible := scaleAmount > 0.002
	cube.set_meta("timeline_visible", timelineVisible)
	cube.visible = timelineVisible and bool(cube.get_meta("layer_enabled", true))
	cube.position = position
	cube.frame = _frameForSpin(spin)
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


static func _frameForSpin(spin: float) -> int:
	var quarterTurn := PI * 0.5
	var quarterProgress := fposmod(spin, quarterTurn) / quarterTurn
	return mini(
		int(floor(quarterProgress * float(Profile.SPRITE_ROTATION_FRAMES))),
		Profile.SPRITE_ROTATION_FRAMES - 1
	)


static func _buildPixelAtlas(palette: Array[Color]) -> ImageTexture:
	var frameSize := Profile.SPRITE_FRAME_SIZE_PX
	var frameCount := Profile.SPRITE_ROTATION_FRAMES
	var atlas := Image.create(frameSize * frameCount, frameSize, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	_paintSourceFrame(atlas, palette)
	for frameIndex in range(1, frameCount):
		_paintRotationFrame(atlas, frameIndex, palette)
	return ImageTexture.create_from_image(atlas)


static func _paintSourceFrame(atlas: Image, palette: Array[Color]) -> void:
	assert(
		Profile.SOURCE_FRAME_ROWS.size() == Profile.SPRITE_FRAME_SIZE_PX,
		"Elemental cube source frame must contain exactly 32 rows."
	)
	for y in range(Profile.SOURCE_FRAME_ROWS.size()):
		var row: String = Profile.SOURCE_FRAME_ROWS[y]
		assert(
			row.length() == Profile.SPRITE_FRAME_SIZE_PX,
			"Elemental cube source frame rows must be exactly 32 pixels wide."
		)
		for x in range(row.length()):
			var role := row.substr(x, 1)
			match role:
				"D": atlas.set_pixel(x, y, palette[0])
				"M": atlas.set_pixel(x, y, palette[1])
				"S": atlas.set_pixel(x, y, palette[2])


static func _paintRotationFrame(
		atlas: Image,
		frameIndex: int,
		palette: Array[Color]) -> void:
	var angle := (
		float(frameIndex) / float(Profile.SPRITE_ROTATION_FRAMES) * PI * 0.5
	)
	var vertices: Array[Vector3] = [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	for vertexIndex in range(vertices.size()):
		vertices[vertexIndex] = _rotatePixelVertex(vertices[vertexIndex], angle)
	var projected: Array[Vector2] = []
	for vertex: Vector3 in vertices:
		projected.append(_projectPixelVertex(vertex))

	var faceSpecs: Array[Dictionary] = [
		{"indices": PackedInt32Array([3, 2, 6, 7]), "normal": Vector3.UP},
		{"indices": PackedInt32Array([1, 5, 6, 2]), "normal": Vector3.RIGHT},
		{"indices": PackedInt32Array([0, 3, 7, 4]), "normal": Vector3.LEFT},
		{"indices": PackedInt32Array([4, 7, 6, 5]), "normal": Vector3.BACK},
		{"indices": PackedInt32Array([0, 1, 2, 3]), "normal": Vector3.FORWARD},
	]
	var cameraDirection := Vector3(-1.0, 1.0, -1.0).normalized()
	var topFace: Array[Vector2] = []
	var atlasOffsetX := frameIndex * Profile.SPRITE_FRAME_SIZE_PX
	for faceSpec: Dictionary in faceSpecs:
		var normal: Vector3 = _rotatePixelVertex(faceSpec["normal"], angle)
		if normal.dot(cameraDirection) <= 0.001:
			continue
		var points: Array[Vector2] = []
		for vertexIndex: int in faceSpec["indices"]:
			points.append(projected[vertexIndex])
		if normal.y > 0.5:
			topFace = points
			continue
		var centroidX := 0.0
		for point: Vector2 in points:
			centroidX += point.x
		centroidX /= float(points.size())
		_fillPixelPolygon(
			atlas,
			atlasOffsetX,
			points,
			palette[2] if centroidX < 15.5 else palette[1]
		)
	if not topFace.is_empty():
		_fillPixelPolygon(atlas, atlasOffsetX, topFace, palette[0])


static func _rotatePixelVertex(vertex: Vector3, angle: float) -> Vector3:
	var cosine := cos(angle)
	var sine := sin(angle)
	return Vector3(
		vertex.x * cosine + vertex.z * sine,
		vertex.y,
		-vertex.x * sine + vertex.z * cosine
	)


static func _projectPixelVertex(vertex: Vector3) -> Vector2:
	return Vector2(
		15.5 + (vertex.x - vertex.z) * 15.5,
		15.5 + (vertex.x + vertex.z) * 7.0 - vertex.y * 14.0
	)


static func _fillPixelPolygon(
		atlas: Image,
		atlasOffsetX: int,
		points: Array[Vector2],
		color: Color) -> void:
	var minimumX := Profile.SPRITE_FRAME_SIZE_PX - 1
	var maximumX := 0
	var minimumY := Profile.SPRITE_FRAME_SIZE_PX - 1
	var maximumY := 0
	for point: Vector2 in points:
		minimumX = mini(minimumX, floori(point.x))
		maximumX = maxi(maximumX, ceili(point.x))
		minimumY = mini(minimumY, floori(point.y))
		maximumY = maxi(maximumY, ceili(point.y))
	minimumX = clampi(minimumX, 0, Profile.SPRITE_FRAME_SIZE_PX - 1)
	maximumX = clampi(maximumX, 0, Profile.SPRITE_FRAME_SIZE_PX - 1)
	minimumY = clampi(minimumY, 0, Profile.SPRITE_FRAME_SIZE_PX - 1)
	maximumY = clampi(maximumY, 0, Profile.SPRITE_FRAME_SIZE_PX - 1)
	for y in range(minimumY, maximumY + 1):
		for x in range(minimumX, maximumX + 1):
			if _pointInsidePolygon(Vector2(float(x) + 0.5, float(y) + 0.5), points):
				atlas.set_pixel(atlasOffsetX + x, y, color)


static func _pointInsidePolygon(point: Vector2, polygon: Array[Vector2]) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for current in range(polygon.size()):
		var a: Vector2 = polygon[current]
		var b: Vector2 = polygon[previous]
		var crosses := (a.y > point.y) != (b.y > point.y)
		if crosses:
			var boundaryX := (
				(b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
			)
			if point.x < boundaryX:
				inside = not inside
		previous = current
	return inside


static func _countNodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _countNodes(child)
	return total
