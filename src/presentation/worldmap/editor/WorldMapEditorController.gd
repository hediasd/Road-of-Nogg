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
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
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
## RE-WIDENED AT GATE 3 (docs/plans/reviews/worldmap-hex-gate-3.md) from two rows to five. The
## trim above was right when the only data model was tile grades; WMH-7, WMH-8 and WMH-10 then
## built three more layer kinds that the map could store, export and undo but that this table
## could not name -- so the editor could paint ground and nothing else. The three added here are
## exactly those, no more: each one has a data model, a tool and a bake path already.
## WIDENED AGAIN BY HXB-10 to carry the battlefield. `tactical` is a grid layer like ground and
## overlay, but its values come from `WorldMapTacticalLayer`'s ledger rather than from a tileset:
## it stores what a cell means to a battle, not what it looks like. That is the one place this
## table's "a grid layer is painted from a tileset" assumption does not hold, and the three
## kind-dispatching functions below each carry the matching exception rather than the assumption
## being loosened for every grid layer.
const LAYERS := [
	{"id": "ground", "label": "Ground", "enabled": false},
	{"id": "overlay", "label": "Overlay (roads)", "enabled": false},
	{"id": LAYER_HEIGHTS, "label": "Terrain height", "enabled": false},
	{"id": LAYER_OBJECTS, "label": "Objects", "enabled": false},
	{"id": LAYER_DETAIL, "label": "Detail (triangles)", "enabled": false},
	{"id": LAYER_TACTICAL, "label": "Tactical (battle)", "enabled": false},
]

## The three layers a hex document does not start with and that their own first edit creates.
## Keyed by id, valued by the kind each is created as -- which is what lets a row be REACHABLE
## and EMPTY at the same time, the distinction `_layerEditable` and `_layerPopulated` split
## between them. A layer is not conjured onto every opened document: `temp2_authored` is square,
## and a height field or a detail fan on a square map would be storage for a lattice it does not
## have.
const AUTHORED_HEX_LAYERS := {
	LAYER_HEIGHTS: MapDataScript.KIND_HEIGHTS,
	LAYER_OBJECTS: MapDataScript.KIND_LIST,
	LAYER_DETAIL: MapDataScript.KIND_DETAIL,
	LAYER_TACTICAL: MapDataScript.KIND_GRID,
}

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
## WMH-10B. One tool per layer kind that had none, rather than one tool per verb: a sculpt is a
## drag, a placement is a click and a triangle paint is a drag, and each reads the value row for
## WHICH raise, WHICH object or WHICH tile it applies. Three tools for three kinds keeps the tool
## list a list of gestures rather than a list of commands.
const TOOL_SCULPT := "sculpt"
const TOOL_PLACE := "place"
const TOOL_DETAIL := "paintTriangle"
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
	{"id": TOOL_SCULPT, "label": "Sculpt"},
	{"id": TOOL_PLACE, "label": "Place object"},
	{"id": TOOL_DETAIL, "label": "Paint triangle"},
]

## What a brand new hex document is created with. There is exactly one hex tileset in the
## catalog right now (WMH-2's 32 px extraction), so "New" has nothing to choose between yet --
## when a second one exists this becomes a picker, not a rewrite of `_newDocument`.
const LAYER_HEIGHTS := WorldMapHeightField.DEFAULT_LAYER
const LAYER_OBJECTS := WorldMapObjectLayer.DEFAULT_LAYER
const LAYER_DETAIL := "detail"
const LAYER_TACTICAL := WorldMapTacticalLayer.DEFAULT_LAYER

## What the value row offers over a height layer. A step per click rather than a target height,
## because sculpting is done by repetition -- and both signs are here rather than behind a
## modifier, so lowering is as reachable as raising and neither needs a key to be discovered.
## `SCULPT_FLATTEN` is the exception that is not a step: it levels every cell a stroke touches to
## the height of the cell the stroke STARTED on, which is what a flatten tool is for.
const SCULPT_FLATTEN := "flatten"
const SCULPT_STEPS := [
	{"label": "Raise  +1.00", "value": "1.0"},
	{"label": "Raise  +0.50", "value": "0.5"},
	{"label": "Raise  +0.25", "value": "0.25"},
	{"label": "Lower  -0.25", "value": "-0.25"},
	{"label": "Lower  -0.50", "value": "-0.5"},
	{"label": "Lower  -1.00", "value": "-1.0"},
	{"label": "Flatten to start", "value": SCULPT_FLATTEN},
]

## What the value row offers over the object layer. A fixed list, deliberately: an object-kind
## palette is named out of scope in WMH-10B, and these are the two kinds `WorldMapSceneExport`
## already builds bodies for. `OBJECT_REMOVE` rides in the same row for the reason "Erase (-)"
## does on the tile row -- removing is a choice of what to apply, not a tool of its own.
const OBJECT_REMOVE := "remove"
const OBJECT_KINDS := ["house", "tower"]

const DEFAULT_HEX_TILESET := "temp2_hex32_ground"
## The region whose palette and place colours a new hex document borrows, matching the tileset
## above's own `PALETTE_REGION` -- a new map starts looking like the place its art came from
## rather than an arbitrary grey.
const DEFAULT_HEX_PALETTE_REGION := "temp2"

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
## Which tool opened the stroke that is currently open. A tile stroke, a sculpt and a triangle
## paint all end differently -- one invalidates cells, one rebuilds the terrain surface -- and
## `_endToolGesture` has only the open stroke to go on, since the active tool can change under a
## held button.
var _strokeKind := ""
## The vertices a sculpt stroke has already moved, and the height it started at. Each vertex is
## raised AT MOST ONCE per stroke: three hexes share every vertex, so a drag across neighbouring
## cells would otherwise raise the shared ones twice and leave a ridge along the drag.
var _sculptVertices: Dictionary = {}
var _sculptBase := 0.0
## The editor-only preview of the object layer, rebuilt whenever objects or terrain move. Built
## through `WorldMapSceneExport.buildObjects` with a null scene owner -- the case that function
## already documents for a preview that is never packed -- so what the editor shows and what an
## export ships are the same construction, not two.
var _objectsPreview: Node3D
## `_history.undoCount()` AT THE LAST SAVE, not a bool any call site sets. See `_isDocumentDirty`
## -- WMH-5's own risk section calls out a dirty flag missing a mutation path as the danger, and
## the fix is to have nothing set it at all: every mutation already goes through `_history`
## (that file's own class note), so deriving dirtiness from its depth cannot miss a path a manual
## flag could.
var _savedUndoDepth := 0
## The action a New/Open/region-switch is waiting on while the open document is dirty, or an
## invalid `Callable` when nothing is pending. See `_guardDirty`.
var _pendingDiscardAction: Callable = Callable()
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
	_editorHud.setDirty(_isDocumentDirty())


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
	_editorHud.buildDocumentControls(
		_newLatticeChoices(), _requestNewDocument, _requestOpenDocument, _requestSaveAsDocument,
		_confirmDiscard, _cancelDiscard
	)
	_editorHud.setOpenChoices(_availableDocumentNames())

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


## Guarded by `_guardDirty` rather than the auto-save this used to do: silently saving on the
## user's behalf is its own way to lose work, if what they actually wanted was to abandon a bad
## edit rather than commit it. `previousIndex` is restored on the dropdown when the switch is
## deferred behind a confirmation -- the `OptionButton` has already moved to `index` by the time
## this signal fires (Godot updates a control's own state before emitting), and it must not keep
## showing a region the document has not actually switched to yet.
func _onRegionSelected(index: int) -> void:
	var ids := RegionCatalog.ids()
	if index < 0 or index >= ids.size():
		return
	var previousIndex := ids.find(_regionID)
	_guardDirty(_performRegionSwitch.bind(index))
	if _pendingDiscardAction.is_valid() and previousIndex >= 0:
		_hud.regionOption.selected = previousIndex


func _performRegionSwitch(index: int) -> void:
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
		elif _strokeOpen and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			# A triangle stroke follows the POINTER, not the cell under it: dragging within one
			# hex crosses fan slots without ever changing cell, and following the cell would
			# paint the first slot and then nothing.
			if _strokeKind == TOOL_DETAIL:
				_paintTriangleAt(motion.position)
			elif _cursorCell != null:
				if _strokeKind == TOOL_SCULPT:
					_sculptCell(_cursorCell as Vector2i)
				else:
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
		KEY_E:
			if not key.ctrl_pressed:
				super._unhandled_key_input(event)
				return
			if key.shift_pressed:
				_exportBattleMap()
			else:
				_exportScene()
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
	if not _toolFitsLayer(_activeTool, _activeLayer):
		_editorHud.setStatus("%s edits %s layers; '%s' is a %s layer." % [
			_toolLabel(_activeTool), _kindLabel(_toolLayerKind(_activeTool)),
			_activeLayer, _kindLabel(_activeLayerKind()),
		])
		return
	# Before `_pickCell`, because a triangle is not a cell: the fan slot comes from WHERE inside
	# the hex the pointer is, which the cell alone has already thrown away.
	if _activeTool == TOOL_DETAIL:
		_beginDetailStroke(screenPosition)
		return
	_cursorCell = _pickCell(screenPosition)
	if _cursorCell == null:
		_editorHud.setStatus("No map cell under the pointer.")
		return
	var cell := _cursorCell as Vector2i
	# The battlefield layer is created by its first edit, the same way the height, object and
	# detail layers are -- a document does not carry an empty one just for having been opened.
	if _activeLayer == LAYER_TACTICAL and not _document.layers.has(LAYER_TACTICAL):
		WorldMapTacticalLayer.ensureLayer(_document, LAYER_TACTICAL)
		_refreshLayerRows()
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
		TOOL_SCULPT:
			_beginSculptStroke(cell)
		TOOL_PLACE:
			_placeOrEditObject(cell)
		TOOL_RECTANGLE, TOOL_LINE, TOOL_SCATTER:
			_gestureStart = cell


func _endToolGesture(screenPosition: Vector2) -> void:
	if _strokeOpen:
		_strokeOpen = false
		var committed := Brushes.endStroke(_history)
		var kind := _strokeKind
		_strokeKind = ""
		_sculptVertices.clear()
		if committed:
			if kind == TOOL_SCULPT:
				_afterHeightsEdited()
			else:
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
			# `Brushes.line()` already reads `_document.layout` and does the cube-lerp itself on
			# a hex map; this call is only for the cell LIST `_afterCellsEdited` invalidates, and
			# it must pass the same flag or it would name the square Bresenham path's cells while
			# the hex path's own cells are what actually got painted.
			var hex := _document.layout == MapDataScript.LAYOUT_HEX_FLAT
			var cells := Brushes.lineCells(start, last, hex)
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


## Sculpting. The stroke raises (or lowers) every vertex of every cell it crosses, once each --
## see `_sculptVertices` for why once matters on a lattice where three hexes share a vertex.
func _beginSculptStroke(cell: Vector2i) -> void:
	HeightField.ensureLayer(_document, LAYER_HEIGHTS)
	_history.beginStroke(LAYER_HEIGHTS)
	_strokeOpen = true
	_strokeKind = TOOL_SCULPT
	_strokeTouched.clear()
	_sculptVertices.clear()
	# Sampled BEFORE the first cell is touched, so "flatten to start" levels to the ground the
	# author put the pointer on rather than to whatever the first step has already made of it.
	_sculptBase = HeightField.centreHeight(_document, cell, LAYER_HEIGHTS)
	_sculptCell(cell)


func _sculptCell(cell: Vector2i) -> void:
	if not _strokeOpen or _document == null:
		return
	var choice := _editorHud.selectedValue()
	var flatten := choice == SCULPT_FLATTEN
	var step := 0.0 if flatten else float(choice)
	for vertex in HeightField.cellVertices(cell):
		if _sculptVertices.has(vertex):
			continue
		_sculptVertices[vertex] = true
		var target := (
			_sculptBase if flatten
			else HeightField.heightAt(_document, vertex, LAYER_HEIGHTS) + step
		)
		_history.paintHeight(_document, vertex, target)
	if not _strokeTouched.has(cell):
		_strokeTouched.append(cell)


## Placing. One click does all three verbs this tool has, chosen by what is already under it:
## an empty cell takes the selected kind, an occupied one TURNS by a facing step, and the Remove
## entry in the value row deletes. No modifier keys -- see `OBJECT_REMOVE`.
func _placeOrEditObject(cell: Vector2i) -> void:
	WorldMapObjectLayer.ensureLayer(_document, LAYER_OBJECTS)
	var existing := _objectAt(cell)
	var choice := _editorHud.selectedValue()
	_history.beginStroke(LAYER_OBJECTS)
	var message := ""
	if choice == OBJECT_REMOVE:
		if existing.is_empty():
			message = "No object at %s to remove." % cell
		else:
			var id := str(existing[WorldMapObjectLayer.K_ID])
			_history.removeObject(_document, id)
			message = "Removed %s from %s." % [id, cell]
	elif existing.is_empty():
		var record := _history.placeObject(_document, choice, cell)
		message = (
			"Placed %s at %s." % [str(record[WorldMapObjectLayer.K_ID]), cell]
			if not record.is_empty() else "Could not place at %s." % cell
		)
	else:
		var id := str(existing[WorldMapObjectLayer.K_ID])
		var facing := int(existing[WorldMapObjectLayer.K_FACING]) + 1
		_history.setObjectFacing(_document, id, facing)
		message = "Turned %s to facing %d." % [id, posmod(facing, WorldMapObjectLayer.FACINGS)]
	if _history.endStroke():
		_afterObjectsEdited()
	_editorHud.setStatus(message)


func _objectAt(cell: Vector2i) -> Dictionary:
	for record in WorldMapObjectLayer.items(_document, LAYER_OBJECTS):
		if WorldMapObjectLayer.cellOf(record as Dictionary) == cell:
			return record
	return {}


## Painting a sub-triangle. The layer is created by its first paint, against the ground's own
## tileset -- see `_groundTilesetID`.
func _beginDetailStroke(screenPosition: Vector2) -> void:
	if not _document.layers.has(_activeLayer):
		_document.addDetailLayer(_activeLayer, _groundTilesetID())
		_refreshLayerRows()
		_refreshValueChoices()
	_history.beginStroke(_activeLayer)
	_strokeOpen = true
	_strokeKind = TOOL_DETAIL
	_strokeTouched.clear()
	_paintTriangleAt(screenPosition)


func _paintTriangleAt(screenPosition: Vector2) -> void:
	if not _strokeOpen or _document == null:
		return
	var target = _pickTriangle(screenPosition)
	if target == null:
		return
	var slot := target as Vector3i
	var cell := Vector2i(slot.x, slot.y)
	_cursorCell = cell
	if Brushes.paintTriangle(
		_document, _history, _activeLayer, cell, slot.z, _editorHud.selectedValue()
	):
		if not _strokeTouched.has(cell):
			_strokeTouched.append(cell)


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
	_editorHud.setStatus("Changed %d %s cell%s. Ctrl+S saves." % [
		cells.size(), layerID, "" if cells.size() == 1 else "s",
	])


## After a sculpt. Nothing about the BAKE changes -- heights are geometry, not pixels -- so this
## rebuilds the ground SURFACE instead, through the same `configureGround` the export uses, and
## then the object preview, because objects anchored to the terrain have just moved with it.
##
## Without this the tool would be the failure WMH-10B named as its second risk: an edit that is
## recorded, undoable and completely invisible.
func _afterHeightsEdited() -> void:
	if _document == null:
		return
	var texture := _baker.texture()
	if texture != null:
		SceneExport.configureGround(_ground, _document, texture, _framing)
	_rebuildObjectPreview()
	_refreshLayerRows()
	_editorHud.setStatus("Sculpted %d cell%s. Ctrl+S saves." % [
		_strokeTouched.size(), "" if _strokeTouched.size() == 1 else "s",
	])


func _afterObjectsEdited() -> void:
	_rebuildObjectPreview()
	_refreshLayerRows()


## The editor's view of the object layer. Built with a null scene owner -- the case
## `WorldMapSceneExport.buildObjects` already documents for a preview that is never packed -- so
## the editor and the export place a building by the same code, not by two that agree today.
func _rebuildObjectPreview() -> void:
	if _map == null:
		return
	if _objectsPreview != null and is_instance_valid(_objectsPreview):
		_objectsPreview.queue_free()
	_objectsPreview = null
	if _document == null or not _document.layers.has(LAYER_OBJECTS):
		return
	_objectsPreview = Node3D.new()
	_objectsPreview.name = "EditorObjectPreview"
	_map.add_child(_objectsPreview)
	SceneExport.buildObjects(
		_objectsPreview, _document, null,
		HeightField.samplerFor(_document) if HeightField.has(_document) else Callable()
	)


func _afterRectEdited(layerID: String, rect: Rect2i) -> void:
	if _document == null:
		return
	_baker.markCellsDirty(_document, layerID, rect)
	_baker.flush(_document)
	_editorHud.setStatus("Changed %s cells. Ctrl+S saves." % layerID)


func _inclusiveRect(from: Vector2i, to: Vector2i) -> Rect2i:
	var first := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var last := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y))
	return Rect2i(first, last - first + Vector2i.ONE)


## Where a screen position lands inside the rendered viewport, or null when it lands outside the
## drawn image. Extracted in WMH-10B so the triangle pick and the cell pick share one definition
## of that mapping rather than each carrying its own copy of the letterboxing arithmetic.
func _viewportPoint(screenPosition: Vector2) -> Variant:
	var displayRect := _display.get_global_rect()
	var bufferSize := Vector2(_viewport.size)
	if displayRect.size.x <= 0.0 or displayRect.size.y <= 0.0 or bufferSize.x <= 0.0 or bufferSize.y <= 0.0:
		return null
	var scale := minf(displayRect.size.x / bufferSize.x, displayRect.size.y / bufferSize.y)
	var drawnSize := bufferSize * scale
	var drawnOrigin := displayRect.position + (displayRect.size - drawnSize) * 0.5
	if not Rect2(drawnOrigin, drawnSize).has_point(screenPosition):
		return null
	return (screenPosition - drawnOrigin) / scale


## The region-local point under a screen position, on the terrain the renderer actually draws.
## `_pickCell` answers WHICH CELL; this answers WHERE, which is what a sub-triangle needs -- a fan
## triangle is a sixth of a hex, and the cell alone cannot say which sixth.
func _pickLocalPoint(screenPosition: Vector2) -> Variant:
	if _document == null:
		return null
	var viewportPoint = _viewportPoint(screenPosition)
	if viewportPoint == null:
		return null
	var region := _ground.regionRect()
	var curvature := float(_framing.get(WorldMapGroundUniforms.K_CURVATURE, 0.0))
	var sampler := (
		HeightField.pointSamplerFor(_document) if HeightField.has(_document) else Callable()
	)
	var point = (
		SurfacePick.surfacePointOnTerrain(
			_editorCamera, viewportPoint as Vector2, curvature, sampler, region.position
		)
		if sampler.is_valid()
		else SurfacePick.surfacePoint(_editorCamera, viewportPoint as Vector2, curvature)
	)
	if point == null:
		return null
	var world := point as Vector3
	var local := Vector2(world.x, world.z) - region.position
	if local.x < 0.0 or local.y < 0.0 or local.x >= region.size.x or local.y >= region.size.y:
		return null
	return local


## The cell and fan triangle under a screen position, as `(col, row, slot)`, or null. Bounded by
## the LATTICE for the reason Gate 1's Finding 1 gives: a point in the region's margin resolves to
## a cell the map does not have, and answering with it is how a click gets silently refused later.
func _pickTriangle(screenPosition: Vector2) -> Variant:
	var local = _pickLocalPoint(screenPosition)
	if local == null:
		return null
	var target := HeightField.triangleAt(local as Vector2)
	if target.z < 0:
		return null
	if not WorldMapHexGrid.contains(
		Vector2i(target.x, target.y), _document.size_tiles.x, _document.size_tiles.y
	):
		return null
	return target


func _pickCell(screenPosition: Vector2) -> Variant:
	if _document == null:
		return null
	if not _document.layers.has(_activeLayer) and not _layerEditable(_activeLayer):
		return null
	var viewportPointOrNull = _viewportPoint(screenPosition)
	if viewportPointOrNull == null:
		return null
	var viewportPoint := viewportPointOrNull as Vector2
	var curvature := float(_framing.get(WorldMapGroundUniforms.K_CURVATURE, 0.0))
	if _document.layout == MapDataScript.LAYOUT_HEX_FLAT:
		# No cel grade on a hex map -- `pickCel` is square-only (hexagons do not subdivide into
		# smaller hexagons; sub-tile detail is the six triangles WMH-10 fans a hex into, and
		# `pickTile` does not resolve those). `_document.size_tiles` bounds the pick to cells the
		# LATTICE actually holds, not the region -- see Gate 1's Finding 1: a margin cell used to
		# come back as an ordinary answer that a paint then silently refused.
		# The height sampler is what keeps the cursor on a hill rather than on the flat plane
		# under it -- and it is the same `WorldMapHeightField.sample` the surface mesh was built
		# from, so picking and rendering cannot disagree about where the ground is.
		return SurfacePick.pickTile(
			_editorCamera, viewportPoint, curvature, _ground.regionRect(), true,
			_document.size_tiles,
			HeightField.pointSamplerFor(_document) if HeightField.has(_document) else Callable()
		)
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
	var hex := _document != null and _document.layout == MapDataScript.LAYOUT_HEX_FLAT
	var lattice := _document.size_tiles if hex else Vector2i.ZERO
	SurfacePick.applyGrid(
		material, _ground.regionRect(), _cursorCell, _activeLayerIsCelGrade(), visible, hex, lattice
	)
	if visible and _tileGrid != null:
		_tileGrid.visible = false


func _activeLayerIsCelGrade() -> bool:
	if _document == null or not _document.layers.has(_activeLayer):
		return false
	return str((_document.layers[_activeLayer] as Dictionary).get("GRID_KIND", Tilesets.GRID_TILE)) == Tilesets.GRID_CEL


## Which layer kind a tool edits, or "" for one that edits nothing (Navigate).
##
## WMH-10B needs this because the layer rows it opened made a mismatch REACHABLE for the first
## time. `WorldMapTileData.setCell` already refuses a non-grid layer -- nothing corrupts -- but it
## refuses by returning `false`, so painting on a height layer would do exactly nothing and say
## exactly nothing. That silence is the item's own named risk, and Gate 1 found its twin in the
## picker. The guard exists for the MESSAGE; the data was never in danger.
func _toolLayerKind(toolID: String) -> String:
	match toolID:
		TOOL_NAVIGATE:
			return ""
		TOOL_SCULPT:
			return MapDataScript.KIND_HEIGHTS
		TOOL_PLACE:
			return MapDataScript.KIND_LIST
		TOOL_DETAIL:
			return MapDataScript.KIND_DETAIL
		_:
			return MapDataScript.KIND_GRID


func _toolFitsLayer(toolID: String, layerID: String) -> bool:
	var wanted := _toolLayerKind(toolID)
	if wanted.is_empty():
		return true
	if _document == null:
		return false
	if _document.layers.has(layerID):
		return str((_document.layers[layerID] as Dictionary).get("KIND", "")) == wanted
	return str(AUTHORED_HEX_LAYERS.get(layerID, MapDataScript.KIND_GRID)) == wanted


func _toolLabel(toolID: String) -> String:
	for tool in TOOLS:
		if str((tool as Dictionary)["id"]) == toolID:
			return str((tool as Dictionary)["label"])
	return toolID


func _kindLabel(kind: String) -> String:
	match kind:
		MapDataScript.KIND_HEIGHTS:
			return "terrain height"
		MapDataScript.KIND_LIST:
			return "object"
		MapDataScript.KIND_DETAIL:
			return "detail"
		_:
			return "tile"


## Can a tool act on this layer? Kind-aware since WMH-10B: it used to answer "is it a grid layer
## with a known tileset", which is why a height, object or detail layer could never become the
## active one no matter what the map stored.
##
## The last clause is the one that needs saying: a layer a hex document does not have YET is
## still editable, because the three authored layers are created by their own first edit rather
## than conjured onto every document that is opened. Reachable and empty are different states --
## `_layerPopulated` is the one that decides how the row READS.
func _layerEditable(layerID: String) -> bool:
	if _document == null:
		return false
	if _document.layers.has(layerID):
		var block: Dictionary = _document.layers[layerID]
		var kind := str(block.get("KIND", ""))
		# The tactical layer is a grid layer with no tileset -- its values are ledger ids, not
		# tile art -- so the tileset test below would call the battlefield uneditable.
		if layerID == LAYER_TACTICAL:
			return _document.layout == MapDataScript.LAYOUT_HEX_FLAT
		if kind == MapDataScript.KIND_GRID or kind == MapDataScript.KIND_DETAIL:
			return Tilesets.has(str(block.get("TILESET", "")))
		return kind == MapDataScript.KIND_HEIGHTS or kind == MapDataScript.KIND_LIST
	return (
		AUTHORED_HEX_LAYERS.has(layerID)
		and _document.layout == MapDataScript.LAYOUT_HEX_FLAT
	)


## Does this layer hold anything yet? What the layer row's "(empty)" label and its dimming read,
## and deliberately NOT the same question as `_layerEditable`: a fresh hex map has a reachable,
## empty height layer, and a row that claimed otherwise in either direction would be the dishonest
## one WMH-5 wrote the "(empty)" marker to avoid.
func _layerPopulated(layerID: String) -> bool:
	if _document == null or not _document.layers.has(layerID):
		return false
	var block: Dictionary = _document.layers[layerID]
	var kind := str(block.get("KIND", ""))
	# A tactical layer holds something once a cell has been painted onto it, which is a question
	# about its cells rather than about a tileset it deliberately has none of.
	if layerID == LAYER_TACTICAL:
		return WorldMapTacticalLayer.playableCount(_document, layerID) > 0
	if kind == MapDataScript.KIND_GRID or kind == MapDataScript.KIND_DETAIL:
		return Tilesets.has(str(block.get("TILESET", "")))
	return true


## The kind the active layer is, or -- for one of the three that its first edit creates -- the
## kind it WILL be. The value row has to offer sculpt steps over a height layer that does not
## exist yet, or the tool that would create it has nothing to apply.
func _activeLayerKind() -> String:
	if _document == null:
		return MapDataScript.KIND_GRID
	if _document.layers.has(_activeLayer):
		return str((_document.layers[_activeLayer] as Dictionary).get("KIND", MapDataScript.KIND_GRID))
	return str(AUTHORED_HEX_LAYERS.get(_activeLayer, MapDataScript.KIND_GRID))


func _refreshLayerRows() -> void:
	for layer in LAYERS:
		var id := str((layer as Dictionary)["id"])
		_editorHud.setLayerEnabled(id, _layerPopulated(id))


func _openDocumentForRegion(regionID: String) -> void:
	_history.clear()
	_savedUndoDepth = 0
	_document = Regions.tileDataFor(regionID)
	_documentPath = Regions.tileDataPathFor(regionID) if _document != null else ""
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
	if _document == null:
		for layer in LAYERS:
			_editorHud.setLayerEnabled(str((layer as Dictionary)["id"]), false)
		_editorHud.setTileChoices([])
		_editorHud.setStatus("%s is a painted preview; choose an authored region to edit." % regionID)
		_updateGrid()
		return
	_bakeAndDisplayDocument("Editing %s (%s)." % [regionID, _documentPath])


## Creates a fresh hex document at `lattice` cells -- an exact-fit size from WMH-2's own table,
## which is all the HUD offers, so a new map never has the margin question WMH-R1 already
## settled (void colour, not a terrain) before a single cell is painted -- named `name`, and
## opens it exactly as `_openDocumentForRegion` would open one from disk. `WorldMapBaker` learned
## hex geometry in WMH-5B, so the ground render is a real bake, not the provisional placeholder
## an earlier version of this function warned about.
func _newDocument(lattice: Vector2i, name: String) -> void:
	_history.clear()
	_savedUndoDepth = 0
	var doc := MapDataScript.create(name, lattice, MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = DEFAULT_HEX_TILESET
	doc.palette_region = DEFAULT_HEX_PALETTE_REGION
	doc.fog_color = Regions.fogColorFor(DEFAULT_HEX_PALETTE_REGION)
	doc.void_color = Regions.voidColorFor(DEFAULT_HEX_PALETTE_REGION)
	_document = doc
	_documentPath = MapDataScript.pathFor(name)
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
	_bakeAndDisplayDocument("New hex map '%s' (%s cells)." % [name, lattice])


## Opens a document BY NAME rather than by region id -- any file under `WorldMapTileData.
## AUTHORED_DIR`, whether or not `WorldMapRegionCatalog` names it. A document `_newDocument`
## creates has no catalog entry (exporting one into the catalog is WMH-6's job, not this one's),
## so "Open" cannot be the inherited region picker alone; this is the other half of the loop
## `_openDocumentForRegion` already covers for documents the catalog does know about.
func _openDocumentByName(name: String) -> void:
	_history.clear()
	_savedUndoDepth = 0
	_document = MapDataScript.loadFrom(MapDataScript.pathFor(name))
	_documentPath = MapDataScript.pathFor(name)
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
	if _document == null:
		_editorHud.setStatus("Could not open '%s'." % name)
		return
	_bakeAndDisplayDocument("Editing %s (%s)." % [name, _documentPath])


## The tail `_openDocumentForRegion`, `_newDocument` and `_openDocumentByName` all share once
## `_document` is set and cleared for a fresh start: bake, configure the ground, settle on an
## editable layer, refresh the tile list and the Open list. `statusMessage` is the one thing
## that differs between the three callers, so it is the only parameter.
func _bakeAndDisplayDocument(statusMessage: String) -> void:
	_refreshLayerRows()
	var texture := _baker.bake(_document)
	if texture == null:
		_editorHud.setStatus("Could not bake '%s'." % _document.region_name)
		return
	# `worldExtent()`, not `Vector2(size_tiles)` -- on a hex document `size_tiles` is columns and
	# rows, not world units, and only `worldExtent()` (already built in WMH-2) converts through
	# `WorldMapHexGrid.latticeExtent`. A no-op change for a square document, where the two agree.
	_regionTiles = _document.worldExtent()
	_regionMapPx = Baker.pixelSizeOf(_document)
	# Through `WorldMapSceneExport`'s own builder rather than calling `_ground.configure()`
	# directly -- the preview and the exported scene are then the SAME construction, so a map
	# cannot preview at one extent and ship at another. See that file's own note.
	SceneExport.configureGround(_ground, _document, texture, _framing)
	_ground.configureCloudShadows(_regionMapPx, str(_framing[WorldMapGroundUniforms.K_CLOUDS]))
	_rebuildObjectPreview()
	if not _layerEditable(_activeLayer):
		for layer in LAYERS:
			var id := str((layer as Dictionary)["id"])
			if _layerEditable(id):
				_activeLayer = id
				break
	_editorHud.setActiveLayer(_layerIndex(_activeLayer))
	_refreshValueChoices()
	_editorHud.setOpenChoices(_availableDocumentNames())
	_editorHud.setStatus(statusMessage)


func _saveDocument() -> void:
	if _document == null or _documentPath.is_empty():
		if _editorHud != null:
			_editorHud.setStatus("No authored document is open.")
		return
	var sourceSaved := _document.saveTo(_documentPath)
	var bakeSaved := _baker.saveTo(Baker.generatedPathFor(_document.region_name))
	if sourceSaved and bakeSaved:
		_savedUndoDepth = _history.undoCount()
	_editorHud.setStatus(
		"Saved source and generated texture." if not _isDocumentDirty()
		else "Save failed; source and generated texture were not both written."
	)
	_editorHud.setOpenChoices(_availableDocumentNames())


## Exports the open document to a gameplay scene (Ctrl+E). Reports the export's own error text
## rather than a generic failure: every way this can fail -- an unsaved document, a bake Godot
## has not imported yet -- has a different fix, and the status line is the only place a user
## finds out which.
func _exportScene() -> void:
	var result := SceneExport.exportScene(_document, _framing)
	if bool(result.get("ok", false)):
		_editorHud.setStatus("Exported %s" % str(result["path"]))
		return
	_editorHud.setStatus("Export failed: %s" % str(result.get("error", "unknown")))


## Exports BOTH battle products together (Ctrl+Shift+E) -- the gameplay scene and the tactical
## map, from one document, stamped with one source identity. One action rather than two on
## purpose: exporting the halves separately is exactly how a scene ends up describing a document
## the map no longer matches.
##
## A refusal reaches the status line with the unsupported feature and its cell in it, because
## "unsupported" alone tells an author nothing about which hill to flatten.
func _exportBattleMap() -> void:
	var result := BattleExport.exportBoth(_document, _framing)
	if bool(result.get("ok", false)):
		_editorHud.setStatus("Exported battle map %s" % str(result["map_path"]))
		return
	_editorHud.setStatus("Battle export failed: %s" % str(result.get("error", "unknown")))


## Writes the open document under a different name and continues editing it under that name --
## the ordinary meaning of Save As, not a copy left behind under the old one.
func _saveDocumentAs(name: String) -> void:
	if _document == null or name.is_empty():
		return
	_document.region_name = name
	_documentPath = MapDataScript.pathFor(name)
	_saveDocument()


## Every `.json` under `WorldMapTileData.AUTHORED_DIR`, sorted -- what "Open" offers. Scanned
## from disk rather than read off `WorldMapRegionCatalog`, because a document `_newDocument`
## creates has no catalog entry until something exports it into one.
func _availableDocumentNames() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(MapDataScript.AUTHORED_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension() == "json":
			result.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## WMH-2's exact-fit table, unmodified -- see the HUD's own note on why "New" offers only these
## and not an arbitrary size.
func _newLatticeChoices() -> Array[Vector2i]:
	return WorldMapHexGrid.exactSquareLattices()


## Whether the open document has any edit since the last successful save, derived from
## `_history`'s own depth rather than a bool any call site sets -- see `_savedUndoDepth`'s own
## note on why that is the fix for the risk this item names.
func _isDocumentDirty() -> bool:
	return _document != null and _history.undoCount() != _savedUndoDepth


## Runs `action` immediately when nothing would be lost; otherwise defers it behind the HUD's
## discard-confirmation dialog, and `action` runs only if the user actually confirms. Every entry
## point that would replace or close the open document -- New, Open, and the inherited region
## picker -- goes through this, so "ask before discarding" cannot be forgotten at a future call
## site the way a manually-set dirty bool could be.
func _guardDirty(action: Callable) -> void:
	if not _isDocumentDirty():
		action.call()
		return
	_pendingDiscardAction = action
	_editorHud.promptDiscard()


func _confirmDiscard() -> void:
	var action := _pendingDiscardAction
	_pendingDiscardAction = Callable()
	if action.is_valid():
		action.call()


func _cancelDiscard() -> void:
	_pendingDiscardAction = Callable()


func _requestNewDocument() -> void:
	var lattice := _editorHud.selectedNewLattice()
	var name := _editorHud.documentNameField()
	if lattice == Vector2i.ZERO:
		_editorHud.setStatus("Choose a lattice size first.")
		return
	if name.is_empty():
		_editorHud.setStatus("Name the new map first.")
		return
	_guardDirty(_newDocument.bind(lattice, name))


func _requestOpenDocument() -> void:
	var name := _editorHud.selectedOpenName()
	if name.is_empty():
		_editorHud.setStatus("Nothing to open yet.")
		return
	_guardDirty(_openDocumentByName.bind(name))


## No guard: Save As never discards anything the open document held, it only chooses where the
## save goes.
func _requestSaveAsDocument() -> void:
	var name := _editorHud.documentNameField()
	if name.is_empty():
		_editorHud.setStatus("Name the document first.")
		return
	_saveDocumentAs(name)


## The value row, per layer kind -- WMH-10B. It was `_refreshTileChoices` and offered tile ids
## unconditionally, which is the specific thing that would have made a kind-aware
## `_layerEditable` produce a tool that silently paints nothing: a sculpt reading a tile id off a
## row that had none applies `float("")`, which is 0.0, which is a no-op no one is told about.
func _refreshValueChoices() -> void:
	var selected := _editorHud.selectedValue() if _editorHud.tileOption != null else ""
	# Dispatched on layer ID before kind, because the tactical layer shares KIND_GRID with ground
	# and overlay while taking its values from a ledger rather than a tileset. Erasing back to
	# "off the battlefield" is offered as a value, the same way the object row offers Remove:
	# unpainting is an edit and has to go through the same stroke and the same undo entry.
	if _activeLayer == LAYER_TACTICAL:
		_editorHud.setValueLabel("Terrain")
		var tacticalLabels: Array[String] = []
		var tacticalValues: Array[String] = []
		for terrainID: String in WorldMapTacticalLayer.knownTerrainIDs():
			tacticalLabels.append(terrainID.capitalize())
			tacticalValues.append(terrainID)
		tacticalLabels.append("Off board")
		tacticalValues.append(MapDataScript.EMPTY)
		_editorHud.setValueChoices(tacticalLabels, tacticalValues, selected)
		_scatterSet.clear()
		_stampPattern = []
		return
	match _activeLayerKind():
		MapDataScript.KIND_HEIGHTS:
			_editorHud.setValueLabel("Sculpt")
			var stepLabels: Array[String] = []
			var stepValues: Array[String] = []
			for step in SCULPT_STEPS:
				stepLabels.append(str((step as Dictionary)["label"]))
				stepValues.append(str((step as Dictionary)["value"]))
			_editorHud.setValueChoices(stepLabels, stepValues, selected)
			_scatterSet.clear()
			_stampPattern = []
		MapDataScript.KIND_LIST:
			_editorHud.setValueLabel("Object")
			var kindLabels: Array[String] = []
			var kindValues: Array[String] = []
			for kind in OBJECT_KINDS:
				kindLabels.append(str(kind).capitalize())
				kindValues.append(str(kind))
			kindLabels.append("Remove")
			kindValues.append(OBJECT_REMOVE)
			_editorHud.setValueChoices(kindLabels, kindValues, selected)
			_scatterSet.clear()
			_stampPattern = []
		_:
			_editorHud.setValueLabel("Tile")
			var ids: Array[String] = []
			if _document != null and _document.layers.has(_activeLayer):
				var tilesetID := str((_document.layers[_activeLayer] as Dictionary).get("TILESET", ""))
				for tile in Tilesets.tilesetFor(tilesetID).get("TILES", []):
					ids.append(str((tile as Dictionary)["ID"]))
			elif _activeLayerKind() == MapDataScript.KIND_DETAIL:
				# The detail layer its first paint will create borrows the ground's tileset, so
				# the row can offer tiles before the layer exists.
				for tile in Tilesets.tilesetFor(_groundTilesetID()).get("TILES", []):
					ids.append(str((tile as Dictionary)["ID"]))
			_editorHud.setTileChoices(ids, selected)
			_scatterSet.clear()
			if ids.has(selected):
				_scatterSet.append(selected)
			elif not ids.is_empty():
				_scatterSet.append(ids[0])
			_stampPattern = []


## The tileset a detail layer is created against: the ground's own, so a triangle painted over a
## hex is drawn from the same sheet the hex under it came from.
func _groundTilesetID() -> String:
	if _document != null and _document.layers.has("ground"):
		return str((_document.layers["ground"] as Dictionary).get("TILESET", DEFAULT_HEX_TILESET))
	return DEFAULT_HEX_TILESET


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
	_refreshValueChoices()
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


## WMH-5's own accessors, same reasoning as the block above: `probe_document_loop.gd` drives the
## document lifecycle through these names rather than through `_newDocument` etc. directly, and
## through `confirmPendingDiscard`/`cancelPendingDiscard` rather than the HUD's actual dialog --
## see `WorldMapEditorHud.promptDiscard`'s own note on why that dialog cannot be driven headless,
## and why that is not a gap in what gets tested: the STATE the dialog fronts is exactly what
## these expose.
func openDocument() -> WorldMapTileData:
	return _document


func documentPath() -> String:
	return _documentPath


func isDocumentDirty() -> bool:
	return _isDocumentDirty()


func hasPendingDiscard() -> bool:
	return _pendingDiscardAction.is_valid()


func confirmPendingDiscard() -> void:
	_confirmDiscard()


func cancelPendingDiscard() -> void:
	_cancelDiscard()


func requestNewDocument(lattice: Vector2i, name: String) -> void:
	_editorHud.newLatticeOption.selected = _newLatticeChoices().find(lattice)
	_editorHud.nameEdit.text = name
	_requestNewDocument()


func requestOpenDocument(name: String) -> void:
	var names := _availableDocumentNames()
	var index := names.find(name)
	if index < 0:
		return
	_editorHud.openOption.selected = index
	_requestOpenDocument()


func requestSaveAsDocument(name: String) -> void:
	_editorHud.nameEdit.text = name
	_requestSaveAsDocument()


func availableDocumentNames() -> Array[String]:
	return _availableDocumentNames()


func saveDocument() -> void:
	_saveDocument()


func layerIsEditable(id: String) -> bool:
	return _layerEditable(id)


## Returns the export's own `{ok, path}` / `{ok, error}` result rather than routing through the
## status line, so `probe_scene_export.gd` can assert WHY an export was refused and not just that
## it was.
func exportScene() -> Dictionary:
	return SceneExport.exportScene(_document, _framing)


## Both battle products from the open document, as `WorldMapBattleExport.exportBoth`'s own
## result. Same shape and same reason as `exportScene()` above: `probe_editor_export.gd` asserts
## WHICH unsupported feature refused a map, which a status string cannot carry.
func exportBattleMap() -> Dictionary:
	return BattleExport.exportBoth(_document, _framing)
