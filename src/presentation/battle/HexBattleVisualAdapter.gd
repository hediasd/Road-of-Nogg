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
const HexBattleVfxBridgeScript = preload(
	"res://src/presentation/battle/effects/HexBattleVfxBridge.gd")
const VisualActionQueueScript = preload("res://src/presentation/VisualActionQueue.gd")
const VisualActionScript = preload("res://src/presentation/VisualAction.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Overlay colours, kept here rather than in the shared theme: these are board markers this item
## owns, and adding rows to `NoggTheme` would be retuning a shared resource the item may not.
const COLOR_REACHABLE := Color(0.35, 0.62, 1.0, 0.42)
const COLOR_ATTACKABLE := Color(1.0, 0.42, 0.35, 0.45)
const COLOR_CURSOR := Color(1.0, 0.88, 0.42, 0.65)
const COLOR_TARGET := Color(1.0, 0.45, 0.45, 0.7)

## Seconds a unit takes to cross one hex. One step rather than a whole path, so a four-cell walk
## reads four times as long as a one-cell one instead of every move taking the same time.
const MOVE_STEP_SECONDS := 0.16

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
var _overlays: Array[Node3D] = []
var _cursorMarker: MeshInstance3D
var _disposed := false


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


# --- board events -----------------------------------------------------------

func _on_monster_spawned(
	monsterID: int, monsterName: String, team: int, pos: Vector2i, _stats: Dictionary
) -> void:
	var model := MonsterModelFactoryScript.build(
		monsterName, NoggThemeScript.team_color(team), []
	)
	model.name = "Unit_%d" % monsterID
	model.position = worldPositionOf(pos)
	_root.add_child(model)
	_models[monsterID] = model


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


func _on_monster_defeated(monsterID: int, _killerID: int) -> void:
	var model := modelFor(monsterID)
	if model != null and is_instance_valid(model):
		model.queue_free()
	_models.erase(monsterID)


## A withdrawn party leaves the board without dying -- commander loss forces retreat, it does not
## kill. Disposal is the same as defeat; the distinction is the simulation's, not the screen's.
func _on_party_withdrawn(_partyID: int, memberIDs: Array) -> void:
	for value in memberIDs:
		var monsterID := int(value)
		var model := modelFor(monsterID)
		if model != null and is_instance_valid(model):
			model.queue_free()
		_models.erase(monsterID)


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
	clear_tactical_overlays()
	_paint(reachable, COLOR_REACHABLE)
	_paint(attackable, COLOR_ATTACKABLE)
	_paint(path, COLOR_CURSOR)


func show_target_options(
	targetPositions: Array, affectedPositions: Array = [], _beneficial: bool = false
) -> void:
	clear_tactical_overlays()
	# Affected first so a target marker draws over it where the two overlap.
	_paint(affectedPositions, COLOR_REACHABLE)
	_paint(targetPositions, COLOR_TARGET)


func show_hover_reach(reachable: Array, attackable: Array = []) -> void:
	show_movement_options(reachable, [], attackable)


func clear_hover_reach() -> void:
	clear_tactical_overlays()


func clear_tactical_overlays() -> void:
	for overlay in _overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_overlays.clear()


## Overlay cells are drawn from the board view's own surface geometry rather than a disc or a
## quad, so a marker sits on the hex it names instead of overhanging its neighbours -- the exact
## failure HXB-9's pick geometry was shaped to avoid.
func _paint(cells: Array, color: Color) -> void:
	for value in cells:
		var cell: Vector2i = value
		if not _map.containsCell(cell):
			continue
		var marker := _buildMarker(color)
		marker.position = worldPositionOf(cell) + Vector3(0.0, 0.015, 0.0)
		_overlayRoot.add_child(marker)
		_overlays.append(marker)


func _buildMarker(color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	# Six sides is a hexagon, and it is rotated so its flat edges face the same way the board's do.
	mesh.radial_segments = 6
	mesh.top_radius = _map.cellWidth * 0.5
	mesh.bottom_radius = _map.cellWidth * 0.5
	mesh.height = 0.02
	marker.mesh = mesh
	marker.rotation_degrees = Vector3(0.0, 30.0, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	marker.material_override = material
	return marker


# --- spells -----------------------------------------------------------------

# --- queue callbacks --------------------------------------------------------

## Starts one queued action, returning whether it holds the queue open. A false return means the
## action finished immediately and the queue may move on this frame.
func _startQueuedAction(action: VisualAction) -> bool:
	match action.kind:
		VisualAction.Kind.MOVE:
			return _startMove(action)
		_:
			# Every other kind is presentation this item does not own yet; it passes through
			# rather than stalling the queue, which would hang the controller waiting to drain.
			return false


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
	_queue.activate(tween, action, MOVE_STEP_SECONDS * float(action.path.size()))
	return true


func _finalizeQueuedAction(action: VisualAction) -> void:
	if action.kind != VisualAction.Kind.MOVE:
		return
	var model := modelFor(action.monster_id)
	if model != null and is_instance_valid(model) and not action.path.is_empty():
		# Snapped to the last cell so a tween interrupted mid-step cannot leave a unit standing
		# between two hexes.
		model.position = worldPositionOf(action.path[action.path.size() - 1])


## Puts every model back where the simulation says it is. The queue calls this when it recovers
## from an overflow or a watchdog timeout, which are exactly the moments the screen and the state
## may have diverged.
func _synchroniseOccupancy(exceptMonsterID: int = -1) -> void:
	if _state == null:
		return
	for monsterID in _models.keys():
		if int(monsterID) == exceptMonsterID:
			continue
		var model: Node3D = _models[monsterID]
		if not is_instance_valid(model):
			continue
		var cell: Vector2i = _state.getMonsterPosition(int(monsterID))
		if not _map.containsCell(cell):
			model.visible = false
			continue
		model.visible = true
		model.position = worldPositionOf(cell)


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
