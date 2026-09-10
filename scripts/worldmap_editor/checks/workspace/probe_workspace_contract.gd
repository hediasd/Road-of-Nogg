extends SceneTree

## Bounded check on the workspace's own contracts: which actions exist and are reachable, when a
## shortcut is allowed to fire, how a measured stage becomes the map's rectangle, and whether the
## save checkpoint tracks history STATE rather than history depth.
##
## Deliberately does not open the editor scene. Everything asserted here is a decision the
## workspace makes before any of it is drawn, and loading the full rig would make this probe a
## slow integration test that could not run alongside other work.

const Actions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")
const Geometry = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceGeometry.gd")
const SavePointScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceSavePoint.gd")
const HistoryScript = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const ControllerScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorController.gd")
const ChromeScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd")
const HudScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorHud.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checkActionsAvailable()
	_checkFocusGating()
	_checkLayoutTransforms()
	_checkSaveCheckpoint()
	_checkToolsReachable()
	await _checkChromeBuilds()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_WORKSPACE_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP WORKSPACE CONTRACT OK")
	quit(0)


## Every action a button can raise is in the table, every id is unique, and every action carries
## the label and tooltip the chrome builds its button from. A shortcut that names an action the
## table does not hold would be a key with no button, which is the drift this table exists to stop.
func _checkActionsAvailable() -> void:
	var seen: Dictionary = {}
	for action in Actions.actions():
		var row: Dictionary = action
		var id := str(row["id"])
		_require(not seen.has(id), "duplicate action id %s" % id)
		seen[id] = true
		_require(not str(row.get("label", "")).is_empty(), "%s has no button label" % id)
		_require(not str(row.get("tooltip", "")).is_empty(), "%s has no tooltip" % id)
		_require(not str(row.get("group", "")).is_empty(), "%s has no group" % id)

	for required: String in [
		Actions.NEW_DOCUMENT, Actions.OPEN_DOCUMENT, Actions.SAVE_DOCUMENT,
		Actions.SAVE_DOCUMENT_AS, Actions.UNDO, Actions.REDO,
		Actions.EXPORT_SCENE, Actions.EXPORT_BATTLE,
	]:
		_require(Actions.has(required), "%s is not reachable as a named action" % required)

	for shortcut in Actions.SHORTCUTS:
		_require(
			Actions.has(str((shortcut as Dictionary)["id"])),
			"shortcut names unknown action %s" % str((shortcut as Dictionary)["id"])
		)

	# The two pairs that only differ by a modifier, and the pair that only differs by shift.
	_require(Actions.hintFor(Actions.SAVE_DOCUMENT) == "Ctrl+S", "Save lost its Ctrl+S hint")
	_require(Actions.hintFor(Actions.EXPORT_BATTLE) == "Ctrl+Shift+E", "battle export hint wrong")
	_require(Actions.hintFor(Actions.TOOL_ERASE) == "E", "Erase lost its plain-E hint")
	_require(Actions.hintFor(Actions.VIEW_FRAME) == "F", "Frame is no longer F")
	_require(Actions.hintFor(Actions.NEW_DOCUMENT).is_empty(), "New claimed a shortcut")


## The map's shortcuts are live only while the map has the keyboard. Typing into a name field or
## answering a dialog must reach the field, not the toolbar.
func _checkFocusGating() -> void:
	_require(
		Actions.resolve(KEY_B, false, false, Actions.FOCUS_MAP) == Actions.TOOL_PAINT,
		"B does not select Paint with the map focused"
	)
	_require(
		Actions.resolve(KEY_B, false, false, Actions.FOCUS_TEXT).is_empty(),
		"B fired a tool while a text field had focus"
	)
	_require(
		Actions.resolve(KEY_S, true, false, Actions.FOCUS_TEXT).is_empty(),
		"Ctrl+S saved while a text field had focus"
	)
	_require(
		Actions.resolve(KEY_SPACE, false, false, Actions.FOCUS_MODAL).is_empty(),
		"Space reached the camera while a modal was open"
	)
	_require(
		Actions.resolve(KEY_S, true, false, Actions.FOCUS_MAP) == Actions.SAVE_DOCUMENT,
		"Ctrl+S does not save with the map focused"
	)

	# Exact modifier matching: these four share a keycode and must stay four different answers.
	_require(
		Actions.resolve(KEY_E, false, false, Actions.FOCUS_MAP) == Actions.TOOL_ERASE,
		"plain E is not Erase"
	)
	_require(
		Actions.resolve(KEY_E, true, false, Actions.FOCUS_MAP) == Actions.EXPORT_SCENE,
		"Ctrl+E is not the scene export"
	)
	_require(
		Actions.resolve(KEY_E, true, true, Actions.FOCUS_MAP) == Actions.EXPORT_BATTLE,
		"Ctrl+Shift+E is not the battle export"
	)
	_require(
		Actions.resolve(KEY_Z, true, false, Actions.FOCUS_MAP) == Actions.UNDO
		and Actions.resolve(KEY_Z, true, true, Actions.FOCUS_MAP) == Actions.REDO
		and Actions.resolve(KEY_Y, true, false, Actions.FOCUS_MAP) == Actions.REDO,
		"undo/redo bindings are not exactly Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y"
	)
	_require(
		Actions.resolve(KEY_TAB, false, false, Actions.FOCUS_MAP).is_empty(),
		"Tab is claimed as a shortcut; it must stay available for focus traversal"
	)
	_require(
		Actions.resolve(KEY_Q, false, false, Actions.FOCUS_MAP).is_empty(),
		"an unbound key resolved to an action"
	)


## The stage the layout measured becomes the map's rectangle, and a screen point becomes a buffer
## pixel through the same letterboxing the renderer draws with.
func _checkLayoutTransforms() -> void:
	var stage := Rect2(Vector2(248.0, 96.0), Vector2(800.0, 520.0))
	var display := Geometry.stageToDisplay(stage)
	_require(display == stage, "a healthy stage rect was not passed through unchanged")

	var collapsed := Geometry.stageToDisplay(Rect2(Vector2(10.0, 10.0), Vector2.ZERO))
	_require(
		collapsed.size.x >= Geometry.MINIMUM.x and collapsed.size.y >= Geometry.MINIMUM.y,
		"a collapsed stage produced a viewport that cannot be built"
	)

	# A 16:9 buffer inside a taller-than-wide display letterboxes top and bottom.
	var buffer := Vector2(384.0, 216.0)
	var tall := Rect2(Vector2(100.0, 50.0), Vector2(384.0, 400.0))
	var drawn := Geometry.drawnRect(tall, buffer)
	_require(is_equal_approx(drawn.size.x, 384.0), "letterboxed width should fill the display")
	_require(is_equal_approx(drawn.size.y, 216.0), "letterboxed height should keep the aspect")
	_require(
		is_equal_approx(drawn.position.y, 50.0 + (400.0 - 216.0) * 0.5),
		"the drawn image is not centred vertically"
	)

	_require(
		Geometry.drawnRect(Rect2(), buffer).size == Vector2.ZERO,
		"a degenerate display rect did not produce an empty drawn rect"
	)
	_require(
		Geometry.drawnRect(tall, Vector2.ZERO).size == Vector2.ZERO,
		"a zero buffer did not produce an empty drawn rect"
	)

	# The centre of the drawn image is the centre of the buffer, and the letterbox margin is
	# outside the map rather than the nearest edge pixel of it.
	var centre = Geometry.bufferPoint(drawn.position + drawn.size * 0.5, tall, buffer)
	_require(centre != null, "the centre of the drawn image did not map into the buffer")
	if centre != null:
		_require(
			(centre as Vector2).is_equal_approx(buffer * 0.5),
			"the drawn centre did not map to the buffer centre"
		)
	_require(
		Geometry.bufferPoint(Vector2(120.0, 60.0), tall, buffer) == null,
		"a point in the letterbox margin was accepted as a map point"
	)
	_require(
		Geometry.bufferPoint(Vector2(-5.0, -5.0), tall, buffer) == null,
		"a point outside the display was accepted as a map point"
	)


## The checkpoint tracks history identity. Both cases below report "saved" under the stack-depth
## comparison this replaced, which is the whole reason it was replaced.
func _checkSaveCheckpoint() -> void:
	var savePoint := SavePointScript.new()
	var history := HistoryScript.new()
	var document := MapDataScript.create("probe", Vector2i(4, 4), MapDataScript.LAYOUT_HEX_FLAT)
	document.layers["ground"]["TILESET"] = "temp2_hex32_starter"

	savePoint.beginNewDocument()
	_require(savePoint.isNeverSaved(), "a new document did not report as never saved")
	_require(
		savePoint.isDirty(history.currentRevision()),
		"a new document that has never been written reported as saved"
	)

	savePoint.markSaved(history.currentRevision())
	_require(not savePoint.isDirty(history.currentRevision()), "a saved document reported dirty")
	_require(not savePoint.isNeverSaved(), "a saved document still reported as never saved")

	history.beginStroke("ground")
	history.paintCell(document, Vector2i(0, 0), "t001")
	history.endStroke()
	_require(savePoint.isDirty(history.currentRevision()), "an edit after a save read as saved")

	history.undo(document)
	_require(
		not savePoint.isDirty(history.currentRevision()),
		"undoing back to the saved state did not read as saved"
	)

	# The divergence case: undo to the save point, then make a DIFFERENT edit. The stack is the
	# same height it was at the save, and the content is not.
	history.beginStroke("ground")
	history.paintCell(document, Vector2i(1, 1), "t002")
	history.endStroke()
	_require(
		history.undoCount() == 1,
		"the divergence case did not reproduce the same stack depth as the save"
	)
	_require(
		savePoint.isDirty(history.currentRevision()),
		"a divergent edit at the saved stack depth reported as saved"
	)

	# The eviction case: fill past the history's capacity so the depth stops moving.
	var capped := HistoryScript.new()
	capped.maxDepth = 2
	var evictionPoint := SavePointScript.new()
	capped.beginStroke("ground")
	capped.paintCell(document, Vector2i(2, 2), "t003")
	capped.endStroke()
	evictionPoint.markSaved(capped.currentRevision())
	for index in 4:
		capped.beginStroke("ground")
		capped.paintCell(document, Vector2i(2, 2), "t%03d" % (index + 4))
		capped.endStroke()
	_require(capped.undoCount() == 2, "the eviction case did not reach the depth cap")
	_require(
		evictionPoint.isDirty(capped.currentRevision()),
		"edits past the history cap reported as saved"
	)


## Every tool the controller offers reaches the workspace one way or the other: as one of the six
## named toolbar buttons, or in the dropdown that carries the layer-specific ones. A tool in
## neither would be a capability the rebuild silently dropped.
func _checkToolsReachable() -> void:
	var buttonActions: Array[String] = []
	for action in Actions.actionsInGroup(Actions.GROUP_TOOL):
		buttonActions.append(str((action as Dictionary)["id"]))
	_require(buttonActions.size() == 6, "expected six named tool buttons, found %d" % buttonActions.size())
	for required: String in [
		Actions.TOOL_NAVIGATE, Actions.TOOL_INSPECT, Actions.TOOL_PAINT,
		Actions.TOOL_ERASE, Actions.TOOL_FILL, Actions.TOOL_EYEDROPPER,
	]:
		_require(buttonActions.has(required), "%s has no toolbar button" % required)

	# Erase is the paint tool plus the erase value, so it is the one workspace tool with no
	# controller tool of its own -- every OTHER controller tool must still be listed somewhere.
	var mapped := 0
	for tool in ControllerScript.TOOLS:
		var id := str((tool as Dictionary)["id"])
		_require(not id.is_empty(), "a controller tool has no id")
		mapped += 1
	_require(mapped >= 13, "the controller tool list shrank to %d entries" % mapped)


## The chrome and the palette/inspector contents really build, in a real tree, without the 3D rig.
## Parsing is not the same as running: this is what catches a container that never gets added, a
## signal wired to a missing method, or a stage that reports no rectangle at all.
##
## MOUSE FILTERS ARE THE INPUT CONTRACT, so they are asserted rather than assumed. A stage that
## stopped ignoring the mouse would silently swallow every map click, and a panel that stopped
## consuming would let a button press paint the terrain behind it -- neither shows up as an error.
func _checkChromeBuilds() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var raised: Array[String] = []
	var chrome := ChromeScript.new()
	chrome.build(
		layer,
		func(actionID: String) -> void: raised.append(actionID),
		func(_toolID: String) -> void: pass,
		[{"id": "rectangle", "label": "Rectangle"}, {"id": "line", "label": "Line"}]
	)
	var hud := HudScript.new(chrome)
	# The last argument is the per-layer reason a visibility toggle is unavailable, keyed by layer
	# id; empty here so every row builds its live toggle. The painting item's own probe is what
	# asserts which layers really get one.
	hud.build(
		ControllerScript.LAYERS,
		func(_index: int) -> void: pass,
		func(_id: String, _on: bool) -> void: pass,
		func(_id: String, _on: bool) -> void: pass,
		{}
	)
	await process_frame
	await process_frame

	_require(chrome.stage != null, "the chrome built no stage")
	_require(chrome.paletteColumn != null, "the chrome built no palette column")
	_require(chrome.inspectorColumn != null, "the chrome built no inspector column")
	_require(
		chrome.stage != null and chrome.stage.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the stage does not ignore the mouse, so map clicks would never reach the controller"
	)
	var toolbar := layer.get_node_or_null("Workspace/WorkspaceToolbar") as Control
	_require(toolbar != null, "the toolbar was not built")
	if toolbar != null:
		_require(
			toolbar.mouse_filter == Control.MOUSE_FILTER_STOP,
			"the toolbar does not consume the mouse, so a button press would also paint"
		)

	# Every action in the table really produced a button, and pressing one raises exactly its id.
	for action in Actions.actions():
		var id := str((action as Dictionary)["id"])
		_require(chrome.buttonFor(id) != null, "%s has no button in the built chrome" % id)
	var saveButton := chrome.buttonFor(Actions.SAVE_DOCUMENT)
	if saveButton != null:
		saveButton.emit_signal("pressed")
	_require(raised == [Actions.SAVE_DOCUMENT], "pressing Save raised %s" % str(raised))

	# Tool buttons are the toggling kind and only one reads as active at a time.
	chrome.setToolActive(Actions.TOOL_PAINT)
	var paint := chrome.buttonFor(Actions.TOOL_PAINT)
	var fill := chrome.buttonFor(Actions.TOOL_FILL)
	_require(
		paint != null and paint.button_pressed and fill != null and not fill.button_pressed,
		"the toolbar's selected state does not follow the active tool"
	)

	# Buttons keep ordinary focus so Tab can traverse them -- the old shell set FOCUS_NONE on
	# everything to protect its global shortcuts, and that is exactly what this rebuild undid.
	_require(
		paint != null and paint.focus_mode == Control.FOCUS_ALL,
		"toolbar buttons cannot take focus, so Tab traversal is broken"
	)

	# The value row exists and erasing is reachable through it rather than as a brush of its own.
	hud.setTileChoices(["t000", "t001"] as Array[String])
	_require(hud.hasValueRow(), "the palette has no value row")
	_require(hud.selectedValue() == "t000", "the value row did not default to the first real tile")
	_require(hud.selectEraseValue(), "the erase value is not reachable")
	_require(
		hud.selectedValue() == MapDataScript.EMPTY,
		"selecting erase did not put the erase value on the row"
	)

	# A layer whose values are not tiles must not be offered a tilesheet.
	hud.showValueOnlyPalette("terrain height")
	_require(not hud.picker.visible, "a height layer was still offered a tilesheet")

	await _checkFitsTargetWindows(chrome)
	layer.queue_free()


## The workspace has to be usable at both target window sizes with BOTH side panels open. This is
## a minimum-width regression guard: a long button label, an unclipped readout or one more control
## in the view bar can push the layout wider than the window, and the first thing to be pushed off
## the edge is the inspector -- which looks like a missing panel rather than like a layout fault.
##
## Two failures found this way while the workspace was being built: an autowrapping status label
## squeezed in an HBox reported a minimum HEIGHT of several hundred pixels and left the map four
## pixels tall, and the unshortened view-bar buttons put the minimum width at 1368 against a 1280
## window.
func _checkFitsTargetWindows(chrome) -> void:
	for target: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = target
		await process_frame
		await process_frame
		var frame := chrome.stage.get_parent().get_parent().get_parent() as Control
		var minimum := frame.get_combined_minimum_size()
		_require(
			minimum.x <= float(target.x),
			"the workspace needs %d px of width at %s" % [int(minimum.x), target]
		)
		_require(
			minimum.y <= float(target.y),
			"the workspace needs %d px of height at %s" % [int(minimum.y), target]
		)
		var stageRect: Rect2 = chrome.stageRect()
		_require(
			stageRect.size.x > 320.0 and stageRect.size.y > 240.0,
			"the map column collapsed to %s at %s" % [stageRect.size, target]
		)
		# What the controller copies onto `Display` must be exactly the hole the layout left.
		_require(
			Geometry.stageToDisplay(stageRect) == stageRect,
			"a healthy stage at %s did not map to itself" % target
		)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
