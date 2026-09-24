## Headless checks for the cube placeholder substrate and the spell VFX spec:
## spec parsing and defaults, the range warp, deterministic random-access
## sampling, allocation-free sampling, capacity and render budget with one and
## with several anchors and elements, lifecycle, and independence from the
## elemental cube rituals.
extends SceneTree

const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Atlas = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderAtlas.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const TestComposition = preload("res://scripts/hex_battle/cube_vfx/shared/probe_test_composition.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")

const SHARED_DIR := "res://src/presentation/effects/cube_placeholders/shared"
const SAMPLE_COUNT := 101

var _failures: PackedStringArray = PackedStringArray()
var _stage: Node3D


func _init() -> void:
	_stage = Node3D.new()
	_stage.name = "ProbeStage"
	root.add_child(_stage)
	# Nodes join the tree on the first frame, and global transforms need it.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkSpecParsing()
	_checkSpecOnSpellData()
	_checkFront()
	_checkWarp()
	_checkPalettes()
	_checkPlayback()
	_checkRange()
	_checkSpreadAndElements()
	_checkIndependence()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_SUBSTRATE_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_SUBSTRATE_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- spec -------------------------------------------------------------------

func _checkSpecParsing() -> void:
	var bare := Spec.fromReference({"NAME": "Bare", "ELEMENT": "fire"})
	_expect(bare.isValid(), "a spell with no VFX block reported %s" % str(bare.errors))
	_expect(bare.profileID() == "", "an unauthored profile is not empty")
	_expect(bare.spread() == Spec.SPREAD_CENTRE, "default spread is not centre")
	_expect(bare.anchor() == Spec.ANCHOR_TARGET, "default anchor is not target")
	_expect(bare.resolvedAreaScaling("spread") == "spread", "open area scaling ignored the profile")
	_expect(bare.resolvedRangeScaling("fixed") == "fixed", "open range scaling ignored the profile")
	_expect(bare.elements() == ["fire"], "ELEMENT did not become the elements")

	var legacy := Spec.fromReference({"NAME": "Legacy", "VFX_PROFILE": "ice_area_storm"})
	_expect(legacy.isValid() and legacy.profileID() == "ice_area_storm", "legacy VFX_PROFILE not read")

	var full := Spec.fromReference({
		"NAME": "Full", "ELEMENT": "water",
		"VFX": {
			"PROFILE": "cube_intercepting_guard", "SPREAD": "each_target",
			"ANCHOR": "caster_front", "AREA_SCALING": "none", "RANGE_SCALING": "fixed",
			"ELEMENTS": ["Steel", "wind"],
		},
	})
	_expect(full.isValid(), "a complete block reported %s" % str(full.errors))
	_expect(full.profileID() == "cube_intercepting_guard", "block PROFILE not read")
	_expect(full.spread() == Spec.SPREAD_EACH_TARGET, "block SPREAD not read")
	_expect(full.anchor() == Spec.ANCHOR_CASTER_FRONT, "block ANCHOR not read")
	_expect(full.resolvedAreaScaling("spread") == "none", "authored AREA_SCALING lost to the default")
	_expect(full.resolvedRangeScaling("travel") == "fixed", "authored RANGE_SCALING lost to the default")
	_expect(full.elements() == ["steel", "wind"], "ELEMENTS not lowercased in order")
	_expect(full.explicit.size() == 6, "explicit keys %d" % full.explicit.size())
	var asData := full.toDictionary()
	_expect(asData["ELEMENTS"] == ["steel", "wind"] and asData["SPREAD"] == "each_target",
		"toDictionary lost values")

	var derived := Spec.fromReference({
		"NAME": "Dual", "DAMAGE_LINES": [
			{"damage": 3, "element": "steel"}, {"damage": 3, "element": "wind"},
			{"damage": 1, "element": "steel"},
		],
	})
	_expect(derived.elements() == ["steel", "wind"], "damage-line elements %s" % str(derived.elements()))
	_expect(Spec.fromReference({"NAME": "Plain"}).elements() == ["none"], "element-less spell is not none")

	var cases := [
		[{"VFX": {"SHAPE": "x"}}, "unknown key"],
		[{"VFX": {"SPREAD": "everywhere"}}, "unknown enum value"],
		[{"VFX": {"SPREAD": 3}}, "non-string enum"],
		[{"VFX": {"PROFILE": ""}}, "empty profile"],
		[{"VFX": {"ELEMENTS": "fire"}}, "non-array elements"],
		[{"VFX": {"ELEMENTS": []}}, "empty elements"],
		[{"VFX": {"ELEMENTS": ["plasma"]}}, "unknown element"],
		[{"VFX": {"ELEMENTS": ["fire", "FIRE"]}}, "duplicate element"],
		[{"VFX": "cube_siphon"}, "block that is not an object"],
		[{"VFX": {"PROFILE": "cube_siphon"}, "VFX_PROFILE": "ice_area_storm"}, "both forms"],
	]
	for entry: Array in cases:
		var reference: Dictionary = (entry[0] as Dictionary).duplicate(true)
		reference["NAME"] = "Case"
		var spec := Spec.fromReference(reference)
		_expect(not spec.isValid(), "%s was accepted" % str(entry[1]))
	# A bad aspect keeps its default so presentation still has something.
	var bad := Spec.fromReference({"NAME": "Bad", "VFX": {"SPREAD": "everywhere"}})
	_expect(bad.spread() == Spec.SPREAD_CENTRE, "a rejected value replaced the default")


## Every spell as it stands today must parse: legacy tags and blocks alike.
func _checkSpecOnSpellData() -> void:
	for reference: Dictionary in SpellReferencesScript.list:
		var spec := Spec.fromReference(reference)
		_expect(spec.isValid(), "spell data: %s" % str(spec.errors))


func _checkFront() -> void:
	var origin := Vector3(0.0, 1.0, 0.0)
	var positions: Array[Vector3] = [Vector3(3.0, 0.0, 0.0), Vector3(0.0, 5.0, -1.5), Vector3(-2.0, 0.0, 0.0)]
	var ids: Array[int] = [9, 4, 2]
	var front := Spec.frontToward(origin, positions, ids)
	_expect(front.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "nearest hostile not chosen: %s" % front)
	var tied: Array[Vector3] = [Vector3(2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0)]
	var tiedIDs: Array[int] = [7, 3]
	_expect(Spec.frontToward(origin, tied, tiedIDs).is_equal_approx(Vector3.LEFT),
		"a tie did not go to the lowest id")
	var none: Array[Vector3] = []
	var noIDs: Array[int] = []
	_expect(Spec.frontToward(origin, none, noIDs, Vector3(0.0, 3.0, 2.0)).is_equal_approx(Vector3.BACK),
		"fallback direction not used")
	_expect(Spec.frontToward(origin, none, noIDs).is_equal_approx(Vector3.RIGHT),
		"final fallback is not +X")
	var onTop: Array[Vector3] = [Vector3(0.0, 4.0, 0.0)]
	var onTopIDs: Array[int] = [1]
	_expect(Spec.frontToward(origin, onTop, onTopIDs).is_equal_approx(Vector3.RIGHT),
		"a candidate standing on the origin was used as a direction")


# --- warp -------------------------------------------------------------------

func _checkWarp() -> void:
	var beats: Array[Dictionary] = TestComposition.new().beats()
	var identity := Effect.buildWarp(beats, 1.0)
	_expect(is_equal_approx(float(identity["factor"]), 1.0), "reference warp changes length")
	for index: int in range((identity["sketch"] as PackedFloat32Array).size()):
		_expect(is_equal_approx(identity["sketch"][index], identity["warped"][index]),
			"reference warp is not the identity")
	var stretched := Effect.buildWarp(beats, 1.5)
	_expect(is_equal_approx(float(stretched["factor"]), 1.2), "1.5x travel over 0.4 is not 1.2x total")
	var warped: PackedFloat32Array = stretched["warped"]
	for index: int in range(1, warped.size()):
		_expect(warped[index] > warped[index - 1], "warp breaks are not increasing")
	# Gather keeps 0.2 of the reference length: 0.2 / 1.2 of the new total.
	_expect(is_equal_approx(warped[1], 0.2 / 1.2), "gather beat changed length")


func _checkPalettes() -> void:
	_expect(Profile.paletteForColor(BattleMeshFactory.elementColor("ice"))
		== Profile.paletteForElement("ice"), "ice colour does not resolve to the ice palette")
	_expect(Profile.paletteForColor(BattleMeshFactory.elementColor("none"))
		!= Profile.paletteForElement("steel"), "element-less grey borrowed an element palette")
	_expect(Atlas.frameForYaw(0.0) == 0 and Atlas.frameForYaw(PI * 0.5) == 0,
		"a quarter turn does not return to frame zero")
	_expect(Atlas.frameForYaw(PI * 0.25) == 6, "an eighth turn is not the middle frame")
	var atlas := Atlas.build([Profile.paletteForElement("fire"), Profile.paletteForElement("wind")])
	_expect(atlas.get_width() == 32 * 12 and atlas.get_height() == 64, "atlas is not 12 frames by 2 rows")


# --- playback ---------------------------------------------------------------

func _makePlayback(distance: float, spec: Spec = null, targets: int = 1) -> Effect:
	var playback: Effect = Effect.create(
		_stage, Vector3(distance * 0.5, 0.5, 0.0), BattleMeshFactory.elementColor("ice"), {},
		TestComposition
	)
	var targetIDs: Array[int] = []
	var targetPositions: Array[Vector3] = []
	var targetBounds: Array[AABB] = []
	for index: int in range(targets):
		targetIDs.append(100 + index)
		targetPositions.append(Vector3(distance * 0.5, 0.5, float(index) * 2.0))
		targetBounds.append(VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS)
	playback.configure_cast_context(VfxCastContext.create(
		1, Vector3(-distance * 0.5, 0.0, 0.0), Vector3(distance * 0.5, 0.5, 0.0),
		targetIDs, targetPositions, targetBounds
	))
	if spec != null:
		playback.configure_spell_spec(spec)
	return playback


## A compact, order-sensitive fingerprint of everything the renderer is fed.
func _signature(playback: Effect) -> String:
	var buffer := playback.get_pose_buffer()
	var parts := PackedStringArray([str(buffer.count)])
	for index: int in range(buffer.count):
		var p := buffer.positions[index]
		parts.append("%d:%.5f,%.5f,%.5f,%.5f,%.4f,%d" % [
			buffer.ids[index], p.x, p.y, p.z, buffer.sizes[index], buffer.yaws[index],
			buffer.roles[index]
		])
	return ",".join(parts)


func _times(order: String) -> Array[float]:
	var times: Array[float] = []
	for index: int in range(SAMPLE_COUNT):
		times.append(float(index) / float(SAMPLE_COUNT - 1))
	if order == "descending":
		times.reverse()
	elif order == "shuffled":
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		for index: int in range(times.size() - 1, 0, -1):
			var swap := rng.randi_range(0, index)
			var held := times[index]
			times[index] = times[swap]
			times[swap] = held
	return times


func _checkPlayback() -> void:
	for seedValue: int in [0, 7]:
		var playback := _makePlayback(Profile.REFERENCE_DISTANCE_U)
		playback.play(seedValue, VfxPlayback.MODE_BATTLE)
		playback.set_playback_scale(0.0)
		var capacity := playback.get_capacity()
		_expect(capacity >= Profile.MIN_CAPACITY_PER_COMPOSITION,
			"capacity %d below the 48-cube floor" % capacity)
		var reference := {}
		var peak := 0
		for time: float in _times("ascending"):
			playback.seek_normalized(time)
			reference[time] = _signature(playback)
			peak = maxi(peak, playback.get_pose_buffer().count)
			_expect(playback.get_pose_buffer().overflow == 0, "overflow at t=%.2f" % time)
			_expectFinite(playback, time)
		_expect(peak == TestComposition.PEAK, "sampled peak %d, composition declares %d" % [
			peak, TestComposition.PEAK])

		var objectsBefore := Performance.get_monitor(Performance.OBJECT_COUNT)
		var nodesBefore := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var resourcesBefore := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
		for order: String in ["descending", "shuffled", "ascending"]:
			for time: float in _times(order):
				playback.seek_normalized(time)
				_expect(_signature(playback) == reference[time],
					"seed %d %s sample at t=%.2f differs from the ascending pass" % [seedValue, order, time])
		_expect(Performance.get_monitor(Performance.OBJECT_COUNT) == objectsBefore,
			"sampling allocated objects")
		_expect(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodesBefore,
			"sampling allocated nodes")
		_expect(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT) == resourcesBefore,
			"sampling allocated resources")
		_expect(playback.get_capacity() == capacity, "capacity changed while sampling")

		_expect(playback.get_render_node_count() <= Profile.MAX_RENDER_NODES, "render nodes over budget")
		playback.seek_normalized(0.55)
		var drawCalls := DebugCapture.estimateDrawCalls(playback)
		_expect(drawCalls >= 1 and drawCalls <= Profile.MAX_DRAW_CALLS,
			"estimated draw calls %d at peak" % drawCalls)
		_expect(playback.get_live_node_count() <= 1 + Profile.MAX_RENDER_NODES, "node count over budget")

		# Role layers hide without changing the pose that is sampled.
		var before := playback.get_live_instance_count()
		playback.set_layer_visible("chips", false)
		_expect(playback.get_live_instance_count() == before - 8, "hiding chips did not hide 8 cubes")
		playback.set_layer_visible("chips", true)

		_checkTimeline(playback)
		playback.dispose()
		playback.dispose()
		_expect(playback.is_queued_for_deletion(), "dispose did not free the playback")

	# Different seeds vary the random offsets; seed 0 matches the sketch hash.
	var zero := _makePlayback(Profile.REFERENCE_DISTANCE_U)
	zero.play(0, VfxPlayback.MODE_BATTLE)
	var frame: CubePlaceholderFrame = zero.get_frames()[0]
	_expect(is_equal_approx(frame.rnd(3.0), _sketchRnd(3.0)), "seed 0 does not reproduce the sketch rnd")
	zero.dispose()


static func _sketchRnd(i: float) -> float:
	var x := sin(i * 127.1 + 311.7) * 43758.5453
	return x - floor(x)


func _expectFinite(playback: Effect, time: float) -> void:
	var buffer := playback.get_pose_buffer()
	for index: int in range(buffer.count):
		var p := buffer.positions[index]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(buffer.sizes[index])):
			_failures.append("non-finite cube at t=%.2f" % time)
			return


func _checkTimeline(playback: Effect) -> void:
	playback.play(3, VfxPlayback.MODE_BATTLE)
	var duration := playback.get_total_duration()
	_expect(is_equal_approx(duration, 1.5), "battle duration at the reference distance is %.3f" % duration)
	playback.set_playback_scale(0.0)
	playback._process(0.25)
	_expect(is_zero_approx(playback.get_elapsed_time()), "zero rate advanced the timeline")
	playback.set_playback_scale(4.0)
	playback._process(0.1)
	_expect(is_equal_approx(playback.get_elapsed_time(), 0.4), "4x rate did not advance 4x")
	playback.set_playback_scale(1.0)
	playback._process(10.0)
	_expect(playback.is_finished(), "the timeline did not finish")
	playback.skip_to_settle()
	_expect(is_equal_approx(playback.get_normalized_time(), playback.normalizedAtSketchTime(0.8)),
		"skip_to_settle did not land on the settle time")
	_expect(is_equal_approx(playback.get_action_hold_seconds(), 0.6 * duration),
		"hold at the reference distance is not the impact beat")
	playback.play(3, VfxPlayback.MODE_REFERENCE)
	_expect(is_equal_approx(playback.get_total_duration(), 3.0), "reference mode duration")


func _checkRange() -> void:
	var cases := {2.0: 0.75, 4.0: 1.0, 6.0: 1.5, 10.0: 1.5}
	for cells: float in cases:
		var playback := _makePlayback(cells * Profile.CELL_PITCH_U)
		playback.play(1, VfxPlayback.MODE_BATTLE)
		var stretch: float = cases[cells]
		_expect(is_equal_approx(playback.get_range_stretch(), stretch),
			"%.0f cells stretched %.3f, expected %.3f" % [cells, playback.get_range_stretch(), stretch])
		var factor := 1.0 + 0.4 * (stretch - 1.0)
		_expect(is_equal_approx(playback.get_total_duration(), 1.5 * factor),
			"%.0f cells total duration %.3f" % [cells, playback.get_total_duration()])
		# Gather keeps its length in seconds; the impact lands at the end of travel.
		var gatherEnd := playback.normalizedAtSketchTime(0.2) * playback.get_total_duration()
		_expect(is_equal_approx(gatherEnd, 0.2 * 1.5), "%.0f cells gather is %.3fs" % [cells, gatherEnd])
		_expect(is_equal_approx(playback.get_action_hold_seconds(), (0.2 + 0.4 * stretch) * 1.5),
			"%.0f cells hold %.3fs" % [cells, playback.get_action_hold_seconds()])
		# The path still ends on the target: the last orbiter reaches the anchor.
		playback.seek_normalized(playback.normalizedAtSketchTime(0.6))
		var frame: CubePlaceholderFrame = playback.get_frames()[0]
		var buffer := playback.get_pose_buffer()
		var centroid := Vector3.ZERO
		for index: int in range(40):
			centroid += buffer.positions[index]
		centroid /= 40.0
		_expect(Vector2(centroid.x - frame.target.x, centroid.z - frame.target.z).length() < 0.05,
			"%.0f cells: the travel does not end on the target" % cells)
		playback.dispose()
	# A fixed spec never stretches.
	var fixedSpec := Spec.fromReference({"NAME": "Fixed", "VFX": {"RANGE_SCALING": "fixed"}})
	var fixed := _makePlayback(10.0 * Profile.CELL_PITCH_U, fixedSpec)
	fixed.play(1, VfxPlayback.MODE_BATTLE)
	_expect(is_equal_approx(fixed.get_range_stretch(), 1.0), "RANGE_SCALING fixed still stretched")
	fixed.dispose()


func _checkSpreadAndElements() -> void:
	var spec := Spec.fromReference({
		"NAME": "Spread", "VFX": {"SPREAD": "each_target", "ELEMENTS": ["steel", "wind"]},
	})
	var playback := _makePlayback(Profile.REFERENCE_DISTANCE_U, spec, 6)
	playback.play(2, VfxPlayback.MODE_BATTLE)
	_expect(playback.get_frames().size() == 6, "each_target built %d anchors" % playback.get_frames().size())
	_expect(playback.get_capacity() >= 6 * TestComposition.PEAK, "capacity does not cover six anchors")
	_expect(playback.get_palette_keys() == ["steel", "wind"], "palettes %s" % str(playback.get_palette_keys()))
	var peak := 0
	for time: float in _times("ascending"):
		playback.seek_normalized(time)
		peak = maxi(peak, playback.get_pose_buffer().count)
		_expect(playback.get_pose_buffer().overflow == 0, "six-anchor overflow at t=%.2f" % time)
	_expect(peak == 6 * TestComposition.PEAK, "six-anchor peak %d" % peak)
	playback.seek_normalized(0.55)
	_expect(DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS,
		"six anchors and two elements exceeded the draw-call budget")
	_expect(playback.get_render_node_count() == 1, "two elements used more than one render node")
	var buffer := playback.get_pose_buffer()
	var rows := {}
	for index: int in range(buffer.count):
		rows[posmod(buffer.ids[index], 2)] = true
	_expect(rows.size() == 2, "two elements did not both appear")
	playback.dispose()

	var front := Spec.fromReference({"NAME": "Front", "VFX": {"ANCHOR": "caster_front"}})
	var anchored := _makePlayback(Profile.REFERENCE_DISTANCE_U, front)
	anchored.configure_facing(Vector3(0.0, 0.0, 1.0))
	anchored.play(2, VfxPlayback.MODE_BATTLE)
	var frame: CubePlaceholderFrame = anchored.get_frames()[0]
	var expected := Vector3(-Profile.REFERENCE_DISTANCE_U * 0.5, 0.0, Profile.CELL_PITCH_U)
	_expect(frame.target.is_equal_approx(expected), "caster_front anchor at %s" % frame.target)
	_expect(frame.forward.is_equal_approx(Vector3.BACK), "caster_front forward is not the front")
	anchored.dispose()


func _checkIndependence() -> void:
	var directory := DirAccess.open(SHARED_DIR)
	_expect(directory != null, "shared directory missing")
	if directory == null:
		return
	for fileName: String in directory.get_files():
		if not fileName.ends_with(".gd"):
			continue
		var source := FileAccess.get_file_as_string(SHARED_DIR.path_join(fileName))
		for line: String in source.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue
			_expect(not trimmed.contains("ElementalCubeRitual"),
				"%s depends on the elemental cube rituals" % fileName)
