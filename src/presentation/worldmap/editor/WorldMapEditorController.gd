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
## both fire for one keypress.

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

## Which camera gesture the mouse is mid-drag on, held here rather than on the camera -- see the
## class note on input ownership.
var _cameraOrbiting := false
var _cameraPanning := false


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
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_routeToActiveLayer()
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
		if _cameraOrbiting:
			_editorCamera.orbitByScreenDelta(motion.relative)
		elif _cameraPanning:
			_editorCamera.panBy(motion.relative)


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
			_editorCamera.frameRegion(_ground.regionRect())
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_editorCamera.snapToContract()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_editorCamera.toggleOrtho()
			get_viewport().set_input_as_handled()
		_:
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
