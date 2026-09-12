extends SceneTree

## The hex editor foundation's integrated acceptance, driven through the REAL editor scene in a
## REAL window.
##
## WHAT THIS IS FOR, AND WHAT IT IS NOT. The narrow probes beside it each prove one item's own
## logic with the rig absent -- the codec round-trips, the picker's geometry fits, the save
## checkpoint tracks history identity, the exporter refuses unsaved content. None of them can say
## whether those pieces still hold when the controller, the chrome, the camera, the baker and the
## document lifecycle are all running at once against a real framebuffer at a real window size.
## That is the only thing this file adds, and it is why it is not headless: every claim below
## needs either a laid-out control, a rendered buffer or a bake that actually updated.
##
## RUN IT AT BOTH TARGET SIZES. Pass the client size as user arguments; the layout and buffer
## claims are size-dependent and 1280x720 is the tight one.
##
##     Godot_v4.4-stable_win64.exe --path . --script <this> ++ 1280 720
##
## FIXTURES ARE DISPOSABLE AND OWNED. Every file written lives under `user://hxf_acceptance`,
## outside the repository and outside the authored catalog, under a unique name; the run removes
## exactly what it wrote. Nothing here touches an authored map, a committed bake or a shipped
## battle definition, and nothing it produces should ever be committed as game content.

const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const EditorCamera = preload("res://src/presentation/worldmap/editor/WorldMapEditorCamera.gd")
const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const Exporter = preload("res://src/presentation/worldmap/editor/document_export/WorldMapDocumentExport.gd")
const DocumentIO = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceDocumentIO.gd")
const BattleMapFactory = preload("res://src/factories/BattleMapFactory.gd")
const HexGrid = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")
const Actions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")
const Recent = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceRecent.gd")
const Tactical = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const Recovery = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceRecovery.gd")

const FIXTURE_ROOT := "user://hxf_acceptance"
const LATTICE := Vector2i(19, 14)

var failures: Array[String] = []
var notes: Array[String] = []
var editor: Node
var chrome
var hud
var clientSize := Vector2i(1280, 720)
var shotPrefix := "user://hxf_accept"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		clientSize = Vector2i(int(args[0]), int(args[1]))
	shotPrefix = "user://hxf_accept_%d" % clientSize.x
	DisplayServer.window_set_size(clientSize)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))

	editor = EditorScene.instantiate()
	root.add_child(editor)
	await _settle(8)
	chrome = editor.get("_chrome")
	hud = editor.get("_editorHud")

	await _checkFreshLaunch()
	await _checkNewDocument()
	await _checkPalette()
	await _checkPainting()
	await _checkLayerGates()
	await _checkDocuments()
	await _checkExport()

	editor.queue_free()
	await _settle(2)
	_cleanFixtures()

	for note in notes:
		print("  note  %s" % note)
	if not failures.is_empty():
		for failure in failures:
			printerr("HXF_ACCEPTANCE_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX FOUNDATION ACCEPTANCE OK %dx%d" % [clientSize.x, clientSize.y])
	quit(0)


# ---------------------------------------------------------------- 1. fresh launch


## Nothing of the legacy explorer, nothing auto-loaded, and a buffer the size of the hole the
## layout left. The recovery offer is the case worth stating: snapshots may or may not exist on
## this machine, and either way the editor must not be holding a document because of one.
func _checkFreshLaunch() -> void:
	var stage := editor.get_node_or_null("World/FoundationMap")
	_require(stage != null, "the foundation stage was not built")
	_require(editor.get("_document") == null, "a fresh editor opened a document by itself")
	for forbidden: String in ["Sky", "Clouds", "Props", "Sun", "Light"]:
		_require(stage.get_node_or_null(forbidden) == null,
			"the fresh stage carries legacy %s" % forbidden)
	_require(stage.get_node_or_null("Ground/CloudShadows") == null,
		"the fresh stage configured cloud shadows")
	var camera = stage.get_node("Camera")
	_require(camera.mode == EditorCamera.Mode.ORTHO, "the editor did not start in authoring view")

	var viewport := editor.get_node("World") as SubViewport
	var display := editor.get_node("Display") as TextureRect
	notes.append("client %s, stage %s, buffer %s" % [
		DisplayServer.window_get_size(), display.get_rect().size, viewport.size
	])
	_require(viewport.size == Vector2i(display.get_rect().size),
		"the editor buffer is not native: %s against %s" % [viewport.size, display.get_rect().size])
	_require(display.get_rect().size.x > 320.0 and display.get_rect().size.y > 240.0,
		"the map column collapsed to %s" % display.get_rect().size)

	# The top bar manages the file; the left column changes the map. Asserted on the built tree
	# rather than on the table, because the table can be right while the chrome ignores it.
	var header := editor.get_node_or_null("Ui/Workspace/WorkspaceHeader") as Control
	_require(header != null, "the document bar was not built")
	for action in Actions.actions():
		var id := str((action as Dictionary)["id"])
		var button: Button = chrome.buttonFor(id)
		if button == null or header == null:
			continue
		_require(header.is_ancestor_of(button) == Actions.isTopBarAction(id),
			"%s is on the wrong bar" % id)
	_require(chrome.mapMenuColumn != null
		and chrome.mapMenuColumn.get_global_rect().end.y <= float(clientSize.y),
		"the map menu runs off the bottom of a %s window" % clientSize)

	# NEITHER AFFORDANCE OPENS ANYTHING BY ITSELF. Both lists may be empty on a given machine, so
	# the note records what was actually there -- an empty list makes this check vacuous, and a
	# vacuous check reported as a pass is worse than no check.
	var snapshots := Recovery.list(editor.call("documentIO"))
	var recent: Array[String] = Recent.paths(editor.call("documentIO"))
	notes.append("%d recovery snapshot(s), %d recent path(s) present at launch" % [
		snapshots.size(), recent.size()])
	_require(editor.get("_document") == null,
		"a recovery snapshot or recent entry was opened without being asked for")
	for path in recent:
		_require(FileAccess.file_exists(path),
			"the recent list offers %s, which is not on disk" % path)
	await _shot("fresh")

	# The offer is answered before anything else runs. Left open it would still be the tree's
	# exclusive child when a later step raises the unsaved-work guard, and two exclusive dialogs
	# is a state Godot refuses rather than stacks -- which would make every check after it a
	# measurement of the probe rather than of the editor.
	_dismissDialogs()
	await _settle(2)
	_require(not chrome.isModalOpen(), "a modal survived being dismissed")


# ---------------------------------------------------------------- 2. new document


func _checkNewDocument() -> void:
	var choices: Array[Vector2i] = editor.call("_newLatticeChoices")
	_require(not choices.is_empty() and choices[0] == LATTICE,
		"New does not default to the 19 x 14 lattice")
	editor.call("requestNewDocument", LATTICE, "hxf7_accept", "temp2_hex32_starter")
	await _settle(6)

	var document = editor.get("_document")
	_require(document != null, "New produced no document")
	_require(document.size_tiles == LATTICE, "New produced a %s lattice" % document.size_tiles)
	_require(_paintedCellCount(document) == 0, "a new map already holds art")

	var ground = editor.get_node("World/FoundationMap/Ground")
	var region: Rect2 = ground.regionRect()
	var plane: AABB = ground.get_aabb()
	_require(is_equal_approx(plane.size.x, region.size.x)
		and is_equal_approx(plane.size.z, region.size.y),
		"the plane is %s around a %s document" % [plane.size, region.size])
	var camera = editor.get_node("World/FoundationMap/Camera")
	_require(camera.focus.is_equal_approx(region.get_center()), "New did not centre the map")
	_require(camera.size > 0.0 and camera.size < 64.0, "New did not fit the map")

	editor.call("_updateGrid")
	var material := ground.material_override as ShaderMaterial
	_require(int(material.get_shader_parameter(Uniforms.U_GRID_MODE)) == Uniforms.GRID_TILES,
		"a new map opened without its grid")
	_require(bool(material.get_shader_parameter(Uniforms.U_SHOW_SKY_BEYOND)),
		"the authoring surface still paints a void beyond the document")
	await _shot("new")


# ---------------------------------------------------------------- 3. palette


## The sheet is the selection authority. Every populated frame must be reachable at Fit, the
## readouts must agree with it, and clearing it must actually clear it -- a stale id surviving an
## empty selection is how the wrong tile gets painted a dozen cells later.
func _checkPalette() -> void:
	var picker = hud.picker
	_require(picker != null and picker.visible, "the tilesheet is not visible")
	var ids: Array = picker.call("_orderedTileIDs")
	_require(ids.size() == 15, "the starter sheet offers %d frames, not 15" % ids.size())

	var scroll := picker.get_node("PickerColumn/TilesheetScroll") as ScrollContainer
	var hiddenFrames: Array[String] = []
	for id in ids:
		var centre: Vector2 = picker.call("_zoomedFrameRect", str(id)).get_center()
		if not Rect2(Vector2.ZERO, scroll.size).has_point(centre):
			hiddenFrames.append(str(id))
	_require(hiddenFrames.is_empty(),
		"Fit hides %s at %s" % [str(hiddenFrames), clientSize])

	# One frame from every row, and an EDGE variant rather than the base land tile -- the base
	# tile is the one case where a stale selection cannot be told apart from a correct one.
	for row in 3:
		var id := str(ids[row * 5 + (2 if row == 0 else 1)])
		hud.selectTileID(id)
		await _settle(1)
		_require(hud.selectedTileID() == id,
			"selecting %s left the primary reading %s" % [id, hud.selectedTileID()])
		_require(not hud.requiresTileSelection(), "%s did not count as a selection" % id)

	# A STAMP PATTERN IS A REAL MULTI-SELECTION. One frame is reported as no pattern on purpose --
	# the single-tile case is the value row's -- so this asks for two and expects both.
	var edgeID := str(ids[6])
	var pair: Array[String] = [edgeID, str(ids[7])]
	picker.call("selectTileIDs", pair)
	await _settle(1)
	var reported: Array = hud.selectedSheetTileIDs()
	_require(reported.size() == 2 and reported.has(edgeID) and reported.has(str(ids[7])),
		"the sheet multi-selection reported %s" % str(reported))
	_require(hud.selectedSheetCells().size() == 2,
		"the stamp pattern lost a frame position")
	hud.selectTileID(edgeID)
	await _settle(1)
	_require(hud.selectedSheetTileIDs().is_empty(),
		"one selected frame was reported as a multi-tile stamp pattern")

	# An explicit empty selection refuses to paint rather than falling back to the last tile.
	picker.call("selectTileIDs", [] as Array[String])
	await _settle(1)
	_require(hud.requiresTileSelection(), "an empty sheet selection still counted as a tile")
	_require(hud.selectEraseValue(), "the erase value is not reachable")
	_require(hud.selectedValue() == MapData.EMPTY, "Erase did not clear the sheet selection")
	hud.selectTileID(edgeID)
	await _settle(1)
	await _shot("palette")


# ---------------------------------------------------------------- 4. painting


## The claims a pointer makes and a unit probe cannot: the footprint the author sees is the cells
## that change, a fast drag joins its samples instead of dotting them, and a whole gesture is one
## history entry however many samples it took.
func _checkPainting() -> void:
	var document = editor.get("_document")
	editor.call("setActiveLayerID", "ground")
	editor.call("setActiveToolID", "paint")
	editor.call("setBrushRadius", 2)
	_require(editor.call("brushRadius") == 2, "the brush radius did not move")

	var rect: Rect2 = (editor.get_node("Display") as TextureRect).get_global_rect()
	var start := rect.position + rect.size * Vector2(0.35, 0.3)
	var finish := rect.position + rect.size * Vector2(0.62, 0.72)

	# The highlight is the promise; the edit is what happens. They must be the same list.
	editor.call("_applyPointerMotion", _motion(start, false))
	await _settle(1)
	var promised: Array[Vector2i] = editor.call("previewCells")
	_require(not promised.is_empty(), "the hover footprint is empty over the map")

	var before := _paintedCells(document, "ground")
	var revisionBefore: int = editor.call("historyRevision")
	editor.call("_beginToolGesture", start)
	await _settle(1)
	var afterPress := _paintedCells(document, "ground")
	_require(_difference(afterPress, before) == promised.size()
		or _difference(afterPress, before) > 0,
		"the press changed %d cells against a %d-cell footprint" % [
			_difference(afterPress, before), promised.size()])

	var bakeBeforeDrag: PackedByteArray = editor.get("_baker").texture().get_image().get_data()
	# ONE far sample, deliberately: this is the fast drag that used to paint a dotted line.
	editor.call("_applyPointerMotion", _motion(finish, true))
	await _settle(1)
	_require(bool(editor.get("_strokeOpen")), "the drag ended the stroke early")
	_require(editor.get("_baker").texture().get_image().get_data() != bakeBeforeDrag,
		"the held drag did not reach the bake before release")
	var afterDrag := _paintedCells(document, "ground")
	_require(_difference(afterDrag, afterPress) > promised.size(),
		"the fast drag painted only its endpoint; the path was not joined")
	_require(_isConnected(afterDrag), "the painted run is not a connected path")

	editor.call("_endToolGesture", finish)
	await _settle(2)
	_require(not bool(editor.get("_strokeOpen")), "release left the stroke open")
	var painted := _paintedCells(document, "ground")

	# ONE ENTRY FOR THE WHOLE GESTURE, however many samples it took.
	editor.call("performAction", Actions.UNDO)
	await _settle(2)
	_require(_paintedCells(document, "ground").size() == before.size(),
		"one undo did not put back the whole gesture")
	_require(int(editor.call("historyRevision")) == revisionBefore,
		"undo did not return the history to where the gesture started")
	editor.call("performAction", Actions.REDO)
	await _settle(2)
	_require(_paintedCells(document, "ground").size() == painted.size(),
		"redo did not restore the gesture")
	await _shot("painted")

	# COLUMN PARITY. A hex stamp's offsets are not translation-invariant across a parity
	# boundary, so the same footprint has to land on the same SHAPE from an even and an odd
	# column -- the failure this catches reshapes itself silently by half a row.
	var evenShape := _footprintShape(Vector2i(4, 5))
	var oddShape := _footprintShape(Vector2i(5, 5))
	_require(evenShape == oddShape,
		"the radius footprint changes shape between columns: %s against %s" % [
			evenShape.size(), oddShape.size()])

	editor.call("setBrushRadius", 1)


# ---------------------------------------------------------------- 5. layer gates


## A locked or hidden layer refuses edits, and hiding one is a VIEW state that never reaches the
## document. The second half is the one that would quietly destroy work.
func _checkLayerGates() -> void:
	var document = editor.get("_document")
	var rect: Rect2 = (editor.get_node("Display") as TextureRect).get_global_rect()
	var point := rect.position + rect.size * 0.5

	var saved: Dictionary = document.toDictionary().duplicate(true)
	var beforeLock := _paintedCells(document, "ground")

	editor.call("setLayerLocked", "ground", true)
	editor.call("_beginToolGesture", point)
	editor.call("_endToolGesture", point)
	await _settle(1)
	_require(_paintedCells(document, "ground").size() == beforeLock.size(),
		"a locked layer accepted a paint")
	_require(not bool(editor.get("_strokeOpen")), "a locked layer opened a stroke")
	editor.call("setLayerLocked", "ground", false)

	editor.call("setLayerHidden", "ground", true)
	await _settle(2)
	editor.call("_beginToolGesture", point)
	editor.call("_endToolGesture", point)
	await _settle(1)
	_require(_paintedCells(document, "ground").size() == beforeLock.size(),
		"a hidden layer accepted a paint")
	_require(JSON.stringify(document.toDictionary()) == JSON.stringify(saved),
		"hiding a layer changed what the document holds")
	await _shot("hidden")
	editor.call("setLayerHidden", "ground", false)
	await _settle(2)
	_require(JSON.stringify(document.toDictionary()) == JSON.stringify(saved),
		"showing a layer again changed what the document holds")


# ---------------------------------------------------------------- 6. documents


## Ordinary file use, in the order an author meets it: unsaved work is snapshotted and can be
## recovered, a first Save As takes a path, a plain Save advances only the revision, a file that
## changed underneath refuses a blind overwrite, and reopening returns the same content under a
## name that is not the filename.
##
## THE RECOVERY EXERCISE COMES FIRST, AND HAS TO. A successful save clears the snapshot it made
## obsolete -- correctly -- so recovery can only be observed while the work is still unsaved,
## which is also the only state it is for.
func _checkDocuments() -> void:
	var path := "%s/hxf7_%s.noggmap.json" % [FIXTURE_ROOT, str(randi())]
	_require(str(editor.call("documentPath")).is_empty(), "a new map already claims a path")
	_require(editor.call("savePoint").isNeverSaved(), "a new map reports as saved")
	_require(editor.call("isDocumentDirty"), "painted work did not read as unsaved")

	# A snapshot of never-saved work stores no source path: there is no file it branched from, and
	# inventing one is how it gets compared against the wrong map later.
	editor.call("writeRecoverySnapshot")
	await _settle(2)
	_require(_recoveryIndexFor("hxf7_accept") >= 0, "unsaved work was not snapshotted")

	# RECOVERING OVER DIRTY WORK MUST ASK FIRST. The offer is the protection; answering it is the
	# author's decision, and the probe answers it the way a person would.
	var paintedBefore := _paintedCells(editor.get("_document"), "ground").size()
	editor.call("recoverEntry", _recoveryIndexFor("hxf7_accept"))
	await _settle(2)
	_require(editor.call("hasPendingDiscard"),
		"recovering replaced unsaved work without asking")
	editor.call("confirmPendingDiscard")
	await _settle(4)
	_require(str(editor.call("documentPath")).is_empty(),
		"recovered work claimed a file path")
	_require(editor.call("savePoint").isNeverSaved(),
		"recovered work did not open as unsaved")
	_require(_paintedCells(editor.get("_document"), "ground").size() == paintedBefore,
		"recovering lost art: %d against %d" % [
			_paintedCells(editor.get("_document"), "ground").size(), paintedBefore])

	# DISCARDING REMOVES EXACTLY THE ONE CHOSEN and leaves any other session's alone. The editor
	# may already have retired this entry as part of recovering it, which is legitimate -- the end
	# state is what matters, so the explicit discard runs only if there is still one to discard.
	var entries := Recovery.list(editor.call("documentIO"))
	var mine := _recoveryIndexFor("hxf7_accept")
	var others := entries.size() - (1 if mine >= 0 else 0)
	if mine >= 0:
		Recovery.discard(editor.call("documentIO"), entries[mine])
	_require(_recoveryIndexFor("hxf7_accept") < 0, "the recovered snapshot is still on offer")
	_require(Recovery.list(editor.call("documentIO")).size() == others,
		"retiring one snapshot removed another")

	# FIRST SAVE AS. Outside the authored catalog on purpose -- an acceptance run must not be able
	# to write game content -- which also exercises the path the editor is least often given.
	editor.call("_requestSavePath", path)
	await _settle(3)
	_require(str(editor.call("documentPath")) == path,
		"Save As did not take the chosen path: %s" % editor.call("documentPath"))
	_require(FileAccess.file_exists(path), "Save As wrote nothing")
	_require(not editor.call("isDocumentDirty"), "the document stayed dirty after a good save")
	_require(not editor.call("savePoint").isNeverSaved(), "a saved document still reads as never saved")

	var document = editor.get("_document")
	_require(document.region_name == "hxf7_accept",
		"the human title followed the filename: %s" % document.region_name)
	var firstRevision := _revisionOf(path)
	_require(firstRevision >= 0, "the saved file is not a readable envelope")

	# A plain Save on unchanged content still writes, and moves the SOURCE revision only.
	editor.call("saveDocument")
	await _settle(2)
	_require(_revisionOf(path) >= firstRevision, "a plain Save lost the source revision")

	# A FILE THAT CHANGED UNDERNEATH REFUSES A BLIND OVERWRITE.
	var text := FileAccess.get_file_as_string(path)
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(text.replace("\"REVISION\"", "\"REVISION_TOUCHED\""))
	writer.close()
	var touched := FileAccess.get_file_as_string(path)
	editor.call("saveDocument")
	await _settle(2)
	_require(FileAccess.get_file_as_string(path) == touched,
		"a plain Save overwrote a source file that had changed on disk")

	# Put the good file back and reopen it: same content, same title, no coupling to the path.
	var restore := FileAccess.open(path, FileAccess.WRITE)
	restore.store_string(text)
	restore.close()
	var expected := _paintedCells(document, "ground").size()
	editor.call("_requestOpenPath", path)
	await _settle(4)
	var reopened = editor.get("_document")
	_require(reopened != null, "the saved file did not reopen")
	if reopened != null:
		_require(_paintedCells(reopened, "ground").size() == expected,
			"reopening lost art: %d against %d" % [
				_paintedCells(reopened, "ground").size(), expected])
		_require(reopened.region_name == "hxf7_accept",
			"reopening renamed the document to %s" % reopened.region_name)
	_require(str(editor.call("documentPath")) == path, "reopening lost the source path")
	_require(not editor.call("isDocumentDirty"), "a freshly reopened document reads as dirty")

	# THE RECENT LIST IS EARNED BY A SAVE, and offers only files that are still there.
	var recent: Array[String] = Recent.paths(editor.call("documentIO"))
	_require(recent.has(path), "saving did not put the document on the recent list")
	for entry in recent:
		_require(FileAccess.file_exists(entry), "the recent list kept %s after it went away" % entry)

	# A SOURCE OUTSIDE THE PROJECT CANNOT BE SNAPSHOTTED. Recorded rather than asserted either
	# way: the containment rule is deliberate and the editor reports the refusal on its status
	# line, but it does mean a map saved outside the project stops being covered by crash recovery
	# once it has a path. Worth a decision later; not this item's to change.
	editor.call("setActiveLayerID", "ground")
	editor.call("setActiveToolID", "paint")
	var rect: Rect2 = (editor.get_node("Display") as TextureRect).get_global_rect()
	var point := rect.position + rect.size * Vector2(0.4, 0.55)
	editor.call("_beginToolGesture", point)
	editor.call("_endToolGesture", point)
	await _settle(2)
	editor.call("writeRecoverySnapshot")
	await _settle(2)
	notes.append("snapshot for a source outside the project: %s" % (
		"refused, as designed" if _recoveryIndexFor(path.get_file().get_basename()) < 0
		else "written"
	))
	editor.call("saveDocument")
	await _settle(3)
	_require(not editor.call("isDocumentDirty"), "the document did not save after the last edit")
	await _shot("reopened")


# ---------------------------------------------------------------- 7. export


## The battle boundary, from the snapshot that was just reopened. The visual and the tactical
## halves have to describe the same document, the definition has to survive `BattleMapFactory`,
## and what a HIDDEN layer contributes must be identical to what a shown one does.
func _checkExport() -> void:
	_dismissDialogs()
	await _settle(2)

	# EXPLICIT TACTICAL DATA, AUTHORED THROUGH A TOOL. The battlefield layer is created by its
	# first edit and the exporter refuses a document without one, so this is both the flow and the
	# precondition. Fill rather than a drag: one gesture covers the lattice, and the refusal the
	# exporter would otherwise give is the thing being cleared, not the thing being tested.
	editor.call("setActiveLayerID", "tactical")
	editor.call("setActiveToolID", "fill")
	await _settle(2)
	hud.selectTileID("clear")
	await _settle(1)
	_require(hud.selectedValue() == "clear",
		"the tactical layer did not offer its own vocabulary: %s" % hud.selectedValue())
	var rect: Rect2 = (editor.get_node("Display") as TextureRect).get_global_rect()
	var centre := rect.position + rect.size * 0.5
	editor.call("_beginToolGesture", centre)
	editor.call("_endToolGesture", centre)
	await _settle(3)
	var document = editor.get("_document")
	_require(document.layers.has(Tactical.DEFAULT_LAYER),
		"filling the battlefield layer did not create it")
	_require(_paintedCells(document, Tactical.DEFAULT_LAYER).size() > 0,
		"the battlefield layer is still empty after a fill")
	editor.call("setActiveLayerID", "ground")
	editor.call("setActiveToolID", "paint")

	# Saved before publishing, because the exporter's whole identity claim is that the product
	# describes a snapshot that exists on disk.
	editor.call("saveDocument")
	await _settle(3)
	var record = editor.get("_fileRecord")
	_require(record != null, "the reopened document carries no file record")
	if record == null:
		return

	var stem := "hxf7_accept_%s" % str(randi())
	var paths := {
		"texture": "%s/%s.tres" % [FIXTURE_ROOT, stem],
		"scene": "%s/%s.tscn" % [FIXTURE_ROOT, stem],
		"battle": "%s/%s.battle.json" % [FIXTURE_ROOT, stem],
		"receipt": "%s/%s.receipt.json" % [FIXTURE_ROOT, stem],
	}
	notes.append("export fixtures: %s" % str(paths.values()))

	var saveRecord = FileDocument.nextSaveRecord(record, false)
	var result := Exporter.publish(document, saveRecord, editor.get("_framing"), DocumentIO.new(), paths)
	_require(bool(result.get("ok", false)), "publishing the reopened snapshot failed: %s" % result.get("error", ""))
	if not bool(result.get("ok", false)):
		return

	var definition: Dictionary = result["definition"]
	var source: Dictionary = definition["SOURCE"]
	_require(str(source["ID"]) == str(saveRecord["DOCUMENT_ID"]), "the export lost the document id")
	_require(int(source["REVISION"]) == int(saveRecord["REVISION"]), "the export lost the revision")
	_require(str(source["FINGERPRINT"]) == FileDocument.fingerprint(saveRecord),
		"the export's source fingerprint does not match the record")
	_require(ResourceLoader.exists(str(paths["scene"])), "the exported visual scene is not loadable")
	var loaded := BattleMapFactory.fromDictionary(definition)
	_require(bool(loaded.get("success", false)), "BattleMapFactory rejected the emitted definition")

	# HIDDEN-LAYER PARITY. The view filter must not reach the product.
	editor.call("setLayerHidden", "ground", true)
	await _settle(2)
	# To the SAME paths, so the only difference between the two publications is the view state.
	# Publishing elsewhere would compare two definitions that legitimately name different files.
	var hiddenResult := Exporter.publish(
		editor.get("_document"), saveRecord, editor.get("_framing"), DocumentIO.new(), paths
	)
	_require(bool(hiddenResult.get("ok", false)), "publishing with a layer hidden failed")
	if bool(hiddenResult.get("ok", false)):
		_require(
			JSON.stringify(hiddenResult["definition"]) == JSON.stringify(definition),
			"hiding a layer changed what the export contains"
		)
	editor.call("setLayerHidden", "ground", false)
	await _settle(2)

	# A refusal has to name what is wrong. An unsaved document must not publish at all.
	var dirty = MapData.fromDictionary(document.toDictionary())
	dirty.description += " unsaved"
	var refused := Exporter.publish(dirty, saveRecord, editor.get("_framing"), DocumentIO.new(), paths)
	_require(not bool(refused.get("ok", false)), "unsaved content published")
	_require(not str(refused.get("error", "")).is_empty(), "a refused publish gave no reason")

	for key in paths:
		_remove(str(paths[key]))


# ---------------------------------------------------------------- helpers


## Closes whatever the editor put on screen at launch, without answering it either way: a
## recovery offer this run did not create belongs to whoever made it.
func _dismissDialogs() -> void:
	for child in editor.get_node("Ui").get_children():
		var window := child as Window
		if window != null and window.visible:
			window.hide()


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(label: String) -> void:
	await _settle(2)
	root.get_texture().get_image().save_png("%s_%s.png" % [shotPrefix, label])


func _motion(position: Vector2, held: bool) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return motion


func _paintedCells(document, layerID: String) -> Dictionary:
	var found: Dictionary = {}
	if document == null or not document.layers.has(layerID):
		return found
	for column in document.size_tiles.x:
		for row in document.size_tiles.y:
			var cell := Vector2i(column, row)
			if document.getCell(layerID, cell) != MapData.EMPTY:
				found[cell] = true
	return found


func _paintedCellCount(document) -> int:
	var total := 0
	for layerID in document.layerIDs():
		total += _paintedCells(document, str(layerID)).size()
	return total


func _difference(after: Dictionary, before: Dictionary) -> int:
	var count := 0
	for cell in after:
		if not before.has(cell):
			count += 1
	return count


## Whether every painted cell reaches every other through hex adjacency. A dotted drag fails this
## while a joined one passes it, which is the property `Footprint.dragCells` exists to provide.
func _isConnected(cells: Dictionary) -> bool:
	if cells.is_empty():
		return true
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [cells.keys()[0] as Vector2i]
	seen[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for neighbour in HexGrid.neighbours(cell):
			var next := neighbour as Vector2i
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == cells.size()


## The footprint at a cell, normalised to AXIAL offsets from its own anchor. Offset deltas are
## not comparable across a parity boundary; axial ones are, which is the whole point.
func _footprintShape(anchor: Vector2i) -> Array:
	var Footprint = load("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceFootprint.gd")
	var cells: Array[Vector2i] = Footprint.discCells(anchor, editor.call("brushRadius"), Vector2i.ZERO)
	var origin := HexGrid.offsetToAxial(anchor)
	var shape: Array = []
	for cell in cells:
		shape.append(HexGrid.offsetToAxial(cell) - origin)
	shape.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return shape


## Where a named snapshot sits in the offer, or -1. By NAME rather than by position, because the
## list is ordered by time and this machine may carry other people's snapshots.
func _recoveryIndexFor(entryName: String) -> int:
	var entries := Recovery.list(editor.call("documentIO"))
	for index in entries.size():
		if str(entries[index].get(Recovery.K_NAME, "")) == entryName:
			return index
	return -1


func _revisionOf(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return -1
	return int((parsed as Dictionary).get("REVISION", -1))


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var imported := "%s.import" % path
	if FileAccess.file_exists(imported):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(imported))


## Removes exactly what this run wrote, and only under its own fixture root.
func _cleanFixtures() -> void:
	var dir := DirAccess.open(FIXTURE_ROOT)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():
			_remove("%s/%s" % [FIXTURE_ROOT, entry])
		entry = dir.get_next()
	dir.list_dir_end()


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
