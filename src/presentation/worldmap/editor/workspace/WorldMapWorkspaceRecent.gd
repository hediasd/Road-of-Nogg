## Persistent path list for explicit Open Recent choices.
class_name WorldMapWorkspaceRecent
extends RefCounted

const CONFIG_PATH := "user://worldmap_editor/recent_maps.cfg"
const SECTION := "recent"
const KEY_PATHS := "paths"
const LIMIT := 12


static func paths(io) -> Array[String]:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return [] as Array[String]
	var result: Array[String] = []
	var raw = config.get_value(SECTION, KEY_PATHS, [])
	if raw is Array:
		for value in raw:
			var path := str(value)
			if not path.is_empty() and io.fileExists(path) and not result.has(path):
				result.append(path)
	return result


static func remember(io, path: String) -> void:
	if path.is_empty() or not io.fileExists(path):
		return
	var next: Array[String] = [path]
	for existing in paths(io):
		if existing != path and next.size() < LIMIT:
			next.append(existing)
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_PATHS, next)
	config.save(CONFIG_PATH)
