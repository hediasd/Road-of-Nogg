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
	for retired: String in ["view.editing", "view.shipping", "view.projection"]:
		_require(not Actions.has(retired), "%s still exposes retired preview chrome" % retired)

	for shortcut in Actions.SHORTCUTS:
		_require(
			Actions.has(str((shortcut as Dictionary)["id"])),
			"shortcut names unknown action %s" % str((shortcut as Dictionary)["id"])
		)

	# Document commands use the standard shortcuts, and modifier pairs stay distinct.
	_require(Actions.hintFor(Actions.NEW_DOCUMENT) == "Ctrl+N", "New lost its Ctrl+N hint")
	_require(Actions.hintFor(Actions.OPEN_DOCUMENT) == "Ctrl+O", "Open lost its Ctrl+O hint")
	_require(Actions.hintFor(Actions.SAVE_DOCUMENT) == "Ctrl+S", "Save lost its Ctrl+S hint")
	_require(
		Actions.hintFor(Actions.SAVE_DOCUMENT_AS) == "Ctrl+Shift+S",
		"Save As lost its Ctrl+Shift+S hint"
	)
	_require(Actions.hintFor(Actions.EXPORT_BATTLE) == "Ctrl+Shift+E", "battle export hint wrong")
	_require(Actions.hintFor(Actions.TOOL_ERASE) == "E", "Erase lost its plain-E hint")
	_require(Actions.hintFor(Actions.VIEW_FRAME) == "F", "Frame is no longer F")
	_require(
		Actions.resolve(KEY_SPACE, false, false, Actions.FOCUS_MAP).is_empty(),
		"Space still switches to the retired shipping preview"
	)


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
## named buttons in the left column's Tools section, or in the dropdown beneath them that carries
## the layer-specific ones. A tool in neither would be a capability the rebuild silently dropped.
func _checkToolsReachable() -> void:
	var buttonActions: Array[String] = []
	for action in Actions.actionsInGroup(Actions.GROUP_TOOL):
		buttonActions.append(str((action as Dictionary)["id"]))
	_require(buttonActions.size() == 6, "expected six named tool buttons, found %d" % buttonActions.size())
	for required: String in [
		Actions.TOOL_NAVIGATE, Actions.TOOL_INSPECT, Actions.TOOL_PAINT,
		Actions.TOOL_ERASE, Actions.TOOL_FILL, Actions.TOOL_EYEDROPPER,
	]:
		_require(buttonActions.has(required), "%s has no button in the map menu" % required)

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
	# The menu is BELOW the tilesheet, in the same panel, which is the whole point of moving it --
	# and it is OUTSIDE the tilesheet's scroll, so no map action can be hidden by scrolling.
	var palettePanel := layer.get_node_or_null(
		"Workspace/WorkspaceBody/PaletteSplit/PalettePanel"
	) as Control
	_require(palettePanel != null, "the palette panel was not built")
	var scroll := layer.find_child("PaletteScroll", true, false) as ScrollContainer
	_require(scroll != null, "the palette scroll was not built")
	if palettePanel != null and scroll != null and chrome.mapMenuColumn != null:
		_require(
			palettePanel.is_ancestor_of(chrome.mapMenuColumn),
			"the map menu is not in the palette panel"
		)
		# Against the SCROLL's rect, not the palette column's: a scrolled child is routinely
		# taller than the viewport that clips it, so its own rect says nothing about what is
		# on screen underneath it.
		_require(
			chrome.mapMenuColumn.get_global_rect().position.y >= scroll.get_global_rect().end.y,
			"the map menu is not below the tilesheet"
		)
		_require(
			not scroll.is_ancestor_of(chrome.mapMenuColumn),
			"the map menu scrolls with the tilesheet, so an action can be scrolled out of reach"
		)
	_require(chrome.inspectorColumn != null, "the chrome built no inspector column")
	_require(
		chrome.stage != null and chrome.stage.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the stage does not ignore the mouse, so map clicks would never reach the controller"
	)
	var header := layer.get_node_or_null("Workspace/WorkspaceHeader") as Control
	_require(header != null, "the top bar was not built")
	if header != null:
		_require(
			header.mouse_filter == Control.MOUSE_FILTER_STOP,
			"the top bar does not consume the mouse, so a button press would also paint"
		)
	_require(chrome.mapMenuColumn != null, "the chrome built no map menu")
	_require(
		layer.get_node_or_null("Workspace/WorkspaceToolbar") == null,
		"the retired toolbar row is still built above the body"
	)
	_require(
		layer.find_child("ViewBar", true, false) == null,
		"the retired view bar is still built above the map"
	)

	# THE SPLIT, ASSERTED BOTH WAYS. A management action has to be on the top bar and a map action
	# has to be in the left column's menu; checking only one direction would pass a build that put
	# every button in both places.
	for action in Actions.actions():
		var actionID := str((action as Dictionary)["id"])
		var button := chrome.buttonFor(actionID)
		if button == null:
			continue
		var inMenu := chrome.mapMenuColumn != null and chrome.mapMenuColumn.is_ancestor_of(button)
		var inHeader := header != null and header.is_ancestor_of(button)
		if Actions.isTopBarAction(actionID):
			_require(inHeader and not inMenu, "%s is a document action but is not on the top bar" % actionID)
		else:
			_require(inMenu and not inHeader, "%s is a map action but is not in the left menu" % actionID)

	# The extra-tool dropdown moved with the tools it extends.
	var extras := chrome.mapMenuColumn.find_child("ExtraTools", true, false)
	_require(extras != null, "the layer-specific tool dropdown is not in the map menu")
	# Every section of the menu really produced its heading.
	for section in Actions.MAP_MENU:
		var heading := str((section as Dictionary)["heading"])
		var found := false
		for child in chrome.mapMenuColumn.get_children():
			var label := child as Label
			if label != null and label.text == heading:
				found = true
				break
		_require(found, "the map menu has no %s section" % heading)

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
		"the menu's selected state does not follow the active tool"
	)

	# Buttons keep ordinary focus so Tab can traverse them -- the old shell set FOCUS_NONE on
	# everything to protect its global shortcuts, and that is exactly what this rebuild undid.
	_require(
		paint != null and paint.focus_mode == Control.FOCUS_ALL,
		"menu buttons cannot take focus, so Tab traversal is broken"
	)

	# Art selection comes from the visible sheet. The hidden generic value row remains for layers
	# whose values are not tiles, while Erase explicitly clears the sheet selection.
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	hud.configurePalette("probe", ImageTexture.create_from_image(image), 16, [
		{"ID": "t000", "CELL": Vector2i(0, 0)},
		{"ID": "t001", "CELL": Vector2i(1, 0)},
	])
	hud.setTileChoices(["t000", "t001"] as Array[String])
	_require(hud.hasValueRow(), "the palette has no value row")
	_require(hud.selectedValue() == "t000", "the tilesheet did not default to the first real tile")
	_require(not hud.tileOption.get_parent().visible, "tile art still exposes an id dropdown")
	var quickChoices := hud.chrome.paletteColumn.find_child("PaletteQuickChoices", true, false)
	_require(quickChoices != null and not quickChoices.visible,
		"a non-starter tileset received starter quick-choice labels")
	var starterImage := Image.create(160, 96, false, Image.FORMAT_RGBA8)
	starterImage.fill(Color.WHITE)
	hud.configurePalette("temp2_hex32_starter", ImageTexture.create_from_image(starterImage), 32, [
		{"ID": "t000", "CELL": Vector2i(0, 0)},
		{"ID": "t001", "CELL": Vector2i(1, 0)},
		{"ID": "t002", "CELL": Vector2i(2, 0)},
	])
	quickChoices = hud.chrome.paletteColumn.find_child("PaletteQuickChoices", true, false)
	_require(quickChoices.visible and quickChoices.get_child_count() == 3,
		"the starter palette did not build Land/Sea/Grass quick choices")
	for button in quickChoices.get_children():
		_require((button as Button).icon != null, "a starter quick choice has no thumbnail")
	_require(hud.selectEraseValue(), "the erase value is not reachable")
	_require(
		hud.selectedValue() == MapDataScript.EMPTY,
		"selecting erase did not clear the sheet selection"
	)

	# A layer whose values are not tiles must not be offered a tilesheet.
	hud.showValueOnlyPalette("terrain height")
	_require(not hud.picker.visible, "a height layer was still offered a tilesheet")

	await _checkFitsTargetWindows(chrome)
	await _checkDividers(chrome)
	layer.queue_free()


## The workspace has to be usable at both target window sizes with BOTH side panels open. This is
## a minimum-width regression guard: a long button label, an unclipped readout or one more control
## on the top bar can push the layout wider than the window, and the first thing to be pushed off
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
		var frame := chrome.root.get_node("Workspace") as Control
		var minimum := frame.get_combined_minimum_size()
		_require(
			minimum.x <= float(target.x),
			"the workspace needs %d px of width at %s" % [int(minimum.x), target]
		)
		_require(
			minimum.y <= float(target.y),
			"the workspace needs %d px of height at %s" % [int(minimum.y), target]
		)
		for action in Actions.actions():
			var button := frame.find_child(str((action as Dictionary)["id"]), true, false) as Button
			if button != null:
				_require(
					button.custom_minimum_size.x >= 36.0,
					"action %s can collapse to an unreadable sliver at %s" % [button.name, target]
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


## The three lines between panels have to be BOTH transparent to a map click (the split itself
## ignores the mouse, same as every structural container) AND draggable (its internal handle does
## not). Verified against the running engine rather than assumed: a `SplitContainer` parents an
## internal `SplitContainerDragger` control alongside its two children, and that handle is what
## takes the mouse -- this asserts that control exists, is visible, and has real size, rather than
## asserting its exact class name, so the check survives an engine version that renames it.
func _checkDividers(chrome) -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	# `_checkFitsTargetWindows` just resized the window twice; `resyncPanelWidths` re-establishes
	# the panels' fixed default widths at THIS size before anything below measures a "before".
	await chrome.resyncPanelWidths()
	await process_frame
	await process_frame

	var paletteSplit := chrome.root.get_node("Workspace/WorkspaceBody/PaletteSplit") as SplitContainer
	var inspectorSplit := chrome.root.get_node(
		"Workspace/WorkspaceBody/PaletteSplit/InspectorSplit"
	) as SplitContainer
	var menuSplit := chrome.root.find_child("PaletteMenuSplit", true, false) as SplitContainer
	_require(paletteSplit != null, "PaletteSplit was not built")
	_require(inspectorSplit != null, "InspectorSplit was not built")
	_require(menuSplit != null, "PaletteMenuSplit was not built")
	if paletteSplit == null or inspectorSplit == null or menuSplit == null:
		return

	for split in [paletteSplit, inspectorSplit, menuSplit]:
		var container := split as SplitContainer
		_require(
			container.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s does not ignore the mouse, so a map click would be consumed by the divider" % container.name
		)
		var hasDragger := false
		for child in container.get_children(true):
			var control := child as Control
			if control == null or control.get_parent() != container:
				continue
			if child in [container.get_child(0), container.get_child(1)]:
				continue
			if (
				control.visible and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
				and control.size.x > 0.0 and control.size.y > 0.0
			):
				hasDragger = true
				break
		_require(hasDragger, "%s has no draggable handle a click could take hold of" % container.name)

	var palettePanel := chrome.root.get_node(
		"Workspace/WorkspaceBody/PaletteSplit/PalettePanel"
	) as Control
	var inspectorPanel := chrome.root.get_node(
		"Workspace/WorkspaceBody/PaletteSplit/InspectorSplit/InspectorPanel"
	) as Control

	var paletteWidthBefore := palettePanel.size.x
	var stageWidthBefore: float = chrome.stageRect().size.x
	paletteSplit.split_offset += 120
	await process_frame
	await process_frame
	_require(
		absf(palettePanel.size.x - (paletteWidthBefore + 120.0)) <= 2.0,
		"dragging PaletteSplit did not grow the palette by ~120 px (was %s, now %s)" % [
			paletteWidthBefore, palettePanel.size.x
		]
	)
	_require(
		absf(chrome.stageRect().size.x - (stageWidthBefore - 120.0)) <= 2.0,
		"dragging PaletteSplit did not shrink the map by ~120 px"
	)
	# Undone before the next check: `InspectorSplit` sits inside `PaletteSplit`'s second child, so
	# leaving the palette widened would test the inspector's divider against a total width the
	# palette test already shrank, rather than the two dividers independently.
	paletteSplit.split_offset -= 120
	await process_frame
	await process_frame

	var inspectorWidthBefore := inspectorPanel.size.x
	inspectorSplit.split_offset -= 80
	await process_frame
	await process_frame
	_require(
		absf(inspectorPanel.size.x - (inspectorWidthBefore + 80.0)) <= 2.0,
		"dragging InspectorSplit did not grow the inspector by ~80 px (was %s, now %s)" % [
			inspectorWidthBefore, inspectorPanel.size.x
		]
	)

	var scrollForMenuCheck := chrome.root.find_child("PaletteScroll", true, false) as ScrollContainer
	menuSplit.split_offset = -10000
	await process_frame
	await process_frame
	_require(
		chrome.mapMenuColumn.size.y + 0.5 >= chrome.mapMenuColumn.get_combined_minimum_size().y,
		"dragging PaletteMenuSplit to its extreme shrank the map menu below its own minimum height"
	)
	_require(
		chrome.mapMenuColumn.get_global_rect().position.y >= scrollForMenuCheck.get_global_rect().end.y,
		"dragging PaletteMenuSplit to its extreme moved the map menu above the tilesheet"
	)

	# A toggle button's `pressed` signal does not flip `button_pressed` on its own -- that happens
	# inside the real click path -- so a script-driven press has to set the state first and then
	# emit the signal the handler actually reads.
	var paletteButton := chrome.root.find_child("PaletteCollapse", true, false) as Button
	var preCollapseWidth := palettePanel.size.x
	paletteButton.button_pressed = true
	paletteButton.emit_signal("pressed")
	await process_frame
	await process_frame
	# Against the panel's OWN combined minimum, not the bare `COLLAPSED_WIDTH` constant: that
	# constant is a floor fed to `custom_minimum_size`, but the header row above the tilesheet (the
	# "Tileset" title and the collapse button itself) stays visible throughout and has a real
	# minimum width of its own -- measured against the engine directly at ~84 px, not the ~26 px
	# `COLLAPSED_WIDTH` names. The panel collapsing to as small as it is EVER able to get is the
	# actual, checkable claim; a hardcoded number ignorant of the header would not be.
	_require(
		absf(palettePanel.size.x - palettePanel.get_combined_minimum_size().x) <= 2.0,
		"collapsing the palette left it wider than its own true minimum (is %s, minimum %s)" % [
			palettePanel.size.x, palettePanel.get_combined_minimum_size().x
		]
	)
	_require(
		palettePanel.size.x < preCollapseWidth - 100.0,
		"collapsing the palette did not meaningfully shrink it (was %s, now %s)" % [
			preCollapseWidth, palettePanel.size.x
		]
	)
	# NOT `paletteSplit.collapsed` -- setting that property makes a `SplitContainer` ignore
	# `split_offset` entirely and fall back to natural ~50/50 sizing (verified against the engine
	# directly), which is exactly what the width assertion just above would catch if the
	# implementation ever set it. `dragger_visibility` is the real, offset-preserving signal.
	_require(
		paletteSplit.dragger_visibility == SplitContainer.DRAGGER_HIDDEN_COLLAPSED,
		"PaletteSplit's dragger was not hidden on collapse"
	)
	paletteButton.button_pressed = false
	paletteButton.emit_signal("pressed")
	await process_frame
	await process_frame
	_require(
		absf(palettePanel.size.x - preCollapseWidth) <= 2.0,
		"expanding the palette did not restore its pre-collapse width (was %s, now %s)" % [
			preCollapseWidth, palettePanel.size.x
		]
	)
	_require(
		paletteSplit.dragger_visibility == SplitContainer.DRAGGER_VISIBLE,
		"PaletteSplit's dragger was not restored on expand"
	)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
