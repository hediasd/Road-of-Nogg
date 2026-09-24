## Headless checks for the VFX debug scene's batch-capture contract: repeatable
## flag parsing, catalog-script merging, batch selection and refusals, the batch
## manifest's shape, and the hex footprint the scene hands hex-aware effects.
##
## Rendering itself cannot run headless; the capture half of the contract is
## exercised by windowed `--effect-prefix` runs recorded in the commit body.
##
## This script doubles as its own catalog-script fixture: its static `entries()`
## is loaded through the same `--catalog-script` merge the scene uses.
extends SceneTree

const ControllerScript = preload("res://src/presentation/debug/VFXDebugController.gd")
const ArgumentsScript = preload("res://src/presentation/debug/VfxDebugArguments.gd")
const CaptureScript = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const WorldScript = preload("res://src/presentation/debug/VfxDebugWorld.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")

const SELF_PATH := "res://scripts/hex_battle/cube_vfx/probe_batch_capture_args.gd"
const FIXTURE_IDS: Array[String] = ["probe_fixture_a", "probe_fixture_b"]

var _failures: PackedStringArray = PackedStringArray()


## Catalog-script fixture rows. The factory is never called by this probe.
static func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for profileId: String in FIXTURE_IDS:
		rows.append({
			"profile_id": profileId,
			"display_name": profileId.capitalize(),
			"factory": Callable(load(SELF_PATH), "createFixture"),
			"action_hold_fraction": 0.5,
			"max_live": 1,
		})
	return rows


static func createFixture(
		_parent: Node3D, _position: Vector3, _color: Color, _overrides: Dictionary) -> VfxPlayback:
	return null


func _init() -> void:
	_checkArguments()
	_checkCatalogMerge()
	_checkBatchSelection()
	_checkManifest()
	_checkHexFootprint()
	if not _failures.is_empty():
		for failure: String in _failures:
			printerr("CUBE_VFX_BATCH_CAPTURE_FAILURE: %s" % failure)
		quit(1)
		return
	print("CUBE_VFX_BATCH_CAPTURE_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _checkArguments() -> void:
	var arguments := PackedStringArray([
		"--catalog-script=res://a.gd", "--seed=7", "--catalog-script=res://b.gd, res://c.gd",
		"--catalog-script=", "--effect-prefix=cube_",
	])
	var values := ArgumentsScript.stringsFrom(arguments, "--catalog-script=")
	_expect(
		values == PackedStringArray(["res://a.gd", "res://b.gd", "res://c.gd"]),
		"repeatable flag parsed as %s" % str(values)
	)
	_expect(
		ArgumentsScript.stringsFrom(arguments, "--missing=").is_empty(),
		"absent repeatable flag is not empty"
	)
	# `--effect-prefix=` must never be read as `--effect=`.
	_expect(
		ArgumentsScript.stringsFrom(arguments, "--effect=").is_empty(),
		"--effect-prefix leaked into --effect"
	)


func _checkCatalogMerge() -> void:
	var base: Array[Dictionary] = SpellVfxCatalogScript.entries()
	for entry: Dictionary in base:
		_expect(
			ControllerScript.catalogRowProblem(entry).is_empty(),
			"registered row %s rejected: %s" % [
				entry["profile_id"], ControllerScript.catalogRowProblem(entry)
			]
		)

	var merged: Dictionary = ControllerScript.mergeCatalogScripts(
		base, PackedStringArray([SELF_PATH])
	)
	var ids := ControllerScript.entryIds(merged["entries"])
	_expect((merged["errors"] as PackedStringArray).is_empty(),
		"clean merge reported %s" % str(merged["errors"]))
	_expect(ids.size() == base.size() + FIXTURE_IDS.size(), "merge row count %d" % ids.size())
	for index: int in range(base.size()):
		_expect(ids[index] == str(base[index]["profile_id"]),
			"base rows must keep their order ahead of script rows")
	for profileId: String in FIXTURE_IDS:
		_expect(ids.has(profileId), "merged catalog lacks %s" % profileId)

	# Loading the same script twice, or a script whose ids collide with the
	# base, must never replace a registered row.
	var twice: Dictionary = ControllerScript.mergeCatalogScripts(
		base,
		PackedStringArray([SELF_PATH, SELF_PATH, "res://src/presentation/effects/SpellVfxCatalog.gd"])
	)
	_expect(
		ControllerScript.entryIds(twice["entries"]).size() == base.size() + FIXTURE_IDS.size(),
		"duplicate rows were merged"
	)
	_expect(
		(twice["errors"] as PackedStringArray).size() == FIXTURE_IDS.size() + base.size(),
		"duplicate rows reported %d errors" % (twice["errors"] as PackedStringArray).size()
	)
	for index: int in range(base.size()):
		_expect(
			(twice["entries"] as Array)[index]["factory"] == base[index]["factory"],
			"a duplicate replaced registered row %s" % base[index]["profile_id"]
		)

	var missing: Dictionary = ControllerScript.mergeCatalogScripts(
		base, PackedStringArray(["res://does/not/exist.gd"])
	)
	_expect((missing["errors"] as PackedStringArray).size() == 1, "missing script not reported")
	var noEntries: Dictionary = ControllerScript.mergeCatalogScripts(
		base, PackedStringArray(["res://src/presentation/debug/VfxDebugArguments.gd"])
	)
	_expect((noEntries["errors"] as PackedStringArray).size() == 1,
		"script without entries() not reported")

	_expect(not ControllerScript.catalogRowProblem({"profile_id": "x"}).is_empty(),
		"incomplete row accepted")
	_expect(not ControllerScript.catalogRowProblem("row").is_empty(), "non-dictionary row accepted")


func _checkBatchSelection() -> void:
	var merged: Dictionary = ControllerScript.mergeCatalogScripts(
		SpellVfxCatalogScript.entries(), PackedStringArray([SELF_PATH])
	)
	var entries: Array[Dictionary] = []
	entries.assign(merged["entries"])
	var fixtures := ControllerScript.entryIds(
		ControllerScript.entriesWithPrefix(entries, "probe_fixture_")
	)
	_expect(fixtures == PackedStringArray(FIXTURE_IDS), "prefix selection gave %s" % str(fixtures))
	var rituals := ControllerScript.entryIds(
		ControllerScript.entriesWithPrefix(entries, "elemental_cube_")
	)
	_expect(rituals.size() == 2, "elemental_cube_ selected %d rows" % rituals.size())
	_expect(
		ControllerScript.entriesWithPrefix(entries, "cube_nothing_matches_").is_empty(),
		"a prefix with no match selected rows"
	)

	var refused := ControllerScript.batchArgumentProblems(PackedStringArray([
		"--effect-prefix=cube_", "--effect=x", "--layers=a", "--tune=A=1", "--tune-load=p",
		"--seed=7",
	]))
	_expect(refused.size() == 4, "batch refused %d flags, expected 4" % refused.size())
	_expect(
		ControllerScript.batchArgumentProblems(PackedStringArray([
			"--effect-prefix=cube_", "--seed=7", "--capture-at=0.3", "--catalog-script=res://a.gd",
		])).is_empty(),
		"a valid batch command was refused"
	)


func _checkManifest() -> void:
	var manifest := CaptureScript.newBatchManifest(
		"cube_", PackedFloat32Array([0.3, 0.7]), 7, "battle",
		PackedStringArray(["--effect-prefix=cube_"]), PackedStringArray(),
		PackedStringArray()
	)
	_expect(manifest["status"] == CaptureScript.BATCH_RUNNING, "a new manifest is not running")
	_expect(manifest["exit_code"] == null, "a new manifest already has an exit code")
	_expect((manifest["profiles"] as Array).is_empty(), "a new manifest has profiles")
	_expect((manifest["times"] as Array).size() == 2, "manifest lost its times")
	CaptureScript.finishBatchManifest(manifest, CaptureScript.BATCH_COMPLETE, OK, PackedStringArray())
	_expect(manifest["status"] == CaptureScript.BATCH_COMPLETE, "finish did not set status")
	_expect(int(manifest["exit_code"]) == OK, "finish did not set the exit code")
	var parsed = JSON.parse_string(JSON.stringify(manifest))
	_expect(parsed is Dictionary and parsed["status"] == "complete", "manifest does not round-trip")


func _checkHexFootprint() -> void:
	var centre := Vector3(2.0, 0.85, 0.0)
	var caster := Vector3(-6.0, 0.35, 0.0)
	for radius: int in range(1, 5):
		var disc: HexVfxFootprint = WorldScript.buildHexFootprint("circle", radius, centre, caster)
		_expect(disc.cellCount() == 3 * radius * (radius + 1) + 1,
			"circle r%d has %d cells" % [radius, disc.cellCount()])
		var cross: HexVfxFootprint = WorldScript.buildHexFootprint("cross", radius, centre, caster)
		_expect(cross.cellCount() == 6 * radius + 1,
			"cross r%d has %d cells" % [radius, cross.cellCount()])
		var line: HexVfxFootprint = WorldScript.buildHexFootprint("line", radius, centre, caster)
		_expect(line.cellCount() == radius, "line r%d has %d cells" % [radius, line.cellCount()])
		# The line starts beside the caster and runs toward the target.
		if line.cellCount() > 1:
			var first := line.world_positions[0]
			var last := line.world_positions[line.cellCount() - 1]
			_expect(first.distance_to(caster) < last.distance_to(caster),
				"line r%d does not run away from the caster" % radius)
		for footprint: HexVfxFootprint in [disc, cross, line]:
			for index: int in range(footprint.cellCount()):
				var cellCentre := footprint.world_positions[index]
				_expect(is_equal_approx(cellCentre.y, centre.y),
					"footprint cell not on the target surface")
				_expect(footprint.containsWorldPoint(cellCentre),
					"footprint does not contain its own cell centre")
				_expect(footprint.bounds.grow(0.001).has_point(cellCentre),
					"footprint bounds miss a cell")
		# Every cell of a disc is empty but the centre, which must sit exactly
		# on the target anchor.
		var centreIndex := disc.cells.find(WorldScript.HEX_CENTRE_CELL)
		_expect(centreIndex >= 0, "circle r%d lacks its centre cell" % radius)
		if centreIndex >= 0:
			_expect(disc.world_positions[centreIndex].is_equal_approx(centre),
				"circle r%d centre is not on the target anchor" % radius)
	var single: HexVfxFootprint = WorldScript.buildHexFootprint("single", 3, centre, caster)
	_expect(single.cellCount() == 1 and single.world_positions[0].is_equal_approx(centre),
		"single footprint is not the target cell")
	# Battle metrics, not the debug scene's legacy one-unit tiles.
	_expect(is_equal_approx(single.cell_width, 2.0) and is_equal_approx(single.cell_height, 2.0),
		"hex footprint does not use the battle cell metrics")
