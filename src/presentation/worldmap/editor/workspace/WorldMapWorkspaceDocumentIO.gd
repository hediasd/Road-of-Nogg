## Every file the editor touches, behind one small object.
##
## WHY AN OBJECT RATHER THAN DIRECT CALLS. The behaviour that matters most here is what happens
## when a write FAILS -- the checkpoint must not advance, the active path must not move, and the
## author must be told which half of the save landed. None of that can be exercised against real
## `FileAccess`, because a probe cannot make a disk fail on demand and must not be writing over
## authored maps to try. Routing every read and write through here lets a probe substitute a
## subclass that fails exactly the call it wants to test, while the shipping editor uses this
## implementation unchanged.
##
## THIS CLASS DECIDES NOTHING. It reads, writes, deletes and lists, and reports success as a bool.
## Whether a failure means "retry", "leave the checkpoint alone" or "keep the old path" is the
## controller's judgement, not this file's -- which is what keeps the substituted version in a
## probe honest: it can only change what the disk did, never what the editor concluded.

class_name WorldMapWorkspaceDocumentIO
extends RefCounted

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")


func saveFileRecord(record: Dictionary, path: String) -> bool:
	if path.is_empty() or record.is_empty():
		return false
	var decoded := FileDocument.decodeRecord(record)
	if not bool(decoded.get("ok", false)):
		return false
	return writeTextAtomic(path, FileDocument.canonicalText(decoded["record"] as Dictionary))


func loadFileRecord(path: String) -> Dictionary:
	if path.is_empty() or not _repairPrevious(path) or not fileExists(path):
		return {"ok": false, "record": {}, "data": null, "error": "file is unavailable"}
	var parser := JSON.new()
	if parser.parse(readText(path)) != OK or not parser.data is Dictionary:
		return {"ok": false, "record": {}, "data": null, "error": "file is not JSON"}
	return FileDocument.decodeRecord(parser.data as Dictionary)


func saveSource(document: WorldMapTileData, path: String) -> bool:
	if document == null or path.is_empty():
		return false
	return writeTextAtomic(path, JSON.stringify(document.toDictionary(), "\t") + "\n")


func saveBake(baker: WorldMapBaker, path: String) -> bool:
	if baker == null or path.is_empty():
		return false
	if not ensureDirectory(path.get_base_dir()):
		return false
	# Keep the real extension so Image.save_png() accepts the temporary destination.
	var temporary := "%s.tmp.%s" % [path.get_basename(), path.get_extension()]
	if not baker.saveTo(temporary):
		return false
	return _installTemporary(path, temporary)


## Null on any failure -- missing, unreadable or malformed. The caller keeps its current document
## when this returns null; a failed Open may not cost the author what they already had open.
func loadSource(path: String) -> WorldMapTileData:
	if path.is_empty() or not _repairPrevious(path) or not fileExists(path):
		return null
	return MapDataScript.loadFrom(path)


func fileExists(path: String) -> bool:
	return FileAccess.file_exists(path)


## Content identity for "is the file on disk still the one this snapshot came from". Modification
## time plus size can miss a same-size rewrite within one filesystem timestamp tick, which is
## precisely the edit recovery must not call unchanged. Snapshots run only after a 30-second idle
## interval, so hashing the authored JSON here is both bounded and worth the stronger answer.
func fingerprint(path: String) -> String:
	if not fileExists(path):
		return ""
	return FileAccess.get_sha256(path)


func readText(path: String) -> String:
	if not fileExists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func saveResource(resource: Resource, path: String) -> bool:
	if resource == null or path.is_empty() or not ensureDirectory(path.get_base_dir()):
		return false
	return ResourceSaver.save(resource, path) == OK


func loadTexture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## Written to a temporary sibling, with the previous file retained until the replacement lands.
## The `.previous` file is also repaired on the next directory listing if the process ended in
## the short interval between the two renames. That makes an interrupted replacement recoverable
## instead of deleting the last good snapshot first.
func writeTextAtomic(path: String, text: String) -> bool:
	if path.is_empty():
		return false
	if not ensureDirectory(path.get_base_dir()):
		return false
	var temporary := "%s.tmp" % path
	if not _repairPrevious(path):
		return false
	if not writeTextFile(temporary, text):
		return false
	return _installTemporary(path, temporary)


func _installTemporary(path: String, temporary: String) -> bool:
	var previous := "%s.previous" % path
	if not _repairPrevious(path):
		deleteFile(temporary)
		return false
	var hadPrevious := fileExists(path)
	if hadPrevious and not moveFile(path, previous):
		deleteFile(temporary)
		return false
	if moveFile(temporary, path):
		if hadPrevious:
			deleteFile(previous)
		return true
	# Installing the new file failed. Put the old one back before returning failure; if that move
	# also fails, leave `.previous` in place for `listFiles()` to repair on the next launch.
	if hadPrevious and not fileExists(path):
		moveFile(previous, path)
	deleteFile(temporary)
	return false


## Kept as overridable operations so the document-safety probe can fail the install rename while
## exercising this real transaction instead of copying its sequence into test code.
func writeTextFile(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func moveFile(from: String, to: String) -> bool:
	return DirAccess.rename_absolute(from, to) == OK


func _repairPrevious(path: String) -> bool:
	var previous := "%s.previous" % path
	if not fileExists(previous):
		return true
	if fileExists(path):
		return deleteFile(previous)
	return moveFile(previous, path)


func deleteFile(path: String) -> bool:
	if not fileExists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


func ensureDirectory(path: String) -> bool:
	if path.is_empty():
		return false
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK


func listFiles(directory: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			if entry.ends_with(".%s.previous" % extension):
				var restoredName := entry.trim_suffix(".previous")
				var restoredPath := "%s/%s" % [directory, restoredName]
				if _repairPrevious(restoredPath) and fileExists(restoredPath) and not result.has(restoredName):
					result.append(restoredName)
			elif entry.get_extension() == extension:
				if not result.has(entry):
					result.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
