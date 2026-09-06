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
## INPUT OWNERSHIP. Left click routes to the active layer's tool. Middle-drag orbit, right-drag
## pan and the wheel belong entirely to `WorldMapEditorCamera`'s own `_unhandled_input`, which
## fires independently because the camera is a node in the tree -- this controller's
## `_unhandled_input` override does not touch them and does not call `super`, because the base
## class's left-drag-pans-the-camera behaviour would otherwise compete with left click as a
## tool input. `KEY_F` is the one collision in `_unhandled_key_input`: both the base's
## `_recentre()` and the editor camera's own frame-region binding want it, so this class claims
## it and marks the event handled before the camera's `_unhandled_input` can see it too: without
## that, one keypress moves the camera via both paths in the same frame.

extends "res://src/presentation/debug/WorldMapDebugController.gd"

const EditorHudScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorHud.gd")

## One entry per layer this programme will eventually hold data for. `enabled` is false for
## every one of them in Phase A -- see the class note -- and a later item flips its own row to
## true as its data model lands. The id list and order are load-bearing: WME items after this
## one address a layer by id, not by position, but tests and tooling built against this table
## should not need it reordered.
const LAYERS := [
	{"id": "ground", "label": "Ground", "enabled": false},
	{"id": "height", "label": "Height", "enabled": false},
	{"id": "overlay", "label": "Overlay (roads)", "enabled": false},
	{"id": "props", "label": "Props", "enabled": false},
	{"id": "walkability", "label": "Walkability", "enabled": false},
	{"id": "graph", "label": "Graph", "enabled": false},
	{"id": "lighting", "label": "Lighting", "enabled": false},
	{"id": "annotations", "label": "Annotations", "enabled": false},
]

## Two tools, chosen to prove the router rather than to edit anything -- WME-9 is where a real
## brush arrives. NAVIGATE hands every mouse button to camera movement, exactly as if no tool
## were selected; INSPECT is the one thing this item can test, a left click that routes to the
## active layer and nothing else.
const TOOL_NAVIGATE := "navigate"
const TOOL_INSPECT := "inspect"
const TOOLS := [
	{"id": TOOL_NAVIGATE, "label": "Navigate"},
	{"id": TOOL_INSPECT, "label": "Inspect"},
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


func _ready() -> void:
	for layer in LAYERS:
		_layerLocked[str(layer["id"])] = false
		_routeCount[str(layer["id"])] = 0

	super._ready()
	_installEditorCamera()
	_buildEditorUi()
	_editorCamera.rememberRegion(_ground.regionRect())


func _process(delta: float) -> void:
	super._process(delta)
	_editorHud.setOffContract(_editorCamera.offContractReason())


## Swaps the shipping camera for the editor's, in place. Ground, Props and Clouds are left
## exactly as `super._ready()` built them -- only the Camera and its Sky child move.
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


## Left click routes to the active layer's tool. Every other button, and all camera movement,
## belongs to `WorldMapEditorCamera`'s own input handling -- see the class note. Deliberately
## does not call `super`: the base class's left-drag-pans-the-camera would otherwise compete
## with left click as a tool input, and only one of them may own that button.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_routeToActiveLayer()


## `KEY_F` is claimed here and marked handled so the editor camera's own binding cannot also
## see it -- see the class note. Every other key falls through to the base class unchanged.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F:
		_editorCamera.frameRegion(_ground.regionRect())
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)


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


func _onToolSelected(index: int) -> void:
	if index < 0 or index >= TOOLS.size():
		return
	_activeTool = str(TOOLS[index]["id"])


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
