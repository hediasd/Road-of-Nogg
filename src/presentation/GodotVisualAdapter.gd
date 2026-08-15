## GodotVisualAdapter — A visual bridge that creates and animates 3D placeholders
## for the underlying headless battle simulation.

class_name GodotVisualAdapter
extends IPlayerTurnVisualAdapter

const MONSTER_PICK_COLLISION_LAYER := 1 << 7
const TILE_PICK_COLLISION_LAYER := 1 << 6
const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const BattleVisualEffectsScript = preload("res://src/presentation/BattleVisualEffects.gd")
const BattleCursorControllerScript = preload("res://src/presentation/BattleCursorController.gd")
const MonsterVisualRegistryScript = preload("res://src/presentation/MonsterVisualRegistry.gd")
const StatusEffectIconsScript = preload("res://src/presentation/StatusEffectIcons.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")
const DamageNumberBillboardScript = preload("res://src/presentation/effects/DamageNumberBillboard.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const VisualActionQueueScript = preload("res://src/presentation/VisualActionQueue.gd")
const VisualActionScript = preload("res://src/presentation/VisualAction.gd")
const VfxCastContextScript = preload("res://src/presentation/effects/VfxCastContext.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const TERRAIN_CELL_HEIGHT := BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
const TERRAIN_SURFACE_OFFSET := TERRAIN_CELL_HEIGHT * 0.5
const ABYSS_VERTICAL_OFFSET := -0.15
const OVERLAY_LIFT := 0.015
const MOVE_STEP_DURATION := 0.28
const MOVE_HEIGHT_DURATION_FACTOR := 0.08
const MOVE_ARC_CLEARANCE := 0.3

## animation_queue_drained is inherited from IPlayerTurnVisualAdapter and must
## not be redeclared here: a redeclared signal is a different signal, and a
## controller connected through the port would never be notified.

var state: BattleState
var root_node: Node3D
var visual_parent: Node3D
var grid_node: Node3D
var monsters_node: Node3D
var overlay_node: Node3D
var threat_overlay_node: Node3D
var hover_overlay_node: Node3D
var damage_number_layer: CanvasLayer
var damage_number_root: Control
var _cursor: MeshInstance3D
var _cursor_controller: BattleCursorController

var _queue: VisualActionQueue
var _live_effects: Array[WeakRef] = []
var _live_effect_profiles: Dictionary = {}
var _active_cast_effect: WeakRef

var visualEffects

var _monster_visuals: Dictionary = {} # monsterID -> MeshInstance3D
var _position_tweens: Dictionary = {} # monsterID -> Tween
var _defeat_tweens: Dictionary = {} # monsterID -> Tween
var _tile_columns: Dictionary = {} # Vector2i -> Node3D
var _tile_surfaces: Dictionary = {} # Vector2i -> MeshInstance3D

func _init(_state: BattleState, _root_node: Node3D, _visual_parent: Node3D = null) -> void:
	state = _state
	root_node = _root_node
	visual_parent = _visual_parent if _visual_parent != null else _root_node
	visualEffects = BattleVisualEffectsScript.new(_monster_visuals)

	grid_node = Node3D.new()
	grid_node.name = "Grid"
	visual_parent.add_child(grid_node)

	monsters_node = Node3D.new()
	monsters_node.name = "Monsters"
	visual_parent.add_child(monsters_node)

	overlay_node = Node3D.new()
	overlay_node.name = "TacticalOverlays"
	visual_parent.add_child(overlay_node)

	damage_number_layer = CanvasLayer.new()
	damage_number_layer.name = "DamageNumbers"
	damage_number_layer.layer = NoggThemeScript.WORLD_EFFECT_LAYER
	root_node.add_child(damage_number_layer)
	damage_number_root = Control.new()
	damage_number_root.name = "DamageNumberRoot"
	damage_number_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_number_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_number_layer.add_child(damage_number_root)

	threat_overlay_node = Node3D.new()
	threat_overlay_node.name = "ThreatOverlays"
	visual_parent.add_child(threat_overlay_node)

	# A third overlay layer, for exactly the reason the threat layer is a second
	# one: hover reach is additive over whatever the player is currently aiming
	# with, so it must not be destroyed by `clear_tactical_overlays()` and must
	# not destroy the aim when it clears itself.
	hover_overlay_node = Node3D.new()
	hover_overlay_node.name = "HoverReachOverlays"
	visual_parent.add_child(hover_overlay_node)

	_cursor = BattleMeshFactoryScript.createMesh("cursor", Color(0.2, 0.6, 1.0, 0.5))
	visual_parent.add_child(_cursor)
	_cursor_controller = BattleCursorControllerScript.new(_cursor, _surface_y)

	_queue = VisualActionQueueScript.new(
		_start_queued_animation,
		_finalize_animation,
		_synchronize_visual_occupancy,
		func(): return root_node.get_tree() if is_instance_valid(root_node) else null
	)
	_queue.drained.connect(func(): animation_queue_drained.emit())


func _log(text: String) -> void:
	if root_node and "log_label" in root_node and root_node.log_label:
		root_node.log_label.text += text + "\n"

## Actor (left) and target (right) status windows now render live monster
## stats resolved from `state` at DISPLAY time, not a frozen string baked when
## the action was queued -- correctly reflects any state change between
## queueing and playback (e.g. a second hit landing before this one animates),
## and is strictly more current than the old text ever was. `-1` clears the
## window to an empty frame rather than a placeholder string (docs/UI_DESIGN.md
## §8, item 4).
func _update_actor_panel(monsterID: int) -> void:
	if root_node and root_node.has_method("_setActorPanelMonster"):
		root_node._setActorPanelMonster(monsterID)

func _update_target_panel(monsterID: int) -> void:
	if root_node and root_node.has_method("_setTargetPanelMonster"):
		root_node._setTargetPanelMonster(monsterID)

## Prose that is not about any one monster's stats (battle-complete, etc.)
## goes to the prompt window instead of a status panel.
func _update_prompt(text: String) -> void:
	if root_node and "battle_ui" in root_node and root_node.battle_ui != null:
		root_node.battle_ui.command_menu.setStatus(text)

# --- HELPERS ---

func _surface_y(coord: Vector2i) -> float:
	var logicalHeight = maxi(state.getHeight(coord), 0)
	var verticalOffset = (
		ABYSS_VERTICAL_OFFSET
		if state.terrainBoard.at(coord) == BattleState.TERRAIN_ABYSS else
		0.0
	)
	return float(logicalHeight) * TERRAIN_CELL_HEIGHT + TERRAIN_SURFACE_OFFSET + verticalOffset


func _coord_to_surface_pos3d(coord: Vector2i) -> Vector3:
	return Vector3(coord.x, _surface_y(coord), coord.y)


## Presentation-only event-time surface samples for target-bound delivery VFX.
## The simulator still emits only board coordinates; this snapshots their
## rendered heights before the visual action can sit behind newer simulation.
func _surface_path_world_positions(fromPos: Vector2i, toPos: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not state.withinBounds(fromPos) or not state.withinBounds(toPos):
		return result
	var delta := toPos - fromPos
	var steps := maxi(absi(delta.x), absi(delta.y))
	for step: int in range(steps + 1):
		var progress := float(step) / float(maxi(steps, 1))
		var coord := Vector2i(
			roundi(lerpf(float(fromPos.x), float(toPos.x), progress)),
			roundi(lerpf(float(fromPos.y), float(toPos.y), progress)))
		if result.is_empty() or result.back() != _coord_to_surface_pos3d(coord):
			result.append(_coord_to_surface_pos3d(coord))
	return result


func _footprint_ground_span(center: Vector2i, radius: int) -> float:
	var footprint_radius := maxi(radius, 0)
	var minimum_y := INF
	var maximum_y := -INF
	for offset_x: int in range(-footprint_radius, footprint_radius + 1):
		for offset_y: int in range(-footprint_radius, footprint_radius + 1):
			if absi(offset_x) + absi(offset_y) > footprint_radius:
				continue
			var coord := center + Vector2i(offset_x, offset_y)
			if not state.withinBounds(coord):
				continue
			var surface_y := _surface_y(coord)
			minimum_y = minf(minimum_y, surface_y)
			maximum_y = maxf(maximum_y, surface_y)
	return 0.0 if minimum_y == INF else maximum_y - minimum_y


func _stop_position_tween(monsterID: int) -> void:
	if not _position_tweens.has(monsterID):
		return
	var tween: Tween = _position_tweens[monsterID]
	if tween != null and tween.is_valid():
		tween.kill()
	_position_tweens.erase(monsterID)


func _synchronize_visual_occupancy(exceptMonsterID: int = -1) -> void:
	state.assertValidOccupancy()
	for monsterID in _monster_visuals.keys():
		if monsterID == exceptMonsterID:
			continue
		_stop_position_tween(monsterID)
		var visual := _liveMonsterVisual(monsterID)
		if visual == null:
			continue
		var authoritativePos = state.getMonsterPosition(monsterID)
		if not state.withinBounds(authoritativePos):
			visual.visible = false
			continue
		visual.position = _coord_to_surface_pos3d(authoritativePos)


func _track_position_tween(monsterID: int, tween: Tween) -> void:
	_position_tweens[monsterID] = tween
	tween.finished.connect(_on_position_tween_finished.bind(monsterID, tween))


func _on_position_tween_finished(monsterID: int, tween: Tween) -> void:
	if _position_tweens.get(monsterID) == tween:
		_position_tweens.erase(monsterID)


func isAnimationBusy() -> bool:
	return _queue.isBusy()


func activeAnimationKind() -> String:
	return _queue.activeActionKind()


func queuedAnimationCount() -> int:
	return _queue.queuedCount()


func setVisualPaused(paused: bool) -> void:
	_queue.setPaused(paused)
	_set_live_effect_playback_scale(0.0 if paused else _animation_speed_scale)


func isVisualPaused() -> bool:
	return _queue.isPaused()


## Presentation-only pacing: never read by the simulation, never affects event
## ordering or replay input. Floored well above zero so a slider dragged to its
## minimum cannot produce a zero-duration tween, which Tween.set_speed_scale()
## would turn into an instant, watchdog-defeating jump.
var _animation_speed_scale: float = 1.0

func setAnimationSpeedScale(scale: float) -> void:
	_animation_speed_scale = clampf(scale, 0.1, 8.0)
	if not isVisualPaused():
		_set_live_effect_playback_scale(_animation_speed_scale)


func getAnimationSpeedScale() -> float:
	return _animation_speed_scale


func _live_effect_from_ref(effect_ref: WeakRef) -> VfxPlayback:
	if effect_ref == null:
		return null
	var effect = effect_ref.get_ref()
	if (
			effect == null
			or not is_instance_valid(effect)
			or not (effect is VfxPlayback)
			or effect.is_queued_for_deletion()
	):
		return null
	return effect as VfxPlayback


func _prune_live_effects() -> void:
	var live_ids: Dictionary = {}
	for index: int in range(_live_effects.size() - 1, -1, -1):
		var effect := _live_effect_from_ref(_live_effects[index])
		if effect == null:
			_live_effects.remove_at(index)
			continue
		live_ids[effect.get_instance_id()] = true
	for instance_id in _live_effect_profiles.keys():
		if not live_ids.has(instance_id):
			_live_effect_profiles.erase(instance_id)


func _on_live_effect_exiting(instance_id: int) -> void:
	for index: int in range(_live_effects.size() - 1, -1, -1):
		var effect_ref := _live_effects[index]
		var effect = effect_ref.get_ref() if effect_ref != null else null
		if (
				effect == null
				or not is_instance_valid(effect)
				or effect.get_instance_id() == instance_id
		):
			_live_effects.remove_at(index)
	_live_effect_profiles.erase(instance_id)
	# The one place `_active_cast_effect` is cleared: when the effect it points
	# at is the one actually exiting the tree, not when the action's queue hold
	# expires. The hold (~0.6x the effect's duration) is deliberately shorter
	# than some effects' full runtime, so clearing on the action boundary let
	# `skipCurrentAnimation()` lose the reference while the effect was still
	# playing out its tail.
	var active_effect := _live_effect_from_ref(_active_cast_effect)
	if active_effect == null or active_effect.get_instance_id() == instance_id:
		_active_cast_effect = null
	_rebalance_live_effect_intensity()


func _remove_live_effect(instance_id: int) -> VfxPlayback:
	var removed: VfxPlayback = null
	for index: int in range(_live_effects.size() - 1, -1, -1):
		var effect_ref := _live_effects[index]
		var effect = effect_ref.get_ref() if effect_ref != null else null
		if effect == null or not is_instance_valid(effect):
			_live_effects.remove_at(index)
		elif effect.get_instance_id() == instance_id:
			removed = effect as VfxPlayback
			_live_effects.remove_at(index)
	_live_effect_profiles.erase(instance_id)
	return removed


func _enforce_live_effect_cap(profile_id: String, maximum_live: int) -> void:
	if maximum_live <= 0:
		return
	_prune_live_effects()
	var matching_effects: Array = []
	for effect_ref: WeakRef in _live_effects:
		var effect := _live_effect_from_ref(effect_ref)
		if (
				effect != null
				and _live_effect_profiles.get(effect.get_instance_id(), "") == profile_id
		):
			matching_effects.append(effect)
	while matching_effects.size() >= maximum_live:
		var oldest := matching_effects.pop_front() as VfxPlayback
		var removed := _remove_live_effect(oldest.get_instance_id())
		if removed != null:
			removed.dispose()


func _track_live_effect(effect: VfxPlayback, profile_id: String) -> WeakRef:
	var effect_ref: WeakRef = weakref(effect)
	var instance_id := effect.get_instance_id()
	_live_effects.append(effect_ref)
	_live_effect_profiles[instance_id] = profile_id
	effect.tree_exiting.connect(
		_on_live_effect_exiting.bind(instance_id), CONNECT_ONE_SHOT
	)
	_rebalance_live_effect_intensity()
	return effect_ref


func _rebalance_live_effect_intensity() -> void:
	_prune_live_effects()
	var scalable_effects: Array = []
	for effect_ref: WeakRef in _live_effects:
		var effect := _live_effect_from_ref(effect_ref)
		if effect != null and effect.has_method("setIntensityScale"):
			scalable_effects.append(effect)
	var intensity := 1.0 / float(maxi(scalable_effects.size(), 1))
	for effect: VfxPlayback in scalable_effects:
		effect.call("setIntensityScale", intensity)


func _set_live_effect_playback_scale(scale: float) -> void:
	_prune_live_effects()
	for effect_ref: WeakRef in _live_effects:
		var effect := _live_effect_from_ref(effect_ref)
		if effect != null:
			effect.set_playback_scale(scale)


func _dispose_live_effects() -> void:
	var effects: Array = []
	for effect_ref: WeakRef in _live_effects:
		var effect := _live_effect_from_ref(effect_ref)
		if effect != null:
			effects.append(effect)
	_live_effects.clear()
	_live_effect_profiles.clear()
	_active_cast_effect = null
	for effect: VfxPlayback in effects:
		effect.dispose()


## Fraction of a spawned effect's own runtime that an action is held on screen
## for. "Mostly through", not "fully through": overlapping the tail of one
## effect with the start of the next is what keeps a battle from reading as a
## slideshow. Applied to the effect's duration, never to the tween's.
const ACTION_HOLD_FRACTION := 0.6

## Lifetime of the defeat animation's capsule-shatter particles. Named so the
## hold below is derived from it rather than from a second copy of the number.
const CAPSULE_SHATTER_LIFETIME := 0.42


## The one path every timed animation activates through.
##
## `holdDuration` is how long the action's *spawned effects* occupy the screen.
## Those effects — cast-area playback, a particle burst — are not part of the
## caster's tween, so the tween's own duration says nothing about them, and the
## queue advancing on it alone cut them off mid-play. When the hold outlasts
## the tween, the remainder is appended to that same tween as an explicit
## `tween_interval`.
##
## Appending to the tween rather than teaching `VisualActionQueue` a separate
## hold is deliberate, and buys four things for free: the queue keeps exactly
## one completion source (`tween.finished`) and all four of its documented
## invariants untouched; `setPaused()` freezes the hold because it pauses this
## very tween; `set_speed_scale()` compresses the hold along with everything
## else, so the hold obeys the speed setting; and `skipActive()`'s `kill()`
## cuts the hold short, so skip works on it too. A parallel SceneTree timer —
## the obvious alternative — would silently break pause and skip, because
## neither reaches a timer.
##
## `tween_interval` is an explicit wait, not padding disguised as animation:
## it declares "then hold", which is exactly what is meant.
func _activateScaled(
		tween: Tween,
		action: VisualAction,
		duration: float,
		holdDuration: float = 0.0) -> void:
	var visibleDuration := duration
	if holdDuration > duration:
		# chain() so this waits for every preceding step, including on a
		# parallel tween where an appended step would otherwise run alongside.
		tween.chain().tween_interval(holdDuration - duration)
		visibleDuration = holdDuration
	tween.set_speed_scale(_animation_speed_scale)
	# The queue uses this only to size its watchdog margin, so it must be the
	# real elapsed time: the full visible duration, divided by the speed scale
	# the tween is now running at. Left unscaled, slow motion would let the
	# watchdog fire before the tween finished and misreport a stall.
	_queue.activate(tween, action, visibleDuration / _animation_speed_scale)


func skipCurrentAnimation() -> void:
	var effect := _live_effect_from_ref(_active_cast_effect)
	if effect != null:
		effect.skip_to_settle()
	_queue.skipActive()


func _start_queued_animation(action: VisualAction) -> bool:
	match action.kind:
		VisualAction.Kind.FOCUS:
			_present_queued_message(action)
		VisualAction.Kind.MESSAGE:
			_present_queued_message(action)
			return _start_message_damage_number(action)
		VisualAction.Kind.MOVE:
			return _start_move_animation(action)
		VisualAction.Kind.BUMP:
			_present_queued_message(action)
			return _start_bump_animation(action)
		VisualAction.Kind.CAST_AREA:
			_present_queued_message(action)
			return _start_cast_area_animation(action)
		VisualAction.Kind.DEFEAT:
			_present_queued_message(action)
			return _start_defeat_animation(action)
		_:
			push_warning("Ignoring unknown visual animation kind: %s" % action.kind_name())
	return false


func _finalize_animation(action: VisualAction) -> void:
	if action.kind == VisualAction.Kind.CAST_AREA:
		# `_active_cast_effect` is intentionally not cleared here. The queue
		# hold this action finalizes on is shorter than some effects' full
		# runtime; the effect itself clears the reference on exiting the tree
		# (`_on_live_effect_exiting`), so `skipCurrentAnimation()` can still
		# reach a storm still playing out after its action has finalized.
		return
	var monsterID := action.monster_id
	var visual := _liveMonsterVisual(monsterID)
	if action.kind == VisualAction.Kind.MOVE and visual != null:
		if not action.path.is_empty():
			visual.position = _coord_to_surface_pos3d(action.path.back())
	elif action.kind == VisualAction.Kind.BUMP and visual != null:
		if action.has_origin:
			visual.position = action.origin
	elif action.kind == VisualAction.Kind.DEFEAT:
		_defeat_tweens.erase(monsterID)
		if visual != null:
			_monster_visuals.erase(monsterID)
			visual.queue_free()
	_position_tweens.erase(monsterID)


func _present_queued_message(action: VisualAction) -> void:
	if state.withinBounds(action.coord):
		match action.cursor_mode:
			VisualAction.CursorMode.TURN:
				_cursor_controller.focusTurn(action.coord)
			VisualAction.CursorMode.MOVEMENT:
				_cursor_controller.focusMovementDestination(action.coord)
			_:
				_focus_cursor_on_coord(action.coord)
	if action.has_left_monster:
		_update_actor_panel(action.left_monster_id)
	if action.has_right_monster:
		_update_target_panel(action.right_monster_id)
	if not action.prompt_text.is_empty():
		_update_prompt(action.prompt_text)
	if not action.log_text.is_empty():
		_log(action.log_text)


## A heal is a MESSAGE-kind action with no tween of its own — `_present_queued_message`
## is a synchronous state update, and the queue has always advanced past it
## instantly. That is still correct for every other MESSAGE action; a heal
## carrying a number is the one case that must hold, so the queue does not
## advance while the number is still on screen.
##
## The number is spawned fire-and-forget and runs on its own tween, exactly as
## a `CAST_AREA` action does for spell playback; what the queue waits on is a
## short interval
## tween representing the *hold*, not the number's whole animation. Handing the
## queue the number's own tween instead would block it for the full drift and
## fade — and the settled rule is "mostly through, not fully through", so the
## tail of the fade is meant to overlap whatever comes next.
func _start_message_damage_number(action: VisualAction) -> bool:
	if not action.has_damage_number:
		return false
	var targetID := action.right_monster_id if action.has_right_monster else action.target_id
	var targetVisual := _liveMonsterVisual(targetID)
	if targetVisual == null:
		return false
	var damageTween: Tween = _spawn_damage_number(
		targetVisual.position, action.damage_number, action.is_heal_number
	)
	if damageTween == null:
		return false
	var hold: float = (
		DamageNumberBillboardScript.visible_duration(action.is_heal_number)
		* ACTION_HOLD_FRACTION
	)
	var tween := visual_parent.create_tween()
	tween.tween_interval(hold)
	_activateScaled(tween, action, hold)
	return true


## `_monster_visuals` can hold an entry whose node has already been freed —
## `Dictionary.has()` answers true for it and every property access then throws.
## Callers that only need "is this unit still on the board" must go through
## here rather than testing `has()`.
func _liveMonsterVisual(monsterID: int) -> Node3D:
	if not _monster_visuals.has(monsterID):
		return null
	var visual = _monster_visuals[monsterID]
	if not is_instance_valid(visual):
		_monster_visuals.erase(monsterID)
		return null
	return visual


func _buildPlaceholderBody(material: Material) -> Node3D:
	var body = Node3D.new()

	var baseBulb = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	baseBulb.mesh.height = 0.2
	baseBulb.mesh.top_radius = 0.3
	baseBulb.mesh.bottom_radius = 0.35
	baseBulb.position.y = 0.3
	baseBulb.material_override = material
	body.add_child(baseBulb)

	var ring = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	ring.mesh.height = 0.05
	ring.mesh.top_radius = 0.31
	ring.mesh.bottom_radius = 0.31
	ring.position.y = 0.425
	ring.material_override = material
	body.add_child(ring)

	var stem = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	stem.mesh.height = 0.6
	stem.mesh.top_radius = 0.1
	stem.mesh.bottom_radius = 0.25
	stem.position.y = 0.75
	stem.material_override = material
	body.add_child(stem)

	var collar = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	collar.mesh.height = 0.05
	collar.mesh.top_radius = 0.2
	collar.mesh.bottom_radius = 0.2
	collar.position.y = 1.075
	collar.material_override = material
	body.add_child(collar)

	var head = BattleMeshFactoryScript.createMesh("shape_sphere", Color.WHITE)
	head.mesh.radius = 0.2
	head.mesh.height = 0.4
	head.position.y = 1.3
	head.material_override = material
	body.add_child(head)

	return body


func _add_selection_body(container: Node3D, monsterID: int) -> void:
	var accumulated = {"has_bounds": false, "bounds": AABB()}
	_accumulate_visual_bounds(container, Transform3D.IDENTITY, accumulated)
	if not accumulated["has_bounds"]:
		return

	var bounds: AABB = accumulated["bounds"].grow(0.08)
	var selectionBody = StaticBody3D.new()
	selectionBody.name = "SelectionBody"
	selectionBody.collision_layer = MONSTER_PICK_COLLISION_LAYER
	selectionBody.collision_mask = 0
	selectionBody.set_meta("monster_id", monsterID)

	var box = BoxShape3D.new()
	box.size = Vector3(
		maxf(bounds.size.x, 0.2),
		maxf(bounds.size.y, 0.2),
		maxf(bounds.size.z, 0.2)
	)
	var collision = CollisionShape3D.new()
	collision.name = "WholeModelBounds"
	collision.position = bounds.get_center()
	collision.shape = box
	selectionBody.add_child(collision)
	container.add_child(selectionBody)


func _status_icon_anchor_y(container: Node3D) -> float:
	var accumulated = {"has_bounds": false, "bounds": AABB()}
	_accumulate_visual_bounds(container, Transform3D.IDENTITY, accumulated)
	if not accumulated["has_bounds"]:
		return 1.25
	return maxf(float(accumulated["bounds"].end.y) + 0.28, 0.75)


func _refresh_status_icons(monsterID: int) -> void:
	var container := _liveMonsterVisual(monsterID)
	if container == null:
		return
	StatusEffectIconsScript.create_or_update(
		container,
		state.getActiveEffects(monsterID),
		_status_icon_anchor_y(container)
	)


func _accumulate_visual_bounds(
		node: Node,
		fromContainer: Transform3D,
		accumulated: Dictionary) -> void:
	for child in node.get_children():
		var childNode = child as Node3D
		if childNode == null:
			continue
		var childTransform = fromContainer * childNode.transform
		var meshInstance = childNode as MeshInstance3D
		if meshInstance != null and meshInstance.mesh != null:
			var childBounds: AABB = childTransform * meshInstance.get_aabb()
			if accumulated["has_bounds"]:
				accumulated["bounds"] = accumulated["bounds"].merge(childBounds)
			else:
				accumulated["bounds"] = childBounds
				accumulated["has_bounds"] = true
		_accumulate_visual_bounds(childNode, childTransform, accumulated)


func _target_body_bounds(monsterID: int) -> AABB:
	var container := _liveMonsterVisual(monsterID)
	if container == null or container.get_child_count() < 2:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	var body := container.get_child(1) as Node3D
	if body == null:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	var accumulated = {"has_bounds": false, "bounds": AABB()}
	var bodyMesh := body as MeshInstance3D
	if bodyMesh != null and bodyMesh.mesh != null:
		accumulated["bounds"] = body.transform * bodyMesh.get_aabb()
		accumulated["has_bounds"] = true
	_accumulate_visual_bounds(body, body.transform, accumulated)
	if not accumulated["has_bounds"]:
		return VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
	return accumulated["bounds"]


# --- EVENTS ---

func _on_battle_started(boardSize: Vector2i, _monsterList: Array) -> void:
	_log("=== BATTLE STARTED ===")
	# Every coordinate owns a full terrain column. Logical height remains the top
	# surface level; supporting blocks are presentation-only volume beneath it.
	for y in range(boardSize.y):
		for x in range(boardSize.x):
			var coord = Vector2i(x, y)
			var terrain = state.terrainBoard.at(coord)
			var baseColor = Color(0.2, 0.8, 0.2) # Grass
			if terrain == BattleState.TERRAIN_OBSTACLE:
				baseColor = Color(0.5, 0.3, 0.1)
			elif terrain == BattleState.TERRAIN_ABYSS:
				baseColor = Color(0.1, 0.3, 0.8)
			_add_tile_column(coord, terrain, baseColor)


func _add_tile_column(coord: Vector2i, terrain: int, baseColor: Color) -> void:
	var column = Node3D.new()
	column.name = "TileColumn_%d_%d" % [coord.x, coord.y]
	column.position = Vector3(coord.x, 0.0, coord.y)
	grid_node.add_child(column)
	_tile_columns[coord] = column

	var logicalHeight = maxi(state.getHeight(coord), 0)
	var topColor = tileColorFor(baseColor, coord, terrain)
	var verticalOffset = ABYSS_VERTICAL_OFFSET if terrain == BattleState.TERRAIN_ABYSS else 0.0
	for layer in range(logicalHeight + 1):
		var blockColor = topColor
		if layer < logicalHeight:
			var depth = logicalHeight - layer
			blockColor = topColor.darkened(minf(0.06 + float(depth) * 0.04, 0.24))
		var block = BattleMeshFactoryScript.createMesh("terrain_block", blockColor)
		block.name = "Layer_%d" % layer
		# Exact half-height blocks touch vertically; logical elevation remains an
		# integer while presentation scales each step to half a world unit.
		block.position = Vector3(
			0.0,
			float(layer) * TERRAIN_CELL_HEIGHT + verticalOffset,
			0.0
		)
		column.add_child(block)
		if layer == logicalHeight:
			_tile_surfaces[coord] = block


	var tile_pick_body = StaticBody3D.new()
	tile_pick_body.name = "TilePickBody"
	tile_pick_body.collision_layer = TILE_PICK_COLLISION_LAYER
	tile_pick_body.collision_mask = 0
	tile_pick_body.set_meta("battle_coord", coord)
	var tile_pick_shape = CollisionShape3D.new()
	var tile_pick_box = BoxShape3D.new()
	tile_pick_box.size = Vector3(1.0, 0.04, 1.0)
	tile_pick_shape.shape = tile_pick_box
	tile_pick_body.add_child(tile_pick_shape)
	tile_pick_body.position.y = _surface_y(coord)
	column.add_child(tile_pick_body)

func getTileColumn(coord: Vector2i) -> Node3D:
	return _tile_columns.get(coord) as Node3D


func getTileSurface(coord: Vector2i) -> MeshInstance3D:
	return _tile_surfaces.get(coord) as MeshInstance3D


func _on_battle_ended(winningTeam: int) -> void:
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.MESSAGE)
	action.prompt_text = "Battle complete. Team %d wins." % winningTeam
	action.log_text = "=== TEAM %d WINS ===" % winningTeam
	_queue.enqueue(action)


static func tileColorFor(baseColor: Color, coord: Vector2i, _terrain: int) -> Color:
	# Every terrain supplies one representative color and automatically receives
	# a coordinated light/dark pair. Future sand, rock, or lava palettes only
	# need to provide their base color to inherit this checker treatment.
	if (coord.x + coord.y) % 2 == 0:
		return baseColor.lightened(0.09)
	return baseColor.darkened(0.11)

func _on_monster_spawned(monsterID: int, _name: String, team: int, pos: Vector2i, _stats: Dictionary) -> void:
	var team_color := NoggThemeScript.team_color(team)
	var m = state.getMonster(monsterID)

	var mat: Material = null
	if m and m.elements.size() >= 2:
		mat = BattleMeshFactoryScript.createHalfMaterial(BattleMeshFactoryScript.elementColor(m.elements[0]), BattleMeshFactoryScript.elementColor(m.elements[1]))
	elif m and m.elements.size() == 1:
		mat = BattleMeshFactoryScript.createMaterial(BattleMeshFactoryScript.elementColor(m.elements[0]))
	else:
		mat = BattleMeshFactoryScript.createMaterial(Color(0.6, 0.6, 0.6))

	var container = Node3D.new()
	container.position = _coord_to_surface_pos3d(pos)

	## Tier comes from the catalog chain, not the spawned instance, so setup,
	## replay reconstruction, and any board refresh all build the same stack.
	var ascensionTier: int = MonsterReferencesScript.ascensionTier(_name)
	container.add_child(
		BattleMeshFactoryScript.createModelBase(team_color, ascensionTier)
	)

	var bodyVisual = MonsterVisualRegistryScript.instantiateVisual(_name)
	if bodyVisual == null:
		bodyVisual = _buildPlaceholderBody(mat)
	container.add_child(bodyVisual)
	BattleMeshFactoryScript.prepareNodeMaterials(bodyVisual)
	if m and m.elements.size() >= 2:
		var splitBounds = {"has_bounds": false, "bounds": AABB()}
		_accumulate_visual_bounds(bodyVisual, Transform3D.IDENTITY, splitBounds)
		if splitBounds["has_bounds"]:
			BattleMeshFactoryScript.configureSplitBounds(
				bodyVisual,
				splitBounds["bounds"]
			)
	_add_selection_body(container, monsterID)

	monsters_node.add_child(container)
	_monster_visuals[monsterID] = container
	_refresh_status_icons(monsterID)
	_log("%s [#%s] spawned at %s" % [_name, monsterID, pos])


func _on_effect_applied(monsterID: int, _effectName: String, _duration: int, _sourceMonsterID: int, _sourceSpellName: String) -> void:
	_refresh_status_icons(monsterID)


func _on_effect_ticked(monsterID: int, _effectName: String, _remainingTurns: int) -> void:
	_refresh_status_icons(monsterID)


func _on_effect_removed(monsterID: int, _effectName: String) -> void:
	_refresh_status_icons(monsterID)


func _on_turn_started(monsterID: int, _roundNumber: int, _turnNumber: int) -> void:
	var monster = state.getMonster(monsterID)
	if monster:
		var turnPos = monster.position
		var action: VisualAction = VisualActionScript.new(VisualAction.Kind.MESSAGE)
		action.coord = turnPos
		action.cursor_mode = VisualAction.CursorMode.TURN
		action.left_monster_id = monsterID
		action.has_left_monster = true
		action.right_monster_id = -1
		action.has_right_monster = true
		action.log_text = "\n--- TURN: %s [#%s] ---" % [monster.name, monsterID]
		_queue.enqueue(action)


func _on_movement_targeted(monsterID: int, destination: Vector2i) -> void:
	if state.currentMonsterID == monsterID and state.withinBounds(destination):
		var action: VisualAction = VisualActionScript.new(VisualAction.Kind.FOCUS)
		action.coord = destination
		action.cursor_mode = VisualAction.CursorMode.MOVEMENT
		_queue.enqueue(action)


func _on_monster_moved(monsterID: int, path: Array) -> void:
	if _liveMonsterVisual(monsterID) == null or path.is_empty():
		return
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.MOVE)
	action.monster_id = monsterID
	action.path = path.duplicate()
	action.log_text = "Moved to %s" % [path.back()]
	_queue.enqueue(action)


# The model follows its path visually; the cursor teleports to the destination.
func _on_action_targeted(
		monsterID: int,
		targetPos: Vector2i,
		_targetID: int,
		_action: String) -> void:
	if state.currentMonsterID == monsterID and state.withinBounds(targetPos):
		var action: VisualAction = VisualActionScript.new(VisualAction.Kind.FOCUS)
		action.coord = targetPos
		_queue.enqueue(action)


func _on_monster_attacked(
		attackerID: int,
		targetPos: Vector2i,
		targetID: int,
		damage: int,
		targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.BUMP)
	action.monster_id = attackerID
	action.target_id = targetID
	action.coord = targetPos
	action.left_monster_id = attackerID
	action.has_left_monster = true
	if target != null:
		action.right_monster_id = targetID
		action.has_right_monster = true
		action.has_damage_number = true
		action.damage_number = damage
		action.log_text = "Attacks %s for %s damage! (HP: %s)" % [
			target.name, damage, targetNewHP
		]
	else:
		action.log_text = "Attacks %s and misses!" % str(targetPos)
	_queue.enqueue(action)


func _on_spell_cast_started(
		casterID: int,
		centerPos: Vector2i,
		spellName: String,
		element: String,
		targetsHit: int,
		resolvedRadius: int,
		areaShape: String,
		resolvedTargetIDs: Array) -> void:
	assert(state.withinBounds(centerPos), "Spell cast centre is outside the board.")
	assert(
		targetsHit == resolvedTargetIDs.size(),
		"Spell cast target count does not match its resolved target identities."
	)
	var reference := SpellReferencesScript.getReference(spellName)
	assert(not reference.is_empty(), "Spell cast lacks a catalog reference: %s" % spellName)
	assert(resolvedRadius >= 0, "Resolved spell radius cannot be negative.")
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.CAST_AREA)
	action.monster_id = casterID
	action.target_id = -1
	action.coord = centerPos
	action.element = element
	action.vfx_profile = str(reference["VFX_PROFILE"])
	action.vfx_radius = resolvedRadius
	action.vfx_area_shape = areaShape
	action.vfx_seed = (
		int(hash(spellName))
		^ (casterID * 73856093)
		^ (centerPos.x * 19349663)
		^ (centerPos.y * 83492791)
	)
	action.vfx_ground_span = _footprint_ground_span(centerPos, action.vfx_radius)
	var impactWorldPosition := _coord_to_surface_pos3d(centerPos)
	var sourceCoord := state.getMonsterPosition(casterID)
	action.vfx_source_world_position = (
		_coord_to_surface_pos3d(sourceCoord)
		if state.withinBounds(sourceCoord)
		else impactWorldPosition
	)
	action.vfx_impact_world_position = impactWorldPosition
	action.vfx_surface_path_world_positions = _surface_path_world_positions(
		sourceCoord, centerPos)
	for resolvedTargetID in resolvedTargetIDs:
		var targetID := int(resolvedTargetID)
		action.vfx_target_ids.append(targetID)
		if _liveMonsterVisual(targetID) == null:
			action.vfx_target_world_positions.append(impactWorldPosition)
			action.vfx_target_body_bounds.append(
				VfxCastContextScript.DEFAULT_TARGET_BODY_BOUNDS
			)
			continue
		var targetCoord := state.getMonsterPosition(targetID)
		action.vfx_target_world_positions.append(
			_coord_to_surface_pos3d(targetCoord)
			if state.withinBounds(targetCoord)
			else impactWorldPosition
		)
		action.vfx_target_body_bounds.append(_target_body_bounds(targetID))
	action.origin = impactWorldPosition
	action.has_origin = true
	action.left_monster_id = casterID
	action.has_left_monster = true
	if targetsHit <= 0:
		action.log_text = "Casts %s at %s; no units are affected." % [spellName, centerPos]
	_queue.enqueue(action)


func _on_monster_cast_spell(
		casterID: int,
		_centerPos: Vector2i,
		targetID: int,
		spellName: String,
		damageLines: Array,
		targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	var totalDamage = 0
	for damageLine in damageLines:
		totalDamage += damageLine.get("damage", 0)
	var spellElement := "none"
	if not damageLines.is_empty():
		spellElement = str(damageLines[0].get("element", "none"))
	if target:
		var action: VisualAction = VisualActionScript.new(VisualAction.Kind.BUMP)
		action.monster_id = casterID
		action.target_id = targetID
		action.coord = state.getMonsterPosition(targetID)
		action.element = spellElement
		action.left_monster_id = casterID
		action.has_left_monster = true
		action.right_monster_id = targetID
		action.has_right_monster = true
		action.has_damage_number = true
		action.damage_number = totalDamage
		action.log_text = "Casts %s on %s for %s damage! (HP: %s)" % [
			spellName, target.name, totalDamage, targetNewHP
		]
		_queue.enqueue(action)


func _on_monster_healed(
		healerID: int,
		_centerPos: Vector2i,
		targetID: int,
		spellName: String,
		healAmount: int,
		targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	if target:
		var action: VisualAction = VisualActionScript.new(VisualAction.Kind.MESSAGE)
		action.coord = state.getMonsterPosition(targetID)
		action.left_monster_id = healerID
		action.has_left_monster = true
		action.right_monster_id = targetID
		action.has_right_monster = true
		action.has_damage_number = true
		action.damage_number = healAmount
		action.is_heal_number = true
		action.log_text = "Casts %s on %s, recovering %s HP! (HP: %s)" % [
			spellName, target.name, healAmount, targetNewHP
		]
		_queue.enqueue(action)

func _focus_cursor_on_coord(targetPos: Vector2i) -> void:
	if state.withinBounds(targetPos):
		_cursor_controller.focusTarget(targetPos)


func _on_monster_defeated(monsterID: int, killerID: int) -> void:
	var monster = state.getMonster(monsterID)
	var displayName = monster.name if monster else "Monster #%d" % monsterID
	var action: VisualAction = VisualActionScript.new(VisualAction.Kind.DEFEAT)
	action.monster_id = monsterID
	action.killer_id = killerID
	action.right_monster_id = monsterID
	action.has_right_monster = true
	action.log_text = "%s was DEFEATED!" % displayName
	_queue.enqueue(action)


func _start_move_animation(action: VisualAction) -> bool:
	var monsterID := action.monster_id
	var path: Array = action.path
	var visual := _liveMonsterVisual(monsterID)
	if visual == null or path.is_empty():
		return false
	_present_queued_message(action)
	_stop_position_tween(monsterID)
	var tween = visual.create_tween()
	_track_position_tween(monsterID, tween)
	var visualStart: Vector3 = visual.position
	var totalDuration := 0.0
	for coord in path:
		var targetPos := _coord_to_surface_pos3d(coord)
		var heightDelta = absf(targetPos.y - visualStart.y)
		var stepDuration = MOVE_STEP_DURATION + heightDelta * MOVE_HEIGHT_DURATION_FACTOR
		var peak = (visualStart + targetPos) * 0.5
		peak.y = maxf(visualStart.y, targetPos.y) + MOVE_ARC_CLEARANCE
		tween.tween_property(visual, "position", peak, stepDuration * 0.5).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "position", targetPos, stepDuration * 0.5).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_IN)
		visualStart = targetPos
		totalDuration += stepDuration
	_activateScaled(tween, action, totalDuration)
	return true


func _start_defeat_animation(action: VisualAction) -> bool:
	var monsterID := action.monster_id
	var container := _liveMonsterVisual(monsterID)
	if container == null:
		return false
	_stop_position_tween(monsterID)
	_disable_selection_collision(container)
	# Child 0 is the ModelBase *container* built by
	# BattleMeshFactory.createModelBase(), which is a Node3D holding one
	# MeshInstance3D per ascension layer — not a mesh itself. This used to cast
	# it straight to MeshInstance3D, which has silently been null ever since
	# the base became a stack, taking the whole defeat animation down with it
	# the moment a defeat actually played.
	var modelBase := container.get_child(0) as Node3D
	var body = container.get_child(1) as Node3D
	if modelBase == null or body == null:
		return false
	var capsuleTarget = modelBase.position + Vector3(0, 0.08, 0)
	var tween = container.create_tween().set_parallel(true)
	_defeat_tweens[monsterID] = tween
	tween.tween_property(body, "scale", Vector3.ZERO, 0.38).set_trans(Tween.TRANS_BACK)
	tween.tween_property(body, "position", capsuleTarget, 0.38).set_trans(Tween.TRANS_QUAD)
	_spawn_capsule_shatter(container, modelBase)
	# The shatter particles outlive the 0.38s collapse only slightly, so this
	# hold works out shorter than the tween and changes nothing today. Stated
	# anyway so the relationship is explicit if either constant moves.
	_activateScaled(
		tween, action, 0.38, CAPSULE_SHATTER_LIFETIME * ACTION_HOLD_FRACTION
	)
	return true

func _disable_selection_collision(container: Node3D) -> void:
	var selectionBody = container.get_node_or_null("SelectionBody") as StaticBody3D
	if selectionBody == null:
		return
	selectionBody.collision_layer = 0
	for shape in selectionBody.find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", true)


## `modelBase` is the ModelBase container, not a mesh: it holds one
## MeshInstance3D per ascension layer. The fragments borrow the bottom layer's
## material so a shattered base still reads as the same plinth, and the whole
## stack is hidden at once rather than just its first layer.
func _spawn_capsule_shatter(container: Node3D, modelBase: Node3D) -> void:
	var particles = GPUParticles3D.new()
	particles.name = "CapsuleShatter"
	particles.amount = 12
	particles.lifetime = CAPSULE_SHATTER_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = modelBase.position
	var processMaterial = ParticleProcessMaterial.new()
	processMaterial.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processMaterial.emission_sphere_radius = 0.16
	processMaterial.direction = Vector3(0, 1, 0)
	processMaterial.spread = 72.0
	processMaterial.initial_velocity_min = 1.4
	processMaterial.initial_velocity_max = 2.4
	processMaterial.gravity = Vector3(0, -5.0, 0)
	particles.process_material = processMaterial
	var fragment = BoxMesh.new()
	fragment.size = Vector3(0.07, 0.035, 0.07)
	particles.draw_pass_1 = fragment
	var bottomLayer := modelBase.get_child(0) as MeshInstance3D if modelBase.get_child_count() > 0 else null
	if bottomLayer != null:
		particles.material_override = bottomLayer.material_override
	particles.speed_scale = _animation_speed_scale
	container.add_child(particles)
	modelBase.visible = false
	particles.emitting = true

func _start_cast_area_animation(action: VisualAction) -> bool:
	if not action.has_origin:
		return false
	var resolved_profile := SpellVfxCatalogScript.resolvedProfileId(action.vfx_profile)
	_enforce_live_effect_cap(
		resolved_profile, SpellVfxCatalogScript.maxLive(action.vfx_profile)
	)
	var aura_color := BattleMeshFactoryScript.elementColor(action.element)
	var effect := SpellVfxCatalogScript.create(
		action.vfx_profile, visual_parent, action.origin, aura_color
	)
	if effect == null:
		return false
	var castContext := VfxCastContextScript.create(
		action.monster_id,
		action.vfx_source_world_position,
		action.vfx_impact_world_position,
		action.vfx_target_ids,
		action.vfx_target_world_positions,
		action.vfx_target_body_bounds,
		action.vfx_surface_path_world_positions
	)
	effect.configure_cast_context(castContext)
	if effect.has_method("setFootprint"):
		effect.call(
			"setFootprint", action.vfx_radius, action.vfx_ground_span, action.vfx_area_shape
		)
	effect.set("_autoDispose", true)
	effect.set_playback_scale(0.0 if isVisualPaused() else _animation_speed_scale)
	_active_cast_effect = _track_live_effect(effect, resolved_profile)
	effect.play(action.vfx_seed, VfxPlayback.MODE_BATTLE)
	var hold_duration := (
		effect.get_total_duration()
		* SpellVfxCatalogScript.actionHoldFraction(action.vfx_profile)
	)
	var tween := visual_parent.create_tween()
	tween.tween_interval(hold_duration)
	_activateScaled(tween, action, hold_duration)
	return true


func _start_bump_animation(action: VisualAction) -> bool:
	var sourceID := action.monster_id
	var targetID := action.target_id
	var sourceVisual := _liveMonsterVisual(sourceID)
	if sourceVisual == null:
		return false
	var originalPos = sourceVisual.position
	action.origin = originalPos
	action.has_origin = true
	var targetWorldPos: Vector3
	var targetVisual := _liveMonsterVisual(targetID)
	if targetVisual != null:
		targetWorldPos = targetVisual.position
	else:
		var targetCoord := action.coord
		if not state.withinBounds(targetCoord):
			return false
		targetWorldPos = _coord_to_surface_pos3d(targetCoord)
	var bumpDirection = targetWorldPos - originalPos
	if bumpDirection.is_zero_approx():
		bumpDirection = Vector3.FORWARD
	var bumpPos = originalPos + bumpDirection.normalized() * 0.4
	var holdDuration := 0.0
	if action.has_damage_number:
		var damageTween: Tween = _spawn_damage_number(
			targetWorldPos, action.damage_number, action.is_heal_number
		)
		# The number appears immediately and owns its pump/disappear timing. Hold
		# the action until it has completed so the next hit cannot cover it.
		if damageTween != null:
			holdDuration = maxf(
				holdDuration,
				DamageNumberBillboardScript.visible_duration(action.is_heal_number)
			)
	var tween = sourceVisual.create_tween()
	_track_position_tween(sourceID, tween)
	tween.tween_property(sourceVisual, "position", bumpPos, 0.1)
	tween.tween_property(sourceVisual, "position", originalPos, 0.15)
	_activateScaled(tween, action, 0.25, holdDuration)
	return true

func highlight_monster(monster_id: int) -> void:
	visualEffects.highlightMonster(monster_id)


## Marks a unit as having spent a phase of its turn, matching the command
## menu's own treatment of a spent row (dim, not hidden). Presentation only —
## does not touch selection state, unlike highlight_monster.
func set_monster_dimmed(monster_id: int, dimmed: bool) -> void:
	var visual := _liveMonsterVisual(monster_id)
	if visual == null:
		return
	BattleMeshFactoryScript.setDimAmountRecursive(visual, 1.0 if dimmed else 0.0)


## How much of a dithered model is discarded. Not 1.0: a fully discarded model
## is invisible, and the point is that the board reads *through* the units
## rather than that they disappear.
const DITHER_STRENGTH := 0.55


## Applies the dither rule to every model at once. `solidMonsterIDs` is the
## whole exception list — the active unit and whatever the pointer is over —
## so callers never track who was dithered and no model can be stranded: any
## id not named here is restored to solid on every call.
##
## Clearing all and re-applying, rather than diffing, is deliberate. A diff
## needs remembered state, and remembered state is exactly what strands a
## model when a phase ends on a path nobody enumerated.
func set_models_dithered(dithered: bool, solidMonsterIDs: Array = []) -> void:
	for monsterID in _monster_visuals.keys():
		var visual := _liveMonsterVisual(monsterID)
		if visual == null:
			continue
		var amount := 0.0
		if dithered and not solidMonsterIDs.has(monsterID):
			amount = DITHER_STRENGTH
		BattleMeshFactoryScript.setDitherAmountRecursive(visual, amount)


## The monster standing on `coord`, or -1. Shares the one pick the rest of the
## game uses; see BattlePresentationController._mouse_to_battle_coord().
##
## The bounds check is load-bearing, not defensive: a miss resolves to
## Vector2i(-1, -1), and `Matrix.at()` indexes its backing arrays directly, so
## GDScript's negative indexing would quietly hand back the far corner of the
## board instead of "nothing there".
func monster_id_at_position(coord: Vector2i) -> int:
	if not state.withinBounds(coord):
		return -1
	var monster = state.getMonsterAt(coord)
	return monster.uniqueID if monster != null else -1


## Project into the host viewport instead of drawing a Label3D in the world.
## The camera returns coordinates in the battle SubViewport; the renderer then
## maps those through its aspect-preserving display rectangle so letterboxing
## and low-resolution presets keep the anchor exact.
func _spawn_damage_number(worldPos: Vector3, amount: int, isHeal: bool) -> Tween:
	if damage_number_root == null or not is_instance_valid(damage_number_root):
		return null
	var camera := visual_parent.get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(worldPos):
		return null
	var viewportPos: Vector2 = camera.unproject_position(
		worldPos + Vector3.UP * DamageNumberBillboardScript.SPAWN_HEIGHT
	)
	var renderer = root_node.get("retro_renderer")
	var screenPos: Vector2 = viewportPos
	if renderer != null:
		screenPos = renderer.world_to_screen(viewportPos)
		var visibleRect: Rect2 = renderer.get_display_rect()
		if not visibleRect.grow(NoggThemeScript.FONT_SIZE_BODY).has_point(screenPos):
			return null
	var tween: Tween = DamageNumberBillboardScript.spawn(
		damage_number_root, screenPos, amount, isHeal
	)
	if tween != null:
		tween.set_speed_scale(_animation_speed_scale)
	return tween

## World position of a monster's visual, for callers that need where a unit
## actually is on screen (the camera pan, for one) rather than its board
## coordinate. Prefers the live visual — mid-tween or bumped off-tile — over
## the authoritative tile position, since those are exactly the moments a
## caller like a camera pan cares about.
func get_monster_world_position(monster_id: int) -> Vector3:
	var visual := _liveMonsterVisual(monster_id)
	if visual != null:
		return visual.position
	var coord := state.getMonsterPosition(monster_id)
	return _coord_to_surface_pos3d(coord)


func show_player_cursor(coord: Vector2i) -> void:
	_cursor_controller.focusPlayerSelection(coord)


func show_target_cursor(coord: Vector2i) -> void:
	_cursor_controller.focusPlayerTarget(coord)


func show_target_status(monsterID: int) -> void:
	_update_target_panel(monsterID)


func release_player_cursor() -> void:
	_cursor_controller.releasePlayerOwnership()


func hide_cursor() -> void:
	_cursor_controller.hide()


func show_movement_options(
		reachable: Array,
		path: Array = [],
		attackable: Array = []) -> void:
	clear_tactical_overlays()
	for coord in reachable:
		_add_overlay(coord, Color(0.15, 0.75, 1.0, 0.32))
	for coord in attackable:
		if not reachable.has(coord):
			# Purple distinguishes attack reach from movement blue and the
			# yellow path preview; the path is drawn last when they overlap.
			_add_overlay(coord, Color(0.72, 0.28, 1.0, 0.44))
	for coord in path:
		_add_overlay(coord, Color(1.0, 0.85, 0.15, 0.72))


func show_threat_options(threatened: Array) -> void:
	clear_threat_options()
	for coord in threatened:
		if coord is Vector2i and state.withinBounds(coord):
			# Magenta-red is intentionally distinct from movement blue,
			# target yellow, and affected-area red/green.
			_add_threat_overlay(coord, Color(0.95, 0.16, 0.48, 0.40))


func clear_threat_options() -> void:
	if not is_instance_valid(threat_overlay_node):
		return
	for child in threat_overlay_node.get_children():
		child.free()


## Paint the reach of the unit under the pointer: where it can move, and what it
## could strike from there. Additive — it draws on its own layer above the
## player's current movement or target overlay rather than replacing it, so
## inspecting an enemy mid-decision never costs the player the aim they were
## working with.
##
## Reuses the movement blue and reach purple `show_movement_options` already
## defines rather than introducing a fifth board colour. Yellow is deliberately
## not used: it already means the hovered path in one overlay and a legal target
## in another, and a third meaning would collide with both. The two sets are
## drawn at lower alpha than the acting unit's own overlay so the player can
## still tell their aim from an inspection when both are on the board.
func show_hover_reach(reachable: Array, attackable: Array = []) -> void:
	clear_hover_reach()
	if not is_instance_valid(hover_overlay_node):
		return
	for coord in reachable:
		if coord is Vector2i and state.withinBounds(coord):
			_add_hover_overlay(coord, Color(0.15, 0.75, 1.0, 0.20))
	for coord in attackable:
		if coord is Vector2i and state.withinBounds(coord) and not reachable.has(coord):
			_add_hover_overlay(coord, Color(0.72, 0.28, 1.0, 0.26))


func clear_hover_reach() -> void:
	if not is_instance_valid(hover_overlay_node):
		return
	for child in hover_overlay_node.get_children():
		child.free()


func show_target_options(
		targetPositions: Array,
		affectedPositions: Array = [],
		beneficial: bool = false) -> void:
	clear_tactical_overlays()
	for coord in targetPositions:
		if coord is Vector2i and state.withinBounds(coord):
			_add_overlay(coord, Color(1.0, 0.78, 0.12, 0.52))
	var preview_color = (
		Color(0.2, 1.0, 0.45, 0.46)
		if beneficial else
		Color(1.0, 0.2, 0.18, 0.46)
	)
	for coord in affectedPositions:
		if coord is Vector2i and state.withinBounds(coord):
			_add_overlay(coord, preview_color, 0.006)


func clear_tactical_overlays() -> void:
	if not is_instance_valid(overlay_node):
		return
	for child in overlay_node.get_children():
		child.free()


func _add_overlay(coord: Vector2i, color: Color, extraLift: float = 0.0) -> void:
	var marker = BattleMeshFactoryScript.createMesh("plane", color)
	marker.position = Vector3(
		coord.x, _surface_y(coord) + OVERLAY_LIFT + extraLift, coord.y
	)
	overlay_node.add_child(marker)


func _add_threat_overlay(coord: Vector2i, color: Color) -> void:
	var marker = BattleMeshFactoryScript.createMesh("plane", color)
	marker.position = Vector3(
		coord.x, _surface_y(coord) + OVERLAY_LIFT + 0.003, coord.y
	)
	threat_overlay_node.add_child(marker)


## Lifted above both the tactical and threat layers, so an inspection reads as
## sitting on top of the aim it is drawn over rather than z-fighting with it.
func _add_hover_overlay(coord: Vector2i, color: Color) -> void:
	var marker = BattleMeshFactoryScript.createMesh("plane", color)
	marker.position = Vector3(
		coord.x, _surface_y(coord) + OVERLAY_LIFT + 0.008, coord.y
	)
	hover_overlay_node.add_child(marker)


func dispose() -> void:
	_queue.dispose()
	_queue = null
	_dispose_live_effects()
	disconnectFromEvents()
	for monsterID in _position_tweens.keys():
		_stop_position_tween(monsterID)
	for monsterID in _defeat_tweens.keys():
		var tween: Tween = _defeat_tweens[monsterID]
		if tween != null and tween.is_valid():
			tween.kill()
	_defeat_tweens.clear()
	for node in [
		grid_node, monsters_node, overlay_node, threat_overlay_node,
		hover_overlay_node, damage_number_layer, _cursor
	]:
		if is_instance_valid(node):
			node.queue_free()
	_monster_visuals.clear()
	_tile_columns.clear()
	_tile_surfaces.clear()


func apply_global_effect(index: int) -> void:
	visualEffects.applyGlobalEffect(index)
