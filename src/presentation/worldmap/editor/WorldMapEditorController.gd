## The world map level editor: a document-first authoring scene with a neutral world stage,
## editor-only camera controls, and workspace chrome for layer and tool state.
##
## A fresh editor deliberately has no region, sky, clouds, props, lights or debug controls. The
## foundation stage supplies only a blank ground and `WorldMapEditorCamera`; New and Open are the
## routes that replace it with authored map content. This keeps old preview-world state from
## becoming accidental map data or obscuring the actual hex authoring workflow.
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
## receive them. Every
## mouse gesture and every navigation key this class owns is read here and applied to the
## camera through its plain methods (`orbitByScreenDelta`, `panBy`, `dollyBy`, `toggleOrtho`,
## `snapToContract`, `snapYaw`, `frameRegion`) -- never by relying on the camera to notice
## anything on its own. Left click routes to the active layer's tool instead of panning. `KEY_F`
## is claimed here and marked handled. Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes -- see
## `WorldMapEditHistory` for why they are wired here even though nothing feeds them yet.

extends Node

const EditorHudScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorHud.gd")
const ChromeScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd")
const WorkspaceActions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")
const WorkspaceGeometry = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceGeometry.gd")
const SavePointScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceSavePoint.gd")
const Footprint = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceFootprint.gd")
const PreviewScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspacePreview.gd")
const LayerViewScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceLayerView.gd")
const WorkspacePaths = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspacePaths.gd")
const DocumentIOScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceDocumentIO.gd")
const RecoveryScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceRecovery.gd")
const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")
const SurfacePick = preload("res://src/presentation/worldmap/editor/WorldMapSurfacePick.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const Regions = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const FoundationStage = preload("res://src/presentation/worldmap/editor/foundation/WorldMapEditorFoundationStage.gd")

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
	# Named for what it is: a rectangle of OFFSET cells, which on a hex lattice reads as a ragged
	# band rather than a tidy block. The hex-shaped area tool is the paint brush's own disc radius.
	{"id": TOOL_RECTANGLE, "label": "Rectangle (offset cells)"},
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

## What "New" starts a document on unless the author chooses otherwise in the dialog. The clean
## 15-frame starter rather than the 75-tile extraction: a new map should begin on art whose frames
## an author can actually tell apart. Opening an existing map never consults this -- a stored
## tileset id is the document's own and is not remapped.
const DEFAULT_HEX_TILESET := "temp2_hex32_starter"
## The region whose palette and place colours a new hex document borrows, matching the tileset
## above's own `PALETTE_REGION` -- a new map starts looking like the place its art came from
## rather than an arbitrary grey.
const DEFAULT_HEX_PALETTE_REGION := "temp2"

var _editorCamera: WorldMapEditorCamera
var _editorHud: WorldMapEditorHud
var _chrome: ChromeScript
var _viewport: SubViewport
var _display: TextureRect
var _map: Node3D
var _ground: WorldMapGround
var _framing: Dictionary = {}
var _regionTiles := Vector2(2.0, 2.0)
var _regionMapPx := Vector2i.ONE
var _regionID := ""
var _tileGrid: MeshInstance3D = null
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
## The save checkpoint, as a history REVISION rather than a stack depth -- see
## `WorldMapWorkspaceSavePoint` for the two ways the depth comparison this replaces reported a
## changed document as saved. Deriving dirtiness from the history rather than from a flag any call
## site sets is unchanged and still the point: every mutation already goes through `_history`, so
## nothing can edit the document without moving its revision.
var _savePoint := SavePointScript.new()
## The action a New/Open/region-switch is waiting on while the open document is dirty, or an
## invalid `Callable` when nothing is pending. See `_guardDirty`.
var _pendingDiscardAction: Callable = Callable()
var _scatterSet: Array[String] = []
var _pointerPosition := Vector2.ZERO
## The authoring grid's own toggle, so it is a decision an author makes rather than a side effect
## of which tool happens to be selected.
var _gridVisible := true
## Last values pushed to the header and inspector, so `_process` rewrites a label only when it
## actually changed rather than every frame.
var _shownDocumentLabel := ""
var _shownDirty := false
var _shownCursorCell := ""

## How many hex RINGS a paint or erase stamp covers. Zero is one cell; the workspace shows the
## cell COUNT rather than this number -- see `WorldMapWorkspaceFootprint.radiusLabel`.
var _brushRadius := 0
const MAX_BRUSH_RADIUS := 4
## The last cell a stroke actually painted, so the next pointer sample can be joined to it rather
## than leaving the cells between them unpainted on a fast drag.
var _lastPaintedCell: Variant = null
var _preview: PreviewScript
var _layerView := LayerViewScript.new()
## The bake shown while a layer is hidden. The canonical `_baker` always holds the COMPLETE map --
## it is what save and export write -- and this one never leaves the screen. See
## `WorldMapWorkspaceLayerView`'s class note.
var _previewBaker: WorldMapBaker = null

## Every file the editor reads or writes goes through this, so a probe can make a write fail
## without a real disk and without touching an authored map. See its own class note.
var _io := DocumentIOScript.new()
var _recovery := RecoveryScript.new()
## The exact listed snapshot that produced the open recovered document. It is retained until a
## successful save (or an explicit Discard), then only that entry is removed.
var _activeRecoveryEntry: Dictionary = {}
## Seconds the document has been dirty with no stroke and no further edit. Reset by every edit;
## read by the snapshot rule, which is the only thing that decides whether to write.
var _idleSeconds := 0.0
var _lastDirtyRevision := -1


func _ready() -> void:
	for layer in LAYERS:
		_layerLocked[str(layer["id"])] = false
		_routeCount[str(layer["id"])] = 0

	_buildFoundationStage()
	_buildEditorUi()
	_editorCamera.rememberRegion(_ground.regionRect())
	_editorHud.setStatus("Choose New or Open to begin building a hex map.")


func _process(delta: float) -> void:
	_editorHud.setOffContract(_editorCamera.offContractReason())
	_cursorCell = _pickCell(_pointerPosition)
	_updateGrid()
	_refreshPreview()
	_refreshDocumentReadouts()
	_tickRecovery(delta)


## The crash-snapshot timer. Counts only quiet, dirty time: any edit moves the revision and
## restarts the clock, a saved document never accumulates any, and an open stroke suspends it --
## so a snapshot is never taken of half a gesture. `WorldMapWorkspaceRecovery.shouldSnapshot` owns
## the rule itself; this only supplies the clock.
func _tickRecovery(delta: float) -> void:
	if _document == null:
		return
	var revision := _history.currentRevision()
	if revision != _lastDirtyRevision:
		_lastDirtyRevision = revision
		_idleSeconds = 0.0
		return
	if not _isDocumentDirty():
		_idleSeconds = 0.0
		return
	_idleSeconds += delta
	if _recovery.shouldSnapshot(true, _strokeOpen, _idleSeconds, revision):
		_writeRecoverySnapshot()


func _writeRecoverySnapshot() -> void:
	if _document == null or not _isDocumentDirty() or _strokeOpen:
		return
	# Never-saved documents pass an empty source path on purpose -- there is no file this snapshot
	# branched from, and inventing one is how a snapshot ends up compared against the wrong map.
	var recoveryName := _document.region_name
	# Once a source path exists (or is reserved by New), its file name is the document identity
	# recovery must use. An old hand-edited file may carry a different NAME internally; trusting it
	# would put the snapshot under one name while plain Save targets another.
	if not _documentPath.is_empty():
		recoveryName = _documentPath.get_file().get_basename()
	var written := _recovery.snapshot(
		_io, _document, recoveryName,
		_documentPath if not _savePoint.isNeverSaved() else "",
		_history.currentRevision()
	)
	# A failed snapshot must not retry every frame after the idle threshold, and it must not leave
	# the author believing recovery exists. A later quiet interval or focus loss will retry.
	_idleSeconds = 0.0
	if not written and _editorHud != null:
		_editorHud.setStatus(
			"Could not write the recovery snapshot. Your edits remain open; save them manually."
		)


## `Display` does not fill the window here -- the fixed left and right panels are laid out
## beside it, not over it, so the map has its own independent centre column. Every framing,
## buffer-size and sky-backdrop calculation in the base class goes through
## `_displaySize()` for exactly this reason: overriding this one method is what keeps the
## rendered buffer, the "tiles across" readout and the sky quad describing what is actually on
## screen instead of the window's full, wider rect.
func _displaySize() -> Vector2:
	return _display.get_rect().size


func _applyRenderScale() -> void:
	if _viewport == null or _editorCamera == null:
		return
	var window := _displaySize()
	if window.x <= 0.0 or window.y <= 0.0:
		return
	var readout := _editorCamera.framingReadout(Vector2i(window))
	var buffer: Vector2 = readout["buffer_size"]
	var wanted := Vector2i(maxi(int(buffer.x), 2), maxi(int(buffer.y), 2))
	if _viewport.size != wanted:
		_viewport.size = wanted


func _applyFraming() -> void:
	_ground.applyFraming(_framing)
	_editorCamera.applyFraming(_framing)
	_applyRenderScale()


## Builds the editor's own minimal stage. The workspace keeps ordinary keyboard focus; shortcuts
## resolve only while the map owns focus, so Tab remains available for control traversal.
func _buildFoundationStage() -> void:
	_viewport = get_node("World") as SubViewport
	_display = get_node("Display") as TextureRect
	_display.texture = _viewport.get_texture()
	var stage := FoundationStage.build(_viewport)
	_map = stage["map"] as Node3D
	_ground = stage["ground"] as WorldMapGround
	_editorCamera = stage["camera"] as WorldMapEditorCamera
	_framing = stage["framing"] as Dictionary
	_regionTiles = _ground.regionRect().size


func _buildEditorUi() -> void:
	var ui := get_node("Ui") as CanvasLayer
	_chrome = ChromeScript.new()
	_chrome.build(ui, _onWorkspaceAction, _onExtraToolChosen, _extraToolRows())
	_chrome.connectStageResized(_layoutDisplayToStage)

	_editorHud = EditorHudScript.new(_chrome)
	var hideableReasons := {}
	for layer in LAYERS:
		var id := str((layer as Dictionary)["id"])
		hideableReasons[id] = LayerViewScript.whyNotHideable(id, LAYER_OBJECTS, LAYER_HEIGHTS)
	_editorHud.build(
		LAYERS, _onLayerSelected, _onLayerVisibilityToggled, _onLayerLockToggled, hideableReasons
	)
	_editorHud.setActiveLayer(_layerIndex(_activeLayer))
	_setActiveTool(TOOL_NAVIGATE)
	_chrome.setActionPressed(WorkspaceActions.VIEW_GRID, true)
	_refreshBrushLabel()
	_preview = PreviewScript.new()
	_map.add_child(_preview)
	# Close is a document action here, so the window may not simply go away -- see `_requestClose`.
	get_tree().auto_accept_quit = false
	call_deferred("_layoutDisplayToStage")
	call_deferred("_offerRecoveryIfAny")


## On startup, say what unsaved work was found and let the author choose. Nothing is loaded
## automatically -- see `WorldMapWorkspaceRecovery`'s class note on why an offer and an
## application are different things.
func _offerRecoveryIfAny() -> void:
	var entries := RecoveryScript.list(_io)
	if entries.is_empty():
		return
	var labels: Array[String] = []
	for entry in entries:
		labels.append(RecoveryScript.describe(_io, entry))
	if not _chrome.promptRecovery(labels, _recoverEntry, _discardRecoveryEntry):
		_editorHud.setStatus(
			"%d recovered edit(s) are waiting; open the recovery dialog to review them."
			% entries.size()
		)


## Recovered content comes back as an UNSAVED document with a fresh history and no save
## checkpoint, so the only way it reaches disk is the author deciding to save it. It never
## overwrites the source it branched from.
func _recoverEntry(index: int) -> void:
	var entries := RecoveryScript.list(_io)
	if index < 0 or index >= entries.size():
		return
	var entry := entries[index]
	_guardDirty(func() -> void:
		var recovered := RecoveryScript.loadDocument(_io, entry)
		if recovered == null:
			_editorHud.setStatus("That recovery snapshot could not be read.")
			return
		if not WorkspacePaths.isValidName(recovered.region_name):
			recovered.region_name = str(entry.get(RecoveryScript.K_NAME, "recovered"))
		_history.clear()
		_document = recovered
		_savePoint.beginNewDocument()
		_recovery.resetForDocument()
		_activeRecoveryEntry = entry.duplicate(true)
		# Deliberately NOT the snapshot's source path: a recovered document is unsaved, and
		# pointing it at the file it diverged from is how a plain Ctrl+S silently overwrites a map
		# the author has not compared against yet.
		_documentPath = ""
		_baker = Baker.new()
		_bakeAndDisplayDocument(
			"Recovered unsaved work for '%s'. It is NOT saved -- use Save As to keep it."
			% str(entry.get(RecoveryScript.K_NAME, ""))
		)
	)


func _discardRecoveryEntry(index: int) -> void:
	var entries := RecoveryScript.list(_io)
	if index < 0 or index >= entries.size():
		return
	# Only the selected one. Discarding a recovery may not quietly remove another map's.
	if RecoveryScript.discard(_io, entries[index]):
		_editorHud.setStatus(
			"Discarded the recovery for '%s'." % str(entries[index].get(RecoveryScript.K_NAME, ""))
		)


## The controller tools that do not get their own toolbar button. Everything not named by the six
## workspace tool actions stays reachable here rather than being dropped -- see the chrome's own
## note on button-first, not button-only.
func _extraToolRows() -> Array:
	var rows: Array = []
	for tool in TOOLS:
		var entry: Dictionary = tool
		if _workspaceActionForTool(str(entry["id"])).is_empty():
			rows.append({"id": str(entry["id"]), "label": str(entry["label"])})
	return rows


## The workspace action id a controller tool is reachable by, or "" when it lives in the dropdown.
## Erase is deliberately absent from this direction: it maps ONTO the paint tool, so asking which
## button "paint" lights is answered by Paint, not by whichever of the two was pressed last.
func _workspaceActionForTool(toolID: String) -> String:
	match toolID:
		TOOL_NAVIGATE:
			return WorkspaceActions.TOOL_NAVIGATE
		TOOL_INSPECT:
			return WorkspaceActions.TOOL_INSPECT
		TOOL_PAINT:
			return WorkspaceActions.TOOL_PAINT
		TOOL_FILL:
			return WorkspaceActions.TOOL_FILL
		TOOL_EYEDROPPER:
			return WorkspaceActions.TOOL_EYEDROPPER
		_:
			return ""


## Every action the workspace can raise, from a button or from a shortcut, lands here. One
## dispatch rather than two paths, so a button and its key cannot come to mean different things.
func _onWorkspaceAction(actionID: String) -> void:
	match actionID:
		WorkspaceActions.NEW_DOCUMENT:
			_openNewDocumentDialog()
		WorkspaceActions.OPEN_DOCUMENT:
			_openOpenDocumentDialog()
		WorkspaceActions.SAVE_DOCUMENT:
			_resolveOpenStroke()
			_saveDocument()
		WorkspaceActions.SAVE_DOCUMENT_AS:
			_openSaveAsDialog()
		WorkspaceActions.EXPORT_SCENE:
			_resolveOpenStroke()
			_exportScene()
		WorkspaceActions.EXPORT_BATTLE:
			_resolveOpenStroke()
			_exportBattleMap()
		WorkspaceActions.UNDO:
			_resolveOpenStroke()
			_undo()
		WorkspaceActions.REDO:
			_resolveOpenStroke()
			_redo()
		WorkspaceActions.TOOL_ERASE:
			_selectEraseTool()
		WorkspaceActions.TOOL_NAVIGATE, WorkspaceActions.TOOL_INSPECT, \
		WorkspaceActions.TOOL_PAINT, WorkspaceActions.TOOL_FILL, \
		WorkspaceActions.TOOL_EYEDROPPER:
			_selectWorkspaceTool(actionID)
		WorkspaceActions.BRUSH_SMALLER:
			_setBrushRadius(_brushRadius - 1)
		WorkspaceActions.BRUSH_LARGER:
			_setBrushRadius(_brushRadius + 1)
		WorkspaceActions.CANCEL_STROKE:
			_cancelOpenStroke()
		WorkspaceActions.VIEW_EDITING:
			if _editorCamera.mode != WorldMapEditorCamera.Mode.ORTHO:
				_editorCamera.toggleOrtho()
			_chrome.setViewLabel("Top-down · editing view")
		WorkspaceActions.VIEW_SHIPPING:
			_editorCamera.snapToContract()
			_chrome.setViewLabel("Shipping view")
		WorkspaceActions.VIEW_PROJECTION:
			_editorCamera.toggleOrtho()
			_chrome.setViewLabel(
				"Top-down · editing view"
				if _editorCamera.mode == WorldMapEditorCamera.Mode.ORTHO
				else "Free perspective"
			)
		WorkspaceActions.VIEW_FRAME:
			_frameRegion()
		WorkspaceActions.VIEW_GRID:
			_gridVisible = not _gridVisible
			_chrome.setActionPressed(WorkspaceActions.VIEW_GRID, _gridVisible)
			_updateGrid()


func _selectWorkspaceTool(actionID: String) -> void:
	for tool in TOOLS:
		var id := str((tool as Dictionary)["id"])
		if _workspaceActionForTool(id) == actionID:
			_setActiveTool(id)
			return


## Erase is the paint tool with the erase value selected -- see `WorldMapEditorHud`'s note on why
## erasing is a value rather than a brush. The button still reads as its own thing because that is
## what the author is doing; internally nothing new exists to go wrong.
func _selectEraseTool() -> void:
	_setActiveTool(TOOL_PAINT)
	if _editorHud.selectEraseValue():
		_chrome.setToolActive(WorkspaceActions.TOOL_ERASE)
		_chrome.setStatus("Erase: painting clears cells on %s." % _activeLayer)
	else:
		_chrome.setStatus("This layer has no erase value.")


func _onExtraToolChosen(toolID: String) -> void:
	_setActiveTool(toolID)


func _setActiveTool(toolID: String) -> void:
	for i in TOOLS.size():
		if str(TOOLS[i]["id"]) == toolID:
			_onToolSelected(i)
			_chrome.setToolActive(_workspaceActionForTool(toolID))
			return


func _setBrushRadius(radius: int) -> void:
	_brushRadius = clampi(radius, 0, MAX_BRUSH_RADIUS)
	_refreshBrushLabel()
	_editorHud.setStatus("Brush: %s." % Footprint.radiusLabel(_brushRadius))


## The radius applies to paint and erase over a GRID layer only. A sculpt step, an object
## placement and a triangle paint each mean something different by "one action", so widening them
## by a hex disc would be inventing semantics rather than sizing a brush -- the readout greys out
## instead of silently not applying.
func _brushRadiusApplies() -> bool:
	if _document == null or not _layerEditable(_activeLayer):
		return false
	if _activeTool != TOOL_PAINT:
		return false
	return _activeLayerKind() == MapDataScript.KIND_GRID


func _refreshBrushLabel() -> void:
	if _chrome == null:
		return
	var applies := _brushRadiusApplies()
	_chrome.setBrushLabel(
		Footprint.radiusLabel(_brushRadius) if applies else "1 hex", applies
	)


## The radius a gesture will actually use, which is zero for every tool the brush size does not
## apply to. One function so the preview and the edit cannot read different sizes.
func _effectiveRadius() -> int:
	return _brushRadius if _brushRadiusApplies() else 0


func _frameRegion() -> void:
	# The aspect that matters is the DISPLAY's, not the window's -- the editor's map column is not
	# the window, and `_displaySize()` is what already accounts for that. Guarded against a zero-
	# height display during the frames before layout has settled, where the aspect is nonsensical.
	var display := _displaySize()
	if display.y > 0.0:
		_editorCamera.frameRegion(_ground.regionRect(), display.x / display.y)


## Guarded by `_guardDirty` rather than the auto-save this used to do: silently saving on the
## user's behalf is its own way to lose work, if what they actually wanted was to abandon a bad
## edit rather than commit it. `previousIndex` is restored on the dropdown when the switch is
## deferred behind a confirmation -- the `OptionButton` has already moved to `index` by the time
## this signal fires (Godot updates a control's own state before emitting), and it must not keep
## showing a region the document has not actually switched to yet.
func _onRegionSelected(_index: int) -> void:
	_editorHud.setStatus("Region previews are not part of the foundation editor. Use Open to choose a map.")


func _performRegionSwitch(index: int) -> void:
	_onRegionSelected(index)


## Puts `Display` exactly where the layout put the map column. Driven by the stage's own measured
## rect rather than by subtracting panel widths from the window: the workspace has a header, a
## toolbar, a view bar and a footer as well as two side panels, and any of them can change height
## when text wraps or a panel collapses. Measuring the hole the layout actually left is the only
## reading that stays true through all of that.
func _layoutDisplayToStage() -> void:
	if _chrome == null or _display == null:
		return
	var target := WorkspaceGeometry.stageToDisplay(_chrome.stageRect())
	if _display.get_global_rect().is_equal_approx(target):
		return
	# Anchored to the top left and positioned in the same global coordinates the stage reported;
	# `Display` is a sibling of the `Ui` CanvasLayer, so it is not laid out by the workspace tree.
	_display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_display.offset_left = target.position.x
	_display.offset_top = target.position.y
	_display.offset_right = target.position.x + target.size.x
	_display.offset_bottom = target.position.y + target.size.y
	_applyRenderScale()


## The header's document identity and the inspector's under-cursor rows. Written only on change --
## see `_shownDocumentLabel`.
func _refreshDocumentReadouts() -> void:
	var documentName := _document.region_name if _document != null else ""
	var neverSaved := _document != null and _savePoint.isNeverSaved()
	var dirty := _isDocumentDirty()
	var label := "%s|%s" % [documentName, neverSaved]
	if label != _shownDocumentLabel or dirty != _shownDirty:
		_shownDocumentLabel = label
		_shownDirty = dirty
		_chrome.setDocumentLabel(documentName, neverSaved, dirty)
	_chrome.setActionEnabled(WorkspaceActions.UNDO, _history.canUndo())
	_chrome.setActionEnabled(WorkspaceActions.REDO, _history.canRedo())

	var cellText := "--"
	var valueText := "--"
	if _cursorCell != null and _document != null:
		var cell := _cursorCell as Vector2i
		cellText = "%d, %d" % [cell.x, cell.y]
		if _document.layers.has(_activeLayer):
			valueText = _document.getCell(_activeLayer, cell)
	var readout := "%s|%s" % [cellText, valueText]
	if readout != _shownCursorCell:
		_shownCursorCell = readout
		_editorHud.setCursorReadout(cellText, valueText)


## Left click routes to the active layer's tool. Middle-drag orbits, right-drag pans, the wheel
## dollies -- all applied to the camera through its plain methods, per the class note. Snapping
## yaw to 45 degrees on a Shift-released middle-drag mirrors the debug-scene convention of a
## modifier changing what a release does rather than needing its own gesture. Deliberately does
## not call `super`: the base class's left-drag-pans-the-camera would otherwise compete with
## left click as a tool input, and only one of them may own that button.
## A gesture already in flight is routed BEFORE hit-tested controls, which `_unhandled_input`
## cannot do: the workspace's panels consume the mouse, so a drag that wanders over the toolbar
## or the tilesheet would stop being delivered and the stroke or the orbit would stall mid-motion
## with the button still held. `_input` runs ahead of the GUI, so this claims exactly the events
## an owned gesture needs and marks them handled; every other event falls through untouched and is
## dealt with by `_unhandled_input` as before. Ownership is acquired on an unhandled press and
## released only on the matching release.
func _input(event: InputEvent) -> void:
	if not (_cameraOrbiting or _cameraPanning or _strokeOpen or _gestureStart != null):
		return
	var button := event as InputEventMouseButton
	if button != null and not button.pressed:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_endToolGesture(button.position)
			MOUSE_BUTTON_MIDDLE:
				_cameraOrbiting = false
				if Input.is_key_pressed(KEY_SHIFT):
					_editorCamera.snapYaw()
			MOUSE_BUTTON_RIGHT:
				_cameraPanning = false
			_:
				return
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_applyPointerMotion(motion)
	get_viewport().set_input_as_handled()


## Left click routes to the active layer's tool. Middle-drag orbits, right-drag pans, the wheel
## dollies -- all applied to the camera through its plain methods, per the class note. Snapping
## yaw to 45 degrees on a Shift-released middle-drag mirrors the debug-scene convention of a
## modifier changing what a release does rather than needing its own gesture. Deliberately does
## not call `super`: the base class's left-drag-pans-the-camera would otherwise compete with
## left click as a tool input, and only one of them may own that button.
##
## Reaching this function AT ALL is the workspace's proof that the press was on the map: every
## panel is `MOUSE_FILTER_STOP` and consumes its own presses, so a click on chrome never arrives
## here. Nothing below needs to ask where the pointer was.
func _unhandled_input(event: InputEvent) -> void:
	if _chrome != null and _chrome.isModalOpen():
		return
	var button := event as InputEventMouseButton
	if button != null:
		_pointerPosition = button.position
		if button.pressed:
			# The stage ignores the mouse, so a map click cannot move focus by itself. Dropping
			# focus here is what makes the toolbar's advertised shortcuts work again after the
			# author has pressed one of its buttons.
			get_viewport().gui_release_focus()
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
		_applyPointerMotion(motion)


func _applyPointerMotion(motion: InputEventMouseMotion) -> void:
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


## Focus loss ends an owned gesture rather than leaving it held -- see `docs/LEARNINGS.md`'s
## cursor-event rule. Without this, alt-tabbing mid-drag returns to an editor that is still
## orbiting or still recording a stroke that the author has stopped making.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cameraOrbiting = false
		_cameraPanning = false
		_gestureStart = null
		_resolveOpenStroke()
		# Losing focus is the cheapest honest moment to protect unsaved work: the stroke is
		# already resolved, so the snapshot captures a complete edit rather than half a gesture.
		_writeRecoverySnapshot()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_requestClose()


## Closing the window is a document-replacing action like New and Open, and goes through the same
## protection. Without this the one path that discards EVERYTHING was the only one that never
## asked.
func _requestClose() -> void:
	_resolveOpenStroke()
	if not _isDocumentDirty():
		get_tree().quit()
		return
	_writeRecoverySnapshot()
	_guardDirty(func() -> void: get_tree().quit())


## Every editor shortcut resolves through one table -- see `WorldMapWorkspaceActions`. A key that
## does not name an action, or that arrives while a text field or a modal owns the keyboard, falls
## through to the base class unchanged, which is what keeps the debug scene's own keys working and
## what lets an author type `b` into a map name without selecting the paint brush.
##
## KEY_TAB IS DELIBERATELY NOT CLAIMED. It used to toggle the orthographic camera globally, which
## cost the workspace keyboard traversal entirely; the projection toggle is a visible button now.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _chrome == null:
		return
	var actionID := WorkspaceActions.resolve(
		key.keycode, key.ctrl_pressed, key.shift_pressed, _chrome.focusState()
	)
	if actionID.is_empty():
		return
	_onWorkspaceAction(actionID)
	get_viewport().set_input_as_handled()


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
		_editorHud.setStatus("%s is locked. Unlock it in the layer list to edit." % _activeLayer)
		return
	# A hidden layer refuses edits for the same reason a locked one does: an author cannot judge
	# an edit they cannot see, and silently painting into an invisible layer is how a map acquires
	# changes nobody meant to make.
	if _layerView.isHidden(_activeLayer):
		_editorHud.setStatus(
			"%s is hidden in this view. Show it in the layer list to edit it." % _activeLayer
		)
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
	if _editorHud.requiresTileSelection() and _activeTool in [
		TOOL_PAINT, TOOL_FILL, TOOL_STAMP, TOOL_REPLACE, TOOL_RECTANGLE, TOOL_LINE, TOOL_SCATTER,
	]:
		_editorHud.setStatus("Choose a tile from the tileset, or choose Erase to clear cells.")
		return
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
			_strokeKind = TOOL_PAINT
			_strokeTouched.clear()
			_lastPaintedCell = null
			_paintStrokeCell(cell)
		TOOL_FILL:
			var flooded := Brushes.floodCells(_document, _activeLayer, cell)
			if Brushes.floodFill(_document, _history, _activeLayer, cell, tileID):
				_afterCellsEdited(_activeLayer, flooded)
		TOOL_STAMP:
			# Through the AXIAL hex stamp path, built from the sheet's own multi-selection.
			# Offset deltas are not translation-invariant across a hex parity boundary, so the
			# rectangular-array stamp silently reshaped itself when its anchor moved one column.
			var pattern := _sheetStampPattern()
			if pattern.is_empty():
				_editorHud.setStatus("Select one or more sheet frames to stamp.")
			else:
				var stamped := Footprint.stampCells(cell, pattern, _latticeSize())
				if Brushes.stampHex(_document, _history, _activeLayer, cell, pattern):
					_afterCellsEdited(_activeLayer, stamped)
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
		_closeOpenStroke()
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
			# The sheet's ordered multi-selection, so scattering several tiles is a matter of
			# selecting them rather than of a separate set editor. That order plus the visible
			# seed is what makes the result reproducible: identical inputs commit identical ids.
			var choices := _editorHud.selectedSheetTileIDs()
			if choices.is_empty():
				choices = _scatterSet
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


## Paints the brush footprint at `cell`, joined to wherever the stroke last painted.
##
## TWO THINGS THIS FIXES, both of which look like the editor dropping input. Pointer samples
## arrive as far apart as the frame rate and the author's hand put them, so a fast drag used to
## paint a dotted line of isolated cells; `Footprint.dragCells` fills the hex path between the
## samples. And the whole swept set goes through the ALREADY-OPEN stroke, so a drag of any length,
## at any radius, over any number of repeated cells, is still exactly one history entry.
func _paintStrokeCell(cell: Vector2i) -> void:
	if not _strokeOpen or _document == null:
		return
	var tileID := _editorHud.selectedTileID()
	var cells := (
		Footprint.discCells(cell, _effectiveRadius(), _latticeSize())
		if _lastPaintedCell == null
		else Footprint.dragCells(
			_lastPaintedCell as Vector2i, cell, _effectiveRadius(), _isHexDocument(),
			_latticeSize()
		)
	)
	for target in cells:
		if Brushes.paintPoint(_document, _history, target, tileID):
			if not _strokeTouched.has(target):
				_strokeTouched.append(target)
	_lastPaintedCell = cell


func _isHexDocument() -> bool:
	return _document != null and _document.layout == MapDataScript.LAYOUT_HEX_FLAT


## The bounds a footprint is clipped to. Zero means unbounded, which is the convention the picker
## and the grid overlay already use for a square document with no declared lattice.
func _latticeSize() -> Vector2i:
	if _document == null:
		return Vector2i.ZERO
	return _document.size_tiles if _isHexDocument() else _document.layerSize(_activeLayer)


## The cells the CURRENT pointer position would change, for the highlight. Computed from the same
## `Footprint` functions the edit itself calls -- see that file's own note on why the preview may
## not be a second opinion.
func _previewCells() -> Array[Vector2i]:
	if _document == null or _cursorCell == null or _activeTool == TOOL_NAVIGATE:
		return []
	var cell := _cursorCell as Vector2i
	var lattice := _latticeSize()
	var hex := _isHexDocument()
	match _activeTool:
		TOOL_PAINT:
			return Footprint.discCells(cell, _effectiveRadius(), lattice)
		TOOL_INSPECT, TOOL_EYEDROPPER, TOOL_SCULPT, TOOL_PLACE:
			return Footprint.discCells(cell, 0, lattice)
		TOOL_FILL:
			return Footprint.clip(
				Brushes.floodCells(_document, _activeLayer, cell), lattice
			)
		TOOL_STAMP:
			return Footprint.stampCells(cell, _sheetStampPattern(), lattice)
		TOOL_LINE:
			if _gestureStart == null:
				return Footprint.discCells(cell, 0, lattice)
			return Footprint.lineCells(_gestureStart as Vector2i, cell, hex, lattice)
		TOOL_RECTANGLE, TOOL_SCATTER:
			if _gestureStart == null:
				return Footprint.discCells(cell, 0, lattice)
			return Footprint.rectangleCells(_gestureStart as Vector2i, cell, lattice)
	return Footprint.discCells(cell, 0, lattice)


## The stamp the sheet's current multi-selection describes, as axial deltas -- see
## `WorldMapWorkspaceFootprint.stampPattern` for why axial and not offset. Falls back to the single
## selected value so the stamp tool still means something with one frame chosen.
func _sheetStampPattern() -> Dictionary:
	var ids := _editorHud.selectedSheetTileIDs()
	var cells := _editorHud.selectedSheetCells()
	if ids.is_empty() or ids.size() != cells.size():
		var single := _editorHud.selectedTileID()
		return {} if single.is_empty() else {Vector2i.ZERO: single}
	return Footprint.stampPattern(cells, ids)


func _refreshPreview() -> void:
	if _preview == null:
		return
	if _document == null or _activeTool == TOOL_NAVIGATE:
		_clearPreview()
		return
	var blocked := (
		bool(_layerLocked.get(_activeLayer, false))
		or _layerView.isHidden(_activeLayer)
		or not _layerEditable(_activeLayer)
	)
	_preview.showCells(_previewCells(), _document, _ground.regionRect().position, blocked)


func _clearPreview() -> void:
	if _preview != null:
		_preview.clear()


func _afterCellsEdited(layerID: String, cells: Array[Vector2i]) -> void:
	if _document == null or cells.is_empty():
		return
	for cell in cells:
		_baker.markCellsDirty(_document, layerID, Rect2i(cell, Vector2i.ONE))
	_baker.flush(_document)
	_refreshFilteredDisplay()
	_editorHud.setStatus("Changed %d %s cell%s. Ctrl+S saves." % [
		cells.size(), layerID, "" if cells.size() == 1 else "s",
	])


## The canonical bake above always takes the cheap dirty-cell path. The filtered display copy has
## no dirty-cell tracking of its own, so it is rebuilt whole -- but only while a layer is actually
## hidden, and only once per COMMITTED edit rather than per pointer sample. With everything
## visible, which is the ordinary state, this costs one dictionary lookup.
func _refreshFilteredDisplay() -> void:
	if not _layerView.anyArtHidden():
		return
	var filtered := _layerView.filteredCopy(_document)
	if filtered == null:
		return
	_previewBaker = Baker.new()
	_previewBaker.bake(filtered)
	_applyDisplayedTexture()


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
	_refreshFilteredDisplay()
	_editorHud.setStatus("Changed %s cells. Ctrl+S saves." % layerID)


func _inclusiveRect(from: Vector2i, to: Vector2i) -> Rect2i:
	var first := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var last := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y))
	return Rect2i(first, last - first + Vector2i.ONE)


## Where a screen position lands inside the rendered viewport, or null when it lands outside the
## drawn image. Extracted in WMH-10B so the triangle pick and the cell pick share one definition
## of that mapping rather than each carrying its own copy of the letterboxing arithmetic.
func _viewportPoint(screenPosition: Vector2) -> Variant:
	return WorkspaceGeometry.bufferPoint(
		screenPosition, _display.get_global_rect(), Vector2(_viewport.size)
	)


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
	var visible := (
		_gridVisible and _document != null and _activeTool != TOOL_NAVIGATE
		and _layerEditable(_activeLayer)
	)
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


func _openDocumentForRegion(
	regionID: String, preloaded: WorldMapTileData = null, loadAttempted := false
) -> bool:
	var loaded := preloaded
	var authored := Regions.isAuthored(regionID)
	if authored and not loadAttempted:
		loaded = _io.loadSource(Regions.tileDataPathFor(regionID))
	if authored and loaded == null:
		if _editorHud != null:
			_editorHud.setStatus(
				"Could not open '%s'; the current document is untouched." % regionID
			)
		return false
	_history.clear()
	_document = loaded
	_savePoint.beginOpenedDocument(_history.currentRevision())
	_recovery.resetForDocument()
	_activeRecoveryEntry = {}
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
		return true
	_bakeAndDisplayDocument("Editing %s (%s)." % [regionID, _documentPath])
	return true


## Creates a fresh hex document at `lattice` cells -- an exact-fit size from WMH-2's own table,
## which is all the HUD offers, so a new map never has the margin question WMH-R1 already
## settled (void colour, not a terrain) before a single cell is painted -- named `name`, and
## opens it exactly as `_openDocumentForRegion` would open one from disk. `WorldMapBaker` learned
## hex geometry in WMH-5B, so the ground render is a real bake, not the provisional placeholder
## an earlier version of this function warned about.
func _newDocument(lattice: Vector2i, name: String, tilesetID := DEFAULT_HEX_TILESET) -> void:
	_history.clear()
	_recovery.resetForDocument()
	_activeRecoveryEntry = {}
	var chosen := tilesetID if Tilesets.has(tilesetID) else DEFAULT_HEX_TILESET
	var doc := MapDataScript.create(name, lattice, MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = chosen
	var paletteRegion := str(
		Tilesets.tilesetFor(chosen).get("PALETTE_REGION", DEFAULT_HEX_PALETTE_REGION)
	)
	doc.palette_region = paletteRegion
	doc.fog_color = Regions.fogColorFor(paletteRegion)
	doc.void_color = Regions.voidColorFor(paletteRegion)
	_document = doc
	# A new document has never been written, so it reads as unsaved from its first frame -- see
	# `WorldMapWorkspaceSavePoint`. Nothing here writes anything to disk.
	_savePoint.beginNewDocument()
	_documentPath = MapDataScript.pathFor(name)
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
	_bakeAndDisplayDocument("New hex map '%s' on %s (%s cells)." % [name, chosen, lattice])


## Opens a document BY NAME rather than by region id -- any file under `WorldMapTileData.
## AUTHORED_DIR`, whether or not `WorldMapRegionCatalog` names it. A document `_newDocument`
## creates has no catalog entry (exporting one into the catalog is WMH-6's job, not this one's),
## so "Open" cannot be the inherited region picker alone; this is the other half of the loop
## `_openDocumentForRegion` already covers for documents the catalog does know about.
## A FAILED OPEN COSTS NOTHING. The document is loaded and checked BEFORE any editor state is
## touched, so a missing, unreadable or malformed file leaves the current document, its history,
## its save checkpoint and its path exactly as they were. The previous version cleared the
## history and reassigned `_document` first, which meant choosing a corrupt file discarded
## whatever the author had open.
func _openDocumentByName(name: String) -> void:
	_resolveOpenStroke()
	var path := WorkspacePaths.sourcePathFor(name)
	if path.is_empty():
		_editorHud.setStatus("Cannot open '%s': %s" % [name, WorkspacePaths.describeInvalidName(name)])
		return
	var loaded := _io.loadSource(path)
	if loaded == null:
		_editorHud.setStatus(
			"Could not open '%s' -- it is missing or not a readable map. The open document is "
			% name + "untouched."
		)
		return
	_history.clear()
	_document = loaded
	_savePoint.beginOpenedDocument(_history.currentRevision())
	_recovery.resetForDocument()
	_activeRecoveryEntry = {}
	_documentPath = path
	_baker = Baker.new()
	_cursorCell = null
	_gestureStart = null
	_strokeOpen = false
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
	_rebuildObjectPreview()
	if not _layerEditable(_activeLayer):
		for layer in LAYERS:
			var id := str((layer as Dictionary)["id"])
			if _layerEditable(id):
				_activeLayer = id
				break
	_editorHud.setActiveLayer(_layerIndex(_activeLayer))
	_refreshValueChoices()
	_refreshBrushLabel()
	# View state survives a document change, so it has to be re-applied to the new one rather than
	# left describing the previous map.
	_applyLayerVisibility()
	_editorHud.setStatus(statusMessage)


func _saveDocument() -> void:
	_resolveOpenStroke()
	if _document == null or _documentPath.is_empty():
		if _editorHud != null:
			_editorHud.setStatus("No authored document is open.")
		return
	# The active source path, not an embedded NAME from a hand-edited file, decides where plain
	# Save writes. `_writeDocumentAs` reconciles the serialized name on successful completion.
	var result := _writeDocumentAs(_documentPath.get_file().get_basename())
	_reportSaveResult(result)


## Writes the open document's TWO files under `name` and reports exactly what happened, without
## changing any editor state. Whether an outcome advances the checkpoint or moves the active path
## is the caller's decision -- see `_reportSaveResult` and `_saveDocumentAs`.
##
## THE SOURCE AND THE BAKE ARE TWO FILES AND THIS IS NOT ATOMIC. Either can fail on its own, and
## a half-written save is a real state the author can reach. Rather than pretending otherwise, the
## result names which half landed so the status line can say so and the checkpoint can stay put --
## promising atomicity across two files without implementing it would be the worse failure, since
## the author would trust a save that only half happened.
func _writeDocumentAs(name: String) -> Dictionary:
	var invalid := WorkspacePaths.describeInvalidName(name)
	if not invalid.is_empty():
		return {"ok": false, "error": invalid, "sourceOk": false, "bakeOk": false}
	var sourcePath := WorkspacePaths.sourcePathFor(name)
	var bakePath := WorkspacePaths.generatedPathFor(name)
	if sourcePath.is_empty() or bakePath.is_empty():
		return {
			"ok": false, "sourceOk": false, "bakeOk": false,
			"error": "'%s' would write outside the authored folder." % name,
		}
	# The name is written INTO the file, so saving under a different one requires the document to
	# carry it. Restored below if the write does not fully land, so a failed Save As leaves the
	# document exactly as it was rather than renamed to somewhere it was never written.
	var previousName := _document.region_name
	_document.region_name = name
	var sourceOk := _io.saveSource(_document, sourcePath)
	var bakeOk := _io.saveBake(_baker, bakePath)
	if not (sourceOk and bakeOk):
		_document.region_name = previousName
	return {
		"ok": sourceOk and bakeOk,
		"sourceOk": sourceOk,
		"bakeOk": bakeOk,
		"sourcePath": sourcePath,
		"bakePath": bakePath,
		"name": name,
	}


## Advances the checkpoint only on a complete success, and says which half failed otherwise so the
## author knows whether their source is safe. A failed save leaves the document dirty on purpose:
## that is what keeps the next Ctrl+S meaningful and the retry route open.
func _reportSaveResult(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		_savePoint.markSaved(_history.currentRevision())
		# The work is on disk, so its crash snapshot has nothing left to protect.
		var recoveryCleared := true
		if not _activeRecoveryEntry.is_empty():
			recoveryCleared = RecoveryScript.discard(_io, _activeRecoveryEntry)
			if recoveryCleared:
				_activeRecoveryEntry = {}
		recoveryCleared = (
			_recovery.clearFor(_io, str(result.get("name", ""))) and recoveryCleared
		)
		_editorHud.setStatus(
			"Saved %s and its generated texture." % str(result.get("name", ""))
			if recoveryCleared
			else (
				"Saved %s and its generated texture, but an old recovery snapshot could not "
				% str(result.get("name", "")) + "be removed; it may be offered next launch."
			)
		)
		return true
	var error := str(result.get("error", ""))
	if not error.is_empty():
		_editorHud.setStatus("Save refused: %s" % error)
		return false
	var sourceOk := bool(result.get("sourceOk", false))
	var bakeOk := bool(result.get("bakeOk", false))
	_editorHud.setStatus(
		"Save incomplete: the source was written but the generated texture was not. "
		+ "The map is still marked unsaved; try Save again."
		if sourceOk and not bakeOk
		else (
			"Save failed: the generated texture was written but the source was NOT. "
			+ "Your edits are still only in the editor; try Save again."
			if bakeOk and not sourceOk
			else "Save failed: neither the source nor the generated texture was written."
		)
	)
	return false


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
##
## THE PATH MOVES ONLY AFTER THE WRITE LANDS. The previous version renamed the document and
## repointed `_documentPath` BEFORE attempting the save, so a refused name or a failed write left
## the editor pointing at a file that had never been written -- and the next plain Ctrl+S would
## then aim at that same phantom path. Now nothing about the editor's idea of where it is editing
## changes unless both files were actually written.
func _saveDocumentAs(name: String) -> void:
	_resolveOpenStroke()
	if _document == null:
		_editorHud.setStatus("No document is open.")
		return
	var previousPath := _documentPath
	var result := _writeDocumentAs(name)
	if not _reportSaveResult(result):
		_documentPath = previousPath
		return
	_documentPath = str(result["sourcePath"])


## Every `.json` under `WorldMapTileData.AUTHORED_DIR`, sorted -- what "Open" offers. Scanned
## from disk rather than read off `WorldMapRegionCatalog`, because a document `_newDocument`
## creates has no catalog entry until something exports it into one.
func _availableDocumentNames() -> Array[String]:
	var result: Array[String] = []
	for entry in _io.listFiles(MapDataScript.AUTHORED_DIR, "json"):
		result.append(entry.get_basename())
	result.sort()
	return result


## WMH-2's exact-fit table, unmodified -- see the HUD's own note on why "New" offers only these
## and not an arbitrary size.
func _newLatticeChoices() -> Array[Vector2i]:
	var choices := WorldMapHexGrid.exactSquareLattices()
	var defaultLattice := Vector2i(19, 14)
	choices.erase(defaultLattice)
	choices.push_front(defaultLattice)
	return choices


## Whether the open document has any edit since the last successful save, compared by history
## REVISION rather than by stack depth -- see `WorldMapWorkspaceSavePoint` for the two states the
## depth comparison called saved while the content had genuinely moved.
func _isDocumentDirty() -> bool:
	return _document != null and _savePoint.isDirty(_history.currentRevision())


## Runs `action` immediately when nothing would be lost; otherwise defers it behind the HUD's
## discard-confirmation dialog, and `action` runs only if the user actually confirms. Every entry
## point that would replace or close the open document -- New, Open, and the inherited region
## picker -- goes through this, so "ask before discarding" cannot be forgotten at a future call
## site the way a manually-set dirty bool could be.
func _guardDirty(action: Callable) -> void:
	# An open stroke is part of the document's content, so it is resolved into history before the
	# question "is anything unsaved" is even asked.
	_resolveOpenStroke()
	if not _isDocumentDirty():
		action.call()
		return
	_pendingDiscardAction = action
	if _chrome == null or not _chrome.promptDiscard(_saveThenContinue, _confirmDiscard, _cancelDiscard):
		# No display server to put a dialog on. The pending action stays pending rather than
		# running: a headless caller drives it through `confirmPendingDiscard()`.
		return


## Ends whatever gesture is mid-flight and commits it as one history entry, so a tool change, a
## layer change, a document action or an export can never land in the middle of a stroke. Safe to
## call when nothing is open.
func _resolveOpenStroke() -> void:
	_gestureStart = null
	_closeOpenStroke()


## THE STROKE POLICY, in one place because every one of these used to be its own answer:
##
##  - Pointer RELEASE, wherever it happens: commits. The gesture is routed ahead of the GUI while
##    it is owned (see `_input`), so releasing over the toolbar or off the window still ends the
##    stroke rather than leaving it held.
##  - FOCUS LOSS: commits. What the author already painted is their work.
##  - TOOL, LAYER or DOCUMENT change, and LOCKING the active layer: commits, before the change.
##  - ESCAPE: CANCELS -- the stroke is closed and then immediately undone, so the map returns to
##    what it held before the gesture began and the history holds no entry for it.
##
## The distinction is deliberate: everything that is an ordinary interruption keeps the work, and
## the single explicit "I did not mean this" gesture is the only one that throws it away. No path
## leaves a stroke open, and none leaves half of one recorded.
func _cancelOpenStroke() -> void:
	_gestureStart = null
	_lastPaintedCell = null
	if not _strokeOpen:
		_clearPreview()
		_editorHud.setStatus("Nothing in progress to cancel.")
		return
	var kind := _strokeKind
	_strokeOpen = false
	_strokeKind = ""
	_sculptVertices.clear()
	var committed := Brushes.endStroke(_history)
	if committed:
		# Undone through the history rather than by replaying inverse edits by hand: the stroke is
		# exactly one command, so its own undo is the complete and correct reversal.
		var touched := _history.undo(_document)
		if not touched.is_empty():
			_onHistoryApplied(touched)
		if kind == TOOL_SCULPT:
			_afterHeightsEdited()
	_strokeTouched.clear()
	_clearPreview()
	_editorHud.setStatus("Stroke cancelled.")


## The stroke half of the above, without abandoning a two-point gesture -- `_endToolGesture` needs
## `_gestureStart` intact to finish a rectangle, a line or a scatter.
func _closeOpenStroke() -> void:
	_lastPaintedCell = null
	if not _strokeOpen:
		return
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


## The third answer the dialog offers, and the one that makes the other two safe to present: save
## the work and then do the thing. A save that FAILS cancels the pending action rather than
## carrying on -- continuing after a failed save is the one path that would lose the document.
func _saveThenContinue() -> void:
	var action := _pendingDiscardAction
	_pendingDiscardAction = Callable()
	if _documentPath.is_empty():
		_editorHud.setStatus(
			"This recovered map has no save destination. Use Save As, then try again."
		)
		return
	_saveDocument()
	if _isDocumentDirty():
		_editorHud.setStatus(
			"Save did not complete, so nothing was discarded. The document is still open."
		)
		return
	if action.is_valid():
		action.call()


func _confirmDiscard() -> void:
	var action := _pendingDiscardAction
	_pendingDiscardAction = Callable()
	_discardCurrentRecovery()
	if action.is_valid():
		action.call()


func _discardCurrentRecovery() -> void:
	if not _activeRecoveryEntry.is_empty():
		RecoveryScript.discard(_io, _activeRecoveryEntry)
		_activeRecoveryEntry = {}
		return
	if _document == null:
		return
	var recoveryName := (
		_documentPath.get_file().get_basename()
		if not _documentPath.is_empty()
		else _document.region_name
	)
	if WorkspacePaths.isValidName(recoveryName):
		_recovery.clearFor(_io, recoveryName)


func _cancelDiscard() -> void:
	_pendingDiscardAction = Callable()


## The dialogs the header's document buttons open. Each one collects a choice and then calls the
## SAME request function a headless caller uses, so the dialog is a way to supply arguments and
## never a place where a decision lives -- which is what lets the probe drive this whole path
## without a window.
func _openNewDocumentDialog() -> void:
	var lattices := _newLatticeChoices()
	var labels: Array[String] = []
	for lattice in lattices:
		var extent: Vector2 = WorldMapHexGrid.latticeExtent(lattice.x, lattice.y)
		labels.append("%d x %d  (%.0f units)" % [lattice.x, lattice.y, extent.x])
	var tilesets := _hexTilesetChoices()
	if not _chrome.promptNewDocument(
		lattices, labels, tilesets, DEFAULT_HEX_TILESET, "untitled", _requestNewDocument
	):
		_editorHud.setStatus("No display server; New needs its dialog.")


func _openOpenDocumentDialog() -> void:
	var names := _availableDocumentNames()
	if names.is_empty():
		_editorHud.setStatus("No authored maps on disk yet.")
		return
	if not _chrome.promptOpenDocument(names, _requestOpenDocument):
		_editorHud.setStatus("No display server; Open needs its dialog.")


func _openSaveAsDialog() -> void:
	if _document == null:
		_editorHud.setStatus("No document is open.")
		return
	if not _chrome.promptSaveAs(_document.region_name, _requestSaveAsDocument):
		_editorHud.setStatus("No display server; Save As needs its dialog.")


## Every hex-capable tileset the catalog knows, which is what New may choose between. A tileset is
## offered for a NEW document only; opening one never remaps a populated layer's stored id.
func _hexTilesetChoices() -> Array[String]:
	var result: Array[String] = []
	for id in Tilesets.ids():
		if int(Tilesets.tilesetFor(id).get("FRAME_PX", 0)) >= 32:
			result.append(id)
	if result.is_empty():
		result.append(DEFAULT_HEX_TILESET)
	return result


func _requestNewDocument(lattice: Vector2i, name: String, tilesetID: String) -> void:
	if lattice == Vector2i.ZERO:
		_editorHud.setStatus("Choose a lattice size first.")
		return
	# Checked HERE rather than at save time: a name that cannot become a path should be refused
	# while the author is still looking at the field they typed it into.
	var invalid := WorkspacePaths.describeInvalidName(name)
	if not invalid.is_empty():
		_editorHud.setStatus("Cannot create '%s': %s" % [name, invalid])
		return
	_guardDirty(_newDocument.bind(lattice, name, tilesetID))


func _requestOpenDocument(name: String) -> void:
	if name.is_empty():
		_editorHud.setStatus("Nothing to open yet.")
		return
	_guardDirty(_openDocumentByName.bind(name))


## No guard: Save As never discards anything the open document held, it only chooses where the
## save goes.
func _requestSaveAsDocument(name: String) -> void:
	var invalid := WorkspacePaths.describeInvalidName(name)
	if not invalid.is_empty():
		_editorHud.setStatus("Cannot save as '%s': %s" % [name, invalid])
		return
	_saveDocumentAs(name)


## The value row, per layer kind -- WMH-10B. It was `_refreshTileChoices` and offered tile ids
## unconditionally, which is the specific thing that would have made a kind-aware
## `_layerEditable` produce a tool that silently paints nothing: a sculpt reading a tile id off a
## row that had none applies `float("")`, which is 0.0, which is a no-op no one is told about.
func _refreshValueChoices() -> void:
	var selected := _editorHud.selectedValue() if _editorHud.hasValueRow() else ""
	_refreshPalette()
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


## Points the palette at the ACTIVE LAYER's own catalog entry, or hides the sheet entirely for a
## layer whose values are not sheet frames. The tactical layer is the case that makes this a
## dispatch rather than a lookup: it is a grid layer, so it would otherwise be offered a tilesheet
## for values that are battle terrain ids and have no art at all.
func _refreshPalette() -> void:
	if _editorHud == null:
		return
	if _document == null:
		_editorHud.showValueOnlyPalette("no document")
		return
	if _activeLayer == LAYER_TACTICAL:
		_editorHud.showValueOnlyPalette("tactical")
		return
	match _activeLayerKind():
		MapDataScript.KIND_HEIGHTS:
			_editorHud.showValueOnlyPalette("terrain height")
			return
		MapDataScript.KIND_LIST:
			_editorHud.showValueOnlyPalette("object")
			return
	var tilesetID := (
		str((_document.layers[_activeLayer] as Dictionary).get("TILESET", ""))
		if _document.layers.has(_activeLayer)
		else (_groundTilesetID() if _activeLayerKind() == MapDataScript.KIND_DETAIL else "")
	)
	if tilesetID.is_empty() or not Tilesets.has(tilesetID):
		_editorHud.showValueOnlyPalette("untextured")
		return
	var tileset := Tilesets.tilesetFor(tilesetID)
	var tiles: Array[Dictionary] = []
	for tile in tileset.get("TILES", []):
		tiles.append(tile as Dictionary)
	# `load()` rather than `preload()`: the sheet is named by data. A tileset Godot has not
	# imported yet returns null, which the picker renders as an empty sheet rather than failing.
	var sheetPath := str(tileset.get("SHEET", ""))
	var sheet: Texture2D = null
	if not sheetPath.is_empty():
		var sourceImage := Tilesets.loadSheetImage(sheetPath)
		if sourceImage != null:
			sheet = ImageTexture.create_from_image(sourceImage)
	_editorHud.configurePalette(
		tilesetID, sheet, int(tileset.get("FRAME_PX", 32)), tiles
	)


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
	# Mid-gesture ownership must not switch layers: the open stroke belongs to the layer it began
	# on and is committed there before the active one moves.
	_resolveOpenStroke()
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
	# Committed rather than discarded: the strokes the author already made with the old tool are
	# their work, and abandoning the open history entry would silently drop the last one.
	_resolveOpenStroke()
	_activeTool = str(TOOLS[index]["id"])
	_refreshBrushLabel()
	_editorHud.setScatterVisible(_activeTool == TOOL_SCATTER)
	_clearPreview()
	_editorHud.setStatus("Tool: %s" % str(TOOLS[index]["label"]))


## Editor VIEW state only. The authored document is never filtered -- see
## `WorldMapWorkspaceLayerView`'s class note -- so this can change what is on screen and can never
## change what a save or an export contains.
func _onLayerVisibilityToggled(id: String, on: bool) -> void:
	if not LayerViewScript.canHide(id, LAYER_OBJECTS):
		return
	# A stroke in flight belongs to the view it was started in; committing it first means a hidden
	# layer can never swallow half a recorded gesture.
	_resolveOpenStroke()
	_layerView.setHidden(id, not on)
	_applyLayerVisibility()
	var description := _layerView.describe()
	_editorHud.setStatus(
		description if not description.is_empty()
		else "Every layer is visible."
	)


## Rebuilds what is DISPLAYED for the current visibility set. The canonical `_baker` is left alone
## and still holds the complete map; only `_previewBaker` ever holds a filtered one, and only the
## ground's displayed texture is switched between them.
func _applyLayerVisibility() -> void:
	if _document == null:
		return
	if _objectsPreview != null and is_instance_valid(_objectsPreview):
		_objectsPreview.visible = not _layerView.isHidden(LAYER_OBJECTS)
	var filtered := _layerView.filteredCopy(_document)
	if filtered == null:
		_previewBaker = null
	else:
		_previewBaker = Baker.new()
		_previewBaker.bake(filtered)
	_applyDisplayedTexture()
	_refreshPreview()


## The texture the ground shows: the filtered bake while a layer is hidden, the canonical one
## otherwise. Save and export never call this -- they read `_baker` directly, which is what keeps
## a hidden layer out of the view and in the file.
func _applyDisplayedTexture() -> void:
	if _document == null:
		return
	var texture := _previewBaker.texture() if _previewBaker != null else _baker.texture()
	if texture != null:
		SceneExport.configureGround(_ground, _document, texture, _framing)


func _onLayerLockToggled(id: String, on: bool) -> void:
	_layerLocked[id] = on
	if on and id == _activeLayer:
		# Locking the layer a stroke is being made on ends that stroke rather than leaving it open
		# against a layer that now refuses input.
		_resolveOpenStroke()


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
	_setActiveTool(id)


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


func savePendingAndContinue() -> void:
	_saveThenContinue()


func recoverEntry(index: int) -> void:
	_recoverEntry(index)


## These take their arguments directly rather than writing them into HUD widgets and reading them
## back out. The old versions poked `newLatticeOption.selected` and `nameEdit.text` -- which meant
## the document actions could only be driven by whatever controls the panel happened to hold, and
## that any redesign of the panel had to keep those exact controls alive to satisfy them. The
## dialogs now call these same functions, so there is one path rather than a real one and a
## test-shaped one.
func requestNewDocument(lattice: Vector2i, name: String, tilesetID := DEFAULT_HEX_TILESET) -> void:
	_requestNewDocument(lattice, name, tilesetID)


func requestOpenDocument(name: String) -> void:
	if not _availableDocumentNames().has(name):
		return
	_requestOpenDocument(name)


func requestSaveAsDocument(name: String) -> void:
	_requestSaveAsDocument(name)


## What the workspace's own probe drives instead of clicking. See
## `scripts/worldmap_editor/checks/workspace/probe_workspace_contract.gd`.
func performAction(actionID: String) -> void:
	_onWorkspaceAction(actionID)


func savePoint() -> SavePointScript:
	return _savePoint


## What the painting probe drives instead of a pointer. `previewCells()` returns the SAME list the
## next edit will change, which is the property the probe asserts rather than assumes.
func previewCells() -> Array[Vector2i]:
	return _previewCells()


func brushRadius() -> int:
	return _brushRadius


func setBrushRadius(radius: int) -> void:
	_setBrushRadius(radius)


func layerView() -> LayerViewScript:
	return _layerView


func setLayerHidden(id: String, hidden: bool) -> void:
	_onLayerVisibilityToggled(id, not hidden)


func cancelOpenStroke() -> void:
	_cancelOpenStroke()


## What the document-safety probe drives. `setDocumentIO` is the injection point that lets it make
## a write fail without a real disk and without touching an authored map -- see
## `WorldMapWorkspaceDocumentIO`'s class note.
func setDocumentIO(io: DocumentIOScript) -> void:
	_io = io


func documentIO() -> DocumentIOScript:
	return _io


func recovery() -> RecoveryScript:
	return _recovery


func writeRecoverySnapshot() -> void:
	_writeRecoverySnapshot()


func saveDocumentAs(name: String) -> void:
	_saveDocumentAs(name)


func openDocumentByName(name: String) -> void:
	_openDocumentByName(name)


func historyRevision() -> int:
	return _history.currentRevision()


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
