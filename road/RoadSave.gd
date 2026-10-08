## Reads and writes a road's progress under `user://road/`, one file per road.
##
## `user://` because progress is the player's, not the project's: it must survive a rebuild and
## must never be committed. The file is the `RoadState.toDictionary()` record, nothing more.

extends RefCounted

const RoadStateScript = preload("res://road/RoadState.gd")

const SAVE_DIR := "user://road"


static func pathFor(roadName: String, directory: String = SAVE_DIR) -> String:
	return "%s/%s.json" % [directory, roadName]


static func exists(roadName: String, directory: String = SAVE_DIR) -> bool:
	return FileAccess.file_exists(pathFor(roadName, directory))


static func write(state, directory: String = SAVE_DIR) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := pathFor(state.roadName, directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not write %s (error %d)" % [path, FileAccess.get_open_error()]}
	file.store_string(JSON.stringify(state.toDictionary(), "\t"))
	file.close()
	return {"ok": true, "error": "", "path": path}


## `{ok, found, error, state}`. A missing save is not an error the player needs to see: `found` is
## false and the caller starts a fresh road. A save that exists but does not fit the road IS one.
static func read(road: Dictionary, directory: String = SAVE_DIR) -> Dictionary:
	var path := pathFor(str(road["name"]), directory)
	if not FileAccess.file_exists(path):
		return {"ok": true, "found": false, "error": "", "state": null}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "found": true, "error": "%s is not a road save" % path, "state": null}
	var restored := RoadStateScript.fromDictionary(parsed as Dictionary, road)
	restored["found"] = true
	return restored


static func erase(roadName: String, directory: String = SAVE_DIR) -> void:
	var path := pathFor(roadName, directory)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
