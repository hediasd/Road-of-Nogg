extends SceneTree

## FHB-3: exports a map's battle products headlessly, without opening the editor.
##
## SLOW BY NECESSITY, NOT ACCIDENT. `export_battle_products.run()` shells out to a real
## `--headless --import --path .` pass so the bake it just wrote becomes loadable -- there is no
## way to test the actual deliverable without paying that cost once. Expect roughly ten seconds.
##
## WRITES TO THE REAL PROJECT DIRECTORIES AND CLEANS UP AFTER ITSELF. `WorldMapBattleExport.
## exportBoth()` has no destination override -- redirecting it to `user://` would mean bypassing
## `export_battle_products.run()` and calling the lower-level pieces directly, which is not
## calling "the runner's own entry function" any more, it is duplicating it. So this probe uses a
## disposable, uniquely-named fixture under the real authored/generated/battle directories and
## removes every file it wrote afterwards -- the fixture source, the bake and its `.import`
## sidecar, the generated scene, and the exported battle map. Nothing here touches an authored map
## that already existed.

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const Tactical = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const BattleMapFactory = preload("res://src/factories/BattleMapFactory.gd")
const ExportScript = preload("res://scripts/worldmap_editor/export_battle_products.gd")

const STARTER := "temp2_hex32_starter"
const LATTICE := Vector2i(3, 3)

## Disposable and unlikely to collide with a real author's map; verified absent before use.
var _fixtureID := "probe_headless_export_fixture"

var failures: Array[String] = []
var _writtenPaths: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checkRejectsPathSeparatorName()
	_checkFullExportSucceeds()
	_cleanup()

	if not failures.is_empty():
		for failure in failures:
			printerr("HEX_HEADLESS_EXPORT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX_HEADLESS_EXPORT_OK")
	quit(0)


## No I/O happens for an invalid name -- `Paths.isValidName` refuses before the source path is
## even built, so this needs no fixture and no cleanup.
func _checkRejectsPathSeparatorName() -> void:
	var result := ExportScript.run("../escaping")
	_require(not bool(result.get("ok", false)), "a name containing '..' was accepted")
	_require(not str(result.get("error", "")).is_empty(), "the path-separator refusal gave no reason")


func _checkFullExportSucceeds() -> void:
	var sourcePath := _writeFixtureSource()
	if sourcePath.is_empty():
		_require(false, "could not write the probe's own fixture source")
		return
	_writtenPaths.append(sourcePath)

	var result := ExportScript.run(_fixtureID)
	_require(bool(result.get("ok", false)), "the export refused a valid fixture: %s" % str(result.get("error", "")))
	if not bool(result.get("ok", false)):
		return

	for key in ["bake_path", "scene_path", "map_path"]:
		var path := str(result.get(key, ""))
		_require(not path.is_empty(), "the result carries no %s" % key)
		if not path.is_empty():
			_writtenPaths.append(path)
			_require(FileAccess.file_exists(path), "%s reports %s but it was not written" % [key, path])

	# The bake's own .import sidecar -- written by the nested import pass, not by run() directly,
	# so its absence would mean the import silently skipped this file rather than truly failing.
	var bakeImport := "%s.import" % str(result.get("bake_path", ""))
	_writtenPaths.append(bakeImport)
	_require(FileAccess.file_exists(bakeImport), "the bake has no .import sidecar after the export")

	# The battle map really parses through the runtime factory, same as a committed one would.
	var mapPath := str(result.get("map_path", ""))
	var loaded := BattleMapFactory.loadFromPath(mapPath)
	_require(bool(loaded.get("success", false)),
		"BattleMapFactory rejected the exported map: %s" % str(loaded.get("error", "")))

	# The scene is really loadable, not merely a path that was returned.
	var scenePath := str(result.get("scene_path", ""))
	_require(ResourceLoader.exists(scenePath), "the exported scene is not loadable")
	var packed := ResourceLoader.load(scenePath) as PackedScene
	_require(packed != null, "the exported scene did not load as a PackedScene")


## A small, valid hex document with a battlefield derived through FHB-2 -- enough for
## buildDefinition() to accept it, nothing more elaborate is needed to prove the export path.
func _writeFixtureSource() -> String:
	var data := MapDataScript.create(_fixtureID, LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = STARTER
	for row in LATTICE.y:
		for col in LATTICE.x:
			data.setCell("ground", Vector2i(col, row), "t000")
	Tactical.applyDerived(data, "ground")

	var record := FileDocument.createRecord(data)
	var saved := FileDocument.nextSaveRecord(record, false)
	if saved.is_empty():
		return ""
	var path := "res://data/worldmap/authored/%s%s" % [_fixtureID, FileDocument.EXTENSION]
	if FileAccess.file_exists(path):
		return ""  # refuse to overwrite -- a leftover from a prior crashed run needs a look, not a clobber
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(FileDocument.canonicalText(saved))
	file.close()
	return path


## Removes exactly what this run wrote, never a glob -- matching the rest of this project's
## disposable-fixture convention. `.godot/imported/` cache entries are left for Godot's own
## garbage collection; they are not tracked and not this probe's to manage.
func _cleanup() -> void:
	for path in _writtenPaths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
