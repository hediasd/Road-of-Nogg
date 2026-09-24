## Headless checks for the impact and area family: declared peaks equal
## sampled peaks, counts and ordering at named beats, radial monotonicity,
## placement on the affected hex cells for single, circle r1-4, cross and line
## footprints under both area modes, reach into empty outer cells when spread,
## deterministic random access, and the substrate budget.
extends SceneTree

const Catalog = preload("res://src/presentation/effects/cube_placeholders/impact/ImpactCatalog.gd")
const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const DebugWorld = preload("res://src/presentation/debug/VfxDebugWorld.gd")

const AREA_PROFILES: Array[String] = [
	"cube_ceiling_collapse", "cube_ground_teeth", "cube_expanding_shockwave",
	"cube_staggered_bombardment",
]
const SAMPLES := 801
## Height above the target's ground within which a cube counts as standing on
## the cells beneath it.
const NEAR_GROUND_U := 1.0

var _failures: PackedStringArray = PackedStringArray()
var _stage: Node3D
var _target := Vector3(4.0, 0.85, 0.0)
var _source := Vector3(-4.0, 0.35, 0.0)


func _init() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rows := Catalog.entries()
	var expectedIDs := [
		"cube_ceiling_collapse", "cube_ground_teeth", "cube_expanding_shockwave",
		"cube_implosion", "cube_rolling_avalanche", "cube_staggered_bombardment",
	]
	_expect(rows.size() == 6, "impact catalog has %d rows" % rows.size())
	for index: int in range(mini(rows.size(), expectedIDs.size())):
		_expect(str(rows[index]["profile_id"]) == expectedIDs[index], "row %d is %s" % [index, rows[index]["profile_id"]])
	for row: Dictionary in rows:
		_checkProfile(row)
	for profileID: String in AREA_PROFILES:
		_checkPlacement(profileID)
	_checkCeiling()
	_checkTeeth()
	_checkShockwave()
	_checkImplosion()
	_checkAvalanche()
	_checkBombardment()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_IMPACT_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_IMPACT_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _footprint(shape: String, radius: int) -> HexVfxFootprint:
	return DebugWorld.buildHexFootprint(shape, radius, _target, _source)


func _make(profileID: String, footprint: HexVfxFootprint = null, areaMode: String = "",
		seedValue: int = 0) -> Effect:
	var row: Dictionary = {}
	for candidate: Dictionary in Catalog.entries():
		if candidate["profile_id"] == profileID:
			row = candidate
	var playback: Effect = (row["factory"] as Callable).call(
		_stage, _target, BattleMeshFactory.elementColor("earth"), {})
	var ids: Array[int] = [2]
	var positions: Array[Vector3] = [_target]
	var bounds: Array[AABB] = [VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS]
	playback.configure_cast_context(VfxCastContext.create(1, _source, _target, ids, positions, bounds))
	if footprint != null:
		playback.setHexFootprint(footprint)
	if not areaMode.is_empty():
		playback.configure_spell_spec(Spec.fromReference({"NAME": "Area", "VFX": {"AREA_SCALING": areaMode}}))
	playback.play(seedValue, VfxPlayback.MODE_BATTLE)
	playback.set_playback_scale(0.0)
	return playback


func _at(playback: Effect, t: float) -> CubePlaceholderPoseBuffer:
	playback.seek_normalized(playback.normalizedAtSketchTime(t))
	return playback.get_pose_buffer()


func _countRole(buffer: CubePlaceholderPoseBuffer, role: int) -> int:
	var total := 0
	for index: int in range(buffer.count):
		if buffer.roles[index] == role:
			total += 1
	return total


func _flatDistance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _signature(buffer: CubePlaceholderPoseBuffer) -> String:
	var parts := PackedStringArray([str(buffer.count)])
	for index: int in range(buffer.count):
		var p := buffer.positions[index]
		parts.append("%d:%.4f,%.4f,%.4f,%.4f" % [buffer.ids[index], p.x, p.y, p.z, buffer.sizes[index]])
	return ",".join(parts)


func _checkProfile(row: Dictionary) -> void:
	var profileID := str(row["profile_id"])
	var composition = (row["composition"] as Script).new()
	var declared: int = composition.peakCubes()
	var measured := 0
	var footprints: Array = [null, _footprint("single", 1), _footprint("circle", 3)]
	for footprint in footprints:
		for mode: String in ["", "spread", "none"]:
			for seedValue: int in [0, 7]:
				var playback := _make(profileID, footprint, mode, seedValue)
				for index: int in range(SAMPLES):
					playback.seek_normalized(float(index) / float(SAMPLES - 1))
					measured = maxi(measured, playback.get_pose_buffer().count)
					if playback.get_pose_buffer().overflow > 0:
						_failures.append("%s overflowed" % profileID)
						break
				_expect(DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS,
					"%s draw calls over budget" % profileID)
				_expect(playback.get_render_node_count() <= Profile.MAX_RENDER_NODES,
					"%s render nodes over budget" % profileID)
				playback.dispose()
	_expect(measured == declared, "%s declares peak %d, samples %d" % [profileID, declared, measured])

	var reference := _make(profileID, _footprint("circle", 2), "spread")
	var poses := {}
	for index: int in range(101):
		reference.seek_normalized(float(index) / 100.0)
		poses[index] = _signature(reference.get_pose_buffer())
	for index: int in range(100, -1, -1):
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index], "%s reverse seek differs at %d" % [profileID, index])
	for index: int in [42, 7, 93, 55, 0, 100, 21]:
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index], "%s shuffled seek differs at %d" % [profileID, index])
	reference._process(0.0)
	reference.set_playback_scale(4.0)
	reference.play(0, VfxPlayback.MODE_BATTLE)
	reference._process(0.1)
	_expect(is_equal_approx(reference.get_elapsed_time(), 0.4), "%s 4x rate" % profileID)
	reference.skip_to_settle()
	_expect(not reference.is_finished() or composition.settleTime() >= 1.0, "%s settle finished the effect" % profileID)
	reference.dispose()
	reference.dispose()


## Every cube of an area profile that is on or near the ground stands on an
## affected cell, for every shape and both modes; spread over a larger area,
## the pattern reaches well out over the empty cells. Cubes still high in the
## air (a bombardment strike on its diagonal) claim no cell, so the check is of
## where cubes land and stand.
func _checkPlacement(profileID: String) -> void:
	var cases := [
		["single", 1], ["circle", 1], ["circle", 2], ["circle", 3], ["circle", 4],
		["cross", 1], ["cross", 3], ["line", 3],
	]
	for entry: Array in cases:
		var footprint := _footprint(str(entry[0]), int(entry[1]))
		for mode: String in ["spread", "none"]:
			var playback := _make(profileID, footprint, mode, 7)
			var outside := 0
			var farthest := 0.0
			var origin: Vector3 = playback.get_composition().areaOrigin(playback.get_frames()[0])
			for index: int in range(201):
				playback.seek_normalized(float(index) / 200.0)
				var buffer := playback.get_pose_buffer()
				for cube: int in range(buffer.count):
					var point := buffer.positions[cube]
					if point.y - _target.y > NEAR_GROUND_U:
						continue
					if not footprint.containsWorldPoint(point):
						outside += 1
					farthest = maxf(farthest, _flatDistance(point, origin))
			_expect(outside == 0, "%s %s r%d %s: %d cube samples off the affected cells" % [
				profileID, entry[0], entry[1], mode, outside])
			if mode == "spread" and str(entry[0]) == "circle" and int(entry[1]) >= 3:
				_expect(farthest > footprint.cell_height * int(entry[1]) * 0.6,
					"%s spread over r%d stops at %.2f, short of the outer ring" % [profileID, entry[1], farthest])
			playback.dispose()
	# Spread reaches further than none on a large disc; on one cell they agree.
	var large := _footprint("circle", 4)
	var spreadReach := _reachOf(profileID, large, "spread")
	var noneReach := _reachOf(profileID, large, "none")
	_expect(spreadReach > noneReach + 0.5, "%s spread (%.2f) does not reach past none (%.2f)" % [profileID, spreadReach, noneReach])
	var single := _footprint("single", 1)
	_expect(is_equal_approx(_reachOf(profileID, single, "spread"), _reachOf(profileID, single, "none")),
		"%s spread and none disagree on one cell" % profileID)


func _reachOf(profileID: String, footprint: HexVfxFootprint, mode: String) -> float:
	var playback := _make(profileID, footprint, mode, 7)
	var reach := 0.0
	for index: int in range(101):
		var buffer := _at(playback, float(index) / 100.0)
		for cube: int in range(buffer.count):
			reach = maxf(reach, _flatDistance(buffer.positions[cube], _target))
	playback.dispose()
	return reach


func _checkCeiling() -> void:
	var playback := _make("cube_ceiling_collapse", _footprint("circle", 2), "spread", 7)
	var composition = playback.get_composition()
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	_expect(_countRole(_at(playback, 0.26), 0) > 0 and _countRole(_at(playback, 0.26), 1) == 0,
		"ceiling: dust is not alone before the heavies")
	var dustSeen := 0
	for index: int in range(12):
		if 0.04 + frame.rnd(index) * 0.16 < 0.27:
			dustSeen += 1
	_expect(dustSeen == 12, "ceiling: only %d dust cubes start before the heavies" % dustSeen)
	_expect(_countRole(_at(playback, 0.5), 1) == 7, "ceiling: 7 heavies hang and fall by 0.50")
	var firstLanding := INF
	for index: int in range(7):
		firstLanding = minf(firstLanding, composition.heavyLandingTime(frame, index))
	_expect(firstLanding >= 0.62 - 0.0001, "ceiling: a heavy lands at %.3f, before the warning ends" % firstLanding)
	_expect(_countRole(_at(playback, 0.7), 2) > 0, "ceiling: no rubble after the fall")
	playback.dispose()


func _checkTeeth() -> void:
	var playback := _make("cube_ground_teeth", _footprint("single", 1))
	var composition = playback.get_composition()
	_expect(_countRole(_at(playback, 0.1), 0) == 5, "teeth: five trembles before the punch")
	for index: int in range(4):
		var t: float = composition.riseStart(index) + 0.1
		var buffer := _at(playback, t)
		var heights := {}
		for cube: int in range(buffer.count):
			if buffer.roles[cube] == 1:
				var tooth := (buffer.ids[cube] - 10) / 4
				heights[tooth] = maxf(float(heights.get(tooth, 0.0)), buffer.positions[cube].y)
		_expect(float(heights.get(index, 0.0)) > float(heights.get(index + 1, 0.0)),
			"teeth: tooth %d is not ahead of tooth %d" % [index, index + 1])
	_expect(_countRole(_at(playback, 0.5), 1) == 20, "teeth: five stacks of four at 0.50")
	playback.dispose()


func _checkShockwave() -> void:
	var playback := _make("cube_expanding_shockwave", _footprint("circle", 3), "spread")
	var core := _at(playback, 0.2)
	_expect(core.count == 1 and core.roles[0] == 0, "shockwave: not one core at 0.20")
	var sizes := PackedFloat32Array()
	for t: float in [0.1, 0.2, 0.28]:
		sizes.append(_at(playback, t).sizes[0])
	_expect(sizes[0] > sizes[1] and sizes[1] > sizes[2], "shockwave: the core does not compress")
	var previous := 0.0
	for t: float in [0.32, 0.4, 0.5, 0.6, 0.7, 0.8]:
		var ring := _at(playback, t)
		_expect(_countRole(ring, 1) == 24, "shockwave: ring of %d at %.2f" % [_countRole(ring, 1), t])
		var mean := 0.0
		for cube: int in range(ring.count):
			mean += _flatDistance(ring.positions[cube], _target)
		mean /= maxf(float(ring.count), 1.0)
		_expect(mean > previous, "shockwave: the ring does not move outward at %.2f" % t)
		previous = mean
	playback.dispose()


func _checkImplosion() -> void:
	var playback := _make("cube_implosion")
	var previous := INF
	for t: float in [0.3, 0.4, 0.5, 0.6, 0.66]:
		var shell := _at(playback, t)
		_expect(_countRole(shell, 0) == 18, "implosion: shell of %d at %.2f" % [_countRole(shell, 0), t])
		var mean := 0.0
		for cube: int in range(shell.count):
			if shell.roles[cube] == 0:
				mean += _flatDistance(shell.positions[cube], _target)
		mean /= 18.0
		_expect(mean < previous, "implosion: the shell does not close in at %.2f" % t)
		previous = mean
	var collapsed := _at(playback, 0.72)
	_expect(collapsed.count == 1 and collapsed.roles[0] == 1, "implosion: not one core at 0.72")
	_expect(_at(playback, 0.95).count == 0, "implosion: the core does not vanish")
	# Spread grows the sphere with the area; none keeps it.
	var small := _make("cube_implosion", _footprint("circle", 3), "none")
	var large := _make("cube_implosion", _footprint("circle", 3), "spread")
	_expect(_flatDistance(_at(large, 0.1).positions[0], _target) > _flatDistance(_at(small, 0.1).positions[0], _target),
		"implosion: spread did not widen the sphere")
	small.dispose()
	large.dispose()
	playback.dispose()


func _checkAvalanche() -> void:
	for cells: float in [2.0, 4.0, 6.0, 10.0]:
		var distance := cells * Profile.CELL_PITCH_U
		var source := Vector3(_target.x - distance, 0.35, 0.0)
		var playback: Effect = Catalog.entries()[4]["factory"].call(
			_stage, _target, BattleMeshFactory.elementColor("ice"), {})
		var ids: Array[int] = [2]
		var positions: Array[Vector3] = [_target]
		var bounds: Array[AABB] = [VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS]
		playback.configure_cast_context(VfxCastContext.create(1, source, _target, ids, positions, bounds))
		playback.setHexFootprint(_footprint("circle", 4))
		playback.play(0, VfxPlayback.MODE_BATTLE)
		var buffer := _at(playback, 0.3)
		_expect(_countRole(buffer, 0) == 2 and _countRole(buffer, 1) == 10, "avalanche: 2 boulders + 10 trail")
		# The boulders pass through the target before the break.
		var passed := false
		for t: float in [0.6, 0.63, 0.66]:
			var roll := _at(playback, t)
			for cube: int in range(roll.count):
				if roll.roles[cube] == 0 and roll.positions[cube].x > _target.x:
					passed = true
		_expect(passed, "avalanche: the boulders do not roll through the target at %.0f cells" % cells)
		_expect(is_equal_approx(playback.get_range_stretch(), clampf(cells / 4.0, 0.75, 1.5)),
			"avalanche: range stretch at %.0f cells" % cells)
		playback.dispose()


func _checkBombardment() -> void:
	var playback := _make("cube_staggered_bombardment", _footprint("circle", 2), "spread")
	var composition = playback.get_composition()
	var landings := PackedFloat32Array()
	for index: int in range(9):
		landings.append(composition.landingTime(index))
	for index: int in range(8):
		_expect(landings[8] > landings[index], "bombardment: strike %d lands after the last" % index)
	var last := _at(playback, 0.7)
	var lastSize := 0.0
	var largestOther := 0.0
	for cube: int in range(last.count):
		if last.roles[cube] != 0:
			continue
		if last.ids[cube] == 8:
			lastSize = last.sizes[cube]
		else:
			largestOther = maxf(largestOther, last.sizes[cube])
	_expect(lastSize > 0.0, "bombardment: the ninth strike is not falling at 0.70")
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var biggestAuthored := 0.0
	for index: int in range(8):
		biggestAuthored = maxf(biggestAuthored, 0.2 + frame.rnd(index) * 0.23)
	_expect(0.64 > biggestAuthored, "bombardment: the ninth strike is not the largest")
	_expect(_countRole(_at(playback, 0.8), 1) >= 14, "bombardment: the last hit has no heavy burst")
	playback.dispose()
