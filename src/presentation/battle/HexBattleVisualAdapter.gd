## The hex battle's visual adapter: the simulation's only way to reach the screen.
##
## EXTENDS `IPlayerTurnVisualAdapter`, which already implements the `IBattleVisualAdapter`
## boundary and already declares `animation_queue_drained`. That signal is INHERITED and must not
## be redeclared here -- a second declaration would shadow the base's, and the controller
## connecting to one while the queue emitted the other is a battle that never advances.
##
## EVERY POSITION GOES THROUGH `HexBattleLayout`. Not one coordinate is converted locally: the
## board view, the cursor, the markers, the unit models and the spell footprints all ask the same
## mapper the exported map was built from, so there is no second definition of where a cell is.
##
## EVENT-TIME POSITIONS, NOT CURRENT ONES. Simulation runs ahead of playback -- that is what the
## queue is for -- so by the time an animation plays, `BattleState` may have moved the unit again.
## Each event therefore captures the positions it happened at and hands those to the effect, which
## is the same discipline `VfxCastContext` was built around.

class_name HexBattleVisualAdapter
extends IPlayerTurnVisualAdapter

const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")
const HexBattleBoardViewScript = preload("res://src/presentation/battle/HexBattleBoardView.gd")
const HexBattleMeshFactoryScript = preload("res://src/presentation/battle/HexBattleMeshFactory.gd")
const HexBattleVfxBridgeScript = preload(
	"res://src/presentation/battle/effects/HexBattleVfxBridge.gd")
const VisualActionQueueScript = preload("res://src/presentation/VisualActionQueue.gd")
const VisualActionScript = preload("res://src/presentation/VisualAction.gd")
const HexBattleCombatFeedbackScript = preload(
	"res://src/presentation/battle/HexBattleCombatFeedback.gd")
const HexBattleDisplayStateScript = preload(
	"res://src/presentation/battle/HexBattleDisplayState.gd")
const HexBattleUnitBadgesScript = preload("res://src/presentation/battle/HexBattleUnitBadges.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const UnitOutlineShader = preload("res://src/presentation/battle/shaders/HexUnitOutline.gdshader")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const VfxCastContextScript = preload("res://src/presentation/effects/VfxCastContext.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

## Overlay colours, kept here rather than in the shared theme: these are board markers this item
## owns, and adding rows to `NoggTheme` would be retuning a shared resource the item may not.
const COLOR_REACHABLE := Color(0.35, 0.62, 1.0, 0.42)
const COLOR_ATTACKABLE := Color(1.0, 0.42, 0.35, 0.45)
const COLOR_CURSOR := Color(1.0, 0.88, 0.42, 0.65)
const COLOR_TARGET := Color(1.0, 0.45, 0.45, 0.7)
const COLOR_THREAT := Color(0.85, 0.35, 0.55, 0.30)
## The preview reads as light laid over the reach rather than as another terrain colour, so it
## can sit on top of any of the layers below without being mistaken for one of them.
const COLOR_PREVIEW := Color(1.0, 0.94, 0.78, 0.34)
const COLOR_PREVIEW_FOCUS := Color(1.0, 0.72, 0.30, 0.62)

## Marker geometry. The rim widths are fractions from the hex edge toward its centre (see
## `HexBattleMeshFactory.appendRingBand`); the edge is dark so the coloured band has contrast
## on light art as well as dark.
const MARKER_THICKNESS := 0.02
const MARKER_RIM_EDGE := 0.05
const MARKER_RIM_BAND := 0.12
const MARKER_RIM_ALPHA := 0.95
const MARKER_RIM_EDGE_COLOR := Color(0.03, 0.03, 0.05, 0.7)

## Hover and selection cues on units. Board markers this file owns, like the overlay colours above.
## Hover is a thin white rim around the unit itself; selection is a ring on the ground under it, so
## the two can be on the same unit at once and still be told apart.
const OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const OUTLINE_WIDTH_PX := 2.5
const COLOR_SELECTED_RING := Color(1.0, 0.97, 0.88, 0.95)
## Inner edge of the ring as a share of the cell's own outline: a band, not a filled hex, so it
## never hides the reach or cursor marker painted on the same cell.
const SELECTED_RING_INNER := 0.78
## Selection ring motion: an entrance that settles once, over a breath that never does
## (docs/VFX_DESIGN.md). Separate constants so either can be retuned alone.
const SELECTED_RING_ENTRANCE_SCALE := 1.3
const SELECTED_RING_ENTRANCE_SECONDS := 0.18
const SELECTED_RING_BREATH_SECONDS := 1.8
const SELECTED_RING_BREATH_ALPHA := 0.45

## Independent overlay layers. Painting one never clears another, which is what lets a pending
## command be previewed over the reach the player is aiming from.
const LAYER_REACH := "reach"
const LAYER_HOVER := "hover"
const LAYER_THREAT := "threat"
const LAYER_TARGET := "target"
const LAYER_PREVIEW := "preview"

## Seconds a unit takes to cross one hex. One step rather than a whole path, so a four-cell walk
## reads four times as long as a one-cell one instead of every move taking the same time.
const MOVE_STEP_SECONDS := 0.16

## Presentation speed bounds, the square adapter's clamp. Floored well above zero so no tween is
## ever given a zero duration, which would be an instant, watchdog-defeating jump.
const PLAYBACK_SPEED_MIN := 0.1
const PLAYBACK_SPEED_MAX := 8.0

var boardView: HexBattleBoardView
var layout: HexBattleLayout

var _map: BattleMapDefinition
var _root: Node3D
## The authoritative board, held only to re-seat models when the queue recovers. Read, never
## written: a visual adapter that wrote to state would be a second simulator.
var _state: BattleState
var _queue: VisualActionQueue
var _models: Dictionary = {}          ## monsterID -> Node3D
var _overlayRoot: Node3D
## Layer name -> its marker nodes. See LAYER_* above.
var _layers: Dictionary = {}
## The combat resolver, for forecasts and affected-cell queries. Optional: the adapter draws a
## board perfectly well without one, and a caller that never previews never needs to set it.
var _combat
var _cursorMarker: MeshInstance3D
var _markerRimMaterial: StandardMaterial3D
var _markerRimMeshes: Dictionary = {}  ## Color -> ArrayMesh
var _disposed := false
var _displayState: HexBattleDisplayState
var _feedback: HexBattleCombatFeedback
## Projected status rows (`HexBattleUnitBadges`). They draw displayed state and never own any.
## Untyped because a brand-new `class_name` is not a usable bare type until a project rescan.
var _badges
## Presentation speed for movement tweens. Combat feedback holds its own copy, set alongside.
var _playbackSpeed := 1.0
var _outlineMaterial: ShaderMaterial
var _hoveredID := -1
var _selectedID := -1
var _selectionRing: MeshInstance3D
var _selectionTween: Tween


func _init(root: Node3D, map: BattleMapDefinition, state: BattleState = null) -> void:
	_root = root
	_map = map
	_state = state
	layout = HexBattleLayoutScript.new(map)

	boardView = HexBattleBoardViewScript.new()
	boardView.name = "HexBoardView"
	_root.add_child(boardView)
	boardView.build(map)

	_overlayRoot = Node3D.new()
	_overlayRoot.name = "HexOverlays"
	_root.add_child(_overlayRoot)

	_queue = VisualActionQueueScript.new(
		_startQueuedAction,
		_finalizeQueuedAction,
		_synchroniseOccupancy,
		func(): return _root.get_tree() if is_instance_valid(_root) else null
	)
	_displayState = HexBattleDisplayStateScript.new()
	_feedback = HexBattleCombatFeedbackScript.new(self, _root, _map, _displayState)
	_badges = HexBattleUnitBadgesScript.new(self, _root)
	_badges.start()
	# The inherited signal, emitted from the queue's own. One hop, so the controller has exactly
	# one thing to wait on and the queue stays the only thing that knows when playback is done.
	_queue.drained.connect(func(): animation_queue_drained.emit())


# --- playback ownership -----------------------------------------------------

func isAnimationBusy() -> bool:
	return _queue != null and _queue.isBusy()


func queuedAnimationCount() -> int:
	return _queue.queuedCount() if _queue != null else 0


func queue() -> VisualActionQueue:
	return _queue


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	disconnectFromEvents()
	clear_tactical_overlays()
	if _queue != null:
		_queue.dispose()
		_queue = null
	if _feedback != null:
		_feedback.dispose()
		_feedback = null
	if _badges != null:
		_badges.dispose()
		_badges = null
	for id in _models.keys():
		var model: Node3D = _models[id]
		if is_instance_valid(model):
			model.queue_free()
	_models.clear()
	if is_instance_valid(boardView):
		boardView.clear()


# --- geometry ---------------------------------------------------------------

## The one conversion. Units stand on the surface of their cell, so the model's origin is the
## cell centre; nothing else in this file computes a position.
func worldPositionOf(cell: Vector2i) -> Vector3:
	return layout.cellCenter(cell)


func modelFor(monsterID: int) -> Node3D:
	return _models.get(monsterID) as Node3D


# --- unit picking and cues ------------------------------------------------------

## The unit whose model is under `point`, or -1. Picks against where models are DRAWN rather than
## where state holds them: playback runs behind the simulation, so a unit mid-walk is where the
## player sees it. `project` maps a world point to the viewport, and is the camera's own
## projection. Unit height comes from the badge row's own measurement, so the pick box and the
## icons over a unit agree about how tall it is.
func unitAtScreenPoint(point: Vector2, project: Callable) -> int:
	var best := -1
	var bestDepth := -INF
	var halfWidth := _map.cellWidth * 0.5
	for id in _models:
		var model := modelFor(int(id))
		if model == null or not is_instance_valid(model):
			continue
		var base := model.global_position
		var top := base + Vector3.UP * HexBattleUnitBadgesScript.anchorHeight(model)
		var baseScreen: Vector2 = project.call(base)
		var topScreen: Vector2 = project.call(top)
		if baseScreen == Vector2.ZERO or topScreen == Vector2.ZERO:
			continue
		# Half a cell either side of the unit's axis, measured on screen at its base, so the pick
		# box narrows with zoom exactly as the model does.
		var right: Vector2 = project.call(base + Vector3(halfWidth, 0.0, 0.0))
		var ahead: Vector2 = project.call(base + Vector3(0.0, 0.0, halfWidth))
		var halfScreen := maxf(
			maxf(baseScreen.distance_to(right), baseScreen.distance_to(ahead)), 1.0
		)
		var rect := Rect2(
			Vector2(baseScreen.x - halfScreen, minf(topScreen.y, baseScreen.y)),
			Vector2(halfScreen * 2.0, absf(baseScreen.y - topScreen.y))
		)
		if not rect.has_point(point):
			continue
		# Where two units overlap on screen, the one lower on screen is nearer the camera, and is
		# the one drawn in front.
		if baseScreen.y > bestDepth:
			bestDepth = baseScreen.y
			best = int(id)
	return best


func hoveredUnit() -> int:
	return _hoveredID


func selectedUnit() -> int:
	return _selectedID


## The quiet hover cue: a rim of constant screen width around the unit's silhouette.
func setHoveredUnit(monsterID: int) -> void:
	if monsterID == _hoveredID:
		return
	_applyOutline(_hoveredID, false)
	_hoveredID = monsterID if _models.has(monsterID) else -1
	_applyOutline(_hoveredID, true)


## The selection cue: a breathing ring on the selected unit's own cell, distinct from the hover rim
## so one unit can carry both at once.
func setSelectedUnit(monsterID: int) -> void:
	if monsterID == _selectedID and _selectionRing != null and is_instance_valid(_selectionRing):
		return
	_clearSelectionRing()
	_selectedID = monsterID if _models.has(monsterID) else -1
	if _selectedID == -1:
		return
	_selectionRing = _buildSelectionRing()
	# A child of the model, so it walks with the unit through playback instead of waiting at the
	# cell the state already moved it to.
	modelFor(_selectedID).add_child(_selectionRing)
	_selectionRing.position = Vector3(0.0, 0.03, 0.0)
	_animateSelectionRing()


## An inverted hull through `material_overlay`: the unit's own materials are never touched, so a
## hover can never leave a unit looking different once the pointer moves on.
func _applyOutline(monsterID: int, on: bool) -> void:
	var model := modelFor(monsterID)
	if model == null or not is_instance_valid(model):
		return
	if on and _outlineMaterial == null:
		_outlineMaterial = ShaderMaterial.new()
		_outlineMaterial.shader = UnitOutlineShader
		_outlineMaterial.set_shader_parameter("outline_color", OUTLINE_COLOR)
		_outlineMaterial.set_shader_parameter("width_px", OUTLINE_WIDTH_PX)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		# The team plinth and the selection ring are not the unit. Outlining the plinth drew a
		# second ring round the base that read as a selection marker.
		if _isUnitChrome(mesh, model):
			continue
		mesh.material_overlay = _outlineMaterial if on else null


func _isUnitChrome(node: Node, model: Node) -> bool:
	var current := node
	while current != null and current != model:
		if current.name == "ModelBase" or current.name == "SelectionRing":
			return true
		current = current.get_parent()
	return false


func _buildSelectionRing() -> MeshInstance3D:
	var outline: PackedVector3Array = layout.cellPolygon(Vector2i.ZERO)
	var centre: Vector3 = layout.cellCenter(Vector2i.ZERO)
	var vertices := PackedVector3Array()
	var count := outline.size()
	for index in range(count + 1):
		var outer: Vector3 = outline[index % count] - centre
		outer.y = 0.0
		vertices.append(outer)
		vertices.append(outer * SELECTED_RING_INNER)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing"
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = COLOR_SELECTED_RING
	ring.material_override = material
	return ring


func _animateSelectionRing() -> void:
	var ring := _selectionRing
	var material := ring.material_override as StandardMaterial3D
	ring.scale = Vector3.ONE * SELECTED_RING_ENTRANCE_SCALE
	var entrance := ring.create_tween()
	entrance.tween_property(ring, "scale", Vector3.ONE, SELECTED_RING_ENTRANCE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var bright := COLOR_SELECTED_RING
	var dim := COLOR_SELECTED_RING
	dim.a = COLOR_SELECTED_RING.a * (1.0 - SELECTED_RING_BREATH_ALPHA)
	_selectionTween = ring.create_tween().set_loops()
	_selectionTween.tween_property(
		material, "albedo_color", dim, SELECTED_RING_BREATH_SECONDS * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_selectionTween.tween_property(
		material, "albedo_color", bright, SELECTED_RING_BREATH_SECONDS * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _clearSelectionRing() -> void:
	if _selectionTween != null and _selectionTween.is_valid():
		_selectionTween.kill()
	_selectionTween = null
	if _selectionRing != null and is_instance_valid(_selectionRing):
		_selectionRing.queue_free()
	_selectionRing = null


## A unit leaving the board takes its cues with it.
func _forgetUnitCues(monsterID: int) -> void:
	if monsterID == _hoveredID:
		_hoveredID = -1
	if monsterID == _selectedID:
		_clearSelectionRing()
		_selectedID = -1


func removeDisplayedModel(monsterID: int) -> void:
	var model := modelFor(monsterID)
	if model != null and is_instance_valid(model):
		model.queue_free()
	_models.erase(monsterID)
	_forgetUnitCues(monsterID)
	_refreshBadges(monsterID)


## Ids of the units that currently have a rendered model, in no particular order.
func shownModelIDs() -> Array:
	return _models.keys()


# --- board events -----------------------------------------------------------

func _on_monster_spawned(
	monsterID: int, monsterName: String, team: int, pos: Vector2i, stats: Dictionary
) -> void:
	var elements: Array = []
	if _state != null:
		var monster := _state.getMonster(monsterID)
		if monster != null:
			elements = monster.elements
	_buildMonsterModel(monsterID, monsterName, team, elements, pos)
	_displayState.registerMonster(monsterID, pos, int(stats.get("hp", 0)))


func _buildMonsterModel(
		monsterID: int, monsterName: String, team: int, elements: Array, pos: Vector2i
) -> Node3D:
	var model := MonsterModelFactoryScript.build(
		monsterName, NoggThemeScript.team_color(team), elements
	)
	model.name = "Unit_%d" % monsterID
	model.position = worldPositionOf(pos)
	_root.add_child(model)
	_models[monsterID] = model
	return model


func _on_monster_moved(monsterID: int, path: Array) -> void:
	var model := modelFor(monsterID)
	if model == null or path.is_empty():
		return
	# Queued rather than applied: the step has to be watchable, and the queue is what the
	# controller's backpressure and drain signal are measured against.
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.MOVE)
	action.monster_id = monsterID
	action.path = path.duplicate()
	_queue.enqueue(action)


## Queued, never applied here. The simulation removes a unit the instant it dies, but the hits
## that killed it are still waiting in the queue; freeing the model now would make those hits land
## on nothing.
func _on_monster_defeated(monsterID: int, killerID: int) -> void:
	_queueRemoval(monsterID, killerID, HexBattleDisplayStateScript.REASON_DEFEATED)


## A withdrawn party leaves the board without dying -- commander loss forces retreat, it does not
## kill. It is queued like a defeat but plays and records as its own removal.
func _on_party_withdrawn(_partyID: int, memberIDs: Array) -> void:
	for value in memberIDs:
		_queueRemoval(int(value), -1, HexBattleDisplayStateScript.REASON_WITHDRAWN)


# --- cursor and overlays ----------------------------------------------------

func show_player_cursor(coord: Vector2i) -> void:
	if _cursorMarker == null:
		_cursorMarker = _buildMarker(COLOR_CURSOR)
		_overlayRoot.add_child(_cursorMarker)
	_cursorMarker.visible = true
	_cursorMarker.position = worldPositionOf(coord) + Vector3(0.0, 0.02, 0.0)


func release_player_cursor() -> void:
	if _cursorMarker != null:
		_cursorMarker.visible = false


func show_target_cursor(coord: Vector2i) -> void:
	show_player_cursor(coord)


## Signature matched to the port exactly, `path` and all: overriding with a different shape would
## leave the base's version live for every caller that passes three arguments, and the overlay
## would silently stop appearing rather than fail loudly.
func show_movement_options(
	reachable: Array, path: Array = [], attackable: Array = []
) -> void:
	clearLayer(LAYER_REACH)
	_paint(LAYER_REACH, reachable, COLOR_REACHABLE)
	_paint(LAYER_REACH, attackable, COLOR_ATTACKABLE)
	_paint(LAYER_REACH, path, COLOR_CURSOR)


func show_target_options(
	targetPositions: Array, affectedPositions: Array = [], _beneficial: bool = false
) -> void:
	clearLayer(LAYER_TARGET)
	# Affected first so a target marker draws over it where the two overlap.
	_paint(LAYER_TARGET, affectedPositions, COLOR_REACHABLE)
	_paint(LAYER_TARGET, targetPositions, COLOR_TARGET)


func show_hover_reach(reachable: Array, attackable: Array = []) -> void:
	clearLayer(LAYER_HOVER)
	_paint(LAYER_HOVER, reachable, COLOR_REACHABLE)
	_paint(LAYER_HOVER, attackable, COLOR_ATTACKABLE)


func clear_hover_reach() -> void:
	clearLayer(LAYER_HOVER)


func show_threat_options(threatened: Array, emphasised: Array = []) -> void:
	clearLayer(LAYER_THREAT)
	_paint(LAYER_THREAT, threatened, COLOR_THREAT)
	_paint(LAYER_THREAT, emphasised, COLOR_ATTACKABLE)


func clear_threat_options() -> void:
	clearLayer(LAYER_THREAT)


## The port's "remove every movement/target overlay". It clears ALL layers, which is what the
## square path meant by it and what a turn ending needs; a caller wanting to drop one layer and
## keep the rest uses `clearLayer`.
func clear_tactical_overlays() -> void:
	for layer: String in _layers.keys():
		clearLayer(layer)


# --- pending-command preview ------------------------------------------------

## Draws what a command WOULD do, on its own layer.
##
## Separate from the reach overlay on purpose. The player aims from the reach, so a preview that
## cleared it would delete the context the aim depends on -- the same reason the square battle
## kept threat and hover as layers of their own rather than repainting one surface.
##
## `cells` is the affected set exactly as the resolver produced it, INCLUDING cells nobody is
## standing on. Passing a shape derived from a radius here would reintroduce the drift HXB-11
## spent an item removing, and a preview that disagrees with the resolution is worse than none.
func showCommandPreview(cells: Array, focusCells: Array = []) -> void:
	clearLayer(LAYER_PREVIEW)
	_paint(LAYER_PREVIEW, cells, COLOR_PREVIEW)
	_paint(LAYER_PREVIEW, focusCells, COLOR_PREVIEW_FOCUS)


func clearCommandPreview() -> void:
	clearLayer(LAYER_PREVIEW)


func previewCellCount() -> int:
	return (_layers.get(LAYER_PREVIEW, []) as Array).size()


func layerCellCount(layer: String) -> int:
	return (_layers.get(layer, []) as Array).size()


func clearLayer(layer: String) -> void:
	var nodes: Array = _layers.get(layer, [])
	for overlay in nodes:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_layers[layer] = []


## Overlay cells are drawn from the board view's own surface geometry rather than a disc or a
## quad, so a marker sits on the hex it names instead of overhanging its neighbours -- the exact
## failure HXB-9's pick geometry was shaped to avoid.
func _paint(layer: String, cells: Array, color: Color) -> void:
	if not _layers.has(layer):
		_layers[layer] = []
	var nodes: Array = _layers[layer]
	for value in cells:
		var cell: Vector2i = value
		if not _map.containsCell(cell):
			continue
		var marker := _buildMarker(color)
		marker.position = worldPositionOf(cell) + Vector3(0.0, _layerHeight(layer), 0.0)
		_overlayRoot.add_child(marker)
		nodes.append(marker)


## Layers are stacked by a hair so two overlapping markers do not z-fight -- the preview sits
## above the reach it is drawn over, which is also the reading order.
func _layerHeight(layer: String) -> float:
	match layer:
		LAYER_THREAT: return 0.012
		LAYER_REACH: return 0.014
		LAYER_HOVER: return 0.016
		LAYER_TARGET: return 0.018
		LAYER_PREVIEW: return 0.020
	return 0.015


func _buildMarker(color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	# Six sides is a hexagon, and it is rotated so its flat edges face the same way the board's do.
	mesh.radial_segments = 6
	mesh.top_radius = _map.cellWidth * 0.5
	mesh.bottom_radius = _map.cellWidth * 0.5
	mesh.height = MARKER_THICKNESS
	marker.mesh = mesh
	marker.rotation_degrees = Vector3(0.0, 30.0, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	marker.material_override = material
	marker.add_child(_buildMarkerRim(color))
	return marker


## The fills were tuned against flat grey, and a translucent fill over painted art mixes
## with whatever colour is under it. The rim does not: it is the marker's own colour at nearly full
## opacity, edged in dark, so the hue and the cell edge both survive any palette. It is a child of
## the fill, so a layer still holds one node per cell and clearing a layer clears its rims.
func _buildMarkerRim(color: Color) -> MeshInstance3D:
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = _markerRimMesh(color)
	if _markerRimMaterial == null:
		_markerRimMaterial = HexBattleMeshFactoryScript.createOverlayMaterial()
	rim.material_override = _markerRimMaterial
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cancel the fill's thirty-degree turn: the rim is built from the layout's own polygon, which
	# is already in board orientation. Lifted to sit on the fill's top face.
	rim.rotation_degrees = Vector3(0.0, -30.0, 0.0)
	rim.position = Vector3(0.0, MARKER_THICKNESS * 0.5 + 0.0005, 0.0)
	return rim


## One mesh per marker colour, shared by every marker of that colour. Hover and aim repaint their
## layers on every cursor move, so building a fresh ring each time would be steady garbage.
func _markerRimMesh(color: Color) -> ArrayMesh:
	if _markerRimMeshes.has(color):
		return _markerRimMeshes[color]
	var origin := layout.cellCenter(Vector2i.ZERO)
	var polygon := PackedVector3Array()
	for corner: Vector3 in layout.cellPolygon(Vector2i.ZERO):
		polygon.append(corner - origin)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	HexBattleMeshFactoryScript.appendRingBand(
		vertices, colors, Vector3.ZERO, polygon, 0.0, MARKER_RIM_EDGE, MARKER_RIM_EDGE_COLOR)
	HexBattleMeshFactoryScript.appendRingBand(
		vertices, colors, Vector3.ZERO, polygon, MARKER_RIM_EDGE, MARKER_RIM_EDGE + MARKER_RIM_BAND,
		Color(color.r, color.g, color.b, MARKER_RIM_ALPHA))
	var mesh := HexBattleMeshFactoryScript.createColoredMesh(vertices, colors)
	_markerRimMeshes[color] = mesh
	return mesh


# --- combat events ----------------------------------------------------------
#
# Event map (IBattleVisualAdapter -> what this adapter does):
#   monster_attacked      strike: attacker lunges, number over the target, HP at impact. A miss
#                         (targetID -1) lunges at the cell with no number and no HP change.
#   spell_cast_started    one cast carrier over the resolved cells; never one per victim.
#   monster_cast_spell    strike per damaged target, summed damage lines, HP at impact.
#   monster_healed        heal number, HP at impact.
#   status_damage_dealt   number over the ticking unit, HP at impact, no lunge.
#   passive_aoe_damage    number over the damaged unit, HP at impact, no lunge.
#   effect_applied/ticked/removed   displayed status rows, in queue order; the projected badge
#                         row for that unit refreshes when the row plays (HexBattleUnitBadges).
#   monster_defeated      queued collapse and removal (see board events).
#   party_withdrawn       queued lift-away and removal, recorded as withdrawn.
#   monster_spawned / monster_moved   model build / queued walk (board events).
# Intentional no-ops, inherited from the base class:
#   passive_triggered     carries no amount or target; its consequence arrives as its own
#                         passive_aoe_damage event, so feedback here would double it.
#   resonance_changed     no visible board consequence; the resonance readout belongs to HPR-6.
#   action_targeted / movement_targeted / turn and activation events   cursor, HUD and
#                         lifecycle presentation owned by the controller and HPR-6/HPR-7.
#   battle_started / battle_ended / round events   lifecycle, HPR-7.

func _on_monster_attacked(
		attackerID: int, targetPos: Vector2i, targetID: int, damage: int, targetNewHP: int
) -> void:
	var payload := _impactPayload(
		HexBattleCombatFeedbackScript.TYPE_STRIKE, attackerID, targetID, targetPos, damage, false)
	if targetID >= 0:
		payload["new_hp"] = targetNewHP
	_queueFeedback(VisualAction.Kind.BUMP, payload)


func _on_spell_cast_started(
		casterID: int,
		centerPos: Vector2i,
		spellName: String,
		element: String,
		targetsHit: int,
		_resolvedRadius: int,
		areaShape: String,
		resolvedAffectedCells: Array,
		resolvedTargetIDs: Array) -> void:
	# Missing or inconsistent event fields are defects to surface, not gaps to fill by guessing.
	var reference := SpellReferencesScript.getReference(spellName)
	if reference.is_empty():
		push_error("Hex cast event names a spell with no catalog reference: %s" % spellName)
	if not _map.containsCell(centerPos):
		push_error("Hex cast event centre %s is off the map (%s)." % [centerPos, spellName])
	if targetsHit != resolvedTargetIDs.size():
		push_error("Hex cast event target count %d does not match its %d target ids (%s)." % [
			targetsHit, resolvedTargetIDs.size(), spellName])
	if resolvedAffectedCells.is_empty() and not resolvedTargetIDs.is_empty():
		push_error("Hex cast event hit targets but carried no affected cells (%s)." % spellName)
	var impactWorld := worldPositionOf(centerPos)
	var casterCell := _eventCellOf(casterID, centerPos)
	var targetWorldPositions: Array[Vector3] = []
	var targetBodyBounds: Array[AABB] = []
	for value in resolvedTargetIDs:
		var targetID := int(value)
		var targetModel := modelFor(targetID)
		if targetModel == null or not is_instance_valid(targetModel):
			targetWorldPositions.append(impactWorld)
			targetBodyBounds.append(VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS)
			continue
		targetWorldPositions.append(worldPositionOf(_eventCellOf(targetID, centerPos)))
		targetBodyBounds.append(_bodyBoundsOf(targetModel))
	var payload := {
		"type": HexBattleCombatFeedbackScript.TYPE_CAST,
		"caster_id": casterID,
		"spell": spellName,
		"source_world": worldPositionOf(casterCell),
		"impact_world": impactWorld,
		"profile": str(reference.get("VFX_PROFILE", "")),
		"element": element,
		"area_shape": areaShape,
		"affected_cells": resolvedAffectedCells.duplicate(true),
		"ground_span": _groundSpanOf(resolvedAffectedCells),
		"surface_path": _surfacePath(casterCell, centerPos),
		"target_ids": resolvedTargetIDs.duplicate(),
		"target_world_positions": targetWorldPositions,
		"target_body_bounds": targetBodyBounds,
		# The donor's deterministic seed: the same cast looks the same on replay.
		"effect_seed": int(hash(spellName)) ^ (casterID * 73856093) \
			^ (centerPos.x * 19349663) ^ (centerPos.y * 83492791),
	}
	_queueFeedback(VisualAction.Kind.CAST_AREA, payload)


func _on_monster_cast_spell(
		casterID: int,
		centerPos: Vector2i,
		targetID: int,
		_spellName: String,
		damageLines: Array,
		targetNewHP: int) -> void:
	var amount := 0
	for line in damageLines:
		amount += int(line.get("damage", 0))
	var payload := _impactPayload(
		HexBattleCombatFeedbackScript.TYPE_STRIKE, casterID, targetID,
		_eventCellOf(targetID, centerPos), amount, false)
	payload["new_hp"] = targetNewHP
	_queueFeedback(VisualAction.Kind.BUMP, payload)


func _on_monster_healed(
		healerID: int,
		centerPos: Vector2i,
		targetID: int,
		_spellName: String,
		healAmount: int,
		targetNewHP: int) -> void:
	var payload := _impactPayload(
		HexBattleCombatFeedbackScript.TYPE_NUMBER, healerID, targetID,
		_eventCellOf(targetID, centerPos), healAmount, true)
	payload["new_hp"] = targetNewHP
	_queueFeedback(VisualAction.Kind.MESSAGE, payload)


func _on_status_damage_dealt(
		monsterID: int, _effectName: String, damage: int, newHP: int) -> void:
	var payload := _impactPayload(
		HexBattleCombatFeedbackScript.TYPE_NUMBER, monsterID, monsterID,
		_eventCellOf(monsterID, Vector2i(-1, -1)), damage, false)
	payload["new_hp"] = newHP
	_queueFeedback(VisualAction.Kind.MESSAGE, payload)


func _on_passive_aoe_damage(
		sourceID: int,
		_passiveName: String,
		targetID: int,
		_element: String,
		damage: int,
		targetNewHP: int) -> void:
	var payload := _impactPayload(
		HexBattleCombatFeedbackScript.TYPE_NUMBER, sourceID, targetID,
		_eventCellOf(targetID, Vector2i(-1, -1)), damage, false)
	payload["new_hp"] = targetNewHP
	_queueFeedback(VisualAction.Kind.MESSAGE, payload)


## The row is copied from the simulation at event time, so the displayed status carries the same
## fields a badge reads, without ever reading a later state.
func _on_effect_applied(
		monsterID: int, effectName: String, duration: int,
		_sourceMonsterID: int, _sourceSpellName: String) -> void:
	var row := {"name": effectName, "remainingTurns": duration}
	if _state != null:
		for existing in _state.getActiveEffects(monsterID):
			if str(existing.get("name", "")) == effectName:
				row = (existing as Dictionary).duplicate(true)
				break
	_queueDisplayUpdate(monsterID, "effect_apply", effectName, duration, row)


func _on_effect_ticked(monsterID: int, effectName: String, remainingTurns: int) -> void:
	_queueDisplayUpdate(monsterID, "effect_tick", effectName, remainingTurns)


func _on_effect_removed(monsterID: int, effectName: String) -> void:
	_queueDisplayUpdate(monsterID, "effect_remove", effectName, 0)


func _impactPayload(
		payloadType: String, sourceID: int, targetID: int, targetCell: Vector2i, amount: int,
		heal: bool
) -> Dictionary:
	return {
		"type": payloadType,
		"source_id": sourceID,
		"target_id": targetID,
		"source_world": worldPositionOf(_eventCellOf(sourceID, targetCell)),
		"target_world": worldPositionOf(targetCell),
		"amount": amount,
		"heal": heal,
	}


## Where a unit stands AT THIS EVENT. Only valid inside an event callback: the simulation emits
## synchronously, so this is the event's own moment, never a later one.
func _eventCellOf(monsterID: int, fallback: Vector2i) -> Vector2i:
	if _state != null and monsterID >= 0:
		var cell := _state.getMonsterPosition(monsterID)
		if _map.containsCell(cell):
			return cell
	return fallback


## Body-only bounds in the model's local space, as the donor measured them: child 1 is the body.
func _bodyBoundsOf(model: Node3D) -> AABB:
	if model.get_child_count() < 2:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	var body := model.get_child(1) as Node3D
	if body == null:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	var accumulated := {"has_bounds": false, "bounds": AABB()}
	var bodyMesh := body as MeshInstance3D
	if bodyMesh != null and bodyMesh.mesh != null:
		accumulated["bounds"] = body.transform * bodyMesh.get_aabb()
		accumulated["has_bounds"] = true
	MonsterModelFactoryScript.accumulateVisualBounds(body, body.transform, accumulated)
	if not accumulated["has_bounds"]:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	return accumulated["bounds"]


## Surface height range across the resolved cells. The donor measured the same range over its
## square diamond; here it is the cells the cast actually covered.
func _groundSpanOf(cells: Array) -> float:
	var lowest := INF
	var highest := -INF
	for value in cells:
		var cell: Vector2i = value
		if not _map.containsCell(cell):
			continue
		var surfaceY := worldPositionOf(cell).y
		lowest = minf(lowest, surfaceY)
		highest = maxf(highest, surfaceY)
	return 0.0 if lowest == INF else highest - lowest


## Event-time surface samples along the hex line from caster to impact, for ground-bound effects
## (the ice trail). Axial interpolation with cube rounding, so it walks the cells a line crosses.
func _surfacePath(fromCell: Vector2i, toCell: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not _map.containsCell(fromCell) or not _map.containsCell(toCell):
		return result
	var steps := HexGridScript.distance(fromCell, toCell)
	var fromAxial := HexGridScript.offsetToAxial(fromCell)
	var toAxial := HexGridScript.offsetToAxial(toCell)
	for step in range(steps + 1):
		var t := float(step) / float(maxi(steps, 1))
		# Nudged off exact ties so rounding never flips between two neighbours.
		var q := lerpf(float(fromAxial.x) + 1e-6, float(toAxial.x) + 1e-6, t)
		var r := lerpf(float(fromAxial.y) + 2e-6, float(toAxial.y) + 2e-6, t)
		var cell := HexGridScript.axialToOffset(_roundAxial(q, r))
		if not _map.containsCell(cell):
			continue
		var world := worldPositionOf(cell)
		if result.is_empty() or not result.back().is_equal_approx(world):
			result.append(world)
	return result


static func _roundAxial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


func _queueDisplayUpdate(
		monsterID: int, operation: String, effectName: String, duration: int,
		row: Dictionary = {}
) -> void:
	_queueFeedback(VisualAction.Kind.MESSAGE, {
		"type": HexBattleCombatFeedbackScript.TYPE_DISPLAY, "monster_id": monsterID,
		"display_op": operation, "effect": effectName, "duration": duration, "row": row,
	})


func _queueRemoval(monsterID: int, killerID: int, reason: String) -> void:
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.DEFEAT)
	action.monster_id = monsterID
	action.killer_id = killerID
	_feedback.attach(action, {"type": HexBattleCombatFeedbackScript.TYPE_REMOVAL,
		"monster_id": monsterID, "reason": reason})
	_queue.enqueue(action)


func _queueFeedback(kind: VisualAction.Kind, payload: Dictionary) -> void:
	var action: VisualAction = VisualActionScript.new(kind)
	action.monster_id = int(payload.get("source_id", payload.get("caster_id",
		payload.get("monster_id", -1))))
	action.target_id = int(payload.get("target_id", -1))
	_feedback.attach(action, payload)
	_queue.enqueue(action)

# --- queue callbacks --------------------------------------------------------

## Starts one queued action, returning whether it holds the queue open. A false return means the
## action finished immediately and the queue may move on this frame.
func _startQueuedAction(action: VisualAction) -> bool:
	match action.kind:
		VisualAction.Kind.MOVE:
			return _startMove(action)
		_:
			if _feedback == null:
				return false
			# The row leaves when the unit starts to leave, not after its collapse has played.
			if action.kind == VisualAction.Kind.DEFEAT and _badges != null:
				_badges.beginRemoval(action.monster_id)
			var started := _feedback.start(action, _queue)
			# Status rows change when their display action plays (an instant action finalizes
			# inside `start`), so this is the event-time refresh, never the event itself.
			_refreshBadgesForAction(action)
			return started


## Walks a unit along the cell centres of its path. Tweened per step rather than straight to the
## destination so the route over the board is legible, which is the whole reason movement is a
## queued action and not a teleport.
func _startMove(action: VisualAction) -> bool:
	var model := modelFor(action.monster_id)
	if model == null or not is_instance_valid(model) or action.path.is_empty():
		return false
	var tree := _root.get_tree()
	if tree == null:
		return false
	var tween := tree.create_tween()
	for value in action.path:
		var cell: Vector2i = value
		tween.tween_property(model, "position", worldPositionOf(cell), MOVE_STEP_SECONDS)
	tween.set_speed_scale(_playbackSpeed)
	_queue.activate(tween, action, MOVE_STEP_SECONDS * float(action.path.size()) / _playbackSpeed)
	return true


func _finalizeQueuedAction(action: VisualAction) -> void:
	if action.kind == VisualAction.Kind.MOVE:
		var model := modelFor(action.monster_id)
		if model != null and is_instance_valid(model) and not action.path.is_empty():
			model.position = worldPositionOf(action.path[action.path.size() - 1])
			_displayState.setPosition(action.monster_id, action.path[action.path.size() - 1])
		return
	if _feedback != null:
		_feedback.finalize(action)


func _refreshBadgesForAction(action: VisualAction) -> void:
	_refreshBadges(action.monster_id)
	if action.target_id != action.monster_id:
		_refreshBadges(action.target_id)


func _refreshBadges(monsterID: int) -> void:
	if _badges != null and monsterID >= 0:
		_badges.refresh(monsterID)


## Puts every model back where the simulation says it is. The queue calls this when it recovers
## from an overflow or a watchdog timeout, which are exactly the moments the screen and the state
## may have diverged.
func _synchroniseOccupancy(exceptMonsterID: int = -1) -> void:
	if _state == null:
		return
	if _feedback != null:
		_feedback.recover(_state)
	for value in _state.monsterPositions.keys():
		var authoritativeID := int(value)
		if modelFor(authoritativeID) != null:
			continue
		var monster = _state.getMonster(authoritativeID)
		if monster != null and monster.is_alive():
			_buildMonsterModel(
				authoritativeID, monster.name, monster.team, monster.elements,
				_state.getMonsterPosition(authoritativeID))
	for monsterID in _models.keys():
		if int(monsterID) == exceptMonsterID:
			continue
		var model: Node3D = _models[monsterID]
		if not is_instance_valid(model):
			continue
		var cell: Vector2i = _state.getMonsterPosition(int(monsterID))
		if not _map.containsCell(cell):
			removeDisplayedModel(int(monsterID))
			continue
		model.visible = true
		model.position = worldPositionOf(cell)
	if _badges != null:
		_badges.refreshAll()


# --- displayed state and playback control ------------------------------------

## What the screen has shown so far. HUD and badge readers use these, never `BattleState`, so a
## number and the HP it changes appear together.
func displayedHitpoints(monsterID: int) -> int:
	return _displayState.hitpointsOf(monsterID)


func displayedPosition(monsterID: int) -> Vector2i:
	return _displayState.positionOf(monsterID)


func displayedEffects(monsterID: int) -> Array:
	return _displayState.effectsOf(monsterID)


## "defeated", "withdrawn", or "" while the unit is still on the board.
func displayedRemovalReason(monsterID: int) -> String:
	return _displayState.removalReason(monsterID)


## Freezes playback: the queue's active tween and every live effect carrier. Presentation only; the
## gate that also stops the battle from advancing is `HexBattlePlayback.setPaused`, which calls this.
func setPlaybackPaused(paused: bool) -> void:
	if _queue != null:
		_queue.setPaused(paused)
	if _feedback != null:
		_feedback.setPaused(paused)


func isPlaybackPaused() -> bool:
	return _queue != null and _queue.isPaused()


## Presentation speed for every tween started from now on and for live effect carriers at once.
func setPlaybackSpeed(scale: float) -> void:
	_playbackSpeed = clampf(scale, PLAYBACK_SPEED_MIN, PLAYBACK_SPEED_MAX)
	if _feedback != null:
		_feedback.setPlaybackScale(_playbackSpeed)


func playbackSpeed() -> float:
	return _playbackSpeed


## Player fast-forward of the active action only. A playing cast jumps to its settle tail first so
## the skip does not cut it mid-burst, then the queue finalizes and moves on.
func skipCurrentAnimation() -> void:
	if _feedback != null:
		_feedback.skipActive()
	if _queue != null:
		_queue.skipActive()


## Abandons queued playback and converges models and displayed state on authoritative state.
func recoverPlayback() -> void:
	if _queue != null:
		_queue.recover()


func pendingFeedbackPayloadCount() -> int:
	return _feedback.pendingPayloadCount() if _feedback != null else 0


func feedbackAttachedCount(payloadType: String) -> int:
	return _feedback.attachedCount(payloadType) if _feedback != null else 0


func feedbackTimeline() -> Array[Dictionary]:
	return _feedback.timeline() if _feedback != null else []


func liveCastEffectCount() -> int:
	return _feedback.liveEffectCount() if _feedback != null else 0


func damageNumberRoot() -> Control:
	return _feedback.numberRoot() if _feedback != null else null


## The projected status row manager, for probes. Null after disposal.
func statusBadges():
	return _badges


# --- forecast ---------------------------------------------------------------

## The combat resolver this adapter forecasts against. Optional and set afterwards rather than
## taken in `_init`, so the constructor the scene and its probe already use keeps working.
func setCombatResolver(resolver) -> void:
	_combat = resolver


## The cells a spell would affect from a position, as the RESOLVER produces them.
##
## `includeUncastableEmpty` is passed true because this is a preview: the resolver's own comment
## says presentation may ask about centres a cast could not be confirmed on, and a player aiming
## needs to see the shape before it is legal, not after.
func previewSpellCells(
	casterID: int, spellSetIndex: int, spellIndex: int, fromPos: Vector2i, centerPos: Vector2i
) -> Array:
	if _combat == null:
		return []
	return _combat.getSpellAffectedPositionsFrom(
		casterID, spellSetIndex, spellIndex, fromPos, centerPos, true
	)


func previewAttackCells(attackerID: int, fromPos: Vector2i) -> Array:
	if _combat == null:
		return []
	return _combat.getBasicAttackTargetPositionsFrom(attackerID, fromPos)


## What a pending command is forecast to do, with its uncertainty stated.
##
## THE HONEST SHAPE OF THE UNCERTAINTY IS NOT A RANGE ON EVERY NUMBER, and this was checked
## rather than assumed. A basic attack in this codebase has NO roll at all: `calculateBasicDamage`
## is arithmetic over attack, defence, elevation, effect multipliers and damage-reduction
## passives, and `executeBasicAttack` applies it directly. Presenting "8-14" for a value that is
## always 11 would be its own dishonesty.
##
## The one genuine roll in combat resolution is `SpellEffectResolver._rollCritical`, which is a
## single `randf()` against the caster's critical chance. So a spell's damage is a TWO-POINT
## distribution with a known probability, not a uniform band -- reported here as `minimum`,
## `maximum` and `critical_chance`, which collapse to one exact number when the chance is zero.
##
## `lethal` is what the player actually wants to know and is knowable exactly, because
## `take_damage` clamps to remaining hitpoints. `reactive_risk` flags the other way a forecast
## can be wrong: an ON_TARGETED passive fires BEFORE the attack lands and can change or end the
## exchange, so the number is conditional on the premise surviving.
##
## `is_simulation` is passed true throughout. The damage-reduction path emits a
## `passive_triggered` event when it is false, and a forecast that fired battle events every time
## the cursor moved would be a forecast that changes the battle it is describing.
func forecastAttack(attackerID: int, targetPos: Vector2i) -> Dictionary:
	if _combat == null or _state == null:
		return {"available": false}
	# Bounds first: Matrix.at indexes its rows directly and has no guard of its own, so an
	# off-board cell -- which a cursor at the edge asks about constantly -- would fault rather
	# than report "nothing to forecast".
	if not _map.containsCell(targetPos):
		return {"available": false}
	var attacker = _state.getMonster(attackerID)
	var targetID: int = _state.board.at(targetPos)
	if attacker == null or targetID == 0:
		return {"available": false}
	var target = _state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {"available": false}

	var damage: int = _combat.calculateBasicDamage(attacker, target, true)
	return _forecast(damage, damage, 0.0, target, targetID)


func forecastSpell(
	casterID: int, spellSetIndex: int, spellIndex: int, targetPos: Vector2i
) -> Dictionary:
	if _combat == null or _state == null:
		return {"available": false}
	if not _map.containsCell(targetPos):
		return {"available": false}
	var caster = _state.getMonster(casterID)
	var targetID: int = _state.board.at(targetPos)
	if caster == null or targetID == 0:
		return {"available": false}
	var target = _state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {"available": false}
	var spell = _combat._resolveSpell(caster, spellSetIndex, spellIndex)
	if spell == null:
		return {"available": false}

	var base: int = 0
	if spell.damage_lines.size() > 0:
		base = int((spell.damage_lines[0] as Dictionary).get("damage", 0))
	var element: String = str(spell.element) if "element" in spell else "none"
	var normal: int = _combat.calculateSpellDamage(
		caster, target, base, element, true, Vector2i(-1, -1), false
	)
	var critical: int = _combat.calculateSpellDamage(
		caster, target, base, element, true, Vector2i(-1, -1), true
	)
	var chance: float = caster.get_critical_chance()
	return _forecast(mini(normal, critical), maxi(normal, critical), chance, target, targetID)


func _forecast(
	minimum: int, maximum: int, criticalChance: float, target, targetID: int
) -> Dictionary:
	var remaining: int = int(target.hitpoints)
	return {
		"available": true,
		"minimum": minimum,
		"maximum": maximum,
		"critical_chance": criticalChance,
		# Exact when there is no roll AND nothing can intervene first.
		"exact": minimum == maximum,
		"target_hitpoints": remaining,
		"lethal": minimum >= remaining,
		"possibly_lethal": maximum >= remaining and minimum < remaining,
		"reactive_risk": _hasReactivePassive(targetID),
	}


## Whether the target retaliates when targeted. `PassiveSkillResolver.fireOnTargeted` runs before
## the attack resolves, so a forecast against a retaliating target is conditional in a way the
## number alone cannot express.
func _hasReactivePassive(targetID: int) -> bool:
	if _state == null:
		return false
	var target = _state.getMonster(targetID)
	if target == null:
		return false
	for passive in target.passives:
		if str(passive.trigger) == "ON_TARGETED":
			return true
	return false


## Plays a cast over its RESOLVED cells, which is the whole reason HXB-11 exists: the affected set
## is what was resolved, including the cells nobody was standing on.
func playSpell(
	profileID: String,
	casterID: int,
	centerCell: Vector2i,
	affectedCells: Array,
	color: Color,
	context: VfxCastContext = null
) -> VfxPlayback:
	var footprint := HexBattleVfxBridgeScript.footprintFor(affectedCells, _map)
	var playback := HexBattleVfxBridgeScript.createPlayback(
		profileID, _root, worldPositionOf(centerCell), color, footprint, context
	)
	if playback != null:
		playback.play(int(casterID), VfxPlayback.MODE_BATTLE)
	return playback
