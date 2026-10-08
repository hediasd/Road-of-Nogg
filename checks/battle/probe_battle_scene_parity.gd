extends SceneTree

## What this proves: every battle map that names a visual scene has that scene committed, and the
## committed scene is exactly what its authored source and committed bake rebuild today.
##
## Why it exists: the scenes used to be gitignored, so a folder move or a fresh clone lost them and
## the default battle opened on a bare board with nothing failing but a notice. They are committed
## now. This probe is what makes committing them safe: a source or bake edited without re-running
## `tools/export_battle_scenes.gd` fails here instead of shipping a stale ground.
##
## The rebuild is written under `user://`, never over the committed file. `ResourceSaver` derives
## each `id="..."` suffix from the destination path, so the same content saved to a different path
## carries different ids; those suffixes are masked before comparing. Everything else, byte for
## byte, must match.

const ExportScenes = preload("res://tools/export_battle_scenes.gd")

const SCRATCH_DIR := "user://battle_scene_parity"
const MARKER := "HXB_SCENE_PARITY_OK"

var failures: Array[String] = []


func _init() -> void:
	var checked := 0
	for mapPath in ExportScenes._mapFiles():
		var record := ExportScenes._readMap(mapPath)
		var source: Dictionary = record.get("SOURCE", {})
		var scenePath := str(source.get("VISUAL_SCENE_PATH", ""))
		if scenePath.is_empty():
			continue
		checked += 1
		_checkMap(mapPath.get_file().get_basename(), str(source.get("ID", "")), scenePath)
	_require(checked >= 3, "expected at least the hexmap, proving_ground and fixture scenes, found %d" % checked)

	for failure in failures:
		printerr("HXB_SCENE_PARITY_FAILURE: %s" % failure)
	if failures.is_empty():
		print("battle scenes matching their rebuild: %d" % checked)
		print(MARKER)
	quit(0 if failures.is_empty() else 1)


func _checkMap(mapID: String, sourceID: String, scenePath: String) -> void:
	if not FileAccess.file_exists(scenePath):
		failures.append("%s: %s is not committed; run tools/export_battle_scenes.gd -- %s" % [mapID, scenePath, mapID])
		return
	var scratchPath := "%s/%s" % [SCRATCH_DIR, scenePath.get_file()]
	var rebuilt := ExportScenes.exportFor(sourceID, scratchPath)
	if not bool(rebuilt.get("ok", false)):
		failures.append("%s: could not rebuild from its source: %s" % [mapID, str(rebuilt.get("error", ""))])
		return
	var committed := _masked(FileAccess.get_file_as_string(scenePath))
	var fresh := _masked(FileAccess.get_file_as_string(scratchPath))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratchPath))
	if committed != fresh:
		failures.append("%s: %s differs from a rebuild (first difference: %s); run tools/export_battle_scenes.gd -- %s"
			% [mapID, scenePath, _firstDifference(committed, fresh), mapID])


## Replaces the path-derived suffix of every resource id with a fixed token, in declarations and
## references alike.
func _masked(text: String) -> String:
	var pattern := RegEx.create_from_string("(id=\"|Resource\\(\")([A-Za-z0-9]+)_[a-z0-9]{5}\"")
	return pattern.sub(text, "$1$2_xxxxx\"", true)


func _firstDifference(a: String, b: String) -> String:
	var linesA := a.split("\n")
	var linesB := b.split("\n")
	for index in range(mini(linesA.size(), linesB.size())):
		if linesA[index] != linesB[index]:
			return "line %d: '%s' vs '%s'" % [index + 1, linesA[index], linesB[index]]
	return "length %d vs %d lines" % [linesA.size(), linesB.size()]


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
