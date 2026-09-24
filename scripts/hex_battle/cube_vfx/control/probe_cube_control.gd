## Headless checks for the shape and control family: declared peaks equal
## sampled peaks, exact structures and closure/contact events, uniform cube
## scale across body presets and under area spread, no claimed area for
## body-only profiles, barricade placement including a zero-length cast,
## deterministic random access across holds, and the substrate budget.
extends SceneTree

const Catalog = preload("res://src/presentation/effects/cube_placeholders/control/ControlCatalog.gd")
const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const DebugWorld = preload("res://src/presentation/debug/VfxDebugWorld.gd")

const BODY_PROFILES: Array[String] = [
	"cube_closing_cage", "cube_climbing_coil", "cube_clapping_slabs", "cube_encasing_frost",
]
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
		"cube_rising_barricade", "cube_closing_cage", "cube_climbing_coil",
		"cube_lifting_vortex", "cube_clapping_slabs", "cube_encasing_frost",
	]
	_expect(rows.size() == 6, "control catalog has %d rows" % rows.size())
	for index: int in range(mini(rows.size(), expectedIDs.size())):
		_expect(str(rows[index]["profile_id"]) == expectedIDs[index], "row %d is %s" % [index, rows[index]["profile_id"]])
	for row: Dictionary in rows:
		_checkProfile(row)
	for profileID: String in BODY_PROFILES:
		_checkBodyScale(profileID)
		_checkNoClaimedArea(profileID)
	_checkBarricade()
	_checkSpreadStaysOnCells()
	_checkCage()
	_checkCoil()
	_checkVortex()
	_checkSlabs()
	_checkFrost()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_CONTROL_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_CONTROL_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _bounds(preset: String) -> AABB:
	for entry: Dictionary in DebugWorld.TARGET_BODY_PRESETS:
		if entry["id"] == preset:
			return entry["bounds"]
	return VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS


func _make(profileID: String, body: String = "standard", spec: Spec = null,
		footprint: HexVfxFootprint = null, source: Vector3 = _source, seedValue: int = 0,
		front: Vector3 = Vector3.ZERO) -> Effect:
	var row: Dictionary = {}
	for candidate: Dictionary in Catalog.entries():
		if candidate["profile_id"] == profileID:
			row = candidate
	var playback: Effect = (row["factory"] as Callable).call(
		_stage, _target, BattleMeshFactory.elementColor("wood"), {})
	var ids: Array[int] = [2]
	var positions: Array[Vector3] = [_target]
	var bounds: Array[AABB] = [_bounds(body)]
	var impact := _target if source != _target else _target
	playback.configure_cast_context(VfxCastContext.create(1, source, impact, ids, positions, bounds))
	if footprint != null:
		playback.setHexFootprint(footprint)
	if spec != null:
		playback.configure_spell_spec(spec)
	if front != Vector3.ZERO:
		playback.configure_facing(front)
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
	var declared: int = (row["composition"] as Script).new().peakCubes()
	var measured := 0
	for body: String in ["standard", "wide", "tall"]:
		for seedValue: int in [0, 7]:
			var playback := _make(profileID, body, null, null, _source, seedValue)
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
	# Random access across the hold: a seek into the hold from either side, or
	# from far away, lands on the same pose.
	var reference := _make(profileID, "wide")
	var poses := {}
	for index: int in range(101):
		reference.seek_normalized(float(index) / 100.0)
		poses[index] = _signature(reference.get_pose_buffer())
	for index: int in range(100, -1, -1):
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index], "%s reverse seek differs at %d" % [profileID, index])
	for index: int in [70, 3, 99, 66, 81, 0, 75]:
		reference.seek_normalized(float(index) / 100.0)
		_expect(_signature(reference.get_pose_buffer()) == poses[index], "%s shuffled seek differs at %d" % [profileID, index])
	reference.dispose()


## Every cube of a body-bound study scales by one factor from the standard
## body to a wide or tall one, and that factor is the substrate's uniform body
## adaptation: the same choreography, only larger.
func _checkBodyScale(profileID: String) -> void:
	var standard := _make(profileID, "standard")
	for preset: String in ["wide", "tall"]:
		var other := _make(profileID, preset)
		var factor: float = (other.get_frames()[0] as CubePlaceholderFrame).bodyScale
		_expect(factor > 1.0, "%s %s body did not scale up" % [profileID, preset])
		for t: float in [0.3, 0.55, 0.7]:
			var small := _at(standard, t)
			var smallSizes := small.sizes.duplicate()
			var smallCount := small.count
			var large := _at(other, t)
			_expect(large.count == smallCount, "%s %s changes the cube count at %.2f" % [profileID, preset, t])
			for index: int in range(mini(smallCount, large.count)):
				if smallSizes[index] <= 0.0001:
					continue
				var ratio := large.sizes[index] / smallSizes[index]
				_expect(absf(ratio - factor) < 0.001,
					"%s %s cube %d scales %.3f, body factor %.3f" % [profileID, preset, index, ratio, factor])
		other.dispose()
	standard.dispose()


## With a footprint but no area spread, a body-bound shape stays within reach
## of the body; with spread it widens to the footprint, cube sizes unchanged.
func _checkNoClaimedArea(profileID: String) -> void:
	var footprint := DebugWorld.buildHexFootprint("circle", 3, _target, _source)
	var none := _make(profileID, "standard", Spec.fromReference({"NAME": "N", "VFX": {"AREA_SCALING": "none"}}), footprint)
	var bare := _make(profileID, "standard")
	var composition = none.get_composition()
	var bodyReach: float = (composition.areaReferenceRadius() + 1.5) * Profile.UNIT_U
	for t: float in [0.3, 0.55, 0.7]:
		_expect(_signature(_at(none, t)) == _signature(_at(bare, t)),
			"%s claims area without a spread at %.2f" % [profileID, t])
		var buffer := _at(none, t)
		for index: int in range(buffer.count):
			_expect(_flatDistance(buffer.positions[index], _target) <= bodyReach,
				"%s reaches past its body at %.2f" % [profileID, t])
	var spread := _make(profileID, "standard", Spec.fromReference({"NAME": "S", "VFX": {"AREA_SCALING": "spread"}}), footprint)
	var wider := false
	for t: float in [0.3, 0.55]:
		var a := _at(spread, t)
		var aSizes := a.sizes.duplicate()
		var aPositions := a.positions.duplicate()
		var b := _at(bare, t)
		for index: int in range(mini(a.count, b.count)):
			_expect(is_equal_approx(aSizes[index], b.sizes[index]), "%s spread changed a cube size" % profileID)
			if _flatDistance(aPositions[index], _target) > _flatDistance(b.positions[index], _target) + 0.5:
				wider = true
	_expect(wider, "%s spread did not widen over the footprint" % profileID)
	none.dispose()
	bare.dispose()
	spread.dispose()


## Spreading only widens a shape onto affected cells: a grounded cube the
## spread moved further out than its body-sized position stands on an affected
## cell, on a disc clipped by the board edge (cells on one side removed), a
## cross and a full disc; and no cube is pulled inside its body-sized
## position. Where the footprint is narrower than the body-sized shape, the
## shape keeps its body size, exactly as without a spread. Found in
## live-battle validation: a spread cage near the board edge put posts off
## the board.
func _checkSpreadStaysOnCells() -> void:
	var spread := Spec.fromReference({"NAME": "Spread", "VFX": {"AREA_SCALING": "spread"}})
	var clipped := DebugWorld.buildHexFootprint("circle", 2, _target, _source)
	var keptCells: Array[Vector2i] = []
	var keptPositions: Array[Vector3] = []
	for index: int in range(clipped.cellCount()):
		if clipped.world_positions[index].x <= _target.x + 1.0:
			keptCells.append(clipped.cells[index])
			keptPositions.append(clipped.world_positions[index])
	clipped.cells = keptCells
	clipped.world_positions = keptPositions
	var cases := {
		"clipped disc": clipped,
		"cross": DebugWorld.buildHexFootprint("cross", 2, _target, _source),
		"full disc": DebugWorld.buildHexFootprint("circle", 2, _target, _source),
	}
	for profileID: String in ["cube_closing_cage", "cube_lifting_vortex"]:
		var bare := _make(profileID)
		for name: String in cases:
			var footprint: HexVfxFootprint = cases[name]
			var playback := _make(profileID, "standard", spread, footprint)
			var off := 0
			var shrunk := 0
			for index: int in range(101):
				var t := float(index) / 100.0
				var buffer := _at(playback, t)
				var positions := buffer.positions.duplicate()
				var count := buffer.count
				var reference := _at(bare, t)
				for cube: int in range(count):
					var spreadReach := _flatDistance(positions[cube], _target)
					var bodyReach := _flatDistance(reference.positions[cube], _target) if cube < reference.count else 0.0
					var widened := spreadReach > bodyReach + 0.001
					if widened and positions[cube].y - _target.y < 1.0 and not footprint.containsWorldPoint(positions[cube]):
						off += 1
					if spreadReach + 0.001 < bodyReach:
						shrunk += 1
			_expect(off == 0, "%s spread over a %s: %d cube samples widened onto unaffected ground" % [profileID, name, off])
			_expect(shrunk == 0, "%s spread over a %s: %d cube samples pulled inside the body-sized shape" % [profileID, name, shrunk])
			playback.dispose()
		bare.dispose()


func _checkBarricade() -> void:
	# Two anchors at the reference distance: the wall stands 57% of the way.
	var playback := _make("cube_rising_barricade")
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var built := _at(playback, 0.6)
	_expect(built.count == 15, "barricade: %d cubes in the built wall" % built.count)
	var centre := Vector3.ZERO
	for index: int in range(built.count):
		centre += built.positions[index]
	centre /= float(built.count)
	var expected := frame.along(CubePlaceholderFrame.progressOfSketchX(-0.25))
	_expect(_flatDistance(centre, expected) < 0.05, "barricade: wall not between caster and target")
	# Rows: three layers of five running across the cast direction.
	var lateral := PackedFloat32Array()
	for index: int in range(5):
		lateral.append((built.positions[index] - centre).dot(frame.side))
	_expect(lateral[4] - lateral[0] > 2.0 and absf((built.positions[4] - built.positions[0]).dot(frame.forward)) < 0.01,
		"barricade: the wall does not run across the cast direction")
	_expect(built.positions[10].y > built.positions[5].y and built.positions[5].y > built.positions[0].y,
		"barricade: the layers do not stack upward")
	_expect(_at(playback, 0.99).count == 0, "barricade: the wall does not withdraw")
	playback.dispose()
	# A self-cast anchored in front of the caster: zero-length source to impact.
	var selfSpec := Spec.fromReference({"NAME": "Barricade", "VFX": {"ANCHOR": "caster_front", "RANGE_SCALING": "fixed"}})
	var selfCast := _make("cube_rising_barricade", "standard", selfSpec, null, _target, 0, Vector3(0.0, 0.0, 1.0))
	var selfFrame: CubePlaceholderFrame = selfCast.get_frames()[0]
	_expect(_flatDistance(selfFrame.target, _target + Vector3(0.0, 0.0, Profile.CELL_PITCH_U)) < 0.001,
		"barricade: caster_front anchor is not a cell in front")
	var wall := _at(selfCast, 0.6)
	var wallCentre := Vector3.ZERO
	for index: int in range(wall.count):
		wallCentre += wall.positions[index]
		_expect(is_finite(wall.positions[index].x) and is_finite(wall.positions[index].z), "barricade: non-finite self-cast cube")
	wallCentre /= maxf(float(wall.count), 1.0)
	_expect(wall.count == 15 and _flatDistance(wallCentre, selfFrame.target) < 0.05,
		"barricade: self-cast wall does not stand on its anchor")
	_expect(absf((wall.positions[4] - wall.positions[0]).dot(Vector3(0.0, 0.0, 1.0))) < 0.01,
		"barricade: self-cast wall does not run across the front")
	selfCast.dispose()


func _checkCage() -> void:
	var playback := _make("cube_closing_cage")
	var open := _at(playback, 0.4)
	_expect(_countRole(open, 0) == 12 and _countRole(open, 1) == 4, "cage: four posts of four at 0.40")
	var before := 0.0
	var after := 0.0
	var closed := _at(playback, 0.66)
	var lidAfter := PackedVector3Array()
	for index: int in range(closed.count):
		if closed.roles[index] == 1:
			lidAfter.append(closed.positions[index])
	var early := _at(playback, 0.4)
	for index: int in range(early.count):
		if early.roles[index] == 1:
			before += _flatDistance(early.positions[index], _target)
	for position: Vector3 in lidAfter:
		after += _flatDistance(position, _target)
	_expect(after < before * 0.5, "cage: the lid does not close overhead")
	var held := _signature(_at(playback, 0.7))
	_expect(held == _signature(_at(playback, 0.8)), "cage: the hold moves")
	playback.dispose()


func _checkCoil() -> void:
	var playback := _make("cube_climbing_coil")
	_expect(_at(playback, 0.6).count == 22, "coil: 22 cubes climbing")
	var loose := _at(playback, 0.6)
	var looseRadius := _flatDistance(loose.positions[0], _target)
	var tight := _flatDistance(_at(playback, 0.82).positions[0], _target)
	_expect(tight < looseRadius * 0.7, "coil: does not tighten")
	var heights := _at(playback, 0.6)
	var rising := true
	for index: int in range(1, heights.count):
		rising = rising and heights.positions[index].y > heights.positions[index - 1].y
	_expect(rising, "coil: not a climbing helix")
	playback.dispose()


func _checkVortex() -> void:
	var playback := _make("cube_lifting_vortex")
	var composition = playback.get_composition()
	_expect(_at(playback, 0.1).count > 0, "vortex: no skirt")
	# Sweep inward then release outward, per cube.
	var released := 0
	for i: int in range(28):
		var start := 0.015 + i * 0.009
		var end := 0.58 + i * 0.009
		var mid: float = composition.radiusAt(i, start + (end - start) * 0.7)
		var late: float = composition.radiusAt(i, end)
		var skirt: float = composition.radiusAt(i, start)
		if skirt > mid and late > mid:
			released += 1
	_expect(released == 28, "vortex: %d of 28 cubes are flung out rather than fading" % released)
	_expect(_at(playback, 0.4).count == 28, "vortex: 28 in the spiral")
	playback.dispose()


func _checkSlabs() -> void:
	var playback := _make("cube_clapping_slabs")
	_expect(_countRole(_at(playback, 0.3), 0) == 12, "slabs: two walls of six")
	var contact := _at(playback, 0.62)
	var near := INF
	for index: int in range(contact.count):
		if contact.roles[index] == 0:
			near = minf(near, _flatDistance(contact.positions[index], _target))
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var slabHalf: float = 0.22 * frame.cubeScale()
	_expect(near - slabHalf < VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS.size.x * 0.5,
		"slabs: the slabs do not meet on the body at 0.62")
	var open := _at(playback, 0.3)
	var far := INF
	for index: int in range(open.count):
		far = minf(far, _flatDistance(open.positions[index], _target))
	_expect(far > near + 1.0, "slabs: no slam, they start where they end")
	var shattered := _at(playback, 0.7)
	_expect(_countRole(shattered, 0) == 0 and _countRole(shattered, 1) == 26, "slabs: fragments do not replace the slabs")
	playback.dispose()


func _checkFrost() -> void:
	var playback := _make("cube_encasing_frost")
	var locked := _at(playback, 0.6)
	_expect(_countRole(locked, 0) == 18, "frost: shell of %d at lock" % _countRole(locked, 0))
	var rows := {}
	for index: int in range(locked.count):
		if locked.roles[index] == 0:
			var key := snappedf(locked.positions[index].y, 0.01)
			rows[key] = int(rows.get(key, 0)) + 1
	_expect(rows.size() == 3 and rows.values().all(func(count: int) -> bool: return count == 6),
		"frost: not three rings of six")
	var seeded := _at(playback, 0.1)
	var lowest := INF
	var highest := -INF
	for index: int in range(seeded.count):
		lowest = minf(lowest, seeded.positions[index].y)
		highest = maxf(highest, seeded.positions[index].y)
	_expect(seeded.count > 0 and highest - lowest < 0.1, "frost: does not start from the feet")
	_expect(_countRole(_at(playback, 0.88), 1) == 12, "frost: no release chips")
	playback.dispose()
