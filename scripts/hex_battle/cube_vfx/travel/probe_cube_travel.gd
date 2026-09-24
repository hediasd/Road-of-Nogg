## Headless checks for the travel and delivery family: declared peaks equal
## sampled peaks, sketch checkpoints at phase and contact boundaries, endpoints
## on the live anchors, deterministic random access, travel-beat stretch at
## 2/4/6/10 cells, and the substrate budget throughout.
extends SceneTree

const Catalog = preload("res://src/presentation/effects/cube_placeholders/travel/TravelCatalog.gd")
const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")

const DISTANCE_CELLS: Array[float] = [2.0, 4.0, 6.0, 10.0]
const DENSE_SAMPLES := 1201

var _failures: PackedStringArray = PackedStringArray()
var _stage: Node3D


func _init() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rows := Catalog.entries()
	_expect(rows.size() == 6, "travel catalog has %d rows" % rows.size())
	var expectedIDs := [
		"cube_arcing_pair", "cube_scattershot", "cube_corkscrew_bolt",
		"cube_returning_throw", "cube_skipping_stone", "cube_flanking_volley",
	]
	for index: int in range(rows.size()):
		_expect(str(rows[index]["profile_id"]) == expectedIDs[index],
			"row %d is %s" % [index, rows[index]["profile_id"]])
	for row: Dictionary in rows:
		_checkProfile(row)
	_checkArcingPair()
	_checkScattershot()
	_checkCorkscrew()
	_checkReturningThrow()
	_checkSkippingStone()
	_checkFlankingVolley()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_TRAVEL_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_TRAVEL_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make(profileID: String, cells: float, seedValue: int = 0, spec: Spec = null) -> Effect:
	var row: Dictionary = {}
	for candidate: Dictionary in Catalog.entries():
		if candidate["profile_id"] == profileID:
			row = candidate
	var distance := cells * Profile.CELL_PITCH_U
	var source := Vector3(-distance * 0.5, 0.35, 0.0)
	var target := Vector3(distance * 0.5, 0.85, 0.0)
	var playback: Effect = (row["factory"] as Callable).call(
		_stage, target, BattleMeshFactory.elementColor("ice"), {})
	var ids: Array[int] = [2]
	var positions: Array[Vector3] = [target]
	var bounds: Array[AABB] = [VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS]
	playback.configure_cast_context(VfxCastContext.create(1, source, target, ids, positions, bounds))
	if spec != null:
		playback.configure_spell_spec(spec)
	playback.play(seedValue, VfxPlayback.MODE_BATTLE)
	playback.set_playback_scale(0.0)
	return playback


## Shows the pose at sketch time `t`, whatever the warp.
func _at(playback: Effect, t: float) -> CubePlaceholderPoseBuffer:
	playback.seek_normalized(playback.normalizedAtSketchTime(t))
	return playback.get_pose_buffer()


func _countRole(buffer: CubePlaceholderPoseBuffer, role: int) -> int:
	var total := 0
	for index: int in range(buffer.count):
		if buffer.roles[index] == role:
			total += 1
	return total


func _flat(vector: Vector3) -> Vector2:
	return Vector2(vector.x, vector.z)


func _signature(buffer: CubePlaceholderPoseBuffer) -> String:
	var parts := PackedStringArray([str(buffer.count)])
	for index: int in range(buffer.count):
		var p := buffer.positions[index]
		parts.append("%d:%.4f,%.4f,%.4f,%.4f" % [buffer.ids[index], p.x, p.y, p.z, buffer.sizes[index]])
	return ",".join(parts)


func _checkProfile(row: Dictionary) -> void:
	var profileID := str(row["profile_id"])
	var declared: int = (row["composition"] as Script).new().peakCubes()
	var measured := 0
	for cells: float in DISTANCE_CELLS:
		for seedValue: int in [0, 7]:
			var playback := _make(profileID, cells, seedValue)
			for index: int in range(DENSE_SAMPLES):
				playback.seek_normalized(float(index) / float(DENSE_SAMPLES - 1))
				var buffer := playback.get_pose_buffer()
				measured = maxi(measured, buffer.count)
				if buffer.overflow > 0:
					_failures.append("%s overflowed at %.0f cells" % [profileID, cells])
					break
			_expect(playback.get_render_node_count() <= Profile.MAX_RENDER_NODES,
				"%s render nodes over budget" % profileID)
			_expect(DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS,
				"%s draw calls over budget" % profileID)
			playback.dispose()
	_expect(measured == declared, "%s declares peak %d, samples %d" % [profileID, declared, measured])

	# Reference distance: every beat boundary is the sketch's.
	var reference := _make(profileID, Profile.REFERENCE_DISTANCE_CELLS)
	for beat: Dictionary in (row["composition"] as Script).new().beats():
		var boundary := float(beat["end"])
		_expect(is_equal_approx(reference.normalizedAtSketchTime(boundary), boundary),
			"%s moves beat boundary %.3f at the reference distance" % [profileID, boundary])
	# Random access in three orders gives one pose per time.
	var poses := {}
	for index: int in range(101):
		var time := float(index) / 100.0
		reference.seek_normalized(time)
		poses[index] = _signature(reference.get_pose_buffer())
	for index: int in range(100, -1, -1):
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index],
			"%s reverse seek differs at %d" % [profileID, index])
	for index: int in [37, 5, 88, 61, 0, 100, 13]:
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index],
			"%s shuffled seek differs at %d" % [profileID, index])
	var referenceHold := reference.get_action_hold_seconds()
	reference.dispose()

	# Range: travel beats stretch, the rest keep their seconds.
	var composition = (row["composition"] as Script).new()
	var firstTravel := 1.0
	for beat: Dictionary in composition.beats():
		if bool(beat.get("travel", false)):
			firstTravel = minf(firstTravel, float(beat["start"]))
	for cells: float in DISTANCE_CELLS:
		var playback := _make(profileID, cells)
		var expected := clampf(cells / 4.0, 0.75, 1.5)
		_expect(is_equal_approx(playback.get_range_stretch(), expected),
			"%s stretch %.3f at %.0f cells" % [profileID, playback.get_range_stretch(), cells])
		var leadIn := playback.normalizedAtSketchTime(firstTravel) * playback.get_total_duration()
		_expect(is_equal_approx(leadIn, firstTravel * composition.battleDurationSeconds()),
			"%s lead-in changed length at %.0f cells" % [profileID, cells])
		if cells > 4.0:
			_expect(playback.get_action_hold_seconds() > referenceHold,
				"%s hold did not lengthen at %.0f cells" % [profileID, cells])
		playback.dispose()


func _checkArcingPair() -> void:
	for cells: float in DISTANCE_CELLS:
		var playback := _make("cube_arcing_pair", cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		_expect(_countRole(_at(playback, 0.4), 0) == 2, "arcing pair: two lobs in flight at 0.40")
		_expect(_countRole(_at(playback, 0.6), 1) == 8, "arcing pair: 8 chips after the first landing")
		_expect(_countRole(_at(playback, 0.7), 1) == 20, "arcing pair: 20 chips after the second")
		var landed := _at(playback, 0.6799)
		var lob := -1
		for index: int in range(landed.count):
			if landed.ids[index] == 1:
				lob = index
		_expect(lob >= 0 and _flat(landed.positions[lob]).distance_to(_flat(frame.nearTarget(0.0, 0.0, 0.22))) < 0.01,
			"arcing pair: second lob does not land beside the target at %.0f cells" % cells)
		# The two lobs leave from opposite sides of the caster.
		var early := _at(playback, 0.3)
		var sides := PackedFloat32Array()
		for index: int in range(early.count):
			sides.append((early.positions[index] - frame.source).dot(frame.side))
		_expect(sides.size() == 2 and sides[0] * sides[1] < 0.0, "arcing pair: lobs are not on both sides")
		playback.dispose()


func _checkScattershot() -> void:
	var playback := _make("cube_scattershot", 4.0)
	_expect(_countRole(_at(playback, 0.3), 0) == 11, "scattershot: eleven in the pack at 0.30")
	# The cone widens: lateral spread grows through the fan.
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var widths := PackedFloat32Array()
	for t: float in [0.25, 0.35, 0.45]:
		var buffer := _at(playback, t)
		var low := INF
		var high := -INF
		for index: int in range(buffer.count):
			if buffer.roles[index] != 0:
				continue
			var lateral := (buffer.positions[index] - frame.source).dot(frame.side)
			low = minf(low, lateral)
			high = maxf(high, lateral)
		widths.append(high - low)
	_expect(widths[0] < widths[1] and widths[1] < widths[2], "scattershot: the cone does not widen")
	playback.dispose()
	# An area spread opens the landing pattern without moving the source.
	var spreadSpec := Spec.fromReference({"NAME": "Splatter", "VFX": {"AREA_SCALING": "spread"}})
	var spread := _make("cube_scattershot", 4.0, 0, spreadSpec)
	_expect(is_equal_approx((spread.get_frames()[0] as CubePlaceholderFrame).areaScale, 1.0),
		"scattershot: spread without a footprint changed scale")
	spread.dispose()


func _checkCorkscrew() -> void:
	var playback := _make("cube_corkscrew_bolt", 4.0)
	var buffer := _at(playback, 0.4)
	_expect(_countRole(buffer, 0) == 1 and _countRole(buffer, 1) == 7, "corkscrew: 1 bolt + 7 wake at 0.40")
	_expect(_countRole(_at(playback, 0.7), 2) == 16, "corkscrew: 16-chip burst at 0.70")
	_expect(_at(playback, 0.66).count >= 8 and _countRole(_at(playback, 0.68), 0) == 0,
		"corkscrew: bolt does not end at 0.67")
	playback.dispose()


func _checkReturningThrow() -> void:
	for cells: float in DISTANCE_CELLS:
		var playback := _make("cube_returning_throw", cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		var clip := _at(playback, 0.505)
		_expect(_flat(clip.positions[0]).distance_to(_flat(frame.target)) < 0.01,
			"returning throw: no target contact at 0.505 (%.0f cells)" % cells)
		var home := _at(playback, 0.889)
		_expect(_flat(home.positions[0]).distance_to(_flat(frame.source)) < 0.05,
			"returning throw: does not return to the caster (%.0f cells)" % cells)
		var outbound := (_at(playback, 0.3).positions[0] - frame.source).dot(frame.side)
		var inbound := (_at(playback, 0.7).positions[0] - frame.source).dot(frame.side)
		_expect(outbound * inbound < 0.0, "returning throw: out and back on the same side")
		playback.dispose()


func _checkSkippingStone() -> void:
	for cells: float in DISTANCE_CELLS:
		var playback := _make("cube_skipping_stone", cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		var composition = playback.get_composition()
		var nodes: Array[Vector3] = composition.nodes(frame)
		var contacts := 0
		for hop: int in range(3):
			var contact: float = composition.contactTime(hop)
			var before := _at(playback, contact - 0.001)
			var stoneIndex := -1
			for index: int in range(before.count):
				if before.roles[index] == 0:
					stoneIndex = index
			var landed := stoneIndex >= 0 and _flat(before.positions[stoneIndex]).distance_to(_flat(nodes[hop + 1])) < 0.1
			var chips := _countRole(_at(playback, contact + 0.05), 1)
			if landed and chips >= 6:
				contacts += 1
		_expect(contacts == 3, "skipping stone: %d contacts at %.0f cells" % [contacts, cells])
		playback.dispose()


func _checkFlankingVolley() -> void:
	for cells: float in DISTANCE_CELLS:
		var playback := _make("cube_flanking_volley", cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		var converge := _at(playback, 0.699)
		_expect(converge.count == 4, "flanking volley: %d cubes at convergence" % converge.count)
		for index: int in range(converge.count):
			_expect(_flat(converge.positions[index]).distance_to(_flat(frame.target)) < 0.15,
				"flanking volley: cube %d not on the target at 0.699 (%.0f cells)" % [index, cells])
		var wide := _at(playback, 0.42)
		var left := 0
		var right := 0
		for index: int in range(wide.count):
			var lateral := (wide.positions[index] - frame.source).dot(frame.side)
			if lateral < -0.5:
				left += 1
			elif lateral > 0.5:
				right += 1
		_expect(left == 2 and right == 2, "flanking volley: flanks %d/%d at mid-flight" % [left, right])
		_expect(_countRole(_at(playback, 0.72), 1) == 18, "flanking volley: 18-chip burst")
		playback.dispose()
