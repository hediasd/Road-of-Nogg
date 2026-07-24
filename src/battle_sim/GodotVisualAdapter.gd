## GodotVisualAdapter — A visual bridge that creates and animates 3D placeholders
## for the underlying headless battle simulation.

class_name GodotVisualAdapter
extends IBattleVisualAdapter

var state: BattleState
var root_node: Node3D
var grid_node: Node3D
var monsters_node: Node3D
var _cursor: MeshInstance3D

var anim_queue: Array = []
var is_animating: bool = false
var anim_tween: Tween

var selected_monster_id: int = -1
var aura_container: Node3D
var monster_nodes: Dictionary = {}

var _monster_visuals: Dictionary = {} # monsterID -> MeshInstance3D

func _init(_state: BattleState, _root_node: Node3D) -> void:
	state = _state
	root_node = _root_node

	grid_node = Node3D.new()
	grid_node.name = "Grid"
	root_node.add_child(grid_node)

	monsters_node = Node3D.new()
	monsters_node.name = "Monsters"
	root_node.add_child(monsters_node)

	_cursor = _create_mesh("cursor", Color(0.2, 0.6, 1.0, 0.5))
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

func _get_element_color(element: String) -> Color:
	match element.to_lower():
		"fire": return Color(0.9, 0.2, 0.2)
		"water", "ice": return Color(0.2, 0.7, 0.9)
		"earth", "nature", "wood": return Color(0.2, 0.7, 0.2)
		"electric", "lightning", "thunder": return Color(0.9, 0.9, 0.1)
		"dark", "darkness": return Color(0.4, 0.1, 0.6)
		"light": return Color(0.9, 0.9, 0.8)
		"steel": return Color(0.6, 0.6, 0.75)
		_: return Color(0.5, 0.5, 0.5)

func _create_half_material(color1: Color, color2: Color, center: Vector3) -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	uniform vec4 color1 : source_color;
	uniform vec4 color2 : source_color;
	uniform float metallic = 0.0;
	uniform float roughness = 1.0;
	varying vec3 local_pos;
	void vertex() {
		local_pos = VERTEX;
	}
	void fragment() {
		METALLIC = metallic;
		ROUGHNESS = roughness;
		SPECULAR = 0.5;

		// Diagonal split from bottom-left to top-right in local object space
		if (local_pos.y - local_pos.x < 0.0) {
			ALBEDO = color1.rgb;
		} else {
			ALBEDO = color2.rgb;
		}
	}
	"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color1", color1)
	mat.set_shader_parameter("color2", color2)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("roughness", 1.0)
	return mat


func _create_mesh(type: String, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0

	if type == "cursor":
		mi.mesh = PlaneMesh.new()
		mi.mesh.size = Vector2(1.1, 1.1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = color
	elif type == "box":
		mi.mesh = BoxMesh.new()
		mi.mesh.size = Vector3(0.9, 0.4, 0.9)
	elif type == "plane":
		mi.mesh = PlaneMesh.new()
		mi.mesh.size = Vector2(0.9, 0.9)
	elif type == "cylinder":
		mi.mesh = CylinderMesh.new()
		mi.mesh.height = 1.0
		mi.mesh.top_radius = 0.3
		mi.mesh.bottom_radius = 0.3
	elif type == "capsule_base":
		mi.mesh = CylinderMesh.new()
		mi.mesh.height = 0.2
		mi.mesh.top_radius = 0.45
		mi.mesh.bottom_radius = 0.45
	elif type == "shape_sphere":
		mi.mesh = SphereMesh.new()
		mi.mesh.radius = 0.4
	elif type == "shape_cube":
		mi.mesh = BoxMesh.new()
		mi.mesh.size = Vector3(0.7, 0.7, 0.7)
	elif type == "shape_coin":
		mi.mesh = CylinderMesh.new()
		mi.mesh.height = 0.2
		mi.mesh.top_radius = 0.4
		mi.mesh.bottom_radius = 0.4
	elif type == "shape_capsule":
		mi.mesh = CapsuleMesh.new()
		mi.mesh.radius = 0.3
		mi.mesh.height = 0.8
	elif type == "shape_pyramid":
		mi.mesh = PrismMesh.new()
		mi.mesh.size = Vector3(0.7, 0.8, 0.7)

	mi.material_override = mat
	return mi


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

			var tile = _create_mesh("box", color)
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
		var pos3d = _coord_to_pos3d(pos)
		mat = _create_half_material(_get_element_color(m.elements[0]), _get_element_color(m.elements[1]), pos3d)
	elif m and m.elements.size() == 1:
		var st_mat = StandardMaterial3D.new()
		st_mat.albedo_color = _get_element_color(m.elements[0])
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

	var base_mesh = _create_mesh("capsule_base", team_color)
	base_mesh.position.y = 0.1
	container.add_child(base_mesh)

	var brain_name = m.brain.get_script().resource_path.get_file().get_basename() if m and m.brain else ""
	var body_mesh = Node3D.new()

	# Base bulb
	var base_bulb = _create_mesh("shape_coin", Color.WHITE)
	base_bulb.mesh.height = 0.2; base_bulb.mesh.top_radius = 0.3; base_bulb.mesh.bottom_radius = 0.35
	base_bulb.position.y = 0.3; base_bulb.material_override = mat

	# Small ring
	var ring = _create_mesh("shape_coin", Color.WHITE)
	ring.mesh.height = 0.05; ring.mesh.top_radius = 0.31; ring.mesh.bottom_radius = 0.31
	ring.position.y = 0.425; ring.material_override = mat

	# Stem
	var stem = _create_mesh("shape_coin", Color.WHITE)
	stem.mesh.height = 0.6; stem.mesh.top_radius = 0.1; stem.mesh.bottom_radius = 0.25
	stem.position.y = 0.75; stem.material_override = mat

	# Collar
	var collar = _create_mesh("shape_coin", Color.WHITE)
	collar.mesh.height = 0.05; collar.mesh.top_radius = 0.2; collar.mesh.bottom_radius = 0.2
	collar.position.y = 1.075; collar.material_override = mat

	# Head
	var head = _create_mesh("shape_sphere", Color.WHITE)
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
	if selected_monster_id == monster_id:
		return

	selected_monster_id = monster_id

	# Clear previous aura
	if is_instance_valid(aura_container):
		aura_container.queue_free()
		aura_container = null

	if monster_id == -1 or not _monster_visuals.has(monster_id):
		return

	var target_node = _monster_visuals[monster_id]

	aura_container = Node3D.new()
	target_node.add_child(aura_container)

	var shader = load("res://assets/shaders/pixel_aura.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("aura_color", Color.WHITE)
	mat.set_shader_parameter("thickness", 0.04)
	mat.set_shader_parameter("pixel_size", 64.0)

	aura_container.position.y += 0.02 # Lift slightly to prevent Z-fighting with floor

	_build_aura_meshes(target_node, aura_container, mat)

func _build_aura_meshes(source: Node, dest: Node3D, mat: Material) -> void:
	for child in source.get_children():
		if child == aura_container: continue
		if child is MeshInstance3D:
			var mi = MeshInstance3D.new()
			mi.mesh = child.mesh
			mi.transform = child.transform
			mi.material_override = mat
			dest.add_child(mi)
		elif child is Node3D:
			var pivot = Node3D.new()
			pivot.transform = child.transform
			dest.add_child(pivot)
			_build_aura_meshes(child, pivot, mat)

func apply_global_effect(index: int) -> void:
	var mat: Material = null
	match index:
		0: mat = null # Default (Clear override)
		1: mat = _load_effect_mat("res://assets/shaders/effects/01_hologram.gdshader")
		2: mat = _load_effect_mat("res://assets/shaders/effects/02_ghost.gdshader")
		3: mat = _load_effect_mat("res://assets/shaders/effects/03_toon.gdshader")
		4: mat = _load_effect_mat("res://assets/shaders/effects/04_molten.gdshader")
		5: mat = _load_effect_mat("res://assets/shaders/effects/05_dissolve.gdshader")
		6: mat = _load_effect_mat("res://assets/shaders/effects/06_matrix.gdshader")
		7: mat = _load_effect_mat("res://assets/shaders/effects/07_glass.gdshader")
		8: mat = _load_effect_mat("res://assets/shaders/effects/08_shadow.gdshader")
		9: mat = _load_effect_mat("res://assets/shaders/effects/09_petrified.gdshader")
		10:
			var std = StandardMaterial3D.new()
			std.albedo_color = Color(1.0, 0.8, 0.1)
			std.metallic = 1.0
			std.roughness = 0.15
			mat = std

	for m_id in _monster_visuals.keys():
		var node = _monster_visuals[m_id]
		_override_materials_recursive(node, mat)

func _load_effect_mat(path: String) -> ShaderMaterial:
	var shader = load(path)
	var sm = ShaderMaterial.new()
	sm.shader = shader
	return sm

func _override_materials_recursive(node: Node, mat: Material) -> void:
	if node == aura_container: return # Don't override the highlight aura itself

	if node is MeshInstance3D:
		# If index is 0, mat is null, which clears the override
		node.material_override = mat

	for child in node.get_children():
		_override_materials_recursive(child, mat)
