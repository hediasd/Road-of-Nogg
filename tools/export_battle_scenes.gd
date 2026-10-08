extends SceneTree

## Rebuilds the visual scene of every battle map from its authored source and its committed bake,
## without touching the battle map itself.
##
## Usage:
##
##     Godot_v4.4-stable_win64.exe --headless --path . --script tools/export_battle_scenes.gd
##     Godot_v4.4-stable_win64.exe --headless --path . --script tools/export_battle_scenes.gd -- hexmap
##
## With no argument it rebuilds every map under `data/maps` that names a `VISUAL_SCENE_PATH`;
## with map ids it rebuilds only those.
##
## WHY THIS EXISTS BESIDE `export_battle_products.gd`. That tool republishes all of a map's
## battle products: bake, scene AND the tactical `data/maps/<id>.json`. Republishing the tactical
## map moves its source fingerprint and makes every scenario bound to it stale, and it refuses an
## authored source without a tactical layer -- which `hexmap.noggmap.json` is, because hexmap's
## battlefield was derived from its art before explicit tactical layers existed. A battle only
## needs the scene to show the ground, and the scene is built from two committed inputs: the
## authored document (extent, water, objects) and the committed bake (the art). So this rebuilds
## exactly the scene, at the path the battle map already names, and leaves the battle map and its
## scenarios alone.
##
## Legacy bare-`.json` sources (`proving_ground`, `hex_battle_fixture`) are read the same way the
## editor reads them, through `WorldMapTileData.fromDictionary`; the envelope format goes through
## `WorldMapFileDocument.decodeRecord`. Either way the document is named after the map's
## `SOURCE.ID`, because that name decides both the bake the scene samples and the source path the
## battle stage checks the scene against.
##
## Prints `HEX_SCENES_OK <count>` on success; exits 1 naming each map it could not rebuild.

const FileDocument = preload("res://map_editor/WorldMapFileDocument.gd")
const MapData = preload("res://map_editor/WorldMapTileData.gd")
const SceneExport = preload("res://map_editor/WorldMapSceneExport.gd")
const Uniforms = preload("res://worldmap/WorldMapGroundUniforms.gd")

const MAP_DIR := "res://data/maps"
const AUTHORED_DIR := "res://data/authored"


func _init() -> void:
	var wanted := OS.get_cmdline_user_args()
	var results := run(wanted)
	var failed := 0
	for result: Dictionary in results:
		if bool(result.get("ok", false)):
			print("wrote %s" % str(result["path"]))
		else:
			failed += 1
			printerr("HEX_SCENE_FAILED %s: %s" % [str(result.get("map", "")), str(result.get("error", ""))])
	if failed > 0 or results.is_empty():
		if results.is_empty():
			printerr("HEX_SCENE_FAILED: no battle map named a visual scene")
		quit(1)
		return
	print("HEX_SCENES_OK %d" % results.size())
	quit(0)


## One result per map rebuilt (or refused), in map-file order. `wanted` empty means every map.
static func run(wanted: PackedStringArray) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for mapPath in _mapFiles():
		var mapID := mapPath.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(mapID):
			continue
		var record := _readMap(mapPath)
		var source: Dictionary = record.get("SOURCE", {})
		var scenePath := str(source.get("VISUAL_SCENE_PATH", ""))
		if scenePath.is_empty():
			continue
		var result := exportFor(str(source.get("ID", "")), scenePath)
		result["map"] = mapID
		results.append(result)
	for mapID in wanted:
		if not FileAccess.file_exists("%s/%s.json" % [MAP_DIR, mapID]):
			results.append({"ok": false, "map": mapID, "error": "no battle map at %s/%s.json" % [MAP_DIR, mapID]})
	return results


static func exportFor(sourceID: String, scenePath: String) -> Dictionary:
	if sourceID.is_empty():
		return {"ok": false, "error": "the battle map names no SOURCE.ID"}
	var data := loadSource(sourceID)
	if data == null:
		return {"ok": false, "error": "no readable authored source for '%s' under %s" % [sourceID, AUTHORED_DIR]}
	data.region_name = sourceID
	return SceneExport.exportScene(data, Uniforms.DEFAULTS.duplicate(true), scenePath)


## The envelope format first, then the legacy bare document the editor still reads.
static func loadSource(sourceID: String) -> WorldMapTileData:
	var envelopePath := "%s/%s%s" % [AUTHORED_DIR, sourceID, FileDocument.EXTENSION]
	if FileAccess.file_exists(envelopePath):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(envelopePath))
		if not parsed is Dictionary:
			return null
		var decoded := FileDocument.decodeRecord(parsed as Dictionary)
		return decoded["data"] if bool(decoded.get("ok", false)) else null
	var legacyPath := "%s/%s.json" % [AUTHORED_DIR, sourceID]
	if FileAccess.file_exists(legacyPath):
		return MapData.loadFrom(legacyPath)
	return null


static func _mapFiles() -> Array[String]:
	var found: Array[String] = []
	for fileName in DirAccess.get_files_at(MAP_DIR):
		if fileName.ends_with(".json") and not fileName.ends_with(".receipt.json"):
			found.append("%s/%s" % [MAP_DIR, fileName])
	found.sort()
	return found


static func _readMap(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Catalogs in `data/` are arrays of records; a battle map file holds exactly one.
	if parsed is Array and parsed.size() == 1 and parsed[0] is Dictionary:
		return parsed[0]
	return parsed if parsed is Dictionary else {}
