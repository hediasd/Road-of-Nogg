## GodotVisualAdapter — A visual bridge that creates and animates 3D placeholders
## for the underlying headless battle simulation.

class_name GodotVisualAdapter
extends IBattleVisualAdapter

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const BattleVisualEffectsScript = preload("res://src/presentation/BattleVisualEffects.gd")

var state: BattleState
var root_node: Node3D
var grid_node: Node3D
var monsters_node: Node3D
var _cursor: MeshInstance3D

var anim_queue: Array = []
var is_animating: bool = false
var anim_tween: Tween

var visualEffects

var _monster_visuals: Dictionary = {} # monsterID -> MeshInstance3D

func _init(_state: BattleState, _root_node: Node3D) -> void:
	state = _state
	root_node = _root_node
	visualEffects = BattleVisualEffectsScript.new(_monster_visuals)

	grid_node = Node3D.new()
	grid_node.name = "Grid"
	root_node.add_child(grid_node)

	monsters_node = Node3D.new()
	monsters_node.name = "Monsters"
	root_node.add_child(monsters_node)

	_cursor = BattleMeshFactoryScript.createMesh("cursor", Color(0.2, 0.6, 1.0, 0.5))
	_cursor.visible = false
	root_node.add_child(_cursor)


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
	return Vector3(coord.x, 0, coord.y)

# --- EVENTS ---

func _on_battle_started(boardSize: Vector2i, _monsterList: Array) -> void:
	_log("=== BATTLE STARTED ===")
	# Draw the board
	for y in range(boardSize.y):
		for x in range(boardSize.x):
			var coord = Vector2i(x, y)
			var terrain = state.terrainBoard.at(coord)
			var color = Color(0.2, 0.8, 0.2) # Grass

			if terrain == 1: color = Color(0.5, 0.3, 0.1) # Trees/Obstacle
			elif terrain == 2: color = Color(0.1, 0.3, 0.8) # Water/Abyss

			var tile = BattleMeshFactoryScript.createMesh("box", color)
			var pos3d = _coord_to_pos3d(coord)

			if terrain == 2:
				pos3d.y -= 0.15 # lower the abyss

			tile.position = pos3d
			grid_node.add_child(tile)


func _on_monster_spawned(monsterID: int, _name: String, team: int, pos: Vector2i, _stats: Dictionary) -> void:
	var team_color = Color(0.8, 0.2, 0.2) if team == 1 else Color(0.2, 0.4, 0.9)
	var m = state.getMonster(monsterID)

	var mat: Material = null
	if m and m.elements.size() >= 2:
		mat = BattleMeshFactoryScript.createHalfMaterial(BattleMeshFactoryScript.elementColor(m.elements[0]), BattleMeshFactoryScript.elementColor(m.elements[1]))
	elif m and m.elements.size() == 1:
		var st_mat = StandardMaterial3D.new()
		st_mat.albedo_color = BattleMeshFactoryScript.elementColor(m.elements[0])
		st_mat.metallic = 0.0
		st_mat.roughness = 1.0
		mat = st_mat
	else:
		var st_mat = StandardMaterial3D.new()
		st_mat.albedo_color = Color(0.6, 0.6, 0.6)
		st_mat.metallic = 0.0
		st_mat.roughness = 1.0
		mat = st_mat

	var container = Node3D.new()
	container.position = _coord_to_pos3d(pos)
	container.position.y = 0.2 # Offset to sit on top of the box tiles

	var base_mesh = BattleMeshFactoryScript.createMesh("capsule_base", team_color)
	base_mesh.position.y = 0.1
	container.add_child(base_mesh)

	var brain_name = m.brain.get_script().resource_path.get_file().get_basename() if m and m.brain else ""
	var body_mesh = Node3D.new()

	# Base bulb
	var base_bulb = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	base_bulb.mesh.height = 0.2; base_bulb.mesh.top_radius = 0.3; base_bulb.mesh.bottom_radius = 0.35
	base_bulb.position.y = 0.3; base_bulb.material_override = mat

	# Small ring
	var ring = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	ring.mesh.height = 0.05; ring.mesh.top_radius = 0.31; ring.mesh.bottom_radius = 0.31
	ring.position.y = 0.425; ring.material_override = mat

	# Stem
	var stem = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	stem.mesh.height = 0.6; stem.mesh.top_radius = 0.1; stem.mesh.bottom_radius = 0.25
	stem.position.y = 0.75; stem.material_override = mat

	# Collar
	var collar = BattleMeshFactoryScript.createMesh("shape_coin", Color.WHITE)
	collar.mesh.height = 0.05; collar.mesh.top_radius = 0.2; collar.mesh.bottom_radius = 0.2
	collar.position.y = 1.075; collar.material_override = mat

	# Head
	var head = BattleMeshFactoryScript.createMesh("shape_sphere", Color.WHITE)
	head.mesh.radius = 0.2; head.mesh.height = 0.4; head.position.y = 1.3; head.material_override = mat

	body_mesh.add_child(base_bulb)
	body_mesh.add_child(ring)
	body_mesh.add_child(stem)
	body_mesh.add_child(collar)
	body_mesh.add_child(head)

	container.add_child(body_mesh)

	monsters_node.add_child(container)
	_monster_visuals[monsterID] = container
	_log("%s [#%s] spawned at %s" % [_name, monsterID, pos])


func _on_turn_started(monsterID: int, _roundNumber: int, _turnNumber: int) -> void:
	var m = state.getMonster(monsterID)
	if m:
		_update_left_ui("CURRENT TURN:\n%s\nHP: %s/%s\nAtk: %s | Spd: %s" % [m.name, m.hitpoints, m.max_hitpoints, m.atk, m.speed])
		_update_right_ui("Waiting for action...")
		_log("\n--- TURN: %s [#%s] ---" % [m.name, monsterID])

		_cursor.visible = true
		_cursor.position = _coord_to_pos3d(m.position)
		_cursor.position.y = 0.21


func _on_monster_moved(monsterID: int, path: Array) -> void:
	if not _monster_visuals.has(monsterID) or path.is_empty(): return
	var mi = _monster_visuals[monsterID]

	_log("Moved to %s" % [path.back()])

	var tween = mi.create_tween()
	var cursor_tween = _cursor.create_tween() if _cursor.visible else null
	for coord in path:
		var target_pos = _coord_to_pos3d(coord)
		target_pos.y = 0.2
		tween.tween_property(mi, "position", target_pos, 0.2)
		if cursor_tween:
			var cursor_pos = target_pos
			cursor_pos.y = 0.21
			cursor_tween.tween_property(_cursor, "position", cursor_pos, 0.2)

	# We don't await the tween here, we just let it play out asynchronously


func _on_monster_attacked(attackerID: int, targetID: int, _damage: int, _targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	if target:
		_update_right_ui("TARGET:\n%s\nTakes %s Damage\nHP Left: %s" % [target.name, _damage, _targetNewHP])
		_log("Attacks %s for %s damage! (HP: %s)" % [target.name, _damage, _targetNewHP])
	_play_bump_animation(attackerID, targetID)


func _on_monster_cast_spell(casterID: int, targetID: int, _spellName: String, damageLines: Array, _targetNewHP: int) -> void:
	var target = state.getMonster(targetID)
	var total_dmg = 0
	for d in damageLines: total_dmg += d.get("damage", 0)

	if target:
		_update_right_ui("SPELL TARGET:\n%s\nTakes %s Dmg from %s\nHP Left: %s" % [target.name, total_dmg, _spellName, _targetNewHP])
		_log("Casts %s on %s for %s damage! (HP: %s)" % [_spellName, target.name, total_dmg, _targetNewHP])
	_play_bump_animation(casterID, targetID)


func _on_monster_defeated(monsterID: int, killerID: int) -> void:
	var m = state.getMonster(monsterID)
	if m:
		_log("%s was DEFEATED!" % m.name)
		_update_right_ui("%s was DEFEATED!" % m.name)

	if not _monster_visuals.has(monsterID): return
	var mi = _monster_visuals[monsterID]

	var tween = mi.create_tween()
	tween.tween_property(mi, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(func():
		mi.queue_free()
		_monster_visuals.erase(monsterID)
	)


func _play_bump_animation(sourceID: int, targetID: int) -> void:
	if not _monster_visuals.has(sourceID) or not _monster_visuals.has(targetID): return
	var src_mi = _monster_visuals[sourceID]
	var tgt_mi = _monster_visuals[targetID]

	var original_pos = src_mi.position
	var target_pos = tgt_mi.position
	var bump_vector = (target_pos - original_pos).normalized() * 0.4
	var bump_pos = original_pos + bump_vector

	var tween = src_mi.create_tween()
	tween.tween_property(src_mi, "position", bump_pos, 0.1)
	tween.tween_property(src_mi, "position", original_pos, 0.15)

func highlight_monster(monster_id: int) -> void:
	visualEffects.highlightMonster(monster_id)


func apply_global_effect(index: int) -> void:
	visualEffects.applyGlobalEffect(index)
