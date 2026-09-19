## Plays the hex battle's combat feedback: hits, casts, numbers, status rows and removals.
##
## IT OWNS NO SCHEDULER. `VisualActionQueue` is the only queue and `HexBattlePlayback` the only
## gate. Every hold this class needs is appended to the tween it hands to `queue.activate()`, so
## pause, skip, the watchdog and recovery reach it through the queue's existing contract.
##
## WHY PAYLOADS LIVE HERE. `VisualAction` is a shared type; widening it for hex-only fields would
## be a shared-contract migration. Instead each action carries a token in `vfx_seed` and the
## event-time payload is held here under that token. The queue clones actions, and the clone
## keeps the token, so start and finalize both find the same payload.
##
## Ported from the square battle's `GodotVisualAdapter` (references/square-battle). Durations,
## hold fractions and the defeat collapse are the donor's numbers, not new tuning.
class_name HexBattleCombatFeedback
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const DamageNumberBillboardScript = preload(
	"res://src/presentation/effects/DamageNumberBillboard.gd")
const HexBattleVfxBridgeScript = preload(
	"res://src/presentation/battle/effects/HexBattleVfxBridge.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")
const VfxCastContextScript = preload("res://src/presentation/effects/VfxCastContext.gd")

const TYPE_STRIKE := "strike"
const TYPE_NUMBER := "number"
const TYPE_CAST := "cast"
const TYPE_REMOVAL := "removal"
const TYPE_DISPLAY := "display"

## Donor bump: out and back along the source-to-target line.
const BUMP_DISTANCE := 0.4
const BUMP_OUT_SECONDS := 0.10
const BUMP_BACK_SECONDS := 0.15
## Donor defeat: the body collapses into its base while the base shatters.
const DEFEAT_SECONDS := 0.38
const DEFEAT_SINK := 0.08
const CAPSULE_SHATTER_LIFETIME := 0.42
## Withdrawal has no donor. It is deliberately a different silhouette from defeat: the whole unit,
## base included, lifts and shrinks away intact, with no collapse and no shatter. One-shot exit,
## so there is no idle layer to add; its constants are its own.
const WITHDRAW_SECONDS := 0.45
const WITHDRAW_RISE := 0.6
## Donor rule: hold an action "mostly through" its visible effect so the tail overlaps the next.
const ACTION_HOLD_FRACTION := 0.6

var _adapter
var _root: Node3D
var _map: BattleMapDefinition
var _display: HexBattleDisplayState
var _payloads: Dictionary = {}
var _nextToken := 1
var _liveEffects: Array[WeakRef] = []
var _liveProfiles: Dictionary = {}
var _activeCast: WeakRef
var _numberLayer: CanvasLayer
var _numberRoot: Control
var _attachedCounts: Dictionary = {}
## Presentation speed and pause, set through the adapter by `HexBattlePlayback`. Every tween this
## class hands the queue runs at `_playbackScale`, and every live effect carrier follows it, or
## freezes at zero while paused. Never read by the simulation.
var _playbackScale := 1.0
var _paused := false
## Probe-facing record of what reached the screen, in order. Bounded so a long battle cannot grow
## it without limit.
var _timeline: Array[Dictionary] = []
const TIMELINE_LIMIT := 512


func _init(
		adapter, root: Node3D, map: BattleMapDefinition, display: HexBattleDisplayState
) -> void:
	_adapter = adapter
	_root = root
	_map = map
	_display = display


# --- queue contract ---------------------------------------------------------

func attach(action: VisualAction, payload: Dictionary) -> void:
	var token := _nextToken
	_nextToken += 1
	action.vfx_seed = token
	_payloads[token] = payload.duplicate(true)
	var payloadType := str(payload.get("type", ""))
	_attachedCounts[payloadType] = int(_attachedCounts.get(payloadType, 0)) + 1


func start(action: VisualAction, queue: VisualActionQueue) -> bool:
	var payload: Dictionary = _payloads.get(action.vfx_seed, {})
	if payload.is_empty():
		return false
	var started := false
	match str(payload.get("type", "")):
		TYPE_STRIKE: started = _startStrike(action, payload, queue)
		TYPE_NUMBER: started = _startNumber(action, payload, queue)
		TYPE_CAST: started = _startCast(action, payload, queue)
		TYPE_REMOVAL: started = _startRemoval(action, payload, queue)
		TYPE_DISPLAY: started = false
	if not started:
		# Resolved instantly: the queue will not call finalize for it, so settle it here.
		finalize(action)
	return started


func finalize(action: VisualAction) -> void:
	var payload: Dictionary = _payloads.get(action.vfx_seed, {})
	if payload.is_empty():
		return
	_payloads.erase(action.vfx_seed)
	match str(payload.get("type", "")):
		TYPE_STRIKE:
			var source: Node3D = _adapter.modelFor(int(payload.get("source_id", -1)))
			if source != null and is_instance_valid(source):
				source.position = payload.get("source_world", source.position)
			_applyImpact(payload)
		TYPE_NUMBER:
			_applyImpact(payload)
		TYPE_CAST:
			# The effect is not cut here: the hold is shorter than some effects' full runtime and
			# they auto-dispose. Only skip or recovery ends one early.
			pass
		TYPE_REMOVAL:
			var monsterID := int(payload.get("monster_id", -1))
			_adapter.removeDisplayedModel(monsterID)
			_display.markRemoved(monsterID, str(payload.get("reason", "")))
		TYPE_DISPLAY:
			_applyDisplay(payload)
	_record(payload)


## Speed for everything started from now on, and at once for every live effect carrier. A tween
## the queue is already running keeps the speed it was activated with: its watchdog was sized for
## that speed, and slowing it mid-flight would let the watchdog cut it short.
func setPlaybackScale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.01)
	_applyEffectScale()


## Freezes or releases the live effect carriers. The queue's own tween is paused by the queue.
func setPaused(paused: bool) -> void:
	_paused = paused
	_applyEffectScale()


func playbackScale() -> float:
	return _playbackScale


func _applyEffectScale() -> void:
	_pruneEffects()
	for ref in _liveEffects:
		var effect := _effectFrom(ref)
		if effect != null:
			effect.set_playback_scale(0.0 if _paused else _playbackScale)


## The one path this class activates a queued tween through, as the donor's `_activateScaled`: the
## tween runs at the playback speed, and the queue is told the real elapsed time so its watchdog
## neither fires early in slow motion nor waits needlessly when fast.
func _activate(
		queue: VisualActionQueue, tween: Tween, action: VisualAction, duration: float
) -> void:
	tween.set_speed_scale(_playbackScale)
	queue.activate(tween, action, duration / _playbackScale)


func skipActive() -> void:
	var effect := _effectFrom(_activeCast)
	if effect != null:
		effect.skip_to_settle()


func recover(authoritative: BattleState) -> void:
	_payloads.clear()
	_disposeEffects()
	_display.recover(authoritative)


func dispose() -> void:
	_payloads.clear()
	_disposeEffects()
	if is_instance_valid(_numberLayer):
		_numberLayer.queue_free()
	_numberLayer = null
	_numberRoot = null


# --- diagnostics ------------------------------------------------------------

func pendingPayloadCount() -> int:
	return _payloads.size()


func attachedCount(payloadType: String) -> int:
	return int(_attachedCounts.get(payloadType, 0))


func timeline() -> Array[Dictionary]:
	return _timeline.duplicate(true)


func liveEffectCount() -> int:
	_pruneEffects()
	return _liveEffects.size()


func numberRoot() -> Control:
	return _numberRoot if is_instance_valid(_numberRoot) else null


# --- strikes and numbers ----------------------------------------------------

## A basic attack or a per-target spell hit: the source lunges toward the target while the number
## appears. Held for the number's whole visible duration, as the donor did, so the next hit cannot
## cover it.
func _startStrike(action: VisualAction, payload: Dictionary, queue: VisualActionQueue) -> bool:
	var source: Node3D = _adapter.modelFor(int(payload.get("source_id", -1)))
	if source == null or not is_instance_valid(source):
		return _startNumber(action, payload, queue)
	var targetWorld: Vector3 = payload.get("target_world", Vector3.ZERO)
	var origin: Vector3 = payload.get("source_world", source.position)
	source.position = origin
	var direction := targetWorld - origin
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	var tween := source.create_tween()
	tween.tween_property(
		source, "position", origin + direction.normalized() * BUMP_DISTANCE, BUMP_OUT_SECONDS)
	# The number answers the impact rather than the wind-up, so it is thrown
	# where the lunge lands: at the end of the bump out, not at frame zero when
	# the attacker has not yet moved. The health it reports changes on the same
	# beat, so the bar and the number cannot disagree about when the hit landed.
	tween.tween_callback(func() -> void:
		_applyImpact(payload)
		_spawnNumber(payload)
	)
	tween.tween_property(source, "position", origin, BUMP_BACK_SECONDS)
	var visible := BUMP_OUT_SECONDS + BUMP_BACK_SECONDS
	if _willShowNumber(payload):
		var hold := BUMP_OUT_SECONDS + DamageNumberBillboardScript.visible_duration(false)
		if hold > visible:
			tween.chain().tween_interval(hold - visible)
			visible = hold
	_activate(queue, tween, action, visible)
	return true


## A heal, a status tick or passive damage: a number with no lunge. Held "mostly through" the
## number, matching the donor's heal hold.
func _startNumber(action: VisualAction, payload: Dictionary, queue: VisualActionQueue) -> bool:
	_applyImpact(payload)
	if not _spawnNumber(payload):
		return false
	var hold := DamageNumberBillboardScript.visible_duration(bool(payload.get("heal", false))) \
		* ACTION_HOLD_FRACTION
	var tween := _root.create_tween()
	tween.tween_interval(hold)
	_activate(queue, tween, action, hold)
	return true


## The displayed HP changes at the impact, not at the event and not after the hold.
func _applyImpact(payload: Dictionary) -> void:
	if payload.has("new_hp"):
		_display.setHitpoints(int(payload.get("target_id", -1)), int(payload["new_hp"]))


## The part of `_spawnNumber`'s guard that can be asked before the lunge, so a
## strike can size its hold while the number itself is still a bump away. The
## rest of that guard -- a layer to draw on, a target the camera can see --
## cannot be answered early and is not predicted here; a number the projection
## later refuses leaves the action fractionally long rather than cutting the
## number off, which is the safer way round.
func _willShowNumber(payload: Dictionary) -> bool:
	return int(payload.get("amount", 0)) > 0 and int(payload.get("target_id", -1)) >= 0


func _spawnNumber(payload: Dictionary) -> bool:
	var amount := int(payload.get("amount", 0))
	if not _willShowNumber(payload):
		return false
	var worldPosition: Vector3 = payload.get("target_world", Vector3.ZERO)
	var screenPosition := _projectToScreen(
		worldPosition + Vector3.UP * DamageNumberBillboardScript.SPAWN_HEIGHT)
	if screenPosition.x < 0.0 or screenPosition.y < 0.0:
		return false
	if not _ensureNumberLayer():
		return false
	var animation := DamageNumberBillboardScript.spawn(
		_numberRoot, screenPosition, amount, bool(payload.get("heal", false)))
	if animation == null:
		return false
	# The donor scaled the number's own tween too, so a hit's number keeps pace with its hold.
	animation.set_speed_scale(_playbackScale)
	return true


## Numbers are native-resolution UI. Under a battle stage the world renders in an isolated
## SubViewport, so the layer must live beside the stage and positions must go through the stage's
## projection, never a SubViewport camera's raw coordinates.
func _projectToScreen(worldPosition: Vector3) -> Vector2:
	var stage := _stage()
	if stage != null:
		return stage.projectWorldToScreen(worldPosition)
	if not is_instance_valid(_root) or not _root.is_inside_tree():
		return Vector2(-1.0, -1.0)
	var camera := _root.get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(worldPosition):
		return Vector2(-1.0, -1.0)
	return camera.unproject_position(worldPosition)


## The nearest ancestor that owns the screen/world boundary (`HexBattleStage`). Found rather than
## injected because the controller that builds both is outside this item; a bare world without a
## stage (probes, tools) falls back to its own viewport, which is then the native one.
func _stage() -> Node:
	if not is_instance_valid(_root):
		return null
	var node: Node = _root.get_parent()
	while node != null:
		if node.has_method("projectWorldToScreen"):
			return node
		node = node.get_parent()
	return null


func _ensureNumberLayer() -> bool:
	if is_instance_valid(_numberRoot):
		return true
	if not is_instance_valid(_root) or not _root.is_inside_tree():
		return false
	var parent: Node = _root
	var stage := _stage()
	if stage != null:
		parent = stage.get_parent() if stage.get_parent() != null else stage
	_numberLayer = CanvasLayer.new()
	_numberLayer.name = "HexCombatNumbers"
	_numberLayer.layer = NoggThemeScript.WORLD_EFFECT_LAYER
	parent.add_child(_numberLayer)
	_numberRoot = Control.new()
	_numberRoot.name = "DamageNumberRoot"
	_numberRoot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numberRoot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_numberLayer.add_child(_numberRoot)
	return true


# --- casts ------------------------------------------------------------------

## One carrier per `spell_cast_started`. Per-target damage arrives as separate strike actions, so
## a six-target storm is one storm followed by six hits, never six storms.
func _startCast(action: VisualAction, payload: Dictionary, queue: VisualActionQueue) -> bool:
	var profile := str(payload.get("profile", ""))
	var resolvedProfile := SpellVfxCatalogScript.resolvedProfileId(profile)
	_enforceLiveCap(resolvedProfile, SpellVfxCatalogScript.maxLive(profile))
	var targetIDs: Array[int] = []
	targetIDs.assign(payload.get("target_ids", []))
	var targetPositions: Array[Vector3] = []
	targetPositions.assign(payload.get("target_world_positions", []))
	var targetBounds: Array[AABB] = []
	targetBounds.assign(payload.get("target_body_bounds", []))
	var surfacePath: Array[Vector3] = []
	surfacePath.assign(payload.get("surface_path", []))
	var context := VfxCastContextScript.create(
		int(payload.get("caster_id", -1)),
		payload.get("source_world", Vector3.ZERO),
		payload.get("impact_world", Vector3.ZERO),
		targetIDs, targetPositions, targetBounds, surfacePath)
	var footprint := HexBattleVfxBridgeScript.footprintFor(
		payload.get("affected_cells", []), _map)
	var effect := HexBattleVfxBridgeScript.createPlayback(
		profile, _root, payload.get("impact_world", Vector3.ZERO),
		BattleMeshFactoryScript.elementColor(str(payload.get("element", "none"))),
		footprint, context, {}, float(payload.get("ground_span", 0.0)),
		str(payload.get("area_shape", "circle")))
	if effect == null:
		push_error("Hex cast could not build playback for profile '%s' (spell %s)." % [
			profile, str(payload.get("spell", ""))])
		return false
	effect.set("_autoDispose", true)
	# Before play, as the donor did, so a cast started at 4x never plays a first frame at 1x.
	effect.set_playback_scale(0.0 if _paused else _playbackScale)
	_activeCast = _trackEffect(effect, resolvedProfile)
	effect.play(int(payload.get("effect_seed", 0)), VfxPlayback.MODE_BATTLE)
	var hold := effect.get_total_duration() * SpellVfxCatalogScript.actionHoldFraction(profile)
	var tween := _root.create_tween()
	tween.tween_interval(hold)
	_activate(queue, tween, action, hold)
	return true


func _enforceLiveCap(profileID: String, maximumLive: int) -> void:
	if maximumLive <= 0:
		return
	_pruneEffects()
	var matching: Array[VfxPlayback] = []
	for ref in _liveEffects:
		var effect := _effectFrom(ref)
		if effect != null and _liveProfiles.get(effect.get_instance_id(), "") == profileID:
			matching.append(effect)
	while matching.size() >= maximumLive:
		var oldest: VfxPlayback = matching.pop_front()
		_untrackEffect(oldest.get_instance_id())
		oldest.dispose()


func _trackEffect(effect: VfxPlayback, profileID: String) -> WeakRef:
	var ref: WeakRef = weakref(effect)
	_liveEffects.append(ref)
	_liveProfiles[effect.get_instance_id()] = profileID
	effect.tree_exiting.connect(_untrackEffect.bind(effect.get_instance_id()), CONNECT_ONE_SHOT)
	_rebalanceIntensity()
	return ref


func _untrackEffect(instanceID: int) -> void:
	for index in range(_liveEffects.size() - 1, -1, -1):
		var effect := _effectFrom(_liveEffects[index])
		if effect == null or effect.get_instance_id() == instanceID:
			_liveEffects.remove_at(index)
	_liveProfiles.erase(instanceID)
	var active := _effectFrom(_activeCast)
	if active == null or active.get_instance_id() == instanceID:
		_activeCast = null
	_rebalanceIntensity()


## Donor rule: overlapping scalable effects share one unit of intensity.
func _rebalanceIntensity() -> void:
	_pruneEffects()
	var scalable: Array[VfxPlayback] = []
	for ref in _liveEffects:
		var effect := _effectFrom(ref)
		if effect != null and effect.has_method("setIntensityScale"):
			scalable.append(effect)
	var intensity := 1.0 / float(maxi(scalable.size(), 1))
	for effect in scalable:
		effect.call("setIntensityScale", intensity)


func _pruneEffects() -> void:
	for index in range(_liveEffects.size() - 1, -1, -1):
		if _effectFrom(_liveEffects[index]) == null:
			_liveEffects.remove_at(index)


func _effectFrom(ref: WeakRef) -> VfxPlayback:
	if ref == null:
		return null
	var effect = ref.get_ref()
	if effect == null or not is_instance_valid(effect) or effect.is_queued_for_deletion():
		return null
	return effect as VfxPlayback


func _disposeEffects() -> void:
	var effects: Array[VfxPlayback] = []
	for ref in _liveEffects:
		var effect := _effectFrom(ref)
		if effect != null:
			effects.append(effect)
	_liveEffects.clear()
	_liveProfiles.clear()
	_activeCast = null
	for effect in effects:
		effect.dispose()


# --- removal ----------------------------------------------------------------

func _startRemoval(action: VisualAction, payload: Dictionary, queue: VisualActionQueue) -> bool:
	var model: Node3D = _adapter.modelFor(int(payload.get("monster_id", -1)))
	if model == null or not is_instance_valid(model):
		return false
	if str(payload.get("reason", "")) == HexBattleDisplayState.REASON_WITHDRAWN:
		var lift := model.create_tween().set_parallel(true)
		lift.tween_property(model, "position:y", model.position.y + WITHDRAW_RISE, WITHDRAW_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		lift.tween_property(model, "scale", Vector3.ZERO, WITHDRAW_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_activate(queue, lift, action, WITHDRAW_SECONDS)
		return true
	# Child 0 is the ModelBase container, child 1 the body (`MonsterModelFactory.build`).
	var modelBase := model.get_child(0) as Node3D if model.get_child_count() > 0 else null
	var body := model.get_child(1) as Node3D if model.get_child_count() > 1 else null
	if modelBase == null or body == null:
		push_error("Hex defeat cannot find the base and body of unit %d." % action.monster_id)
		return false
	var collapse := model.create_tween().set_parallel(true)
	collapse.tween_property(body, "scale", Vector3.ZERO, DEFEAT_SECONDS).set_trans(Tween.TRANS_BACK)
	collapse.tween_property(
		body, "position", modelBase.position + Vector3(0.0, DEFEAT_SINK, 0.0), DEFEAT_SECONDS
	).set_trans(Tween.TRANS_QUAD)
	_spawnCapsuleShatter(model, modelBase)
	var visible := DEFEAT_SECONDS
	var hold := CAPSULE_SHATTER_LIFETIME * ACTION_HOLD_FRACTION
	if hold > visible:
		collapse.chain().tween_interval(hold - visible)
		visible = hold
	_activate(queue, collapse, action, visible)
	return true


## The donor's capsule shatter, unchanged: fragments borrow the bottom base layer's material and
## the whole base stack hides at once.
func _spawnCapsuleShatter(model: Node3D, modelBase: Node3D) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "CapsuleShatter"
	particles.amount = 12
	particles.lifetime = CAPSULE_SHATTER_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.speed_scale = _playbackScale
	particles.position = modelBase.position
	var processMaterial := ParticleProcessMaterial.new()
	processMaterial.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processMaterial.emission_sphere_radius = 0.16
	processMaterial.direction = Vector3(0, 1, 0)
	processMaterial.spread = 72.0
	processMaterial.initial_velocity_min = 1.4
	processMaterial.initial_velocity_max = 2.4
	processMaterial.gravity = Vector3(0, -5.0, 0)
	particles.process_material = processMaterial
	var fragment := BoxMesh.new()
	fragment.size = Vector3(0.07, 0.035, 0.07)
	particles.draw_pass_1 = fragment
	var bottomLayer: MeshInstance3D = null
	if modelBase.get_child_count() > 0:
		bottomLayer = modelBase.get_child(0) as MeshInstance3D
	if bottomLayer != null:
		particles.material_override = bottomLayer.material_override
	model.add_child(particles)
	modelBase.visible = false
	particles.emitting = true


# --- displayed status -------------------------------------------------------

func _applyDisplay(payload: Dictionary) -> void:
	var monsterID := int(payload.get("monster_id", -1))
	match str(payload.get("display_op", "")):
		"effect_apply":
			_display.applyEffect(monsterID, payload.get("row", {}))
		"effect_tick":
			_display.tickEffect(
				monsterID, str(payload.get("effect", "")), int(payload.get("duration", 0)))
		"effect_remove":
			_display.removeEffect(monsterID, str(payload.get("effect", "")))


func _record(payload: Dictionary) -> void:
	var targetID := int(payload.get("target_id", payload.get("monster_id", -1)))
	var targetModel: Node3D = _adapter.modelFor(targetID) if targetID >= 0 else null
	_timeline.append({
		"type": str(payload.get("type", "")),
		"target_id": targetID,
		"displayed_hp": _display.hitpointsOf(targetID),
		"target_rendered": targetModel != null and is_instance_valid(targetModel),
		"reason": str(payload.get("reason", payload.get("display_op", ""))),
	})
	if _timeline.size() > TIMELINE_LIMIT:
		_timeline.pop_front()
