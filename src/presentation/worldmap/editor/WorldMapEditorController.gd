## The world map's LEVEL EDITOR shell: an authoring scene built on the exact rig the game
## ships, with a second camera for looking around it and a second HUD panel for editor-only
## chrome -- which layer is active, which tool is selected, and whether the current view is
## off the shipping contract.
##
## REUSE, NOT A FORK. This extends `WorldMapDebugController` rather than duplicating it: every
## framing preset, region picker, sun, cloud and shadow control here is the debug scene's own,
## unmodified, because two copies of the framing controls would diverge the first time either
## one changes. What this file adds is layer and tool STATE and where mouse input goes; it does
## not touch anything `WorldMapDebugController` already owns, and `WorldMapDebugScene.tscn`
## keeps working exactly as before.
##
## THE CAMERA IS SWAPPED, NOT FORKED. `WorldMap.tscn`'s Camera node ships as a plain
## `WorldMapCameraRig`; once the base scene has built, `_installEditorCamera()` replaces it in
## place with a `WorldMapEditorCamera` (which subclasses that same rig -- see its own header)
## and reparents the Sky backdrop onto the new node. Ground, Props and Clouds are untouched:
## they are the same nodes `super._ready()` built, which is what keeps this an authoring VIEW
## of the shipping rig rather than a second copy of it. `probe_editor_shell.gd` asserts the
## Ground and Props instances are literally the ones the base class constructs.
##
## PHASE A SHIPS NO DATA MODEL. Every layer in `LAYERS` is real, selectable chrome, and every
## one is `enabled = false` -- there is nothing yet for a ground brush, a height edit or a road
## stroke to act on. An empty layer shows as disabled rather than absent, so the shape of the
## tool is visible from Gate 1 and later phases flip one bit each rather than adding rows.
##
## WHAT "ROUTING" MEANS WITHOUT A DATA MODEL. `_routeToActiveLayer()` cannot hit-test a tile
## that does not exist yet, so what it proves now is narrower and still real: a click reaches
## EXACTLY the active layer and no other, and never reaches a locked one. That contract is
## exactly what Phase B's brushes need to be able to trust, and it is why the router is built
## and tested now rather than arriving bundled with the first brush.
##
## INPUT OWNERSHIP, AND WHY IT ALL LIVES HERE RATHER THAN ON THE CAMERA. `WorldMapEditorCamera`
## sits inside the "World" `SubViewport`, which the scene displays through a plain `TextureRect`
## rather than a `SubViewportContainer` -- so it never receives a real, engine-dispatched mouse
## or key event, ever. This controller is a sibling of "World", not a child of it, and DOES
## receive them, matching the base class's own established pattern for drag-to-pan. So every
## mouse gesture and every navigation key this class owns is read here and applied to the
## camera through its plain methods (`orbitByScreenDelta`, `panBy`, `dollyBy`, `toggleOrtho`,
## `snapToContract`, `snapYaw`, `frameRegion`) -- never by relying on the camera to notice
## anything on its own. Left click routes to the active layer's tool instead of panning, which
## is why this class does not call `super._unhandled_input`: the base class's left-drag-pans-
## the-camera would otherwise compete with left click as a tool input. `KEY_F` is claimed here
## rather than left to the base's inherited `_recentre()`, and marked handled, so the two do not
## both fire for one keypress. Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes -- see
## `WorldMapEditHistory` for why they are wired here even though nothing feeds them yet.

extends "res://src/presentation/debug/WorldMapDebugController.gd"

const EditorHudScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorHud.gd")
const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")
const SurfacePick = preload("res://src/presentation/worldmap/editor/WorldMapSurfacePick.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const Regions = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")

## One entry per layer this tool currently means to hold data for. `enabled` is false for both
## in Phase A -- see the class note -- and a later item flips its own row to true as its data
## model lands. The id list and order are load-bearing: WME items after this one address a
## layer by id, not by position, but tests and tooling built against this table should not need
## it reordered.
##
## TRIMMED FROM EIGHT TO TWO AT GATE 1 (docs/plans/reviews/worldmap-editor-gate-1.md), on
## direct request: "For now I only think the map builder should deal with ground and overlay,
## can we add more as we go later." Height, props, walkability, graph, lighting and annotations
## are not cancelled -- they come back as their own items when there is a reason to build them,
## not as one bundled wave. `probe_editor_shell.gd` needed no change for this: it iterates
## LAYERS/TOOLS generically, which is the entire point of layers being data rather than code.
const LAYERS := [
	{"id": "ground", "label": "Ground", "enabled": false},
	{"id": "overlay", "label": "Overlay (roads)", "enabled": false},
]

## Two tools, chosen to prove the router rather than to edit anything -- WME-9 is where a real
## brush arrives. NAVIGATE hands every mouse button to camera movement, exactly as if no tool
## were selected; INSPECT is the one thing this item can test, a left click that routes to the
## active layer and nothing else.
const TOOL_NAVIGATE := "navigate"
const TOOL_INSPECT := "inspect"
const TOOL_PAINT := "paint"
const TOOL_RECTANGLE := "rectangle"
const TOOL_LINE := "line"
const TOOL_FILL := "fill"
const TOOL_EYEDROPPER := "eyedropper"
const TOOL_STAMP := "stamp"
const TOOL_SCATTER := "scatter"
const TOOL_REPLACE := "replace"
const TOOLS := [
	{"id": TOOL_NAVIGATE, "label": "Navigate"},
	{"id": TOOL_INSPECT, "label": "Inspect"},
	{"id": TOOL_PAINT, "label": "Paint / erase"},
	{"id": TOOL_RECTANGLE, "label": "Rectangle"},
	{"id": TOOL_LINE, "label": "Line"},
	{"id": TOOL_FILL, "label": "Flood fill"},
	{"id": TOOL_EYEDROPPER, "label": "Eyedropper"},
	{"id": TOOL_STAMP, "label": "Stamp"},
	{"id": TOOL_SCATTER, "label": "Scatter"},
	{"id": TOOL_REPLACE, "label": "Replace kind"},
]

var _editorCamera: WorldMapEditorCamera
var _editorHud: WorldMapEditorHud
var _layerLocked: Dictionary = {}
var _activeLayer := "ground"
var _activeTool := TOOL_NAVIGATE

## The last layer a routed click actually reached, and a per-layer hit count. Both exist for
## `probe_editor_shell.gd` -- see the class note on what "routing" can mean before a data model.
var _lastRoutedLayer := ""
var _routeCount: Dictionary = {}

## Which camera gesture the mouse is mid-drag on, held here rather than on the camera -- see the
## class note on input ownership.
var _cameraOrbiting := false
var _cameraPanning := false

## Undo/redo, wired now even though nothing feeds it yet. `WorldMapEditHistory` is decoupled
## from any particular document -- it operates on whatever `WorldMapTileData` it is handed -- so
## there is nothing wrong with owning it before the editor has one open; WME-9's brushes are
## what will call `beginStroke` / `paintCell` / `endStroke` on it. Until then Ctrl+Z and Ctrl+Y
## are live keys that correctly do nothing, because `_document` is null and `canUndo()` is
## false, rather than dead keys nobody has bound yet.
var _history := WorldMapEditHistory.new()
## The currently open authored document, or null. Set by whatever later item gives the editor a
## document to edit; nothing here creates one.
var _document: WorldMapTileData = null
var _documentPath := ""
var _baker := WorldMapBaker.new()
var _cursorCell: Variant = null
var _gestureStart: Variant = null
var _strokeOpen := false
var _strokeTouched: Array[Vector2i] = []
var _documentDirty := false
var _stampPattern: Array = []
var _scatterSet: Array[String] = []
var _pointerPosition := Vector2.ZERO


func _ready() -> void:
	for layer in LAYERS:
		_layerLocked[str(layer["id"])] = false
		_routeCount[str(layer["id"])] = 0

	super._ready()
	_neutralizeDebugHudFocus()
	_installEditorCamera()
	_buildEditorUi()
	_editorCamera.rememberRegion(_ground.regionRect())
	_openDocumentForRegion(_regionID)


func _process(delta: float) -> void:
	super._process(delta)
	_editorHud.setOffContract(_editorCamera.offContractReason())
	_cursorCell = _pickCell(_pointerPosition)
	_updateGrid()


## `Display` does not fill the window here -- the fixed left and right panels are laid out
## beside it, not over it, so the map has its own independent centre column. Every framing,
## buffer-size and sky-backdrop calculation in the base class goes through
## `_displaySize()` for exactly this reason: overriding this one method is what keeps the
## rendered buffer, the "tiles across" readout and the sky quad describing what is actually on
## screen instead of the window's full, wider rect.
func _displaySize() -> Vector2:
	return _display.get_rect().size


## Swaps the shipping camera for the editor's, in place. Ground, Props and Clouds are left
## exactly as `super._ready()` built them -- only the Camera and its Sky child move.
## Strips keyboard focus from every control the REUSED debug HUD builds -- the framing preset and
## region pickers, the tile-grid toggle, copy-settings, and every slider, colour picker and
## option button `WorldMapDebugHud.SECTIONS` builds from data.
##
## DONE HERE, NOT IN WorldMapDebugHud. That class also builds the shipping debug scene's own
## panel, where Tab and Space are not camera shortcuts and must keep their ordinary focus
## behaviour -- see `WorldMapEditorHud`'s own controls, which set `focus_mode = FOCUS_NONE`
## themselves for the same reason on chrome that belongs only to the editor. This is the other
## half of that fix, applied from outside because the HUD it targets is not this editor's own.
##
## The playtest that found the original defect reproduced it specifically on the tile-grid
## checkbox: Space toggled the grid AND reset the camera in one keypress, because the checkbox
## had focus from having just been interacted with. `WorldMapEditorController._unhandled_key_
## input` marking Tab/Space/F handled is the OTHER half of this fix -- that stops a focused
## control from receiving the event at all when the SceneTree already consumed it, but only once
## nothing upstream (the control's own focus-driven handling) has already acted on it first. A
## control with focus intercepts before an event ever reaches "unhandled"; only removing its
## focus closes that path.
func _neutralizeDebugHudFocus() -> void:
	for control in [_hud.presetOption, _hud.regionOption, _hud.tileGridToggle, _hud.copyButton]:
		if control != null:
			control.focus_mode = Control.FOCUS_NONE
	for control in _hud._controls.values():
		(control as Control).focus_mode = Control.FOCUS_NONE


func _installEditorCamera() -> void:
	var oldCamera := _camera
	var sky := _sky
	oldCamera.remove_child(sky)
	var parent := oldCamera.get_parent()
	var index := oldCamera.get_index()
	parent.remove_child(oldCamera)
	oldCamera.queue_free()

	_editorCamera = WorldMapEditorCamera.new()
	_editorCamera.name = "Camera"
	parent.add_child(_editorCamera)
	parent.move_child(_editorCamera, index)
	_editorCamera.add_child(sky)
	_editorCamera.current = true

	# `_camera` is the base class's own reference, and everything it already calls --
	# `_applyFraming`, `_refreshStatus`, the base `_recentre` -- reads it by that name. Pointing
	# it at the new node is what lets every one of those keep working completely unmodified.
	_camera = _editorCamera
	_applyFraming()


func _buildEditorUi() -> void:
	_editorHud = EditorHudScript.new(get_node("Ui") as CanvasLayer)
	_editorHud.build(
		LAYERS, TOOLS, _onLayerSelected, _onToolSelected,
		_onLayerVisibilityToggled, _onLayerLockToggled
	)
	_editorHud.setActiveLayer(_layerIndex(_activeLayer))
	_editorHud.setActiveTool(0)
	_editorHud.saveButton.pressed.connect(_saveDocument)

	# A PanelContainer whose width comes from its content's minimum size (see the .tscn: neither
	# side panel is given a fixed pixel width) does not settle in one deferred call -- WorldMap-
	# DebugHud builds many sections, and each can still be growing the panel's reported minimum
	# size a frame after the last one was added. `resized` is emitted every time that settles
	# further, so connecting to it -- rather than reading the size once -- is what makes Display
	# converge on the panels' TRUE final width instead of freezing on however far layout had
	# gotten when a single deferred call happened to fire.
	var leftPanel := get_node("Ui/EditorPanel") as Control
	var rightPanel := get_node("Ui/PanelContainer") as Control
	leftPanel.resized.connect(_layoutDisplayBetweenPanels)
	rightPanel.resized.connect(_layoutDisplayBetweenPanels)
	call_deferred("_layoutDisplayBetweenPanels")


func _onRegionSelected(index: int) -> void:
	if _documentDirty:
		_saveDocument()
	super._onRegionSelected(index)
	_openDocumentForRegion(_regionID)
	_editorCamera.rememberRegion(_ground.regionRect())


## Confines `Display` to the column left over once both side panels have taken what their own
## content actually needs. Connected to both panels' `resized` signal rather than measured once
## -- see the connection site's own note on why one reading is not enough.
func _layoutDisplayBetweenPanels() -> void:
	var leftWidth: float = (get_node("Ui/EditorPanel") as Control).size.x
	var rightWidth: float = (get_node("Ui/PanelContainer") as Control).size.x
	if is_equal_approx(_display.offset_left, leftWidth) and is_equal_approx(_display.offset_right, -rightWidth):
		return
	_display.offset_left = leftWidth
	_display.offset_right = -rightWidth
	_applyRenderScale()


## Left click routes to the active layer's tool. Middle-drag orbits, right-drag pans, the wheel
## dollies -- all applied to the camera through its plain methods, per the class note. Snapping
## yaw to 45 degrees on a Shift-released middle-drag mirrors the debug-scene convention of a
## modifier changing what a release does rather than needing its own gesture. Deliberately does
## not call `super`: the base class's left-drag-pans-the-camera would otherwise compete with
## left click as a tool input, and only one of them may own that button.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_pointerPosition = button.position
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_beginToolGesture(button.position)
				else:
					_endToolGesture(button.position)
			MOUSE_BUTTON_MIDDLE:
				_cameraOrbiting = button.pressed
				if not button.pressed and Input.is_key_pressed(KEY_SHIFT):
					_editorCamera.snapYaw()
			MOUSE_BUTTON_RIGHT:
				_cameraPanning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_editorCamera.dollyBy(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_editorCamera.dollyBy(-1.0)
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		_pointerPosition = motion.position
		_cursorCell = _pickCell(motion.position)
		if _cameraOrbiting:
			_editorCamera.orbitByScreenDelta(motion.relative)
		elif _cameraPanning:
			_editorCamera.panBy(motion.relative)
		elif _strokeOpen and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _cursorCell != null:
			_paintStrokeCell(_cursorCell as Vector2i)


## `KEY_F`, `KEY_SPACE` and `KEY_TAB` are claimed here, each marking the event handled so it
## cannot also reach a focused HUD control's own key handling (a `Button` treats Space as
## activate-focused-control, and Godot's default UI focus traversal treats Tab as
## focus-next -- `WorldMapEditorHud` sets `focus_mode = FOCUS_NONE` on its own controls
## specifically so neither can grab that focus in the first place, but marking handled here is
## the second half of that guarantee and costs nothing when the first half already held). Every
## other key falls through to the base class unchanged.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		super._unhandled_key_input(event)
		return
	match key.keycode:
		KEY_F:
			# The aspect that matters is the DISPLAY's, not the window's -- the editor's map
			# column is not the window, and _displaySize() is what already accounts for that
			# (see its own note). Guarded against a zero-height display during the one frame
			# before the panels have settled, where the aspect would be nonsensical.
			var display := _displaySize()
			if display.y > 0.0:
				_editorCamera.frameRegion(_ground.regionRect(), display.x / display.y)
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_editorCamera.snapToContract()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_editorCamera.toggleOrtho()
			get_viewport().set_input_as_handled()
		KEY_Z:
			if not key.ctrl_pressed:
				super._unhandled_key_input(event)
				return
			if key.shift_pressed:
				_redo()
			else:
				_undo()
			get_viewport().set_input_as_handled()
		KEY_Y:
			if not key.ctrl_pressed:
				super._unhandled_key_input(event)
				return
			_redo()
			get_viewport().set_input_as_handled()
		KEY_S:
			if not key.ctrl_pressed:
				super._unhandled_key_input(event)
				return
			_saveDocument()
			get_viewport().set_input_as_handled()
		_:
			super._unhandled_key_input(event)


func _undo() -> void:
	if _document == null:
		return
	var touched := _history.undo(_document)
	if not touched.is_empty():
		_onHistoryApplied(touched)


func _redo() -> void:
	if _document == null:
		return
	var touched := _history.redo(_document)
	if not touched.is_empty():
		_onHistoryApplied(touched)


## What a live document's renderer needs invalidated after undo or redo touches a set of cells --
## empty until a later item gives the editor a baked document and a baker to invalidate. `touched`
## is the exact `{layerID, cells}` `WorldMapEditHistory.undo`/`redo` returns, which is what makes
## this the same invalidation a forward edit would have triggered rather than a coarser guess.
func _onHistoryApplied(touched: Dictionary) -> void:
	if _document == null:
		return
	var layerID := str(touched.get("layerID", ""))
	var cells: Array[Vector2i] = []
	for value in touched.get("cells", []):
		cells.append(value as Vector2i)
	_afterCellsEdited(layerID, cells)


## What "routing" can mean before a data model: identify the target and stop there. A locked
## layer refuses the click outright -- neither the count nor `_lastRoutedLayer` moves -- which
## is the standard editor meaning of a lock and is distinct from `enabled`, which only ever
## gates whether a reached layer goes on to mutate anything.
func _routeToActiveLayer() -> void:
	if _activeTool != TOOL_INSPECT:
		return
	if bool(_layerLocked.get(_activeLayer, false)):
		return
	_lastRoutedLayer = _activeLayer
	_routeCount[_activeLayer] = int(_routeCount.get(_activeLayer, 0)) + 1
	# Phase B's brushes act here, once a layer has data to act on. There is deliberately
	# nothing past this line in Phase A.


func _beginToolGesture(screenPosition: Vector2) -> void:
	_routeToActiveLayer()
	if _activeTool == TOOL_NAVIGATE:
		return
	if bool(_layerLocked.get(_activeLayer, false)):
		_editorHud.setStatus("%s is locked." % _activeLayer)
		return
	if not _layerEditable(_activeLayer):
		_editorHud.setStatus("Choose an authored layer with a tileset before editing.")
		return
	_cursorCell = _pickCell(screenPosition)
	if _cursorCell == null:
		_editorHud.setStatus("No map cell under the pointer.")
		return
	var cell := _cursorCell as Vector2i
	var tileID := _editorHud.selectedTileID()
	match _activeTool:
		TOOL_INSPECT:
			_editorHud.setStatus("%s %s = %s" % [_activeLayer, cell, _document.getCell(_activeLayer, cell)])
		TOOL_EYEDROPPER:
			var sampled := Brushes.eyedropper(_document, _activeLayer, cell)
			_editorHud.selectTileID(sampled)
			_editorHud.setStatus("Selected %s from %s." % [sampled, cell])
		TOOL_PAINT:
			Brushes.beginStroke(_history, _activeLayer)
			_strokeOpen = true
			_strokeTouched.clear()
			_paintStrokeCell(cell)
		TOOL_FILL:
			var flooded := Brushes.floodCells(_document, _activeLayer, cell)
			if Brushes.floodFill(_document, _history, _activeLayer, cell, tileID):
				_afterCellsEdited(_activeLayer, flooded)
		TOOL_STAMP:
			var pattern := _stampPattern if not _stampPattern.is_empty() else [[tileID]]
			if Brushes.stamp(_document, _history, _activeLayer, cell, pattern):
				var affected := Rect2i(cell, Vector2i((pattern[0] as Array).size(), pattern.size()))
				_afterRectEdited(_activeLayer, affected)
		TOOL_REPLACE:
			var source := _document.getCell(_activeLayer, cell)
			if Brushes.replaceAllOfKind(
				_document, _history, _activeLayer, source, tileID, _terrainByIDForActiveLayer()
			):
				_afterRectEdited(_activeLayer, Rect2i(Vector2i.ZERO, _document.layerSize(_activeLayer)))
		TOOL_RECTANGLE, TOOL_LINE, TOOL_SCATTER:
			_gestureStart = cell


func _endToolGesture(screenPosition: Vector2) -> void:
	if _strokeOpen:
		_strokeOpen = false
		if Brushes.endStroke(_history):
			_afterCellsEdited(_activeLayer, _strokeTouched)
		_strokeTouched.clear()
		return
	if _gestureStart == null or _document == null:
		return
	var finish = _pickCell(screenPosition)
	var start := _gestureStart as Vector2i
	_gestureStart = null
	if finish == null:
		return
	var last := finish as Vector2i
	var tileID := _editorHud.selectedTileID()
	match _activeTool:
		TOOL_RECTANGLE:
			var cells := Brushes.rectangleCells(start, last)
			if Brushes.rectangle(_document, _history, _activeLayer, start, last, tileID):
				_afterCellsEdited(_activeLayer, cells)
		TOOL_LINE:
			var cells := Brushes.lineCells(start, last)
			if Brushes.line(_document, _history, _activeLayer, start, last, tileID):
				_afterCellsEdited(_activeLayer, cells)
		TOOL_SCATTER:
			var rect := _inclusiveRect(start, last)
			var choices := _scatterSet
			if choices.is_empty():
				choices = [tileID]
			if Brushes.randomFromSet(
				_document, _history, _activeLayer, rect, choices, _editorHud.scatterSeed()
			):
				_afterRectEdited(_activeLayer, rect)


func _paintStrokeCell(cell: Vector2i) -> void:
	if not _strokeOpen or _document == null:
		return
	if Brushes.paintPoint(_document, _history, cell, _editorHud.selectedTileID()):
		if not _strokeTouched.has(cell):
			_strokeTouched.append(cell)


func _afterCellsEdited(layerID: String, cells: Array[Vector2i]) -> void:
	if _document == null or cells.is_empty():
		return
	for cell in cells:
		_baker.markCellsDirty(_document, layerID, Rect2i(cell, Vector2i.ONE))
	_baker.flush(_document)
	_documentDirty = true
	_editorHud.setStatus("Changed %d %s cell%s. Ctrl+S saves." % [
		cells.size(), layerID, "" if cells.size() == 1 else "s",
	])


func _afterRectEdited(layerID: String, rect: Rect2i) -> void:
	if _document == null:
		return
	_baker.markCellsDirty(_document, layerID, rect)
	_baker.flush(_document)
	_documentDirty = true
	_editorHud.setStatus("Changed %s cells. Ctrl+S saves." % layerID)


func _inclusiveRect(from: Vector2i, to: Vector2i) -> Rect2i:
	var first := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var last := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y))
	return Rect2i(first, last - first + Vector2i.ONE)


func _pickCell(screenPosition: Vector2) -> Variant:
	if _document == null or not _document.layers.has(_activeLayer):
		return null
	var displayRect := _display.get_global_rect()
	var bufferSize := Vector2(_viewport.size)
	if displayRect.size.x <= 0.0 or displayRect.size.y <= 0.0 or bufferSize.x <= 0.0 or bufferSize.y <= 0.0:
		return null
	var scale := minf(displayRect.size.x / bufferSize.x, displayRect.size.y / bufferSize.y)
	var drawnSize := bufferSize * scale
	var drawnOrigin := displayRect.position + (displayRect.size - drawnSize) * 0.5
	if not Rect2(drawnOrigin, drawnSize).has_point(screenPosition):
		return null
	var viewportPoint := (screenPosition - drawnOrigin) / scale
	var curvature := float(_framing.get(WorldMapGroundUniforms.K_CURVATURE, 0.0))
	return (
		SurfacePick.pickCel(_editorCamera, viewportPoint, curvature, _ground.regionRect())
		if _activeLayerIsCelGrade()
		else SurfacePick.pickTile(_editorCamera, viewportPoint, curvature, _ground.regionRect())
	)


func _updateGrid() -> void:
	if _ground == null:
		return
	var material := _ground.material_override as ShaderMaterial
	var visible := _document != null and _activeTool != TOOL_NAVIGATE and _layerEditable(_activeLayer)
	SurfacePick.applyGrid(material, _ground.regionRect(), _cursorCell, _activeLayerIsCelGrade(), visible)
	if visible and _tileGrid != null:
		_tileGrid.visible = false


func _activeLayerIsCelGrade() -> bool:
	if _document == null or not _document.layers.has(_activeLayer):
		return false
	return str((_document.layers[_activeLayer] as Dictionary).get("GRID_KIND", Tilesets.GRID_TILE)) == Tilesets.GRID_CEL


func _layerEditable(layerID: String) -> bool:
	if _document == null or not _document.layers.has(layerID):
		return false
	var block: Dictionary = _document.layers[layerID]
	return str(block.get("KIND", "")) == MapDataScript.KIND_GRID and Tilesets.has(str(block.get("TILESET", "")))


func _openDocumentForRegion(regionID: String) -> void:
	_history.clear()
	_document = Regions.tileDataFor(regionID)
	_documentPath = Regions.tileDataPathFor(regionID) if _document != null else ""
	_documentDirty = false
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
	for layer in LAYERS:
		var id := str((layer as Dictionary)["id"])
		_editorHud.setLayerEnabled(id, _layerEditable(id))
	if _document == null:
		_editorHud.setTileChoices([])
		_editorHud.setStatus("%s is a painted preview; choose an authored region to edit." % regionID)
		_updateGrid()
		return
	var texture := _baker.bake(_document)
	if texture == null:
		_editorHud.setStatus("Could not bake authored region %s." % regionID)
		return
	_regionTiles = Vector2(_document.size_tiles)
	_regionMapPx = Baker.pixelSizeOf(_document)
	_ground.configure(
		_regionTiles, texture, _framing, _document.fog_color, _document.void_color
	)
	_ground.configureCloudShadows(_regionMapPx, str(_framing[WorldMapGroundUniforms.K_CLOUDS]))
	if not _layerEditable(_activeLayer):
		for layer in LAYERS:
			var id := str((layer as Dictionary)["id"])
			if _layerEditable(id):
				_activeLayer = id
				break
	_editorHud.setActiveLayer(_layerIndex(_activeLayer))
	_refreshTileChoices()
	_editorHud.setStatus("Editing %s (%s)." % [regionID, _documentPath])


func _saveDocument() -> void:
	if _document == null or _documentPath.is_empty():
		if _editorHud != null:
			_editorHud.setStatus("No authored document is open.")
		return
	var sourceSaved := _document.saveTo(_documentPath)
	var bakeSaved := _baker.saveTo(Baker.generatedPathFor(_document.region_name))
	_documentDirty = not (sourceSaved and bakeSaved)
	_editorHud.setStatus(
		"Saved source and generated texture." if not _documentDirty
		else "Save failed; source and generated texture were not both written."
	)


func _refreshTileChoices() -> void:
	var selected := _editorHud.selectedTileID() if _editorHud.tileOption != null else ""
	var ids: Array[String] = []
	if _document != null and _document.layers.has(_activeLayer):
		var tilesetID := str((_document.layers[_activeLayer] as Dictionary).get("TILESET", ""))
		var reference := Tilesets.tilesetFor(tilesetID)
		for tile in reference.get("TILES", []):
			ids.append(str((tile as Dictionary)["ID"]))
	_editorHud.setTileChoices(ids, selected)
	_scatterSet.clear()
	if ids.has(selected):
		_scatterSet.append(selected)
	elif not ids.is_empty():
		_scatterSet.append(ids[0])
	_stampPattern = []


func _terrainByIDForActiveLayer() -> Dictionary:
	var result := {}
	if _document == null or not _document.layers.has(_activeLayer):
		return result
	var tilesetID := str((_document.layers[_activeLayer] as Dictionary).get("TILESET", ""))
	for tile in Tilesets.tilesetFor(tilesetID).get("TILES", []):
		result[str((tile as Dictionary)["ID"])] = str((tile as Dictionary).get("TERRAIN", ""))
	return result


func _layerIndex(id: String) -> int:
	for i in LAYERS.size():
		if str(LAYERS[i]["id"]) == id:
			return i
	return -1


func _onLayerSelected(index: int) -> void:
	if index < 0 or index >= LAYERS.size():
		return
	_activeLayer = str(LAYERS[index]["id"])
	_editorHud.setActiveLayer(index)
	_cursorCell = null
	_refreshTileChoices()
	_editorHud.setStatus(
		"Editing %s." % _activeLayer if _layerEditable(_activeLayer)
		else "%s has no tileset yet." % _activeLayer
	)


func _onToolSelected(index: int) -> void:
	if index < 0 or index >= TOOLS.size():
		return
	_activeTool = str(TOOLS[index]["id"])
	_gestureStart = null
	if _strokeOpen:
		_strokeOpen = false
		_history.endStroke()
	_editorHud.setStatus("Tool: %s" % str(TOOLS[index]["label"]))


func _onLayerVisibilityToggled(_id: String, _on: bool) -> void:
	# Phase A has nothing to hide -- ground, props and clouds are not layers a toggle reaches
	# into yet. The HUD row already holds its own state; nothing downstream reads it until a
	# later phase gives a layer something visibility can act on.
	pass


func _onLayerLockToggled(id: String, on: bool) -> void:
	_layerLocked[id] = on


## Test and tooling accessors. Reaching into `_activeLayer` etc. directly would work too --
## GDScript does not enforce the underscore as real privacy -- but a named accessor is what
## keeps `probe_editor_shell.gd` readable as intent rather than as field-poking.
func activeLayerID() -> String:
	return _activeLayer


func activeToolID() -> String:
	return _activeTool


func lastRoutedLayer() -> String:
	return _lastRoutedLayer


func routeCount(id: String) -> int:
	return int(_routeCount.get(id, 0))


func isLayerLocked(id: String) -> bool:
	return bool(_layerLocked.get(id, false))


func setActiveLayerID(id: String) -> void:
	_onLayerSelected(_layerIndex(id))


func setActiveToolID(id: String) -> void:
	for i in TOOLS.size():
		if str(TOOLS[i]["id"]) == id:
			_onToolSelected(i)
			return


func setLayerLocked(id: String, locked: bool) -> void:
	_layerLocked[id] = locked
