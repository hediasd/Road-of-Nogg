extends Node3D

var sim: BattleSimulator
var visual_adapter: GodotVisualAdapter
var turn_timer: Timer
var camera: BattleCameraController

# UI Elements
var left_ui_label: Label
var right_ui_label: Label
var log_label: RichTextLabel
var log_panel: PanelContainer

func _ready() -> void:
	_setup_background()
	_setup_camera_and_lighting()
	_setup_ui()
	_setup_simulation()

	var ss_timer = Timer.new()
	ss_timer.wait_time = 1.0
	ss_timer.one_shot = true
	ss_timer.timeout.connect(_on_screenshot_pressed)
	add_child(ss_timer)
	ss_timer.start()
func _setup_background() -> void:
	var bg_canvas = CanvasLayer.new()
	bg_canvas.layer = -1
	add_child(bg_canvas)

	var shader = load("res://assets/textures/sky/retro_sky_2d.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader

	var crect = ColorRect.new()
	crect.material = mat
	crect.set_anchors_preset(Control.PRESET_FULL_RECT)
	crect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.add_child(crect)

	var env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8) # Brute bright ambient
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _setup_camera_and_lighting() -> void:
	camera = BattleCameraController.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(6, 15, 14)
	add_child(camera)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	light.shadow_blur = 0.0 # Brute sharp shadows
	light.light_energy = 1.0
	light.light_color = Color(1.0, 1.0, 1.0)
	add_child(light)

func _setup_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# Top Left Controls
	var top_panel = PanelContainer.new()
	top_panel.position = Vector2(20, 20)
	canvas.add_child(top_panel)

	var hbox = HBoxContainer.new()
	top_panel.add_child(hbox)

	var play_btn = CheckButton.new()
	play_btn.text = "Auto-Play"
	play_btn.toggled.connect(_on_play_toggled)
	hbox.add_child(play_btn)

	var speed_label = Label.new()
	speed_label.text = "  Speed:"
	hbox.add_child(speed_label)

	var speed_slider = HSlider.new()
	speed_slider.custom_minimum_size = Vector2(100, 20)
	speed_slider.min_value = 0.5
	speed_slider.max_value = 10.0
	speed_slider.step = 0.5
	speed_slider.value = 1.25
	speed_slider.value_changed.connect(_on_speed_changed)
	hbox.add_child(speed_slider)

	turn_timer = Timer.new()
	turn_timer.wait_time = 1.0 / speed_slider.value
	turn_timer.timeout.connect(_on_turn_timer_timeout)
	add_child(turn_timer)

	# Top Right Log Toggle
	var log_btn = CheckButton.new()
	log_btn.text = "Show Battle Log"
	log_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_btn.position = Vector2(-200, 20)
	log_btn.toggled.connect(func(pressed): log_panel.visible = pressed)
	canvas.add_child(log_btn)

	# Top Right Clayness Option
	var clayness_btn = OptionButton.new()
	clayness_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clayness_btn.position = Vector2(-200, 60)
	clayness_btn.add_item("Clayness: Default")
	for i in range(1, 11):
		clayness_btn.add_item("Clayness Profile %d" % i)
	clayness_btn.item_selected.connect(_on_clayness_selected)
	canvas.add_child(clayness_btn)

	# Top Right Material Option
	var mat_btn = OptionButton.new()
	mat_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mat_btn.position = Vector2(-200, 100)
	mat_btn.add_item("0: Default / Reset")
	mat_btn.add_item("1: Hologram")
	mat_btn.add_item("2: Ghostly Apparition")
	mat_btn.add_item("3: Toon Outline")
	mat_btn.add_item("4: Molten Core")
	mat_btn.add_item("5: Thanos Snap")
	mat_btn.add_item("6: Matrix Rain")
	mat_btn.add_item("7: Prismatic Glass")
	mat_btn.add_item("8: Shadow Demon")
	mat_btn.add_item("9: Petrified")
	mat_btn.add_item("10: Golden Idol")
	mat_btn.item_selected.connect(_on_material_selected)
	canvas.add_child(mat_btn)

	# Battle Log Panel
	log_panel = PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	log_panel.position = Vector2(-320, 60)
	log_panel.size = Vector2(300, 400)
	log_panel.visible = false

	# Add semi-transparent background to log
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	log_panel.add_theme_stylebox_override("panel", style)

	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_panel.add_child(log_label)
	canvas.add_child(log_panel)

	# Bottom Left Info
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left_panel.position = Vector2(20, -150)
	left_panel.size = Vector2(250, 130)
	left_ui_label = Label.new()
	left_ui_label.text = "Waiting for turn..."
	left_panel.add_child(left_ui_label)
	canvas.add_child(left_panel)

	# Bottom Right Info
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_panel.position = Vector2(-270, -150)
	right_panel.size = Vector2(250, 130)
	right_ui_label = Label.new()
	right_ui_label.text = "No Target"
	right_panel.add_child(right_ui_label)
	canvas.add_child(right_panel)

	# Bottom Center Debug Tools
	var debug_panel = PanelContainer.new()
	debug_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	debug_panel.position = Vector2(-150, -60)
	canvas.add_child(debug_panel)

	var debug_hbox = HBoxContainer.new()
	debug_panel.add_child(debug_hbox)

	var screenshot_btn = Button.new()
	screenshot_btn.text = "📸 AI Screenshot"
	screenshot_btn.pressed.connect(_on_screenshot_pressed)
	debug_hbox.add_child(screenshot_btn)

	var dump_btn = Button.new()
	dump_btn.text = "💾 Dump AI State"
	dump_btn.pressed.connect(_on_dump_state_pressed)
	debug_hbox.add_child(dump_btn)


func _setup_simulation() -> void:
	sim = BattleSimulator.new()
	sim.loadMap("Meadow")
	visual_adapter = preload("res://src/battle_sim/GodotVisualAdapter.gd").new(sim.state, self)
	sim.setVisualAdapter(visual_adapter)
	sim.setSeed(42)

	# --- Teams ---
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6))
	sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 7))
	sim.spawnMonster("Healer Mage", 1, Vector2i(1, 6))
	sim.spawnMonster("Mage Dragon", 1, Vector2i(2, 7))

	sim.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0))
	sim.spawnMonster("Megidos", 2, Vector2i(14, 1))
	sim.spawnMonster("Oracle of Ages", 2, Vector2i(14, 0))
	sim.spawnMonster("Snowzilla", 2, Vector2i(13, 1))

	sim.startBattle()
	sim.turnManager.startNewRound()


func _on_play_toggled(button_pressed: bool) -> void:
	if button_pressed:
		turn_timer.start()
	else:
		turn_timer.stop()


func _on_speed_changed(value: float) -> void:
	turn_timer.wait_time = 1.0 / value
	if not turn_timer.is_stopped():
		turn_timer.start()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click_selection(event.position)

func _handle_click_selection(mouse_pos: Vector2) -> void:
	if not camera or not sim or not sim.state: return
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)

	# Intersect with Y=0 plane
	if ray_normal.y >= 0.0: return # Parallel or pointing up
	var t = -ray_origin.y / ray_normal.y
	var intersection = ray_origin + ray_normal * t

	var grid_x = roundi(intersection.x)
	var grid_z = roundi(intersection.z)
	var pos = Vector2i(grid_x, grid_z)

	var monster_id = -1
	if sim.state.withinBounds(pos):
		var monster = sim.state.getMonsterAt(pos)
		if monster != null:
			monster_id = monster.uniqueID

	if monster_id != -1:
		visual_adapter.highlight_monster(monster_id)
		_update_selection_ui(monster_id)
	else:
		visual_adapter.highlight_monster(-1)
		_update_selection_ui(-1)

func _update_selection_ui(monster_id: int) -> void:
	if monster_id == -1:
		left_ui_label.text = "Waiting for turn..."
		return

	var m = sim.state.getMonster(monster_id)
	if not m: return

	var info = "[ %s ]\n" % m.name
	info += "HP: %d/%d\n" % [m.hitpoints, m.max_hitpoints]
	info += "ATK: %d | DEF: %d\n" % [m.atk, m.def]
	info += "SPD: %d | MOV: %d\n" % [m.speed, m.move]

	var elements_str = "None"
	if m.elements and m.elements.size() > 0:
		elements_str = ", ".join(m.elements)
	info += "Elements: %s" % elements_str

	left_ui_label.text = info


func _on_turn_timer_timeout() -> void:
	if not sim.turnManager.hasNextTurn():
		var winner = sim.checkWinCondition()
		if winner != -1:
			turn_timer.stop()
			sim.events.battle_ended.emit(winner)
			return

		sim.events.round_ended.emit(sim.state.roundCount)
		sim.turnManager.startNewRound()

	var monsterID = sim.turnManager.startNextTurn()
	if monsterID != -1:
		sim.executeTurn(monsterID)
		sim.turnManager.endTurn(monsterID)

		var winner = sim.checkWinCondition()
		if winner != -1:
			turn_timer.stop()
			sim.events.battle_ended.emit(winner)

func _on_screenshot_pressed() -> void:
	DirAccess.make_dir_absolute("res://debug")
	var img = get_viewport().get_texture().get_image()
	img.save_png("res://debug/screenshot.png")
	print("Screenshot saved to debug/screenshot.png")

func _on_dump_state_pressed() -> void:
	DirAccess.make_dir_absolute("res://debug")
	var state_dict = sim.state.serialize_state()
	var file = FileAccess.open("res://debug/state_dump.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state_dict, "\t"))
		file.close()
		print("State dumped to debug/state_dump.json")

func _on_clayness_selected(index: int) -> void:
	var env_node = null
	var light_node = null
	for child in get_children():
		if child is WorldEnvironment: env_node = child
		if child is DirectionalLight3D: light_node = child
	if not env_node or not light_node: return

	var env = env_node.environment

	if index == 0:
		env.ambient_light_color = Color(0.8, 0.8, 0.8)
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		light_node.shadow_blur = 0.0
		light_node.light_energy = 1.0
		light_node.light_color = Color(1.0, 1.0, 1.0)
		return

	index -= 1

	# Reset defaults before applying profile
	env.ssao_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	light_node.light_energy = 0.8

	match index:
		0: # Profile 1 (Base Clay)
			env.ssao_intensity = 3.0; env.ssao_radius = 2.0; light_node.shadow_blur = 3.0; env.ambient_light_color = Color(0.6, 0.65, 0.7)
		1: # Profile 2 (Harsh SSAO)
			env.ssao_intensity = 8.0; env.ssao_radius = 1.0; light_node.shadow_blur = 1.0; env.ambient_light_color = Color(0.5, 0.55, 0.6)
		2: # Profile 3 (Soft SSAO)
			env.ssao_intensity = 2.0; env.ssao_radius = 4.0; light_node.shadow_blur = 5.0; env.ambient_light_color = Color(0.7, 0.75, 0.8)
		3: # Profile 4 (High Contrast)
			env.ssao_intensity = 5.0; env.ssao_radius = 3.0; light_node.shadow_blur = 0.5; env.ambient_light_color = Color(0.3, 0.35, 0.4)
		4: # Profile 5 (No SSAO)
			env.ssao_intensity = 0.0; env.ssao_radius = 1.0; light_node.shadow_blur = 3.0; env.ambient_light_color = Color(0.6, 0.65, 0.7)
		5: # Profile 6 (Glowy Ambient)
			env.ssao_intensity = 4.0; env.ssao_radius = 2.0; light_node.shadow_blur = 3.0; env.ambient_light_color = Color(0.8, 0.8, 0.85)
		6: # Profile 7 (Dark Clay)
			env.ssao_intensity = 6.0; env.ssao_radius = 1.5; light_node.shadow_blur = 4.0; env.ambient_light_color = Color(0.2, 0.25, 0.3); light_node.light_energy = 1.2
		7: # Profile 8 (Vibrant/Linear)
			env.ssao_intensity = 4.0; env.ssao_radius = 2.0; light_node.shadow_blur = 3.0; env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		8: # Profile 9 (Filmic Clay)
			env.ssao_intensity = 5.0; env.ssao_radius = 2.5; light_node.shadow_blur = 2.0; env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		9: # Profile 10 (Deep Shadows)
			env.ssao_intensity = 10.0; env.ssao_radius = 5.0; light_node.shadow_blur = 1.0; env.ambient_light_color = Color(0.1, 0.1, 0.15); light_node.light_energy = 1.5

func _on_material_selected(index: int) -> void:
	if visual_adapter:
		visual_adapter.apply_global_effect(index)
