extends SceneTree

## Bounded check on the ways the editor can lose an author's work: a half-written save, a refused
## name that still moves the active path, an Open that discards what was already open, a snapshot
## that overwrites a real map, and a recovery applied over a source that has since moved on.
##
## Every write goes through an INJECTED WorldMapWorkspaceDocumentIO, so failures are produced on
## demand and nothing here touches an authored map or a generated asset. The recovery cases use a
## temp root under `user://`, which is where recovery lives anyway.

const Paths = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspacePaths.gd")
const DocumentIOScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceDocumentIO.gd")
const RecoveryScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceRecovery.gd")
const SavePointScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceSavePoint.gd")
const HistoryScript = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const BakerScript = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")

var failures: Array[String] = []


## An IO that records what it was asked to do and fails whichever call the case under test needs
## to fail. Everything it "writes" stays in memory, so no case can reach a real authored map.
class FakeIO extends DocumentIOScript:
	var files: Dictionary = {}
	var failSource := false
	var failBake := false
	var failWrite := false
	var sourceWrites: Array[String] = []
	var bakeWrites: Array[String] = []
	var fingerprints: Dictionary = {}

	func saveSource(document: WorldMapTileData, path: String) -> bool:
		if failSource:
			return false
		sourceWrites.append(path)
		files[path] = JSON.stringify(document.toDictionary())
		return true

	func saveBake(_baker: WorldMapBaker, path: String) -> bool:
		if failBake:
			return false
		bakeWrites.append(path)
		files[path] = "PNG"
		return true

	func loadSource(path: String) -> WorldMapTileData:
		if not files.has(path):
			return null
		var parser := JSON.new()
		if parser.parse(str(files[path])) != OK or not parser.data is Dictionary:
			return null
		return MapDataScript.fromDictionary(parser.data)

	func fileExists(path: String) -> bool:
		return files.has(path)

	func fingerprint(path: String) -> String:
		return str(fingerprints.get(path, "fp:%s" % path)) if files.has(path) else ""

	func readText(path: String) -> String:
		return str(files.get(path, ""))

	func writeTextAtomic(path: String, text: String) -> bool:
		if failWrite:
			return false
		files[path] = text
		return true

	func deleteFile(path: String) -> bool:
		files.erase(path)
		return true

	func ensureDirectory(_path: String) -> bool:
		return true

	func listFiles(directory: String, extension: String) -> Array[String]:
		var result: Array[String] = []
		for path: String in files:
			if path.get_base_dir() == directory and path.get_extension() == extension:
				result.append(path.get_file())
		result.sort()
		return result


## Exercises DocumentIO's real replace transaction while keeping every byte in memory. The one
## injected failure is the temporary-file install, after the old snapshot has moved aside.
class AtomicIO extends DocumentIOScript:
	var files: Dictionary = {}
	var failInstall := false

	func fileExists(path: String) -> bool:
		return files.has(path)

	func writeTextFile(path: String, content: String) -> bool:
		files[path] = content
		return true

	func moveFile(from: String, to: String) -> bool:
		if failInstall and from.ends_with(".tmp"):
			return false
		if not files.has(from) or files.has(to):
			return false
		files[to] = files[from]
		files.erase(from)
		return true

	func deleteFile(path: String) -> bool:
		files.erase(path)
		return true

	func ensureDirectory(_path: String) -> bool:
		return true


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checkNameValidation()
	_checkPathContainment()
	_checkAtomicReplacement()
	_checkRealFileTransactions()
	_checkSaveOutcomes()
	_checkSaveAsDoesNotMoveOnFailure()
	_checkFailedOpenKeepsDocument()
	_checkCheckpointIdentity()
	_checkSnapshotTiming()
	_checkRecoveryContainmentAndStatus()
	await _checkControllerTransactions()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_DOCUMENT_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP DOCUMENT SAFETY OK")
	quit(0)


## A failed install leaves the prior snapshot readable, and an interrupted transaction whose
## `.previous` file survived is repaired before a later replacement begins.
func _checkAtomicReplacement() -> void:
	var path := "%s/atomic.json" % RecoveryScript.ROOT
	var io := AtomicIO.new()
	io.files[path] = "old"
	io.failInstall = true
	_require(not io.writeTextAtomic(path, "new"), "a failed snapshot install reported success")
	_require(str(io.files.get(path, "")) == "old", "a failed install lost the prior snapshot")
	_require(not io.files.has("%s.tmp" % path), "a failed install left its temporary file")

	var interrupted := AtomicIO.new()
	interrupted.files["%s.previous" % path] = "older"
	_require(
		interrupted.writeTextAtomic(path, "newer"),
		"an interrupted replacement could not be repaired and retried"
	)
	_require(str(interrupted.files.get(path, "")) == "newer", "the repaired retry did not land")
	_require(
		not interrupted.files.has("%s.previous" % path),
		"the repaired retry left a stale previous snapshot"
	)


## One disposable user:// directory proves that the real Windows FileAccess/DirAccess path can
## perform both transactional formats. Every exact file is removed before the probe returns.
func _checkRealFileTransactions() -> void:
	var io := DocumentIOScript.new()
	var directory := "user://worldmap_editor/document_probe_%d" % Time.get_ticks_usec()
	var sourcePath := "%s/source.json" % directory
	var bakePath := "%s/bake.png" % directory
	var document := _document("real_io")
	document.description = "AAAA"
	var baker := BakerScript.new()
	baker.bake(document)

	_require(io.saveSource(document, sourcePath), "the real transactional source write failed")
	var fingerprintBefore := io.fingerprint(sourcePath)
	document.description = "BBBB"
	_require(io.saveSource(document, sourcePath), "the real source replacement failed")
	var fingerprintAfter := io.fingerprint(sourcePath)
	_require(
		not fingerprintBefore.is_empty() and fingerprintBefore != fingerprintAfter,
		"content fingerprint did not change after a source rewrite"
	)
	_require(io.loadSource(sourcePath) != null, "the transaction produced an unreadable source")
	_require(io.saveBake(baker, bakePath), "the real transactional bake write failed")
	_require(io.fileExists(bakePath), "the transactional bake did not land at its final path")

	for path in [
		sourcePath, "%s.tmp" % sourcePath, "%s.previous" % sourcePath,
		bakePath, "%s.tmp.png" % bakePath.get_basename(), "%s.previous" % bakePath,
	]:
		io.deleteFile(path)
	DirAccess.remove_absolute(directory)


func _document(name := "probe") -> WorldMapTileData:
	var doc := MapDataScript.create(name, Vector2i(7, 5), MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = "temp2_hex32_starter"
	return doc


## A map name becomes a file name, so anything that could steer the write elsewhere is refused --
## and refused with a message the author can act on rather than silently.
func _checkNameValidation() -> void:
	for good: String in ["untitled", "temp2_hex32_authored", "map-01", "A_b-9"]:
		_require(Paths.isValidName(good), "'%s' should be a valid map name" % good)
	for bad: String in [
		"", "  ", "../escape", "a/b", "a\\b", "..", ".hidden", "with space", "sub/dir/map",
		"map.json", "C:map", "map:1", "map*", "map\nnewline",
	]:
		_require(not Paths.isValidName(bad), "'%s' should be refused as a map name" % bad)
		_require(
			not Paths.describeInvalidName(bad).is_empty(),
			"'%s' was refused without saying why" % bad
		)
	_require(
		not Paths.isValidName("x".repeat(Paths.MAX_NAME_LENGTH + 1)),
		"an over-long name was accepted"
	)


## Validation is not enough on its own: the CONSTRUCTED path is confirmed to sit under the
## expected root, so a future change to how a path is built cannot quietly escape.
func _checkPathContainment() -> void:
	var source := Paths.sourcePathFor("valid_name")
	_require(not source.is_empty(), "a valid name produced no source path")
	_require(
		Paths.isContained(source, Paths.sourceRoot()),
		"the source path escaped the authored root"
	)
	_require(
		Paths.generatedPathFor("valid_name").begins_with(Paths.generatedRoot()),
		"the generated path escaped the generated root"
	)
	for bad: String in ["../escape", "a/b", ".."]:
		_require(
			Paths.sourcePathFor(bad).is_empty(),
			"'%s' produced a source path instead of being refused" % bad
		)
	# A sibling directory whose name merely starts with the root's must not pass containment.
	_require(
		not Paths.isContained("res://data/worldmap/authored_elsewhere/x.json", Paths.sourceRoot()),
		"a prefix-similar sibling directory passed the containment check"
	)
	_require(
		not Paths.isContained("res://data/worldmap/authored/sub/x.json", Paths.sourceRoot()),
		"a nested subdirectory passed the containment check"
	)


## The source and the bake are two files and either can fail alone. The checkpoint may advance
## only when BOTH landed; a half-written save must leave the document dirty.
func _checkSaveOutcomes() -> void:
	for scenario: Dictionary in [
		{"source": true, "bake": true, "clean": true, "label": "both wrote"},
		{"source": false, "bake": true, "clean": false, "label": "the source failed"},
		{"source": true, "bake": false, "clean": false, "label": "the bake failed"},
		{"source": false, "bake": false, "clean": false, "label": "both failed"},
	]:
		var io := FakeIO.new()
		io.failSource = not bool(scenario["source"])
		io.failBake = not bool(scenario["bake"])
		var document := _document()
		var history := HistoryScript.new()
		var savePoint := SavePointScript.new()
		savePoint.beginOpenedDocument(history.currentRevision())

		history.beginStroke("ground")
		history.paintCell(document, Vector2i(1, 1), "t001")
		history.endStroke()
		_require(savePoint.isDirty(history.currentRevision()), "an edit did not mark the map dirty")

		var sourceOk := io.saveSource(document, Paths.sourcePathFor("probe"))
		var bakeOk := io.saveBake(BakerScript.new(), Paths.generatedPathFor("probe"))
		if sourceOk and bakeOk:
			savePoint.markSaved(history.currentRevision())
		_require(
			savePoint.isDirty(history.currentRevision()) != bool(scenario["clean"]),
			"after '%s' the document's dirty state was wrong" % str(scenario["label"])
		)


## A refused or failed Save As must leave the editor pointing where it already was. Both halves
## are checked: the name written into the document, and the path it would next save to.
func _checkSaveAsDoesNotMoveOnFailure() -> void:
	var io := FakeIO.new()
	io.failBake = true
	var document := _document("original")
	var previousName := document.region_name

	# The controller's own sequence: set the name, attempt both writes, restore on failure.
	document.region_name = "renamed"
	var sourceOk := io.saveSource(document, Paths.sourcePathFor("renamed"))
	var bakeOk := io.saveBake(BakerScript.new(), Paths.generatedPathFor("renamed"))
	if not (sourceOk and bakeOk):
		document.region_name = previousName
	_require(
		document.region_name == "original",
		"a failed Save As left the document renamed to '%s'" % document.region_name
	)
	_require(not bakeOk, "the bake was supposed to fail in this scenario")

	# A refused NAME must not even attempt a write.
	_require(
		Paths.sourcePathFor("../escape").is_empty(),
		"a traversal name produced a path a Save As would have written to"
	)


## Choosing a corrupt or missing file must cost nothing. The load is attempted and checked before
## any editor state is replaced.
func _checkFailedOpenKeepsDocument() -> void:
	var io := FakeIO.new()
	var goodPath := Paths.sourcePathFor("good")
	io.saveSource(_document("good"), goodPath)

	var malformedPath := Paths.sourcePathFor("malformed")
	io.files[malformedPath] = "{ this is not json"
	_require(io.loadSource(malformedPath) == null, "a malformed file loaded as a document")
	_require(
		io.loadSource(Paths.sourcePathFor("absent")) == null,
		"a missing file loaded as a document"
	)
	_require(io.loadSource(goodPath) != null, "a good file failed to load")

	# The controller only clears history and reassigns after a non-null load, so a null result is
	# exactly the signal that keeps the open document alive.
	var history := HistoryScript.new()
	var document := _document("open")
	history.beginStroke("ground")
	history.paintCell(document, Vector2i(0, 0), "t001")
	history.endStroke()
	var revisionBefore := history.currentRevision()
	if io.loadSource(malformedPath) != null:
		history.clear()
	_require(
		history.currentRevision() == revisionBefore and history.undoCount() == 1,
		"a failed open cleared the history of the document that was already open"
	)


## The checkpoint tracks history identity, not depth -- re-asserted here against the two states
## a depth comparison reported as saved, because this is the item that owns save correctness.
func _checkCheckpointIdentity() -> void:
	var savePoint := SavePointScript.new()
	var history := HistoryScript.new()
	var document := _document()
	savePoint.beginNewDocument()
	_require(
		savePoint.isDirty(history.currentRevision()),
		"a never-saved document reported as saved"
	)
	savePoint.markSaved(history.currentRevision())

	history.beginStroke("ground")
	history.paintCell(document, Vector2i(1, 1), "t001")
	history.endStroke()
	history.undo(document)
	history.beginStroke("ground")
	history.paintCell(document, Vector2i(2, 2), "t002")
	history.endStroke()
	_require(history.undoCount() == 1, "the divergence case did not reproduce the saved depth")
	_require(
		savePoint.isDirty(history.currentRevision()),
		"divergent history at the saved depth reported as saved"
	)

	var capped := HistoryScript.new()
	capped.maxDepth = 2
	var evictionPoint := SavePointScript.new()
	capped.beginStroke("ground")
	capped.paintCell(document, Vector2i(3, 3), "t003")
	capped.endStroke()
	evictionPoint.markSaved(capped.currentRevision())
	for index in 4:
		capped.beginStroke("ground")
		capped.paintCell(document, Vector2i(3, 3), "t%03d" % (index + 4))
		capped.endStroke()
	_require(
		evictionPoint.isDirty(capped.currentRevision()),
		"edits past the history cap reported as saved"
	)


## No writes while the document is unchanged, saved, or mid-gesture -- and no repeated write of
## content that has not moved since the last snapshot.
func _checkSnapshotTiming() -> void:
	var recovery := RecoveryScript.new()
	var longEnough := RecoveryScript.IDLE_SECONDS + 1.0

	_require(
		not recovery.shouldSnapshot(false, false, longEnough, 5),
		"a clean document was snapshotted"
	)
	_require(
		not recovery.shouldSnapshot(true, true, longEnough, 5),
		"a snapshot was taken in the middle of a stroke"
	)
	_require(
		not recovery.shouldSnapshot(true, false, RecoveryScript.IDLE_SECONDS - 1.0, 5),
		"a snapshot was taken before the idle interval elapsed"
	)
	_require(
		recovery.shouldSnapshot(true, false, longEnough, 5),
		"a dirty, idle, stroke-free document was not snapshotted"
	)

	var io := FakeIO.new()
	_require(
		recovery.snapshot(io, _document("timing"), "timing", "", 5),
		"the snapshot did not write"
	)
	_require(
		not recovery.shouldSnapshot(true, false, longEnough, 5),
		"the same revision was snapshotted twice"
	)
	_require(
		recovery.shouldSnapshot(true, false, longEnough, 6),
		"a further edit did not become snapshottable"
	)


## Snapshots live outside every tracked root, describe whether their source has moved on, and are
## discarded one at a time.
func _checkRecoveryContainmentAndStatus() -> void:
	var path := RecoveryScript.pathFor("anything")
	_require(path.begins_with("user://"), "recovery is not under user://")
	_require(
		not path.begins_with(Paths.sourceRoot()) and not path.begins_with(Paths.generatedRoot()),
		"a recovery snapshot could land in an authored or generated folder"
	)

	var io := FakeIO.new()
	var recovery := RecoveryScript.new()
	var sourcePath := Paths.sourcePathFor("tracked")
	io.saveSource(_document("tracked"), sourcePath)
	_require(
		not recovery.snapshot(
			io, _document("escape_source"), "escape_source",
			"res://data/worldmap/authored/../outside.json", 1
		),
		"a snapshot accepted a source identity outside the authored root"
	)

	# Snapshot of a document that HAS a source on disk.
	var tracked := _document("tracked")
	recovery.snapshot(io, tracked, "tracked", sourcePath, 3)
	# ...and one that has never been saved at all.
	var recovery2 := RecoveryScript.new()
	recovery2.snapshot(io, _document("neversaved"), "neversaved", "", 2)

	var entries := RecoveryScript.list(io)
	_require(entries.size() == 2, "expected two recoveries, found %d" % entries.size())

	var byName := {}
	for entry in entries:
		byName[str(entry[RecoveryScript.K_NAME])] = entry

	_require(
		RecoveryScript.statusFor(io, byName["tracked"]) == RecoveryScript.STATUS_SOURCE_UNCHANGED,
		"an untouched source was not reported as unchanged"
	)
	_require(
		RecoveryScript.statusFor(io, byName["neversaved"]) == RecoveryScript.STATUS_SOURCE_UNCHANGED,
		"a never-saved snapshot should have nothing to conflict with"
	)

	# The source moves on: the snapshot must say so rather than quietly recovering over it.
	io.fingerprints[sourcePath] = "changed"
	_require(
		RecoveryScript.statusFor(io, byName["tracked"]) == RecoveryScript.STATUS_SOURCE_NEWER,
		"a source modified since the snapshot was not reported as newer"
	)
	_require(
		RecoveryScript.describe(io, byName["tracked"]).contains("CHANGED"),
		"the recovery offer did not warn that the saved map had changed"
	)

	# The source disappears entirely.
	io.files.erase(sourcePath)
	_require(
		RecoveryScript.statusFor(io, byName["tracked"]) == RecoveryScript.STATUS_SOURCE_MISSING,
		"a missing source was not reported as missing"
	)

	# The snapshot really carries the document back.
	var restored := RecoveryScript.loadDocument(io, byName["tracked"])
	_require(restored != null, "a snapshot did not restore its document")
	if restored != null:
		_require(
			restored.size_tiles == tracked.size_tiles,
			"the restored document lost its lattice size"
		)

	# Discarding one leaves the other alone.
	_require(RecoveryScript.discard(io, byName["tracked"]), "discarding a recovery failed")
	var remaining := RecoveryScript.list(io)
	_require(remaining.size() == 1, "discarding one recovery left %d" % remaining.size())
	_require(
		str(remaining[0][RecoveryScript.K_NAME]) == "neversaved",
		"discarding removed the wrong recovery"
	)

	# A failed snapshot write reports failure rather than claiming success.
	io.failWrite = true
	_require(
		not recovery.snapshot(io, _document("x"), "x", "", 9),
		"a failed snapshot write reported success"
	)

	# The JSON record is untrusted. Its embedded name and source path may affect what is shown, but
	# they may never redirect the file that Recover/Discard reads or deletes.
	io.failWrite = false
	var listedPath := RecoveryScript.pathFor("listed")
	var outsidePath := "user://worldmap_editor/outside.json"
	io.files[outsidePath] = "outside stays"
	io.files[listedPath] = JSON.stringify({
		RecoveryScript.K_NAME: "../outside",
		RecoveryScript.K_SOURCE_PATH: "res://data/worldmap/authored/../outside.json",
		RecoveryScript.K_FINGERPRINT: "anything",
		RecoveryScript.K_REVISION: 10,
		RecoveryScript.K_SAVED_AT: 10,
		RecoveryScript.K_DOCUMENT: _document("listed").toDictionary(),
	})
	var hostileEntries := RecoveryScript.list(io)
	var listed: Dictionary = {}
	for entry in hostileEntries:
		if str(entry[RecoveryScript.K_NAME]) == "listed":
			listed = entry
	_require(not listed.is_empty(), "a valid listed snapshot disappeared because its metadata lied")
	if not listed.is_empty():
		_require(
			str(listed[RecoveryScript.K_SNAPSHOT_PATH]) == listedPath,
			"embedded metadata redirected the snapshot's runtime path"
		)
		_require(
			RecoveryScript.statusFor(io, listed) == RecoveryScript.STATUS_SOURCE_INVALID,
			"an escaping source path was inspected as if it were authored"
		)
		_require(RecoveryScript.loadDocument(io, listed) != null, "the listed snapshot did not load")
		_require(RecoveryScript.discard(io, listed), "the listed snapshot could not be discarded")
	_require(str(io.files.get(outsidePath, "")) == "outside stays", "discard escaped recovery root")

	# Expected corruption is skipped quietly. The repository runner rejects engine ERROR lines even
	# when a success marker appears, so malformed recovery is also a logging contract.
	io.files[RecoveryScript.pathFor("malformed_snapshot")] = "{ not json"
	RecoveryScript.list(io)


## Drive the controller through the same public entry points the dialogs call. This catches state
## ordering bugs that helper-only tests cannot, while injected I/O keeps authored files untouched.
func _checkControllerTransactions() -> void:
	var io := FakeIO.new()
	var controller = EditorScene.instantiate()
	controller.setDocumentIO(io)
	root.add_child(controller)
	await process_frame

	controller.requestNewDocument(Vector2i(16, 12), "first", "temp2_hex32_starter")
	_require(controller.openDocument() != null, "the controller did not create a new document")
	_require(controller.isDocumentDirty(), "a never-saved controller document reported clean")

	# Asking for another document creates the headless equivalent of the Save/Discard/Cancel
	# dialog. Save and Continue must be able to save a named New document, then run the action.
	controller.requestNewDocument(Vector2i(16, 12), "second", "temp2_hex32_starter")
	_require(controller.hasPendingDiscard(), "a replacing action bypassed the dirty guard")
	controller.savePendingAndContinue()
	_require(
		controller.openDocument() != null and controller.openDocument().region_name == "second",
		"Save and Continue did not continue from a named new document"
	)
	_require(io.sourceWrites.has(Paths.sourcePathFor("first")), "Save and Continue wrote no source")
	_require(io.bakeWrites.has(Paths.generatedPathFor("first")), "Save and Continue wrote no bake")

	# Save As is allowed to write one half, but failure may not move the live document identity.
	var beforeDocument = controller.openDocument()
	var beforePath: String = controller.documentPath()
	io.failBake = true
	controller.saveDocumentAs("renamed")
	_require(controller.openDocument() == beforeDocument, "failed Save As replaced the document")
	_require(controller.openDocument().region_name == "second", "failed Save As renamed the document")
	_require(controller.documentPath() == beforePath, "failed Save As moved the active path")
	_require(controller.isDocumentDirty(), "failed Save As marked a never-saved document clean")

	# Plain Save follows the active source path even when an old hand-edited file carries a
	# different embedded NAME. Otherwise opening expected.json and pressing Save writes surprise.json.
	io.failBake = false
	controller.saveDocument()
	var expectedPath := Paths.sourcePathFor("expected")
	io.files[expectedPath] = JSON.stringify(_document("surprise").toDictionary())
	controller.openDocumentByName("expected")
	_require(controller.documentPath() == expectedPath, "the expected source did not open")
	controller.saveDocument()
	_require(io.sourceWrites.back() == expectedPath, "plain Save followed the embedded name")
	_require(controller.openDocument().region_name == "expected", "Save did not reconcile source identity")

	# A recovered document remains protected until its replacement save succeeds. Saving it under a
	# different name removes the selected old snapshot, not another recovery and not the new source.
	var recovery := RecoveryScript.new()
	recovery.snapshot(io, _document("recover_me"), "recover_me", expectedPath, 12)
	controller.recoverEntry(0)
	_require(controller.documentPath().is_empty(), "recovered content inherited its old source path")
	_require(controller.isDocumentDirty(), "recovered content was not opened as unsaved")
	controller.saveDocumentAs("recovered_copy")
	_require(
		not io.files.has(RecoveryScript.pathFor("recover_me")),
		"saving recovered content left its stale snapshot behind"
	)
	_require(
		io.files.has(Paths.sourcePathFor("recovered_copy")),
		"saving recovered content did not create its chosen source"
	)

	controller.requestNewDocument(Vector2i(16, 12), "discarded", "temp2_hex32_starter")
	controller.writeRecoverySnapshot()
	_require(
		io.files.has(RecoveryScript.pathFor("discarded")),
		"the dirty controller document produced no recovery snapshot"
	)
	controller.requestNewDocument(Vector2i(16, 12), "after_discard", "temp2_hex32_starter")
	controller.confirmPendingDiscard()
	_require(
		not io.files.has(RecoveryScript.pathFor("discarded")),
		"explicitly discarding a document left its recovery behind"
	)
	_require(
		controller.openDocument().region_name == "after_discard",
		"the explicitly confirmed replacement did not run"
	)

	# Missing/malformed Open is loaded before any live state changes.
	io.files[Paths.sourcePathFor("malformed")] = "{ broken"
	beforeDocument = controller.openDocument()
	beforePath = controller.documentPath()
	var revisionBefore: int = controller.historyRevision()
	controller.openDocumentByName("malformed")
	_require(controller.openDocument() == beforeDocument, "malformed Open replaced the document")
	_require(controller.documentPath() == beforePath, "malformed Open moved the active path")
	_require(controller.historyRevision() == revisionBefore, "malformed Open cleared history")

	controller.queue_free()
	await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
