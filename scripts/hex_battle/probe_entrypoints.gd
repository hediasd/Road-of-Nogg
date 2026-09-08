extends SceneTree

const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const ManifestScript = preload("res://src/presentation/battle/BattleMapAssetManifest.gd")

const MAIN_SCENE := "res://scenes/battle/HexBattle.tscn"
const DEBUG_SCENE := "res://scenes/debug/HexBattleDebugScene.tscn"

## Retired by this item. Each must be gone from disk AND unreferenced by anything that remains --
## a deleted file that something still preloads is a project that imports and then crashes on the
## one path that loads it.
const RETIRED := [
	"res://scenes/Battle25D.tscn",
	"res://scenes/debug/BattleDebugScene.tscn",
	"res://src/systems/BattlePresentationController.gd",
	"res://src/systems/PlayerTurnController.gd",
	"res://src/presentation/GodotVisualAdapter.gd",
	"res://src/presentation/BattleCursorController.gd",
	"res://src/presentation/BattleCameraDirector.gd",
	"res://src/presentation/TurnOrderRail.gd",
	"res://src/presentation/BattleSetupUI.gd",
	"res://src/presentation/BattleSetupUIRefs.gd",
	"res://src/presentation/BattleUIBuilder.gd",
	"res://src/presentation/BattleUIRefs.gd",
	"res://src/board/BattleBoard.gd",
	"res://src/algorithms/ParabolicArc.gd",
]

## Kept on purpose, each with a live consumer this item checked. Asserting they SURVIVE is as
## much the point as asserting the retired ones are gone: the risk named for this item is a
## debug scene left needing a helper that was swept up with the rest.
const PRESERVED := [
	"res://scenes/debug/VFXDebugScene.tscn",
	"res://scenes/debug/WorldMapDebugScene.tscn",
	"res://scenes/debug/WorldMapEditorScene.tscn",
	"res://scenes/WorldMap.tscn",
	"res://src/presentation/BattleMeshFactory.gd",
	"res://src/presentation/MonsterModelFactory.gd",
	"res://src/presentation/VisualActionQueue.gd",
	"res://src/presentation/PlayerCommandMenu.gd",
	"res://src/presentation/ActionRow.gd",
	"res://src/presentation/ConsoleVisualAdapter.gd",
	"res://src/presentation/effects/SpellVfxCatalog.gd",
]

## Directories whose scripts must not load anything retired.
const LIVE_DIRS := ["res://src", "res://scripts", "res://scenes"]

## HXB-2 recorded this for the frozen archive. Re-checked here because retiring the live square
## battle is exactly the change that could disturb the copy meant to outlive it.
const ARCHIVE_SHA256 := "26ef69890641c705c0cba50003601eb6bb538b0600abf105377be805d2140006"

## Battle data that must survive packaging. `data/*.json` alone does not match these -- they are
## nested a directory deeper, which is the export gap this item's risk names.
const NESTED_BATTLE_DATA := [
	"res://data/battle/maps/editor_fixture.json",
	"res://data/battle/maps/technical_hxb_contract_map.json",
	"res://data/battle/scenarios/technical_hxb_contract_player_cpu.json",
	"res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json",
]

var failures: Array[String] = []


func _init() -> void:
	_checkMainSceneIsHex()
	_checkRetiredAreGoneAndUnreferenced()
	_checkPreservedSurvive()
	_checkNestedBattleDataIsExported()
	_checkArchiveIsUndisturbed()
	_checkNoSquareScenarioIsSelectable()
	_checkDocumentsRouteToTheArchive()
	_checkConsoleDemoUsesThePartyRuntime()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_ENTRYPOINTS_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_ENTRYPOINTS_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _readText(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _checkMainSceneIsHex() -> void:
	var settings := _readText("res://project.godot")
	_require(settings.contains('run/main_scene="%s"' % MAIN_SCENE),
		"project.godot does not name %s as the main scene" % MAIN_SCENE)
	_require(ResourceLoader.exists(MAIN_SCENE), "the main scene does not exist")
	_require(ResourceLoader.exists(DEBUG_SCENE), "the hex debug scene does not exist")
	# Loaded, not merely present: a main scene that does not load is a build that starts on black.
	_require(ResourceLoader.load(MAIN_SCENE) is PackedScene, "the main scene did not load")


func _checkRetiredAreGoneAndUnreferenced() -> void:
	for path: String in RETIRED:
		_require(not FileAccess.file_exists(path), "%s was retired but is still on disk" % path)
		var sidecar := "%s.uid" % path
		if path.ends_with(".gd"):
			_require(not FileAccess.file_exists(sidecar),
				"%s was retired but its uid sidecar remains" % path)

	# Nothing that survives may still load one of them.
	var offenders: Array[String] = []
	for directory: String in LIVE_DIRS:
		_scanForRetiredReferences(directory, offenders)
	for offender: String in offenders:
		failures.append(offender)


func _scanForRetiredReferences(directory: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scanForRetiredReferences("%s/%s" % [directory, sub], offenders)
	for fileName in dir.get_files():
		if not (fileName.ends_with(".gd") or fileName.ends_with(".tscn")):
			continue
		var path := "%s/%s" % [directory, fileName]
		# The probe's own lists name every retired path by design.
		if path == "res://scripts/hex_battle/probe_entrypoints.gd":
			continue
		var text := _readText(path)
		for retired: String in RETIRED:
			for form in ["preload(\"%s\"" % retired, "load(\"%s\"" % retired, "path=\"%s\"" % retired]:
				if text.contains(form):
					offenders.append("%s still loads retired %s" % [path, retired])


func _checkPreservedSurvive() -> void:
	for path: String in PRESERVED:
		_require(FileAccess.file_exists(path) or ResourceLoader.exists(path),
			"%s should have been preserved but is missing" % path)


## `data/*.json` does not match a file one directory deeper, so battle maps and scenarios need
## their own filters or a packaged build has no battles in it at all.
func _checkNestedBattleDataIsExported() -> void:
	var preset := _readText("res://export_presets.cfg")
	_require(not preset.is_empty(), "export_presets.cfg is unreadable")
	var includeLine := ""
	for line in preset.split("\n"):
		if str(line).begins_with("include_filter="):
			includeLine = str(line)
	_require(not includeLine.is_empty(), "the export preset declares no include_filter")
	for path: String in NESTED_BATTLE_DATA:
		_require(FileAccess.file_exists(path), "battle data %s is missing" % path)
		var directory := path.replace("res://", "").get_base_dir()
		_require(includeLine.contains("%s/*.json" % directory),
			"the export preset does not include %s/*.json, so %s would not ship" % [
				directory, path.get_file()
			])
	# The frozen archive must NOT ship inside the playable build; it is 13 MB of source for a
	# different product.
	var excludeLine := ""
	for line in preset.split("\n"):
		if str(line).begins_with("exclude_filter="):
			excludeLine = str(line)
	_require(excludeLine.contains("references/*"),
		"the export preset does not exclude the frozen square archive")

	# Every generated product the fixture map needs must be declared, so packaging knows to
	# regenerate rather than discover a missing scene at load.
	var products := ManifestScript.productsFor("editor_fixture")
	_require(products.size() == 1,
		"the asset manifest reports %d products for the fixture map" % products.size())


func _checkArchiveIsUndisturbed() -> void:
	var path := "res://references/square-battle/source.zip"
	_require(FileAccess.file_exists(path), "the frozen square archive is missing")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	file.close()
	var digest := context.finish().hex_encode()
	_require(digest == ARCHIVE_SHA256,
		"the frozen archive hashes %s, not the %s HXB-2 recorded" % [digest, ARCHIVE_SHA256])


## Old square map factories may remain as reference utilities, but a square map must never be
## offered as something a hex battle can be fought on.
func _checkNoSquareScenarioIsSelectable() -> void:
	var dir := DirAccess.open("res://data/battle/scenarios")
	_require(dir != null, "the scenario directory is missing")
	if dir == null:
		return
	var scenarioCount := 0
	for fileName in dir.get_files():
		if not fileName.ends_with(".json"):
			continue
		scenarioCount += 1
		var text := _readText("res://data/battle/scenarios/%s" % fileName)
		_require(text.contains("\"MAP\""),
			"scenario %s names no map" % fileName)
	_require(scenarioCount > 0, "no scenario is selectable at all")

	# And every map a scenario can reach is a hex map through the strict factory.
	var maps := DirAccess.open("res://data/battle/maps")
	if maps == null:
		return
	for fileName in maps.get_files():
		if not fileName.ends_with(".json"):
			continue
		var loaded := BattleMapFactoryScript.loadFromPath("res://data/battle/maps/%s" % fileName)
		if not loaded["success"]:
			# A map needing a regenerated visual product is a known, declared state -- the
			# manifest reports it -- not a square map leaking into the selectable set.
			_require(str(loaded.get("error", "")) == "missing_visual_resource",
				"map %s is unusable for a reason other than a pending re-export: %s" % [
					fileName, str(loaded.get("error", ""))
				])
			continue
		_require(loaded["definition"].gridKind == "hex_flat",
			"map %s is selectable and is not hex" % fileName)


## Documentation must have one clear route to the square reference and must not send future work
## back to the retired live battle.
func _checkDocumentsRouteToTheArchive() -> void:
	var readme := _readText("res://README.md")
	_require(readme.contains("references/square-battle"),
		"README.md does not point at the frozen square reference")
	_require(readme.contains(MAIN_SCENE) or readme.contains("scenes/battle/HexBattle.tscn"),
		"README.md does not name the hex battle scene")
	for path in ["res://README.md", "res://docs/ARCHITECTURE.md", "res://docs/DEVELOPMENT.md"]:
		var text := _readText(path)
		_require(not text.is_empty(), "%s is unreadable" % path)
		for retired in ["scenes/Battle25D.tscn", "scenes/debug/BattleDebugScene.tscn"]:
			_require(not text.contains(retired),
				"%s still routes readers to retired %s" % [path, retired])


func _checkConsoleDemoUsesThePartyRuntime() -> void:
	var text := _readText("res://scripts/demo_battle.gd")
	_require(text.contains("configureHexState"),
		"the console demo does not build a hex party state")
	# Matched on real calls, not on the header prose that explains what the demo no longer does.
	for line in text.split("
"):
		var code := str(line).strip_edges()
		if code.begins_with("#"):
			continue
		_require(not code.contains("sim.loadMap("),
			"the console demo still composes a square board by hand: %s" % code)
		_require(not code.contains("sim.spawnMonster("),
			"the console demo still spawns monsters individually: %s" % code)
