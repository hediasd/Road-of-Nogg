## GodotVisualAdapter — A visual bridge that creates and animates 3D placeholders
## for the underlying headless battle simulation.

class_name GodotVisualAdapter
extends IBattleVisualAdapter

const MONSTER_PICK_COLLISION_LAYER := 1 << 7
const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const BattleVisualEffectsScript = preload("res://src/presentation/BattleVisualEffects.gd")
const BattleCursorControllerScript = preload("res://src/presentation/BattleCursorController.gd")
const MonsterVisualRegistryScript = preload("res://src/presentation/MonsterVisualRegistry.gd")
const MAX_QUEUED_ANIMATIONS := 4096
const ANIMATION_WATCHDOG_MARGIN := 0.75

signal animation_queue_drained

var state: BattleState
var root_node: Node3D
var visual_parent: Node3D
var grid_node: Node3D
var monsters_node: Node3D
var overlay_node: Node3D
var _cursor: MeshInstance3D
var _cursor_controller: BattleCursorController

var anim_queue: Array = []
var is_animating: bool = false
var anim_tween: Tween
var _active_animation: Dictionary = {}
var _animation_serial: int = 0
var _disposed: bool = false

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

	_cursor = BattleMeshFactoryScript.createMesh("cursor", Color(0.2, 0.6, 1.0, 0.5))
	visual_parent.add_child(_cursor)
	_cursor_controller = BattleCursorControllerScript.new(_cursor, state.getHeight)


func _log(text: String) -> void:
	if root_node and "log_label" in root_node and root_node.log_label:
		root_node.log_label.text += text + "\n"

func _update_left_ui(text: String) -> void:
	if root_node and "left_ui_label" in root_node and root_node.left_ui_label:
		root_node.left_ui_label.text = text

func _update_right_ui(text: String) -> void:
	if root_node and "right_ui_label" in root_node and root_node.right_ui_label:
		root_node.right_ui_label.text = text

# --- HELPERS ---

func _coord_to_pos3d(coord: Vector2i) -> Vector3:
	return Vector3(coord.x, float(state.getHeight(coord)), coord.y)


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
		var visual: Node3D = _monster_visuals[monsterID]
		var authoritativePos = state.getMonsterPosition(monsterID)
		if not state.withinBounds(authoritativePos):
			visual.visible = false
			continue
		var targetPos = _coord_to_pos3d(authoritativePos)
		targetPos.y += 0.2
		visual.position = targetPos


func _track_position_tween(monsterID: int, tween: Tween) -> void:
	_position_tweens[monsterID] = tween
	tween.finished.connect(_on_position_tween_finished.bind(monsterID, tween))


func _on_position_tween_finished(monsterID: int, tween: Tween) -> void:
	if _position_tweens.get(monsterID) == tween:
		_position_tweens.erase(monsterID)


func isAnimationBusy() -> bool:
	return is_animating or not anim_queue.is_empty()


func activeAnimationKind() -> String:
	return str(_active_animation.get("kind", ""))


func queuedAnimationCount() -> int:
	return anim_queue.size()


func _enqueue_animation(action: Dictionary) -> void:
	if _disposed:
		return
	if anim_queue.size() >= MAX_QUEUED_ANIMATIONS:
		push_error("Visual animation queue overflow; recovering to authoritative positions.")
		_recover_animation_queue()
	anim_queue.append(action.duplicate(true))
	_start_next_animation()


func _start_next_animation() -> void:
	if _disposed or is_animating:
		return
	while not anim_queue.is_empty():
		var action: Dictionary = anim_queue.pop_front()
		if _start_queued_animation(action):
			return
	animation_queue_drained.emit()


func _start_queued_animation(action: Dictionary) -> bool:
	match str(action.get("kind", "")):
		"focus":
			_present_queued_message(action)
		"message":
			_present_queued_message(action)
		"move":
			return _start_move_animation(action)
		"bump":
			_present_queued_message(action)
			return _start_bump_animation(action)
		"defeat":
			_present_queued_message(action)
			return _start_defeat_animation(action)
		_:
			push_warning("Ignoring unknown visual animation kind: %s" % action.get("kind"))
	return false


func _activate_tween(tween: Tween, action: Dictionary, duration: float) -> void:
	is_animating = true
	anim_tween = tween
	_active_animation = action
	_animation_serial += 1
	var serial = _animation_serial
	tween.finished.connect(_complete_active_animation.bind(serial, false), CONNECT_ONE_SHOT)
	var tree = root_node.get_tree() if is_instance_valid(root_node) else null
	if tree:
		tree.create_timer(duration + ANIMATION_WATCHDOG_MARGIN).timeout.connect(
			_complete_active_animation.bind(serial, true),
			CONNECT_ONE_SHOT
		)


func _complete_active_animation(serial: int, timedOut: bool) -> void:
	if _disposed or not is_animating or serial != _animation_serial:
		return
	var completedAction = _active_animation
	if timedOut:
		push_warning("Visual animation watchdog recovered a stalled %s action." % completedAction.get("kind", "unknown"))
		if anim_tween != null and anim_tween.is_valid():
			anim_tween.kill()
	_finalize_animation(completedAction)
	is_animating = false
	anim_tween = null
	_active_animation = {}
	call_deferred("_start_next_animation")


func _finalize_animation(action: Dictionary) -> void:
	var monsterID = int(action.get("monster_id", -1))
	var kind = str(action.get("kind", ""))
	if kind == "move" and _monster_visuals.has(monsterID):
		var path: Array = action.get("path", [])
		if not path.is_empty():
			var finalPos = _coord_to_pos3d(path.back())
			finalPos.y += 0.2
			_monster_visuals[monsterID].position = finalPos
	elif kind == "bump" and _monster_visuals.has(monsterID):
		_monster_visuals[monsterID].position = action.get(
			"origin",
			_monster_visuals[monsterID].position
		)
	elif kind == "defeat":
		_defeat_tweens.erase(monsterID)
		if _monster_visuals.has(monsterID):
			var container: Node3D = _monster_visuals[monsterID]
			_monster_visuals.erase(monsterID)
			container.queue_free()
	_position_tweens.erase(monsterID)


func _recover_animation_queue() -> void:
	_animation_serial += 1
	var interruptedAction = _active_animation
	if anim_tween != null and anim_tween.is_valid():
		anim_tween.kill()
	if not interruptedAction.is_empty():
		_finalize_animation(interruptedAction)
	anim_queue.clear()
	is_animating = false
	anim_tween = null
	_active_animation = {}
	_synchronize_visual_occupancy()


func _present_queued_message(action: Dictionary) -> void:
	var coord = action.get("coord", Vector2i(-1, -1))
	if coord is Vector2i and state.withinBounds(coord):
		match str(action.get("cursor_mode", "target")):
			"turn":
				_cursor_controller.focusTurn(coord)
			"movement":
				_cursor_controller.focusMovementDestination(coord)
			_:
				_focus_cursor_on_coord(coord)
	var leftText = str(action.get("left_text", ""))
	if not leftText.is_empty():
		_update_left_ui(leftText)
	var rightText = str(action.get("right_text", ""))
	if not rightText.is_empty():
		_update_right_ui(rightText)
	var logText = str(action.get("log_text", ""))
	if not logText.is_empty():
		_log(logText)


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
	var verticalOffset = -0.15 if terrain == BattleState.TERRAIN_ABYSS else 0.0
	for layer in range(logicalHeight + 1):
		var blockColor = topColor
		if layer < logicalHeight:
			var depth = logicalHeight - layer
			blockColor = topColor.darkened(minf(0.06 + float(depth) * 0.04, 0.24))
		var block = BattleMeshFactoryScript.createMesh("terrain_block", blockColor)
		block.name = "Layer_%d" % layer
		# A one-unit block centered at layer - 0.3 retains the historical top
		# surface at logical height + 0.2, so every existing anchor stays valid.
		block.position = Vector3(0.0, float(layer) - 0.3 + verticalOffset, 0.0)
		column.add_child(block)
		if layer == logicalHeight:
			_tile_surfaces[coord] = block


func getTileColumn(coord: Vector2i) -> Node3D:
	return _tile_columns.get(coord) as Node3D


func getTileSurface(coord: Vector2i) -> MeshInstance3D:
	return _tile_surfaces.get(coord) as MeshInstance3D


func _on_battle_ended(winningTeam: int) -> void:
	_enqueue_animation({
		"kind": "message",
		"right_text": "BATTLE COMPLETE\nTeam %d wins.\nChoose New Battle to return to setup." % winningTeam,
		"log_text": "=== TEAM %d WINS ===" % winningTeam
	})


static func tileColorFor(baseColor: Color, coord: Vector2i, _terrain: int) -> Color:
	# Every terrain supplies one representative color and automatically receives
	# a coordinated light/dark pair. Future sand, rock, or lava palettes only
	# need to provide their base color to inherit this checker treatment.
	if (coord.x + coord.y) % 2 == 0:
		return baseColor.lightened(0.09)
	return baseColor.darkened(0.11)

func _on_monster_spawned(monsterID: int, _name: String, team: int, pos: Vector2i, _stats: Dictionary) -> void:
	var team_color = Color(0.18, 0.42, 0.95) if team == 1 else Color(0.9, 0.2, 0.16)
	var m = state.getMonster(monsterID)

	var mat: Material = null
	if m and m.elements.size() >= 2:
		mat = BattleMeshFactoryScript.createHalfMaterial(BattleMeshFactoryScript.elementColor(m.elements[0]), BattleMeshFactoryScript.elementColor(m.elements[1]))
	elif m and m.elements.size() == 1:
		mat = BattleMeshFactoryScript.createMaterial(BattleMeshFactoryScript.elementColor(m.elements[0]))
	else:
		mat = BattleMeshFactoryScript.createMaterial(Color(0.6, 0.6, 0.6))

	var container = Node3D.new()
	container.position = _coord_to_pos3d(pos)
	container.position.y += 0.2 # Offset to sit on top of the tile surface

	var base_mesh = BattleMeshFactoryScript.createMesh("capsule_base", team_color)
	base_mesh.position.y = 0.1
	container.add_child(base_mesh)

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
	_log("%s [#%s] spawned at %s" % [_name, monsterID, pos])


func _on_turn_started(monsterID: int, _roundNumber: int, _turnNumber: int) -> void:
	var monster = state.getMonster(monsterID)
	if monster:
		var turnPos = monster.position
		_enqueue_animation({
			"kind": "message",
			"coord": turnPos,
			"cursor_mode": "turn",
			"left_text": "CURRENT TURN:\n%s  Lv.%s\nHP: %s/%s\nATK %s | DEF %s | SPD %s\nMOVE %s | JUMP %s | HEIGHT %s" % [monster.name, monster.level, monster.hitpoints, monster.max_hitpoints, monster.atk, monster.def, monster.speed, monster.move, monster.jump, state.getHeight(turnPos)],
			"right_text": "Waiting for action...",
			"log_text": "\n--- TURN: %s [#%s] ---" % [monster.name, monsterID]
		})


func _on_movement_targeted(monsterID: int, destination: Vector2i) -> void:
	if state.currentMonsterID == monsterID and state.withinBounds(destination):
		_enqueue_animation({
			"kind": "focus",
			"coord": destination,
			"cursor_mode": "movement"
		})


func _on_monster_moved(monsterID: int, path: Array) -> void:
	if not _monster_visuals.has(monsterID) or path.is_empty():
		return
	_enqueue_animation({
		"kind": "move",
		"monster_id": monsterID,
		"path": path.duplicate(),
		"log_text": "Moved to %s" % [path.back()]
	})


# The model follows its path visually; the cursor teleports to the destination.
func _on_action_targeted(monsterID: int, targetID: int, _action: String) -> void:
	if state.currentMonsterID == monsterID:
		var targetPos = state.getMonsterPosition(targetID)
		if state.withinBounds(targetPos):
			_enqueue_animation({"kind": "focus", "coord": targetPos})


func _on_monster_attacked(attackerID: int, targetID: int, damage: int, targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	if target:
		_enqueue_animation({
			"kind": "bump",
			"monster_id": attackerID,
			"target_id": targetID,
			"coord": state.getMonsterPosition(targetID),
			"right_text": "TARGET:\n%s\nTakes %s Damage\nHP Left: %s" % [target.name, damage, targetNewHP],
			"log_text": "Attacks %s for %s damage! (HP: %s)" % [target.name, damage, targetNewHP]
		})


func _on_monster_cast_spell(casterID: int, targetID: int, spellName: String, damageLines: Array, targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	var totalDamage = 0
	for damageLine in damageLines:
		totalDamage += damageLine.get("damage", 0)
	if target:
		_enqueue_animation({
			"kind": "bump",
			"monster_id": casterID,
			"target_id": targetID,
			"coord": state.getMonsterPosition(targetID),
			"right_text": "SPELL TARGET:\n%s\nTakes %s Dmg from %s\nHP Left: %s" % [target.name, totalDamage, spellName, targetNewHP],
			"log_text": "Casts %s on %s for %s damage! (HP: %s)" % [spellName, target.name, totalDamage, targetNewHP]
		})


func _on_monster_healed(_healerID: int, targetID: int, spellName: String, healAmount: int, targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	if target:
		_enqueue_animation({
			"kind": "message",
			"coord": state.getMonsterPosition(targetID),
			"right_text": "HEAL TARGET:\n%s\nRecovers %s HP from %s\nHP: %s" % [
				target.name, healAmount, spellName, targetNewHP
			]
		})



func _focus_cursor_on_coord(targetPos: Vector2i) -> void:
	if state.withinBounds(targetPos):
		_cursor_controller.focusTarget(targetPos)


func _on_monster_defeated(monsterID: int, killerID: int) -> void:
	var monster = state.getMonster(monsterID)
	var displayName = monster.name if monster else "Monster #%d" % monsterID
	_enqueue_animation({
		"kind": "defeat",
		"monster_id": monsterID,
		"killer_id": killerID,
		"right_text": "%s was DEFEATED!" % displayName,
		"log_text": "%s was DEFEATED!" % displayName
	})


func _start_move_animation(action: Dictionary) -> bool:
	var monsterID = int(action.get("monster_id", -1))
	var path: Array = action.get("path", [])
	if not _monster_visuals.has(monsterID) or path.is_empty():
		return false
	_present_queued_message(action)
	_stop_position_tween(monsterID)
	var visual: Node3D = _monster_visuals[monsterID]
	var tween = visual.create_tween()
	_track_position_tween(monsterID, tween)
	var visualStart = visual.position
	for coord in path:
		var targetPos = _coord_to_pos3d(coord)
		targetPos.y += 0.2
		var peak = (visualStart + targetPos) * 0.5
		peak.y = maxf(visualStart.y, targetPos.y) + 0.32
		tween.tween_property(visual, "position", peak, 0.1)
		tween.tween_property(visual, "position", targetPos, 0.1)
		visualStart = targetPos
	_activate_tween(tween, action, float(path.size()) * 0.2)
	return true


func _start_defeat_animation(action: Dictionary) -> bool:
	var monsterID = int(action.get("monster_id", -1))
	if not _monster_visuals.has(monsterID):
		return false
	_stop_position_tween(monsterID)
	var container: Node3D = _monster_visuals[monsterID]
	_disable_selection_collision(container)
	var baseMesh = container.get_child(0) as MeshInstance3D
	var body = container.get_child(1) as Node3D
	var capsuleTarget = baseMesh.position + Vector3(0, 0.08, 0)
	var tween = container.create_tween().set_parallel(true)
	_defeat_tweens[monsterID] = tween
	tween.tween_property(body, "scale", Vector3.ZERO, 0.38).set_trans(Tween.TRANS_BACK)
	tween.tween_property(body, "position", capsuleTarget, 0.38).set_trans(Tween.TRANS_QUAD)
	_spawn_capsule_shatter(container, baseMesh)
	_activate_tween(tween, action, 0.38)
	return true

func _disable_selection_collision(container: Node3D) -> void:
	var selectionBody = container.get_node_or_null("SelectionBody") as StaticBody3D
	if selectionBody == null:
		return
	selectionBody.collision_layer = 0
	for shape in selectionBody.find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", true)


func _spawn_capsule_shatter(container: Node3D, baseMesh: MeshInstance3D) -> void:
	var particles = GPUParticles3D.new()
	particles.name = "CapsuleShatter"
	particles.amount = 12
	particles.lifetime = 0.42
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = baseMesh.position
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
	particles.material_override = baseMesh.material_override
	container.add_child(particles)
	baseMesh.visible = false
	particles.emitting = true

func _start_bump_animation(action: Dictionary) -> bool:
	var sourceID = int(action.get("monster_id", -1))
	var targetID = int(action.get("target_id", -1))
	if not _monster_visuals.has(sourceID) or not _monster_visuals.has(targetID):
		return false
	var sourceVisual: Node3D = _monster_visuals[sourceID]
	var targetVisual: Node3D = _monster_visuals[targetID]
	var originalPos = sourceVisual.position
	action["origin"] = originalPos
	var targetPos = targetVisual.position
	var bumpDirection = targetPos - originalPos
	if bumpDirection.is_zero_approx():
		bumpDirection = Vector3.FORWARD
	var bumpPos = originalPos + bumpDirection.normalized() * 0.4
	var tween = sourceVisual.create_tween()
	_track_position_tween(sourceID, tween)
	tween.tween_property(sourceVisual, "position", bumpPos, 0.1)
	tween.tween_property(sourceVisual, "position", originalPos, 0.15)
	_activate_tween(tween, action, 0.25)
	return true

func highlight_monster(monster_id: int) -> void:
	visualEffects.highlightMonster(monster_id)


func show_player_cursor(coord: Vector2i) -> void:
	_cursor_controller.focusPlayerSelection(coord)


func show_target_cursor(coord: Vector2i) -> void:
	_cursor_controller.focusPlayerTarget(coord)


func release_player_cursor() -> void:
	_cursor_controller.releasePlayerOwnership()


func hide_cursor() -> void:
	_cursor_controller.hide()


func show_movement_options(reachable: Array, path: Array = []) -> void:
	clear_tactical_overlays()
	for coord in reachable:
		_add_overlay(coord, Color(0.15, 0.75, 1.0, 0.32))
	for coord in path:
		_add_overlay(coord, Color(1.0, 0.85, 0.15, 0.72))


func show_target_options(targetIDs: Array) -> void:
	clear_tactical_overlays()
	for targetID in targetIDs:
		var coord = state.getMonsterPosition(targetID)
		if state.withinBounds(coord):
			_add_overlay(coord, Color(1.0, 0.2, 0.25, 0.68))


func clear_tactical_overlays() -> void:
	if not is_instance_valid(overlay_node):
		return
	for child in overlay_node.get_children():
		child.free()


func _add_overlay(coord: Vector2i, color: Color) -> void:
	var marker = BattleMeshFactoryScript.createMesh("plane", color)
	marker.position = Vector3(coord.x, float(state.getHeight(coord)) + 0.215, coord.y)
	overlay_node.add_child(marker)


func dispose() -> void:
	_disposed = true
	_animation_serial += 1
	anim_queue.clear()
	is_animating = false
	_active_animation = {}
	if anim_tween != null and anim_tween.is_valid():
		anim_tween.kill()
	anim_tween = null
	disconnectFromEvents()
	for monsterID in _position_tweens.keys():
		_stop_position_tween(monsterID)
	for monsterID in _defeat_tweens.keys():
		var tween: Tween = _defeat_tweens[monsterID]
		if tween != null and tween.is_valid():
			tween.kill()
	_defeat_tweens.clear()
	for node in [grid_node, monsters_node, overlay_node, _cursor]:
		if is_instance_valid(node):
			node.queue_free()
	_monster_visuals.clear()
	_tile_columns.clear()
	_tile_surfaces.clear()


func apply_global_effect(index: int) -> void:
	visualEffects.applyGlobalEffect(index)
