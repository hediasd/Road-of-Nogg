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
const COLOR_THREAT := Color(0.85, 0.35, 0.55, 0.30)
## The preview reads as light laid over the reach rather than as another terrain colour, so it
## can sit on top of any of the layers below without being mistaken for one of them.
const COLOR_PREVIEW := Color(1.0, 0.94, 0.78, 0.34)
const COLOR_PREVIEW_FOCUS := Color(1.0, 0.72, 0.30, 0.62)

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
