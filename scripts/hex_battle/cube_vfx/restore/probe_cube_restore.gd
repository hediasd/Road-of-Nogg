## Headless checks for the restore and transform family: declared peaks equal
## sampled peaks, directional motion, population handoffs, guard collision and
## recovery with one and six anchors, stable coincident-anchor casts, two-element
## palettes, the charge's hold, deterministic random access at every handoff,
## and the substrate budget.
extends SceneTree

const Catalog = preload("res://src/presentation/effects/cube_placeholders/restore/RestoreCatalog.gd")
const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")

const SAMPLES := 801

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
		"cube_repair_mend", "cube_intercepting_guard", "cube_siphon",
		"cube_cleanse", "cube_blink_transfer", "cube_charge_release",
	]
	_expect(rows.size() == 6, "restore catalog has %d rows" % rows.size())
	for index: int in range(mini(rows.size(), expectedIDs.size())):
		_expect(str(rows[index]["profile_id"]) == expectedIDs[index], "row %d is %s" % [index, rows[index]["profile_id"]])
	for row: Dictionary in rows:
		_checkProfile(row)
		_checkCoincident(str(row["profile_id"]))
	_checkRepair()
	_checkGuard()
	_checkGuardSpread()
	_checkSiphon()
	_checkCleanse()
	_checkBlink()
	_checkCharge()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_RESTORE_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_RESTORE_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make(profileID: String, source: Vector3 = _source, spec: Spec = null, targets: int = 1,
		seedValue: int = 0, fronts: Array[Vector3] = [], cells: float = 4.0) -> Effect:
	var row: Dictionary = {}
	for candidate: Dictionary in Catalog.entries():
		if candidate["profile_id"] == profileID:
			row = candidate
	var target := _target if source != _source or is_equal_approx(cells, 4.0) \
		else Vector3(_source.x + cells * Profile.CELL_PITCH_U, _target.y, 0.0)
	var playback: Effect = (row["factory"] as Callable).call(
		_stage, target, BattleMeshFactory.elementColor("water"), {})
	var ids: Array[int] = []
	var positions: Array[Vector3] = []
	var bounds: Array[AABB] = []
	for index: int in range(targets):
		ids.append(10 + index)
		positions.append(target + Vector3(0.0, 0.0, 1.8 * index))
		bounds.append(VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS)
	playback.configure_cast_context(VfxCastContext.create(1, source, target, ids, positions, bounds))
	if spec != null:
		playback.configure_spell_spec(spec)
	if not fronts.is_empty():
		playback.configure_facing(fronts[0], fronts)
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


func _positionOf(buffer: CubePlaceholderPoseBuffer, id: int) -> Vector3:
	for index: int in range(buffer.count):
		if buffer.ids[index] == id:
			return buffer.positions[index]
	return Vector3(INF, INF, INF)


func _sizeOf(buffer: CubePlaceholderPoseBuffer, id: int) -> float:
	for index: int in range(buffer.count):
		if buffer.ids[index] == id:
			return buffer.sizes[index]
	return 0.0


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
	for cells: float in [2.0, 4.0, 10.0]:
		for seedValue: int in [0, 7]:
			var playback := _make(profileID, _source, null, 1, seedValue, [], cells)
			for index: int in range(SAMPLES):
				playback.seek_normalized(float(index) / float(SAMPLES - 1))
				measured = maxi(measured, playback.get_pose_buffer().count)
				if playback.get_pose_buffer().overflow > 0:
					_failures.append("%s overflowed" % profileID)
					break
			_expect(DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS, "%s draw calls over budget" % profileID)
			_expect(playback.get_render_node_count() <= Profile.MAX_RENDER_NODES, "%s render nodes over budget" % profileID)
			playback.dispose()
	_expect(measured == declared, "%s declares peak %d, samples %d" % [profileID, declared, measured])
	# Random access at every beat boundary (the handoffs) and between.
	var reference := _make(profileID)
	var times: Array[float] = []
	for beat: Dictionary in composition.beats():
		for offset: float in [-0.002, 0.0, 0.002]:
			times.append(clampf(float(beat["start"]) + offset, 0.0, 1.0))
	for index: int in range(21):
		times.append(float(index) / 20.0)
	var poses := {}
	for t: float in times:
		poses[t] = _signature(_at(reference, t))
	var reversed := times.duplicate()
	reversed.reverse()
	for t: float in reversed:
		_expect(_signature(_at(reference, t)) == poses[t], "%s seek differs at %.3f" % [profileID, t])
	reference.dispose()


## A cast whose source and anchor coincide: every cube finite, a unit forward.
func _checkCoincident(profileID: String) -> void:
	for spread: bool in [false, true]:
		var spec: Spec = null
		if spread:
			spec = Spec.fromReference({"NAME": "Self", "VFX": {"SPREAD": "each_target"}})
		var playback := _make(profileID, _target, spec)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		_expect(is_equal_approx(frame.forward.length(), 1.0) and is_equal_approx(frame.side.length(), 1.0),
			"%s self-cast has no direction" % profileID)
		var bad := 0
		for index: int in range(101):
			var buffer := _at(playback, float(index) / 100.0)
			for cube: int in range(buffer.count):
				var p := buffer.positions[cube]
				if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(buffer.sizes[cube])):
					bad += 1
		_expect(bad == 0, "%s self-cast produced %d non-finite cubes" % [profileID, bad])
		playback.dispose()


func _checkRepair() -> void:
	var playback := _make("cube_repair_mend", _target)
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	_expect(_countRole(_at(playback, 0.3), 0) == 12 and _countRole(_at(playback, 0.3), 1) == 0, "repair: 12 fragments first")
	var handoff := _at(playback, 0.58)
	_expect(_countRole(handoff, 0) == 12 and _countRole(handoff, 1) == 4, "repair: fragments and blocks overlap at the handoff")
	var built := _at(playback, 0.7)
	_expect(_countRole(built, 0) == 0 and _countRole(built, 1) == 4, "repair: not four blocks after reassembly")
	var base: Vector3 = playback.get_composition().stackBase(frame)
	for index: int in range(built.count):
		_expect(_flatDistance(built.positions[index], base) < 0.001, "repair: blocks not stacked")
	_expect(_flatDistance(base, frame.target) > VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS.size.x * 0.5,
		"repair: the stack stands inside the body")
	var early := 0.0
	var late := 0.0
	for index: int in range(12):
		early += _flatDistance(_positionOf(_at(playback, 0.1), index), base)
		late += _flatDistance(_positionOf(_at(playback, 0.5), index), base)
	_expect(late < early * 0.5, "repair: fragments do not gather")
	playback.dispose()


func _checkGuard() -> void:
	var front: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0)]
	var playback := _make("cube_intercepting_guard", _source, null, 1, 0, front)
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var axis := frame.front
	var orbit := _at(playback, 0.1)
	_expect(_countRole(orbit, 0) == 6, "guard: six orbiters")
	var engaged := _at(playback, 0.55)
	var incoming := _positionOf(_at(playback, 0.549), 10)
	for id: int in range(6):
		var guard := _positionOf(engaged, id)
		_expect((guard - frame.target).dot(axis) > 0.5, "guard: orbiter %d not on the threat side at 0.55" % id)
		_expect(_flatDistance(guard, incoming) < 1.2, "guard: orbiter %d does not meet the incoming cube" % id)
	var start := _positionOf(_at(playback, 0.24), 10)
	_expect((start - frame.target).dot(axis) > (incoming - frame.target).dot(axis) + 2.0,
		"guard: the incoming cube does not come in along the threat axis")
	_expect(_countRole(_at(playback, 0.56), 1) == 0 and _countRole(_at(playback, 0.56), 2) == 9,
		"guard: the incoming cube is not absorbed into chips")
	var recovered := _at(playback, 0.88)
	for id: int in range(6):
		var r := _flatDistance(_positionOf(recovered, id), frame.target)
		_expect(absf(r - 0.85 * frame.targetScale()) < 0.05, "guard: orbiter %d does not recover its orbit" % id)
	playback.dispose()


## Six adjacent protected allies, each with its own threat side: six rings,
## each forming its wall on its own front.
func _checkGuardSpread() -> void:
	var spec := Spec.fromReference({"NAME": "Ooze Shield", "VFX": {"SPREAD": "each_target"}})
	var fronts: Array[Vector3] = []
	for index: int in range(6):
		var angle := index * TAU / 6.0
		fronts.append(Vector3(cos(angle), 0.0, sin(angle)))
	var playback := _make("cube_intercepting_guard", _target, spec, 6, 0, fronts)
	_expect(playback.get_frames().size() == 6, "guard spread: %d anchors" % playback.get_frames().size())
	var engaged := _at(playback, 0.5)
	_expect(engaged.count == 6 * 7, "guard spread: %d cubes engaged, expected six rings and six incoming" % engaged.count)
	for anchor: int in range(6):
		var frame: CubePlaceholderFrame = playback.get_frames()[anchor]
		_expect(frame.front.is_equal_approx(fronts[anchor]), "guard spread: anchor %d lost its front" % anchor)
		for index: int in range(engaged.count):
			if engaged.anchors[index] == anchor and engaged.roles[index] == 0:
				_expect((engaged.positions[index] - frame.target).dot(fronts[anchor]) > 0.5,
					"guard spread: anchor %d wall not on its own front" % anchor)
	var peak := 0
	for index: int in range(201):
		playback.seek_normalized(float(index) / 200.0)
		peak = maxi(peak, playback.get_pose_buffer().count)
		_expect(playback.get_pose_buffer().overflow == 0, "guard spread overflow")
	_expect(peak == 6 * 15, "guard spread peak %d" % peak)
	_expect(DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS, "guard spread draw calls")
	playback.dispose()


func _checkSiphon() -> void:
	for cells: float in [2.0, 4.0, 10.0]:
		var playback := _make("cube_siphon", _source, null, 1, 0, [], cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		for id: int in range(9):
			var a := 0.07 + id * 0.04
			var first := _positionOf(_at(playback, a + 0.02), id)
			var middle := _positionOf(_at(playback, a + 0.18), id)
			var last := _positionOf(_at(playback, a + 0.34), id)
			_expect(_flatDistance(first, frame.target) < _flatDistance(first, frame.source),
				"siphon: stream cube %d does not leave the target" % id)
			_expect(_flatDistance(last, frame.source) < _flatDistance(middle, frame.source)
				and _flatDistance(middle, frame.source) < _flatDistance(first, frame.source),
				"siphon: stream cube %d does not travel to the caster at %.0f cells" % [id, cells])
		var grown := PackedFloat32Array()
		for t: float in [0.3, 0.5, 0.7]:
			grown.append(_sizeOf(_at(playback, t), 20))
		_expect(grown[0] < grown[1] and grown[1] < grown[2], "siphon: the caster's cube does not grow")
		_expect(_flatDistance(_positionOf(_at(playback, 0.5), 20), frame.source) < 0.001, "siphon: absorber not over the caster")
		playback.dispose()


func _checkCleanse() -> void:
	var playback := _make("cube_cleanse")
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var clinging := _at(playback, 0.2)
	_expect(clinging.count == 10, "cleanse: ten attached")
	var clingRadius := _flatDistance(clinging.positions[0], frame.target)
	var outward := _flatDistance(_positionOf(_at(playback, 0.6), 0), frame.target)
	_expect(outward > clingRadius * 1.5, "cleanse: cubes do not cast away outward")
	_expect(_at(playback, 0.9).count == 0, "cleanse: the target is not left clear")
	playback.dispose()


func _checkBlink() -> void:
	var spec := Spec.fromReference({"NAME": "Feather Time", "VFX": {"ELEMENTS": ["steel", "wind"]}})
	for cells: float in [2.0, 4.0, 10.0]:
		var playback := _make("cube_blink_transfer", _source, spec, 1, 0, [], cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		var start := _at(playback, 0.15)
		_expect(start.count == 8, "blink: eight in the cluster")
		for index: int in range(start.count):
			_expect(_flatDistance(start.positions[index], frame.source) < 0.5, "blink: cluster not at the caster")
		var end := _at(playback, 0.7)
		for index: int in range(end.count):
			_expect(_flatDistance(end.positions[index], frame.target) < 0.5, "blink: cluster not reformed at the target (%.0f cells)" % cells)
		# In sequence: the first cube is further along than the last mid-streak.
		var mid := _at(playback, 0.4)
		_expect(_flatDistance(_positionOf(mid, 0), frame.target) < _flatDistance(_positionOf(mid, 7), frame.target),
			"blink: cubes do not cross in sequence")
		_expect(playback.get_palette_keys() == ["steel", "wind"], "blink: palettes %s" % str(playback.get_palette_keys()))
		var rows := {}
		for index: int in range(end.count):
			rows[posmod(end.ids[index], 2)] = true
		_expect(rows.size() == 2, "blink: both elements not present")
		playback.dispose()


func _checkCharge() -> void:
	for cells: float in [2.0, 4.0, 10.0]:
		var playback := _make("cube_charge_release", _source, null, 1, 0, [], cells)
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		_expect(_countRole(_at(playback, 0.1), 0) == 16, "charge: sixteen gathering")
		_expect(_countRole(_at(playback, 0.45), 0) == 0 and _countRole(_at(playback, 0.45), 1) == 1,
			"charge: gather does not hand off to one heavy cube")
		var held := _positionOf(_at(playback, 0.42), 20)
		var heldSize := _sizeOf(_at(playback, 0.42), 20)
		for t: float in [0.45, 0.5, 0.549]:
			var buffer := _at(playback, t)
			_expect(_positionOf(buffer, 20).distance_to(held) < 0.0001, "charge: the charge moves during the hold (%.3f)" % t)
			_expect(absf(_sizeOf(buffer, 20) - heldSize) <= heldSize * 0.051, "charge: the charge grows during the hold")
		_expect(_flatDistance(held, frame.source) < 0.001, "charge: the hold is not over the caster")
		var fired := _positionOf(_at(playback, 0.7), 20)
		_expect(_flatDistance(fired, frame.target) < _flatDistance(held, frame.target), "charge: does not fire toward the target")
		_expect(_countRole(_at(playback, 0.77), 2) == 24, "charge: no shatter at the target")
		# The hold keeps its seconds at any range; only the fire stretches.
		var holdSeconds := (playback.normalizedAtSketchTime(0.55) - playback.normalizedAtSketchTime(0.42)) * playback.get_total_duration()
		_expect(is_equal_approx(holdSeconds, 0.13 * playback.get_composition().battleDurationSeconds()),
			"charge: hold length changed at %.0f cells" % cells)
		playback.dispose()
