extends SceneTree

## FHB-3: exports a saved `.noggmap.json` map's battle products -- the tactical JSON under
## `data/battle/maps` and the visual scene under `scenes/worldmap/generated` -- without opening
## the editor. This is the same product pair `WorldMapBattleExport.exportBoth()` already builds
## for the in-editor Export Battle flow; this file is a headless caller of that same API, not a
## second exporter.
##
## Usage:
##
##     Godot_v4.4-stable_win64.exe --headless --path . --script \
##         scripts/worldmap_editor/export_battle_products.gd -- <mapID>
##
## `<mapID>` names an authored source under `data/worldmap/authored/<mapID>.noggmap.json` -- the
## versioned envelope format the editor's own Save/Save As write, and the ONLY format this reads.
## A pre-migration bare `.json` region (e.g. the frozen `proving_ground` fixture) is out of this
## script's scope; it predates the envelope and the editor's own Open dialog cannot read it back
## either. `hexmap` and every map saved from now on are the format this targets.
##
## THE BAKE NEEDS A REAL IMPORT PASS, WHICH THIS SCRIPT RUNS FOR YOU. `ResourceLoader.load()`
## refuses a texture with no `.import` sidecar -- verified directly: a freshly written PNG is not
## loadable in the same process that wrote it, headless or not, until Godot's own import scan has
## seen it. `--headless --import --path .` is that scan, and it is documented in `DEVELOPMENT.md`
## as a manual step; this script runs it for you with `OS.execute()`, blocking until it finishes,
## so the whole export really is the one command in the usage line above. That nested process logs
## `ERROR: Do not use progress dialog (task) while flushing the message queue` lines to its own
## stderr -- this is the same headless-import noise `DEVELOPMENT.md`'s "Windows execution
## safeguards" section already names ("`--editor --quit` ... can hit progress-dialog ... errors
## during import"); the import still completes and the exit code is the thing to trust, not the
## text.
##
## A CONTENT REFUSAL IS CAUGHT BEFORE ANYTHING IS WRITTEN. `WorldMapBattleExport.buildDefinition()`
## does no I/O -- it only reads the document and answers ok or refused -- so this script calls it
## once, dry, before baking or exporting, on the exact same untouched `data` object `exportBoth()`
## will use. A missing tactical layer, an unsupported slope, a bridge: all of it is caught here,
## and refusing here means neither the bake nor the scene nor the battle map is ever written for
## that failure. What this canNOT promise is atomicity against a genuine I/O failure once writing
## has started -- `exportBoth()` writes the scene before the tactical map, and this script does
## not add rollback around an API it was told not to modify; a disk failure between those two
## writes could leave a scene with no matching battle map. That is a narrower, rarer risk than the
## content refusals this dry run already rules out, and it is the same risk the in-editor Export
## Battle action already carries.
##
## THE EXPORTED PRODUCTS ARE NAMED FOR THE FILE, NEVER FOR THE DOCUMENT'S OWN TITLE.
## `WorldMapSceneExport` derives the bake path AND the scene path from `data.region_name`, and the
## editor deliberately keeps a document's title independent of its filename (`WORLDMAP_EDITOR.md`
## §12) -- `hexmap.noggmap.json` itself carries the title "Untitled" for exactly that reason. A
## headless export needs a stable, predictable filename, not whatever an author typed into New, so
## this script overwrites `data.region_name` to `mapID` in memory before baking or exporting. The
## source file on disk is read-only input and is never touched.
##
## RE-EXPORTING INVALIDATES ANY SCENARIO BOUND TO THE OLD FINGERPRINT. `BattleScenarioFactory`
## refuses to load a scenario whose `MAP.SOURCE_FINGERPRINT` no longer matches -- that is the
## binding working as designed, not a bug this script works around. On success this script scans
## `data/battle/scenarios/*.json` for any scenario naming this `mapID` and reminds you to update
## it, matching the map's freshly written fingerprint.

const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const Paths = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspacePaths.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const TacticalLayer = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const SCENARIO_DIR := "res://data/battle/scenarios"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0].is_empty():
		printerr("usage: export_battle_products.gd -- <mapID>")
		quit(1)
		return

	var mapID: String = args[0]
	var result := run(mapID)
	if not bool(result.get("ok", false)):
		printerr("HEX_EXPORT_FAILED: %s" % str(result.get("error", "")))
		quit(1)
		return

	print("wrote %s" % str(result["bake_path"]))
	print("wrote %s" % str(result["scene_path"]))
	print("wrote %s" % str(result["map_path"]))
	for reminder: String in _boundScenarios(mapID):
		print("reminder: %s names this map; its fingerprint is now stale until re-exported" % reminder)
	print("HEX_EXPORT_OK %s" % mapID)
	quit(0)


## The whole export, as one function so the probe can call it without re-running the process.
static func run(mapID: String) -> Dictionary:
	if not Paths.isValidName(mapID):
		return {"ok": false, "error": Paths.describeInvalidName(mapID)}

	var sourcePath := Paths.sourcePathFor(mapID)
	if sourcePath.is_empty() or not FileAccess.file_exists(sourcePath):
		return {"ok": false, "error": "no authored source at %s" % Paths.sourceRoot().path_join(
			"%s%s" % [mapID, FileDocument.EXTENSION]
		)}

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sourcePath))
	if not parsed is Dictionary:
		return {"ok": false, "error": "%s is not valid JSON" % sourcePath}
	var decoded := FileDocument.decodeRecord(parsed as Dictionary)
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "error": "could not decode %s: %s" % [sourcePath, decoded.get("error", "")]}

	var data: WorldMapTileData = decoded["data"]
	# See the class note: export identity follows the file, not the document's own title.
	data.region_name = mapID

	# Dry run first -- see the class note on why this, and not exportBoth() alone, is what makes
	# a content refusal write nothing.
	var dryRun := BattleExport.buildDefinition(data, "", TacticalLayer.DEFAULT_LAYER, mapID)
	if not bool(dryRun.get("ok", false)):
		return dryRun

	var baker := Baker.new()
	var texture := baker.bake(data)
	if texture == null:
		return {"ok": false, "error": "could not bake the ground texture for %s" % mapID}
	var bakePath := Baker.generatedPathFor(mapID)
	if not baker.saveTo(bakePath):
		return {"ok": false, "error": "could not write the bake to %s" % bakePath}

	if not _importGeneratedArt():
		return {
			"ok": false,
			"error": (
				"the bundled Godot's headless import pass failed -- rerun "
				+ "'godot --headless --import --path .' by hand and inspect its output"
			),
		}

	var framing := Uniforms.DEFAULTS.duplicate(true)
	var exported := BattleExport.exportBoth(data, framing, mapID)
	if not bool(exported.get("ok", false)):
		return exported
	exported["bake_path"] = bakePath
	return exported


## Runs the same import scan `DEVELOPMENT.md` documents as a manual step, blocking until it
## finishes. See the class note for why this makes the export genuinely one command, and why its
## own stderr noise is expected rather than a sign it failed.
static func _importGeneratedArt() -> bool:
	var executable := OS.get_executable_path()
	var projectPath := ProjectSettings.globalize_path("res://")
	var output := []
	var exitCode := OS.execute(
		executable, ["--headless", "--import", "--path", projectPath], output, true
	)
	if exitCode != 0:
		printerr("import pass exited %d:\n%s" % [exitCode, "\n".join(output)])
	return exitCode == 0


## Every scenario file naming `mapID`, as a human-readable "<file> (SCENARIO_ID)" line -- see the
## class note on why re-exporting makes these stale.
static func _boundScenarios(mapID: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(SCENARIO_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var fileName := dir.get_next()
	while not fileName.is_empty():
		if not dir.current_is_dir() and fileName.ends_with(".json"):
			var path := "%s/%s" % [SCENARIO_DIR, fileName]
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Array:
				for entry in parsed:
					if entry is Dictionary and str((entry as Dictionary).get("MAP", {}).get("ID", "")) == mapID:
						found.append("%s (%s)" % [fileName, str((entry as Dictionary).get("NAME", ""))])
		fileName = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
