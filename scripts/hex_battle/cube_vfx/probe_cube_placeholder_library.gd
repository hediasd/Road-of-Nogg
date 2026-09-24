## The whole-library gate for the cube placeholder spells: all 26 active
## profiles against one reviewable manifest
## (`scripts/hex_battle/fixtures/vfx/cube_placeholder_manifest.json`).
##
## WHAT IT DEFENDS AND HOW. The manifest mirrors the plan's roster: for each of
## the 24 cube profiles its family, carrier spells and their spec, binding,
## ingredient counts per role (distinct cubes over the whole timeline), peak,
## beats with their travel flags, impact, and pose signatures at checkpoint
## times. A signature is a coarse description per role — count, centroid,
## mean horizontal radius from the target, and height range, in sketch units
## relative to the target at the reference configuration — never a renderer
## internal. Positions tolerate 0.05 sketch units, so harmless refactoring
## passes and a visibly different pose does not.
##
## Beyond the manifest it checks what no single family probe can: the catalog,
## the spell data and the manifest agree exactly; every factory is either a
## ritual or the cube placeholder playback; one-frame holes (a role's count
## dipping for a single sample) and seek-only pops (a sought pose differing
## from the same time reached by playing) do not occur; every profile stays
## finite, within its population cap and within the render budget across
## seeds, distances, body presets, footprints and both spreads; lifecycle,
## rate, settle and disposal hold; and the two rituals still build.
##
## Diagnostics name the profile and the time, so a whole-library failure still
## points at the one effect that broke.
extends SceneTree

const Effect = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderEffect.gd")
const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")
const RitualEffect = preload("res://src/presentation/effects/ElementalCubeRitualEffect.gd")
const RitualProfile = preload("res://src/presentation/effects/ElementalCubeRitualProfile.gd")
const DebugCapture = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const DebugWorld = preload("res://src/presentation/debug/VfxDebugWorld.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")

const MANIFEST_PATH := "res://scripts/hex_battle/fixtures/vfx/cube_placeholder_manifest.json"
const CHECKPOINTS: Array[float] = [0.12, 0.3, 0.5, 0.7, 0.9]
const POSITION_TOLERANCE := 0.05
const DENSE := 2001

## The plan's roster: distinct cubes per role over the whole timeline. This is
## the independent copy the manifest is checked against, not read from it.
const INGREDIENTS := {
	"cube_arcing_pair": {"lobs": 2, "chips": 20},
	"cube_scattershot": {"shot": 11, "chips": 33},
	"cube_corkscrew_bolt": {"bolt": 1, "wake": 7, "burst": 16},
	"cube_returning_throw": {"blade": 1, "chips": 8},
	"cube_skipping_stone": {"stone": 1, "chips": 18},
	"cube_flanking_volley": {"volley": 4, "burst": 18},
	"cube_ceiling_collapse": {"dust": 12, "heavy": 7, "rubble": 35},
	"cube_ground_teeth": {"tremble": 5, "teeth": 20, "crumbs": 25},
	"cube_expanding_shockwave": {"core": 1, "ring": 24},
	"cube_implosion": {"shell": 18, "core": 1},
	"cube_rolling_avalanche": {"boulders": 2, "trail": 10, "rubble": 18},
	"cube_staggered_bombardment": {"strikes": 9, "rubble": 54},
	"cube_rising_barricade": {"wall": 15},
	"cube_closing_cage": {"posts": 12, "lid": 4},
	"cube_climbing_coil": {"coil": 22},
	"cube_lifting_vortex": {"vortex": 28},
	"cube_clapping_slabs": {"slabs": 12, "fragments": 26},
	"cube_encasing_frost": {"shell": 18, "chips": 12},
	"cube_repair_mend": {"fragments": 12, "blocks": 4},
	"cube_intercepting_guard": {"guards": 6, "incoming": 1, "chips": 9},
	"cube_siphon": {"stream": 9, "absorber": 1},
	"cube_cleanse": {"attached": 10},
	"cube_blink_transfer": {"cluster": 8},
	"cube_charge_release": {"gather": 16, "charge": 1, "chips": 24},
}

var _failures: PackedStringArray = PackedStringArray()
var _stage: Node3D


func _init() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest is Dictionary, "manifest does not parse")
	if manifest is Dictionary:
		_checkAgreement(manifest)
		var measured := measure(_stage)
		for profileID: String in INGREDIENTS:
			_compareProfile(profileID, (manifest["profiles"] as Dictionary).get(profileID, {}),
				(measured["profiles"] as Dictionary).get(profileID, {}))
	for row: Dictionary in SpellVfxCatalog.entries():
		if str(row["profile_id"]).begins_with("cube_"):
			_checkRobustness(row)
	_checkRituals()
	_stage.free()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_LIBRARY_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_LIBRARY_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- measurement -------------------------------------------------------------

## Measures every cube profile at the reference configuration: 4 cells, a
## standard body, no footprint, default spec, seed 0, battle mode. Static so
## the manifest is regenerated from the same code that checks it: a throwaway
## SceneTree script that, one frame after adding a Node3D to the root, stores
## `JSON.stringify(measure(stage), "\t", false)` at `MANIFEST_PATH`. Regenerate
## only for a deliberate choreography change, and review the diff: it is the
## visual contract.
static func measure(stage: Node3D) -> Dictionary:
	var profiles := {}
	var carriers := _carriersByProfile()
	for row: Dictionary in SpellVfxCatalog.entries():
		var profileID := str(row["profile_id"])
		if not profileID.begins_with("cube_"):
			continue
		var composition = (row["composition"] as Script).new()
		var playback := _referencePlayback(stage, row)
		var roles: Array[String] = composition.roles()
		var distinct := {}
		for role: String in roles:
			distinct[role] = {}
		var peak := 0
		for index: int in range(DENSE):
			playback.seek_normalized(float(index) / float(DENSE - 1))
			var buffer := playback.get_pose_buffer()
			peak = maxi(peak, buffer.count)
			for cube: int in range(buffer.count):
				(distinct[roles[buffer.roles[cube]]] as Dictionary)[buffer.ids[cube]] = true
		var ingredients := {}
		for role: String in roles:
			ingredients[role] = (distinct[role] as Dictionary).size()
		var beats: Array = []
		for beat: Dictionary in composition.beats():
			beats.append({
				"name": str(beat["name"]), "start": float(beat["start"]),
				"end": float(beat["end"]), "travel": bool(beat.get("travel", false)),
			})
		var signatures := {}
		for t: float in CHECKPOINTS:
			playback.seek_normalized(playback.normalizedAtSketchTime(t))
			signatures["%.2f" % t] = _signature(playback, roles)
		profiles[profileID] = {
			"family": str(row["family"]),
			"binding": str(row["binding"]),
			"carriers": carriers.get(profileID, []),
			"ingredients": ingredients,
			"peak": peak,
			"declared_peak": composition.peakCubes(),
			"beats": beats,
			"impact": composition.impactTime(),
			"settle": composition.settleTime(),
			"signatures": signatures,
		}
		playback.dispose()
	return {"format": 1, "reference": {
		"distance_cells": Profile.REFERENCE_DISTANCE_CELLS, "body": "standard", "footprint": "none",
		"seed": 0, "mode": "battle", "units": "sketch units relative to the target",
	}, "profiles": profiles}


static func _carriersByProfile() -> Dictionary:
	var result := {}
	for reference: Dictionary in SpellReferencesScript.list:
		if not reference.has("VFX"):
			continue
		var spec: SpellVfxSpec = SpellVfxCatalog.specForSpell(reference)
		var entry := spec.toDictionary()
		entry["SPELL"] = str(reference["NAME"])
		var rows: Array = result.get(spec.profileID(), [])
		rows.append(entry)
		result[spec.profileID()] = rows
	return result


static func _referencePlayback(stage: Node3D, row: Dictionary, cells: float = Profile.REFERENCE_DISTANCE_CELLS,
		body: AABB = VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS, footprint: HexVfxFootprint = null,
		spec: SpellVfxSpec = null, seedValue: int = 0, targets: int = 1) -> Effect:
	var distance := cells * Profile.CELL_PITCH_U
	var target := Vector3(distance * 0.5, 0.85, 0.0)
	var source := Vector3(-distance * 0.5, 0.35, 0.0)
	var playback: Effect = (row["factory"] as Callable).call(
		stage, target, BattleMeshFactory.elementColor("ice"), {})
	var ids: Array[int] = []
	var positions: Array[Vector3] = []
	var bounds: Array[AABB] = []
	for index: int in range(targets):
		ids.append(10 + index)
		positions.append(target + Vector3(0.0, 0.0, 2.0 * index))
		bounds.append(body)
	playback.configure_cast_context(VfxCastContext.create(1, source, target, ids, positions, bounds))
	if footprint != null:
		playback.setHexFootprint(footprint)
	if spec != null:
		playback.configure_spell_spec(spec)
	var sourceFront := Vector3.RIGHT
	var targetFronts: Array[Vector3] = []
	for index: int in range(targets):
		targetFronts.append(Vector3.LEFT)
	playback.configure_facing(sourceFront, targetFronts)
	playback.play(seedValue, VfxPlayback.MODE_BATTLE)
	playback.set_playback_scale(0.0)
	return playback


## Per role: count, centroid, mean horizontal radius and height range, in
## sketch units relative to the first anchor's target, rounded to 0.01.
static func _signature(playback: Effect, roles: Array[String]) -> Dictionary:
	var frame: CubePlaceholderFrame = playback.get_frames()[0]
	var buffer := playback.get_pose_buffer()
	var result := {}
	for roleIndex: int in range(roles.size()):
		var count := 0
		var centroid := Vector3.ZERO
		var radius := 0.0
		var low := INF
		var high := -INF
		for cube: int in range(buffer.count):
			if buffer.roles[cube] != roleIndex:
				continue
			var local := (buffer.positions[cube] - frame.target) / Profile.UNIT_U
			var planar := Vector3(local.dot(frame.forward), local.y, local.dot(frame.side))
			count += 1
			centroid += planar
			radius += Vector2(planar.x, planar.z).length()
			low = minf(low, planar.y)
			high = maxf(high, planar.y)
		if count == 0:
			result[roles[roleIndex]] = {"count": 0}
			continue
		centroid /= float(count)
		result[roles[roleIndex]] = {
			"count": count,
			"centroid": [snappedf(centroid.x, 0.01), snappedf(centroid.y, 0.01), snappedf(centroid.z, 0.01)],
			"radius": snappedf(radius / float(count), 0.01),
			"height": [snappedf(low, 0.01), snappedf(high, 0.01)],
		}
	return result


# --- checks ------------------------------------------------------------------

func _checkAgreement(manifest: Dictionary) -> void:
	var catalogIDs := PackedStringArray()
	for row: Dictionary in SpellVfxCatalog.entries():
		var profileID := str(row["profile_id"])
		catalogIDs.append(profileID)
		var factory: Callable = row["factory"]
		var owner := factory.get_object() as Script
		_expect(owner == Effect or owner == RitualEffect,
			"%s builds through %s, which is neither a ritual nor the cube placeholder playback" % [
				profileID, owner.resource_path if owner != null else "nothing"])
	var profiles: Dictionary = manifest.get("profiles", {})
	_expect(profiles.size() == INGREDIENTS.size(), "manifest lists %d profiles" % profiles.size())
	for profileID: String in INGREDIENTS:
		_expect(catalogIDs.has(profileID), "%s is in the roster but not the catalog" % profileID)
		_expect(profiles.has(profileID), "%s is in the roster but not the manifest" % profileID)
	for profileID in profiles:
		_expect(INGREDIENTS.has(profileID), "manifest lists %s, which the roster does not" % profileID)
	var carriers := _carriersByProfile()
	for profileID in profiles:
		var listed: Array = (profiles[profileID] as Dictionary).get("carriers", [])
		_expect(JSON.stringify(listed) == JSON.stringify(carriers.get(profileID, [])),
			"%s carriers in the manifest differ from the spell data" % profileID)
		_expect(listed.size() >= 1, "%s has no carrier spell" % profileID)


func _compareProfile(profileID: String, expected: Dictionary, rawMeasured: Dictionary) -> void:
	if expected.is_empty() or rawMeasured.is_empty():
		_failures.append("%s missing from the manifest or the measurement" % profileID)
		return
	# JSON reads every number as a float; pass the measurement and the roster
	# through JSON too, so both sides compare as the manifest stores them.
	var measured: Dictionary = JSON.parse_string(JSON.stringify(rawMeasured))
	var roster: Dictionary = JSON.parse_string(JSON.stringify(INGREDIENTS[profileID]))
	for key: String in ["family", "binding", "peak", "declared_peak", "impact", "settle"]:
		_expect(str(expected[key]) == str(measured[key]),
			"%s %s: manifest %s, measured %s" % [profileID, key, expected[key], measured[key]])
	_expect(int(measured["peak"]) == int(measured["declared_peak"]),
		"%s peak %d differs from its declared %d" % [profileID, measured["peak"], measured["declared_peak"]])
	_expect(JSON.stringify(measured["ingredients"]) == JSON.stringify(roster),
		"%s ingredients %s, roster %s" % [profileID, JSON.stringify(measured["ingredients"]), JSON.stringify(roster)])
	_expect(JSON.stringify(expected["ingredients"]) == JSON.stringify(roster),
		"%s manifest ingredients disagree with the roster" % profileID)
	_expect(JSON.stringify(expected["beats"]) == JSON.stringify(measured["beats"]),
		"%s beats differ from the manifest" % profileID)
	for key: String in (expected["signatures"] as Dictionary):
		var want: Dictionary = expected["signatures"][key]
		var got: Dictionary = (measured["signatures"] as Dictionary).get(key, {})
		for role: String in want:
			var a: Dictionary = want[role]
			var b: Dictionary = got.get(role, {})
			var where := "%s t=%s %s" % [profileID, key, role]
			_expect(int(a.get("count", -1)) == int(b.get("count", -2)), "%s count %s vs %s" % [where, a.get("count"), b.get("count")])
			if int(a.get("count", 0)) == 0 or b.is_empty() or int(b.get("count", 0)) == 0:
				continue
			for axis: int in range(3):
				_expect(absf(float(a["centroid"][axis]) - float(b["centroid"][axis])) <= POSITION_TOLERANCE,
					"%s centroid %s vs %s" % [where, str(a["centroid"]), str(b["centroid"])])
			_expect(absf(float(a["radius"]) - float(b["radius"])) <= POSITION_TOLERANCE,
				"%s radius %s vs %s" % [where, a["radius"], b["radius"]])
			for bound: int in range(2):
				_expect(absf(float(a["height"][bound]) - float(b["height"][bound])) <= POSITION_TOLERANCE,
					"%s height %s vs %s" % [where, str(a["height"]), str(b["height"])])


## Everything a single family probe cannot see at once, per profile.
func _checkRobustness(row: Dictionary) -> void:
	var profileID := str(row["profile_id"])
	var composition = (row["composition"] as Script).new()
	var roles: Array[String] = composition.roles()

	# One-frame holes: no role's count dips for a single dense sample.
	var reference := _referencePlayback(_stage, row)
	var counts: Array = []
	for index: int in range(DENSE):
		reference.seek_normalized(float(index) / float(DENSE - 1))
		var perRole := PackedInt32Array()
		perRole.resize(roles.size())
		var buffer := reference.get_pose_buffer()
		for cube: int in range(buffer.count):
			perRole[buffer.roles[cube]] += 1
		counts.append(perRole)
	for index: int in range(1, DENSE - 1):
		for role: int in range(roles.size()):
			var before: int = counts[index - 1][role]
			var now: int = counts[index][role]
			var after: int = counts[index + 1][role]
			_expect(not (now < before and now < after),
				"%s %s dips for one sample at t=%.4f" % [profileID, roles[role], float(index) / float(DENSE - 1)])

	# Seek-only pops: a sought pose equals the pose reached by playing there.
	for target: float in [0.2, 0.47, 0.73]:
		reference.play(0, VfxPlayback.MODE_BATTLE)
		reference.set_playback_scale(1.0)
		var step := reference.get_total_duration() / 240.0
		while reference.get_normalized_time() < target - 0.00001:
			reference._process(minf(step, (target - reference.get_normalized_time()) * reference.get_total_duration()))
		var played := _flatSignature(reference)
		reference.set_playback_scale(0.0)
		reference.seek_normalized(reference.get_normalized_time())
		_expect(played == _flatSignature(reference), "%s pops when sought at %.2f" % [profileID, target])

	# Lifecycle, rate and settle.
	reference.play(1, VfxPlayback.MODE_BATTLE)
	reference.set_playback_scale(0.0)
	reference._process(0.3)
	_expect(is_zero_approx(reference.get_elapsed_time()), "%s moved at zero rate" % profileID)
	reference.set_playback_scale(4.0)
	reference._process(0.05)
	_expect(is_equal_approx(reference.get_elapsed_time(), 0.2), "%s 4x rate" % profileID)
	reference.skip_to_settle()
	_expect(is_equal_approx(reference.get_normalized_time(), reference.normalizedAtSketchTime(composition.settleTime())),
		"%s did not settle" % profileID)
	reference.dispose()
	reference.dispose()
	_expect(reference.is_queued_for_deletion(), "%s did not dispose" % profileID)

	# Variation sweep: finite, capped, within budget.
	var sweeps: Array = []
	for cells: float in [2.0, 4.0, 6.0, 10.0]:
		sweeps.append({"cells": cells})
	for body: String in ["wide", "tall"]:
		sweeps.append({"body": body})
	for shape: Array in [["single", 1], ["circle", 3], ["cross", 2], ["line", 3]]:
		sweeps.append({"footprint": shape})
	sweeps.append({"spread": "each_target"})
	for sweep: Dictionary in sweeps:
		var cells: float = sweep.get("cells", Profile.REFERENCE_DISTANCE_CELLS)
		var body := VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
		for preset: Dictionary in DebugWorld.TARGET_BODY_PRESETS:
			if preset["id"] == sweep.get("body", ""):
				body = preset["bounds"]
		var footprint: HexVfxFootprint = null
		var spec: SpellVfxSpec = null
		var targets := 1
		if sweep.has("footprint"):
			var distance := cells * Profile.CELL_PITCH_U
			footprint = DebugWorld.buildHexFootprint(str(sweep["footprint"][0]), int(sweep["footprint"][1]),
				Vector3(distance * 0.5, 0.85, 0.0), Vector3(-distance * 0.5, 0.35, 0.0))
			spec = Spec.fromReference({"NAME": "Sweep", "VFX": {"AREA_SCALING": "spread"}})
		if sweep.has("spread"):
			spec = Spec.fromReference({"NAME": "Sweep", "VFX": {"SPREAD": str(sweep["spread"])}})
			targets = 4
		for seedValue: int in [0, 11]:
			var playback := _referencePlayback(_stage, row, cells, body, footprint, spec, seedValue, targets)
			var bad := 0
			for index: int in range(201):
				playback.seek_normalized(float(index) / 200.0)
				var buffer := playback.get_pose_buffer()
				if buffer.overflow > 0 or buffer.count > playback.get_capacity():
					bad += 1
				for cube: int in range(buffer.count):
					var p := buffer.positions[cube]
					if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(buffer.sizes[cube])):
						bad += 1
			_expect(bad == 0, "%s %s seed %d: %d non-finite or over-capacity samples" % [profileID, str(sweep), seedValue, bad])
			_expect(playback.get_render_node_count() <= Profile.MAX_RENDER_NODES
				and DebugCapture.estimateDrawCalls(playback) <= Profile.MAX_DRAW_CALLS,
				"%s %s over the render budget" % [profileID, str(sweep)])
			playback.dispose()


func _flatSignature(playback: Effect) -> String:
	var buffer := playback.get_pose_buffer()
	var parts := PackedStringArray([str(buffer.count)])
	for index: int in range(buffer.count):
		var p := buffer.positions[index]
		parts.append("%d:%.4f,%.4f,%.4f,%.4f" % [buffer.ids[index], p.x, p.y, p.z, buffer.sizes[index]])
	return ",".join(parts)


func _checkRituals() -> void:
	for profileID: String in [RitualProfile.CROWNBURST_PROFILE_ID, RitualProfile.SPIRAL_PROFILE_ID]:
		var effect := SpellVfxCatalog.create(profileID, _stage, Vector3.ZERO, Color(0.6, 0.9, 0.9))
		_expect(effect != null and effect is RitualEffect, "%s no longer builds as a ritual" % profileID)
		if effect == null:
			continue
		effect.play(7, VfxPlayback.MODE_BATTLE)
		effect.seek_normalized(0.5)
		_expect(effect.get_live_instance_count() == RitualProfile.CUBE_COUNT, "%s lost cubes" % profileID)
		_expect(not effect.has_method("configure_spell_spec") and not effect.has_method("setHexFootprint"),
			"%s grew cube placeholder inputs" % profileID)
		effect.dispose()
