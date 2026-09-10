## Crash recovery for unsaved editing, and the rules that stop it from becoming data loss of its
## own.
##
## A SNAPSHOT IS NOT A SAVE, and the separation is the whole design. Snapshots live under
## `user://worldmap_editor/recovery/`, which is outside the repository, outside the authored
## source tree and outside the generated asset tree. Nothing here can write a `.json` into
## `data/worldmap/authored` or a `.png` into the generated folder, so an autosave cannot overwrite
## the author's map -- the failure mode that makes autosave worse than no autosave.
##
## RECOVERED CONTENT IS OFFERED, NEVER APPLIED. On reopen the editor lists what it found and the
## author chooses; nothing is loaded over a source file automatically and nothing is written back
## automatically. A recovered document comes back as an UNSAVED document with a fresh history, so
## the only way its content reaches disk is the author deciding to save it.
##
## THE SOURCE MAY HAVE MOVED ON. A snapshot records the source path and a fingerprint of that file
## at snapshot time, so `statusFor` can say whether the map on disk is still the one the snapshot
## branched from. A source that changed since is the case where blindly recovering would silently
## discard whatever changed it, so it is reported rather than resolved.
##
## WHEN IT WRITES: only when the document is dirty, only when no stroke is open, only after a
## quiet interval, and only when the content actually moved since the last snapshot. A saved or
## untouched document is never written, so leaving the editor open costs nothing.

class_name WorldMapWorkspaceRecovery
extends RefCounted

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const DocumentIO = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceDocumentIO.gd")
const Paths = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspacePaths.gd")

## Outside every tracked root -- see the class note.
const ROOT := "user://worldmap_editor/recovery"
const EXTENSION := "json"
## Seconds of dirty, stroke-free quiet before a snapshot is worth writing.
const IDLE_SECONDS := 30.0

const K_NAME := "MAP_NAME"
const K_SOURCE_PATH := "SOURCE_PATH"
const K_FINGERPRINT := "SOURCE_FINGERPRINT"
const K_REVISION := "REVISION"
const K_SAVED_AT := "SNAPSHOT_UNIX"
const K_DOCUMENT := "DOCUMENT"
## Runtime-only identity supplied by `list()`. Never read from snapshot JSON: the enumerated file
## is the authority for what Recover or Discard may touch.
const K_SNAPSHOT_PATH := "_SNAPSHOT_PATH"

const STATUS_SOURCE_UNCHANGED := "unchanged"
const STATUS_SOURCE_NEWER := "newer"
const STATUS_SOURCE_MISSING := "missing"
const STATUS_SOURCE_INVALID := "invalid"

## The revision the last snapshot captured, so an idle document is not rewritten every interval.
var _snapshotRevision := -1


func resetForDocument() -> void:
	_snapshotRevision = -1


## The one place the timing rule lives, so the controller's timer and the probe agree about it.
## `idleSeconds` is how long the document has been dirty with no stroke and no further edit.
func shouldSnapshot(
	dirty: bool, strokeOpen: bool, idleSeconds: float, revision: int
) -> bool:
	if not dirty or strokeOpen:
		return false
	if idleSeconds < IDLE_SECONDS:
		return false
	return revision != _snapshotRevision


## True when the snapshot really was written. `sourcePath` may be empty for a never-saved
## document -- that is the case recovery matters most for, and it is stored as empty rather than
## invented.
func snapshot(
	io: DocumentIO, document: WorldMapTileData, mapName: String,
	sourcePath: String, revision: int
) -> bool:
	if document == null or io == null:
		return false
	var snapshotPath := pathFor(mapName)
	if snapshotPath.is_empty():
		return false
	if (
		not sourcePath.is_empty()
		and (sourcePath.get_extension() != "json" or not Paths.isContained(sourcePath, Paths.sourceRoot()))
	):
		return false
	var record := {
		K_NAME: mapName,
		K_SOURCE_PATH: sourcePath,
		K_FINGERPRINT: io.fingerprint(sourcePath) if not sourcePath.is_empty() else "",
		K_REVISION: revision,
		K_SAVED_AT: int(Time.get_unix_time_from_system()),
		K_DOCUMENT: document.toDictionary(),
	}
	var written := io.writeTextAtomic(
		snapshotPath, JSON.stringify(record, "\t") + "\n"
	)
	if written:
		_snapshotRevision = revision
	return written


## Snapshot files are named from the map name, which has already been validated -- see
## `WorldMapWorkspacePaths`. A never-saved document still has a name, because New requires one.
static func pathFor(mapName: String) -> String:
	if not Paths.isValidName(mapName):
		return ""
	return "%s/%s.%s" % [ROOT, mapName, EXTENSION]


static func entryName(fileName: String) -> String:
	return fileName.get_basename()


## Every snapshot on disk, newest first, as records the caller can show without loading the whole
## document back. Malformed files are skipped rather than failing the listing: one unreadable
## snapshot must not hide the others.
static func list(io: DocumentIO) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if io == null:
		return entries
	for fileName in io.listFiles(ROOT, EXTENSION):
		var snapshotPath := "%s/%s" % [ROOT, fileName]
		if not _isSnapshotPath(snapshotPath):
			continue
		var listedName := entryName(fileName)
		if not Paths.isValidName(listedName):
			continue
		var raw = _parseRecord(io.readText(snapshotPath))
		if not raw is Dictionary:
			continue
		var record: Dictionary = raw
		if not record.get(K_DOCUMENT, null) is Dictionary:
			continue
		entries.append({
			# The file name came from a direct listing of ROOT. Embedded metadata may describe the
			# document but may never redirect a later read or delete.
			K_NAME: listedName,
			K_SOURCE_PATH: str(record.get(K_SOURCE_PATH, "")),
			K_FINGERPRINT: str(record.get(K_FINGERPRINT, "")),
			K_REVISION: int(record.get(K_REVISION, 0)),
			K_SAVED_AT: int(record.get(K_SAVED_AT, 0)),
			K_SNAPSHOT_PATH: snapshotPath,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a[K_SAVED_AT]) > int(b[K_SAVED_AT])
	)
	return entries


## Whether the map this snapshot branched from is still what it was. A never-saved snapshot has no
## source at all, which counts as unchanged: there is nothing it could conflict with.
static func statusFor(io: DocumentIO, entry: Dictionary) -> String:
	if io == null:
		return STATUS_SOURCE_INVALID
	var sourcePath := str(entry.get(K_SOURCE_PATH, ""))
	if sourcePath.is_empty():
		return STATUS_SOURCE_UNCHANGED
	if sourcePath.get_extension() != "json" or not Paths.isContained(sourcePath, Paths.sourceRoot()):
		return STATUS_SOURCE_INVALID
	if not io.fileExists(sourcePath):
		return STATUS_SOURCE_MISSING
	return (
		STATUS_SOURCE_UNCHANGED
		if io.fingerprint(sourcePath) == str(entry.get(K_FINGERPRINT, ""))
		else STATUS_SOURCE_NEWER
	)


## What the recovery offer says about one entry, including the warning that matters.
static func describe(io: DocumentIO, entry: Dictionary) -> String:
	var when := Time.get_datetime_string_from_unix_time(int(entry.get(K_SAVED_AT, 0)), true)
	match statusFor(io, entry):
		STATUS_SOURCE_INVALID:
			return (
				"%s -- unsaved work from %s. Its recorded source path is invalid; recovering "
				+ "will open a new unsaved document and will not inspect or overwrite that path."
			) % [str(entry.get(K_NAME, "")), when]
		STATUS_SOURCE_NEWER:
			return (
				"%s -- unsaved work from %s. The saved map has CHANGED since this snapshot; "
				+ "recovering will not overwrite it, but the two have diverged."
			) % [str(entry.get(K_NAME, "")), when]
		STATUS_SOURCE_MISSING:
			return "%s -- unsaved work from %s. It was never saved to disk." % [
				str(entry.get(K_NAME, "")), when,
			]
		_:
			return "%s -- unsaved work from %s." % [str(entry.get(K_NAME, "")), when]


## The document a snapshot holds, or null. The caller opens it as an UNSAVED document with a fresh
## history -- see the class note on why recovery never writes anything back by itself.
static func loadDocument(io: DocumentIO, entry: Dictionary) -> WorldMapTileData:
	var snapshotPath := _entryPath(entry)
	if io == null or snapshotPath.is_empty():
		return null
	var raw = _parseRecord(io.readText(snapshotPath))
	if not raw is Dictionary:
		return null
	var stored = (raw as Dictionary).get(K_DOCUMENT, null)
	if not stored is Dictionary:
		return null
	return MapDataScript.fromDictionary(stored)


## Removes exactly the selected snapshot. Every other recovery is left alone -- discarding one
## map's unsaved work may not quietly discard another's.
static func discard(io: DocumentIO, entry: Dictionary) -> bool:
	var snapshotPath := _entryPath(entry)
	return io != null and not snapshotPath.is_empty() and io.deleteFile(snapshotPath)


## Called after a successful save: the work is on disk, so its snapshot has nothing left to
## protect and would otherwise be offered back forever.
func clearFor(io: DocumentIO, mapName: String) -> bool:
	_snapshotRevision = -1
	var snapshotPath := pathFor(mapName)
	return io != null and not snapshotPath.is_empty() and io.deleteFile(snapshotPath)


static func _entryPath(entry: Dictionary) -> String:
	var snapshotPath := str(entry.get(K_SNAPSHOT_PATH, ""))
	return snapshotPath if _isSnapshotPath(snapshotPath) else ""


static func _isSnapshotPath(path: String) -> bool:
	return path.get_extension() == EXTENSION and Paths.isContained(path, ROOT)


## `JSON.parse_string()` logs an engine error for expected malformed input. Recovery treats a bad
## snapshot as one skipped entry, so use the non-logging parser result and let the caller decide.
static func _parseRecord(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null
