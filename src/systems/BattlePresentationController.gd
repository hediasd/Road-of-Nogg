extends Node3D

const BattleUIBuilderScript = preload("res://src/presentation/BattleUIBuilder.gd")
const BattleSetupUIScript = preload("res://src/presentation/BattleSetupUI.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const GodotVisualAdapterScript = preload("res://src/presentation/GodotVisualAdapter.gd")
const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")

const PlayerTurnControllerScript = preload("res://src/systems/PlayerTurnController.gd")

enum Lifecycle { SETUP, BATTLE, COMPLETE }

var sim: BattleSimulator
var visual_adapter: GodotVisualAdapter
var turn_timer: Timer
var camera: BattleCameraController
var retro_renderer

var left_ui_label: Label
var right_ui_label: Label
var log_label: RichTextLabel
var log_panel: PanelContainer

var battle_ui: Dictionary = {}
var setup_ui: Dictionary = {}
var current_config
var lifecycle: Lifecycle = Lifecycle.SETUP
## Owns the player-turn phase machine. Null outside a battle. This controller
## routes input to it and reacts to its signals; it does not track phases.
var player_turn: PlayerTurnControllerScript


func _ready() -> void:
	retro_renderer = RetroRenderControllerScript.new(self)
	_setup_background()
	_setup_camera_and_lighting()
	_build_battle_ui()
	_build_setup_ui()
	_show_setup()


func _setup_background() -> void:
	var bgCanvas = CanvasLayer.new()
	bgCanvas.layer = -1
	retro_renderer.world_viewport.add_child(bgCanvas)
	var material = ShaderMaterial.new()
	material.shader = load("res://assets/textures/sky/retro_sky_2d.gdshader")
	var background = ColorRect.new()
	background.material = material
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgCanvas.add_child(background)

	var environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = -1
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var worldEnvironment = WorldEnvironment.new()
	worldEnvironment.environment = environment
	retro_renderer.world_root.add_child(worldEnvironment)


func _setup_camera_and_lighting() -> void:
	camera = BattleCameraController.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(6, 15, 14)
	retro_renderer.world_root.add_child(camera)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	# Vertex-snapped shadow passes create large diagonal bands in the battle view.
	light.shadow_enabled = false
	light.light_energy = 1.0
	light.light_color = Color.WHITE
	retro_renderer.world_root.add_child(light)


func _build_battle_ui() -> void:
	battle_ui = BattleUIBuilderScript.build(self, {
		"play_toggled": Callable(self, "_on_play_toggled"),
		"speed_changed": Callable(self, "_on_speed_changed"),
		"turn_timeout": Callable(self, "_on_turn_timer_timeout"),
		"new_battle_pressed": Callable(self, "_on_new_battle_pressed"),
		"screenshot_pressed": Callable(self, "_on_screenshot_pressed"),
		"dump_state_pressed": Callable(self, "_on_dump_state_pressed"),
		"graphics_reset_pressed": Callable(self, "_on_graphics_reset_pressed"),
		"graphics_preset_selected": Callable(self, "_on_battle_rendering_preset_selected"),
		"graphics_feature_selected": Callable(self, "_on_battle_rendering_feature_selected"),
		"look_parameter_changed": Callable(self, "_on_look_parameter_changed"),
		"crt_parameter_changed": Callable(self, "_on_crt_parameter_changed"),
		"player_move": Callable(self, "_on_player_move"),
		"player_undo_move": Callable(self, "_on_player_undo_move"),
		"player_attack": Callable(self, "_on_player_attack"),
		"player_spell": Callable(self, "_on_player_spell"),
		"player_confirm": Callable(self, "_on_player_confirm"),
		"player_cancel": Callable(self, "_on_player_cancel"),
		"player_pass": Callable(self, "_on_player_pass"),
		"spell_selected": Callable(self, "_on_spell_selected")
	})
	turn_timer = battle_ui["turn_timer"]
	left_ui_label = battle_ui["left_ui_label"]
	right_ui_label = battle_ui["right_ui_label"]
	log_label = battle_ui["log_label"]
	log_panel = battle_ui["log_panel"]
	_sync_rendering_options()


func _build_setup_ui() -> void:
	setup_ui = BattleSetupUIScript.build(
		self,
		{
			"preset_selected": Callable(self, "_on_preset_selected"),
			"monster_selected": Callable(self, "_on_monster_selected"),
			"seed_changed": Callable(self, "_on_seed_changed"),
			"rendering_preset_selected": Callable(self, "_on_rendering_preset_selected"),
			"rendering_feature_selected": Callable(self, "_on_rendering_feature_selected"),
			"confirmed": Callable(self, "_on_setup_confirmed")
		},
		MapReferencesScript.getNames(),
		MonsterReferencesScript.getNames(),
		BattleSetupPresetsScript.getPresetNames()
	)
	_apply_preset(1, BattleSetupPresetsScript.PRESET_DEFAULT)
	_apply_preset(2, BattleSetupPresetsScript.PRESET_DEFAULT)
	_sync_rendering_options()
	_update_duplicate_note()


func _show_setup() -> void:
	if camera:
		camera.cancelDrag()
	lifecycle = Lifecycle.SETUP
	player_turn = null
	if turn_timer:
		turn_timer.stop()
	if not battle_ui.is_empty():
		battle_ui["graphics_button"].set_pressed_no_signal(false)
		battle_ui["graphics_panel"].visible = false
		battle_ui["play_button"].set_pressed_no_signal(true)
		battle_ui["play_button"].text = "Pause"
		battle_ui["play_button"].tooltip_text = "Pause computer-controlled turns."
		battle_ui["play_button"].disabled = false
	if visual_adapter:
		visual_adapter.dispose()
	visual_adapter = null
	sim = null
	battle_ui["canvas"].visible = false
	battle_ui["action_panel"].visible = false
	setup_ui["canvas"].visible = true
	setup_ui["error_label"].text = ""
	setup_ui["confirm_button"].call_deferred("grab_focus")


func _on_preset_selected(index: int, team: int) -> void:
	var presetOption: OptionButton = setup_ui["team_%d_preset" % team]
	var presetName: String = presetOption.get_item_metadata(index)
	_apply_preset(team, presetName)


func _apply_preset(team: int, presetName: String) -> void:
	if presetName == BattleSetupPresetsScript.PRESET_CUSTOM:
		return
	var roster = BattleSetupPresetsScript.getRoster(presetName, team, int(setup_ui["seed_input"].value))
	var slots: Array = setup_ui["team_%d_slots" % team]
	for index in range(min(roster.size(), slots.size())):
		_select_option_by_metadata(slots[index], roster[index])
	_update_duplicate_note()


func _on_monster_selected(_selectedIndex: int, team: int, _slotIndex: int) -> void:
	var preset: OptionButton = setup_ui["team_%d_preset" % team]
	_select_option_by_metadata(preset, BattleSetupPresetsScript.PRESET_CUSTOM)
	_update_duplicate_note()


func _sync_rendering_options() -> void:
	if not setup_ui.is_empty():
		_select_option_by_metadata(
			setup_ui["render_mode_option"],
			retro_renderer.render_preset
		)
		_select_option_by_metadata(
			setup_ui["geometry_option"],
			"jitter" if retro_renderer.vertex_snap_enabled else "stable"
		)
		_select_option_by_metadata(
			setup_ui["upscale_option"],
			"nearest" if retro_renderer.nearest_filter_enabled else "linear"
		)

	if battle_ui.is_empty():
		return
	_select_option_by_metadata(
		battle_ui["graphics_look_option"],
		retro_renderer.render_preset
	)
	battle_ui["graphics_preset_description"].text = (
		RenderPresetCatalogScript.description(retro_renderer.render_preset)
	)
	_select_option_by_metadata(
		battle_ui["graphics_geometry_option"],
		"jitter" if retro_renderer.vertex_snap_enabled else "stable"
	)
	_select_option_by_metadata(
		battle_ui["graphics_upscale_option"],
		"nearest" if retro_renderer.nearest_filter_enabled else "linear"
	)
	for parameter in battle_ui["graphics_look_sliders"]:
		var lookSliderData: Dictionary = battle_ui["graphics_look_sliders"][parameter]
		var lookSlider: HSlider = lookSliderData["slider"]
		var lookValue = retro_renderer.get_look_parameter(parameter)
		lookSlider.set_value_no_signal(lookValue)
		lookSlider.editable = (
			retro_renderer.vertex_snap_enabled
			if parameter == retro_renderer.LOOK_SNAP_STRENGTH else
			true
		)
		lookSliderData["value_label"].text = "%.2f" % lookValue
	var crtActive = retro_renderer.crt_enabled
	battle_ui["graphics_crt_hint"].modulate = (
		Color(0.82, 0.9, 1.0) if crtActive else Color(0.48, 0.54, 0.64)
	)
	for parameter in battle_ui["graphics_crt_sliders"]:
		var sliderData: Dictionary = battle_ui["graphics_crt_sliders"][parameter]
		var slider: HSlider = sliderData["slider"]
		var value = retro_renderer.get_crt_parameter(parameter)
		slider.set_value_no_signal(value)
		slider.editable = crtActive
		sliderData["value_label"].text = "%.2f" % value


func _on_rendering_preset_selected(_index: int) -> void:
	var renderMode: OptionButton = setup_ui["render_mode_option"]
	retro_renderer.set_preset(renderMode.get_item_metadata(renderMode.selected))
	_sync_rendering_options()


func _on_rendering_feature_selected(_index: int) -> void:
	var geometry: OptionButton = setup_ui["geometry_option"]
	var upscale: OptionButton = setup_ui["upscale_option"]
	retro_renderer.set_features(
		geometry.get_item_metadata(geometry.selected) == "jitter",
		upscale.get_item_metadata(upscale.selected) == "nearest"
	)
	_sync_rendering_options()


func _on_graphics_reset_pressed() -> void:
	retro_renderer.reset_defaults()
	_sync_rendering_options()


func _on_battle_rendering_preset_selected(_index: int) -> void:
	var option: OptionButton = battle_ui["graphics_look_option"]
	retro_renderer.set_preset(option.get_item_metadata(option.selected))
	_sync_rendering_options()


func _on_battle_rendering_feature_selected(_index: int) -> void:
	var geometry: OptionButton = battle_ui["graphics_geometry_option"]
	var upscale: OptionButton = battle_ui["graphics_upscale_option"]
	retro_renderer.set_features(
		geometry.get_item_metadata(geometry.selected) == "jitter",
		upscale.get_item_metadata(upscale.selected) == "nearest"
	)
	_sync_rendering_options()


func _on_look_parameter_changed(value: float, parameter: String) -> void:
	retro_renderer.set_look_parameter(parameter, value)
	_sync_rendering_options()


func _on_crt_parameter_changed(value: float, parameter: String) -> void:
	retro_renderer.set_crt_parameter(parameter, value)
	_sync_rendering_options()


func _on_seed_changed(_value: float) -> void:
	for team in [1, 2]:
		var preset: OptionButton = setup_ui["team_%d_preset" % team]
		var presetName: String = preset.get_item_metadata(preset.selected)
		if presetName == BattleSetupPresetsScript.PRESET_RANDOM_BALANCED:
			_apply_preset(team, presetName)


func _select_option_by_metadata(option: OptionButton, value) -> void:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _read_roster(team: int) -> Array[String]:
	var roster: Array[String] = []
	for option in setup_ui["team_%d_slots" % team]:
		roster.append(option.get_item_metadata(option.selected))
	return roster


func _update_duplicate_note() -> void:
	if setup_ui.is_empty():
		return
	var hasDuplicates = false
	for roster in [_read_roster(1), _read_roster(2)]:
		var seen: Dictionary = {}
		for monsterName in roster:
			if seen.has(monsterName):
				hasDuplicates = true
			seen[monsterName] = true
	setup_ui["duplicate_note"].text = (
		"Duplicates selected — allowed, but varied teams are recommended."
		if hasDuplicates else
		"Duplicates are allowed, but varied teams are recommended."
	)


func _read_setup_config():
	var config = BattleSetupConfigScript.new()
	var modeOption: OptionButton = setup_ui["mode_option"]
	var mapOption: OptionButton = setup_ui["map_option"]
	config.battleMode = modeOption.get_item_metadata(modeOption.selected)
	config.mapName = mapOption.get_item_metadata(mapOption.selected)
	config.seed = int(setup_ui["seed_input"].value)
	config.team1 = _read_roster(1)
	config.team2 = _read_roster(2)
	return config


func _on_setup_confirmed() -> void:
	var config = _read_setup_config()
	var validation = config.validate()
	if not validation["success"]:
		setup_ui["error_label"].text = "\n".join(validation["errors"])
		return
	_start_battle(config)


func _start_battle(config) -> void:
	current_config = config
	setup_ui["canvas"].visible = false
	battle_ui["canvas"].visible = true
	lifecycle = Lifecycle.BATTLE
	log_label.text = ""
	left_ui_label.text = "Battle ready"
	right_ui_label.text = "No target"
	battle_ui["graphics_button"].set_pressed_no_signal(false)
	battle_ui["graphics_panel"].visible = false
	battle_ui["play_button"].set_pressed_no_signal(true)
	battle_ui["play_button"].text = "Pause"
	battle_ui["play_button"].tooltip_text = "Pause computer-controlled turns."
	battle_ui["play_button"].disabled = false

	sim = BattleSetupFactoryScript.createSimulator(config, Callable(self, "_create_visual_adapter"))
	player_turn = PlayerTurnControllerScript.new(
		sim,
		visual_adapter,
		Callable(visual_adapter, "isAnimationBusy"),
		visual_adapter.animation_queue_drained
	)
	player_turn.menu_changed.connect(_on_player_menu_changed)
	player_turn.status_changed.connect(_set_action_status)
	player_turn.turn_finished.connect(_on_player_turn_finished)
	var size = sim.state.boardSize
	var highestTile = 0
	for y in range(size.y):
		for x in range(size.x):
			highestTile = maxi(highestTile, sim.state.getHeight(Vector2i(x, y)))
	var highestWorldElevation = float(highestTile) * GodotVisualAdapterScript.TERRAIN_CELL_HEIGHT
	camera.focus_point = Vector3(
		(size.x - 1) * 0.5,
		highestWorldElevation * 0.5,
		(size.y - 1) * 0.5
	)
	camera.size = max(size.x, size.y) * 0.95 + highestWorldElevation * 0.35
	sim.startBattle()
	sim.turnManager.startNewRound()
	turn_timer.start()


func _create_visual_adapter(state: BattleState):
	visual_adapter = GodotVisualAdapterScript.new(state, self, retro_renderer.world_root)
	return visual_adapter


func _on_new_battle_pressed() -> void:
	_show_setup()


func _on_play_toggled(buttonPressed: bool) -> void:
	battle_ui["play_button"].text = "Pause" if buttonPressed else "Play"
	battle_ui["play_button"].tooltip_text = (
		"Pause computer-controlled turns."
		if buttonPressed else
		"Start computer-controlled turns."
	)
	if lifecycle != Lifecycle.BATTLE or _player_turn_active():
		return
	if buttonPressed:
		turn_timer.start()
	else:
		turn_timer.stop()


func _on_speed_changed(value: float) -> void:
	turn_timer.wait_time = 1.0 / value
	if not turn_timer.is_stopped():
		turn_timer.start()


func _on_turn_timer_timeout() -> void:
	_advance_battle()


func _advance_battle() -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or _player_turn_active():
		return
	if not sim.turnManager.hasNextTurn():
		var winner = sim.checkWinCondition()
		if winner != -1:
			_finish_battle(winner)
			return
		sim.events.round_ended.emit(sim.state.roundCount)
		sim.turnManager.startNewRound()

	var monsterID = sim.turnManager.startNextTurn()
	if monsterID == -1:
		return
	var monster = sim.state.getMonster(monsterID)
	if sim.state.hasEffect(monsterID, "petrify"):
		sim.executeCommand(monsterID, {"move_path": [], "action": "wait"}, "system")
		sim.turnManager.endTurn(monsterID)
		return
	if current_config.controllerForTeam(monster.team) == "player":
		_begin_player_turn(monsterID)
		return

	sim.executeTurn(monsterID)
	sim.turnManager.endTurn(monsterID)
	var winner = sim.checkWinCondition()
	if winner != -1:
		_finish_battle(winner)


func _finish_battle(winner: int) -> void:
	camera.cancelDrag()
	lifecycle = Lifecycle.COMPLETE
	turn_timer.stop()
	battle_ui["play_button"].set_pressed_no_signal(false)
	battle_ui["play_button"].text = "Play"
	battle_ui["play_button"].tooltip_text = "Battle complete."
	battle_ui["play_button"].disabled = true
	player_turn = null
	battle_ui["action_panel"].visible = false
	visual_adapter.clear_tactical_overlays()
	visual_adapter.release_player_cursor()
	# The adapter queues the victory message after every preceding visual action;
	# simulation completion itself remains immediate and independent.
	sim.events.battle_ended.emit(winner)


func _begin_player_turn(monsterID: int) -> void:
	turn_timer.stop()
	battle_ui["play_button"].disabled = true
	battle_ui["action_panel"].visible = true
	_populate_spell_options(monsterID)
	player_turn.beginTurn(monsterID)


func _on_player_turn_finished(_monsterID: int) -> void:
	## The phase controller has closed the turn out. Everything from here is
	## scene-level: turn order, win condition, and CPU pacing.
	sim.turnManager.endTurn(_monsterID)
	battle_ui["action_panel"].visible = false
	battle_ui["play_button"].disabled = false
	var winner = sim.checkWinCondition()
	if winner != -1:
		_finish_battle(winner)
	elif battle_ui["play_button"].button_pressed:
		turn_timer.start()


func _on_player_move() -> void:
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_MOVE)


func _on_player_undo_move() -> void:
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_UNDO_MOVE)


func _on_player_attack() -> void:
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_ATTACK)


func _on_player_spell() -> void:
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_MAGIC)


func _on_player_pass() -> void:
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_PASS)


func _on_player_confirm() -> void:
	player_turn.confirmSelection()


func _on_player_cancel() -> void:
	player_turn.cancel()


func _populate_spell_options(monsterID: int) -> void:
	var option: OptionButton = battle_ui["spell_option"]
	option.clear()
	var monster = sim.state.getMonster(monsterID)
	if monster == null:
		return
	var firstAvailable = -1
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell = monster.spellSets[setIndex][spellIndex]
			var remaining = int(monster.spell_cooldowns.get(spell.name, 0))
			var ready = monster.can_cast(spell)
			var suffix = "R%d" % spell.range if ready else "CD %d" % remaining
			option.add_item("%s [%s]" % [spell.name, suffix])
			var itemIndex = option.item_count - 1
			option.set_item_metadata(itemIndex, Vector2i(setIndex, spellIndex))
			option.set_item_disabled(itemIndex, not ready)
			if ready and firstAvailable == -1:
				firstAvailable = itemIndex
	if option.item_count == 0:
		option.add_item("No spells")
		option.set_item_metadata(0, Vector2i(-1, -1))
		option.set_item_disabled(0, true)
	elif firstAvailable >= 0:
		option.select(firstAvailable)


func _on_spell_selected(index: int) -> void:
	if player_turn == null or not player_turn.isActive():
		return
	var option: OptionButton = battle_ui["spell_option"]
	var metadata = option.get_item_metadata(index)
	if metadata is Vector2i and metadata.x >= 0:
		player_turn.selectSpell(metadata.x, metadata.y)


func _set_action_status(text: String) -> void:
	battle_ui["action_status"].text = text


func _on_player_menu_changed() -> void:
	## The menu model is authoritative; these buttons are a temporary rendering
	## of it until PC-3 replaces them with the vertical menu.
	if player_turn == null:
		return
	var buttonForEntry := {
		PlayerTurnControllerScript.ENTRY_MOVE: "move_button",
		PlayerTurnControllerScript.ENTRY_UNDO_MOVE: "undo_button",
		PlayerTurnControllerScript.ENTRY_ATTACK: "attack_button",
		PlayerTurnControllerScript.ENTRY_MAGIC: "cast_button",
		PlayerTurnControllerScript.ENTRY_PASS: "pass_button"
	}
	for key in buttonForEntry.values():
		battle_ui[key].disabled = true
		battle_ui[key].visible = true
	for entry in player_turn.menuEntries():
		var button: Button = battle_ui[buttonForEntry[entry["id"]]]
		button.visible = entry["visible"]
		button.disabled = not entry["enabled"]

	var phase = player_turn.phase
	battle_ui["spell_option"].disabled = phase != PlayerTurnControllerScript.Phase.MENU
	battle_ui["confirm_button"].disabled = (
		phase != PlayerTurnControllerScript.Phase.CONFIRM_ACTION
	)
	battle_ui["cancel_button"].disabled = phase not in [
		PlayerTurnControllerScript.Phase.MOVE_SELECT,
		PlayerTurnControllerScript.Phase.TARGET_SELECT,
		PlayerTurnControllerScript.Phase.CONFIRM_ACTION
	]


func _input(event: InputEvent) -> void:
	# Space: toggle battle UI visibility
	if (
		lifecycle in [Lifecycle.BATTLE, Lifecycle.COMPLETE] and
		event is InputEventKey and
		event.pressed and
		not event.echo and
		(event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE)
	):
		battle_ui["canvas"].visible = not battle_ui["canvas"].visible
		get_viewport().set_input_as_handled()
		return
	# Ctrl+R: hot-reload monster catalog (Stage 1 feature)
	if (
		event is InputEventKey and
		event.pressed and
		not event.echo and
		event.ctrl_pressed and
		(event.keycode == KEY_R or event.physical_keycode == KEY_R)
	):
		var MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
		if MonsterReferencesScript.reloadCatalog():
			print("✓ Monster catalog reloaded from JSON")
		else:
			print("✗ Monster catalog reload failed; check logs")
		get_viewport().set_input_as_handled()
		return
	# A drag that began over the world keeps owning motion and its release even
	# when the pointer crosses UI or an animated model moves underneath it.
	if lifecycle != Lifecycle.BATTLE or not camera or not camera.isDragging():
		return
	if camera.handle_input(event, retro_renderer.screen_motion_scale()):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if lifecycle != Lifecycle.BATTLE:
		return
	if camera.handle_input(event, retro_renderer.screen_motion_scale()):
		get_viewport().set_input_as_handled()
		return
	if _player_turn_active():
		if event.is_action_pressed("ui_cancel"):
			player_turn.cancel()
			get_viewport().set_input_as_handled()
			return
		# Grid keys only mean something while a tile or target is being aimed.
		# PC-3 gives the menu itself keyboard navigation.
		if player_turn.acceptsGridInput():
			if event.is_action_pressed("ui_accept"):
				player_turn.confirmSelection()
				get_viewport().set_input_as_handled()
				return
			var direction = Vector2i.ZERO
			if event.is_action_pressed("ui_left"): direction = Vector2i.LEFT
			elif event.is_action_pressed("ui_right"): direction = Vector2i.RIGHT
			elif event.is_action_pressed("ui_up"): direction = Vector2i.UP
			elif event.is_action_pressed("ui_down"): direction = Vector2i.DOWN
			if direction != Vector2i.ZERO:
				player_turn.moveCursor(direction)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pos = _mouse_to_battle_coord(event.position)
		if _player_turn_active() and player_turn.acceptsGridInput():
			player_turn.selectGridPosition(pos)
		else:
			_handle_click_selection(pos)


func _player_turn_active() -> bool:
	return player_turn != null and player_turn.isActive()


func _mouse_to_grid(mousePos: Vector2) -> Vector2i:
	if not camera:
		return Vector2i(-1, -1)
	var worldMousePos = retro_renderer.screen_to_world(mousePos)
	if worldMousePos.x < 0.0:
		return Vector2i(-1, -1)
	var rayOrigin = camera.project_ray_origin(worldMousePos)
	var rayNormal = camera.project_ray_normal(worldMousePos)
	if rayNormal.y >= 0.0:
		return Vector2i(-1, -1)
	var distance = -rayOrigin.y / rayNormal.y
	var intersection = rayOrigin + rayNormal * distance
	return Vector2i(roundi(intersection.x), roundi(intersection.z))


func _mouse_to_battle_coord(mousePos: Vector2) -> Vector2i:
	var monsterID = _mouse_to_monster_id(mousePos)
	if monsterID != -1 and sim != null:
		var monsterPos = sim.state.getMonsterPosition(monsterID)
		if sim.state.withinBounds(monsterPos):
			return monsterPos
	return _mouse_to_grid(mousePos)


func _mouse_to_monster_id(mousePos: Vector2) -> int:
	if not camera or visual_adapter == null:
		return -1
	var worldMousePos = retro_renderer.screen_to_world(mousePos)
	if worldMousePos.x < 0.0:
		return -1
	var rayOrigin = camera.project_ray_origin(worldMousePos)
	var rayNormal = camera.project_ray_normal(worldMousePos)
	var query = PhysicsRayQueryParameters3D.create(
		rayOrigin,
		rayOrigin + rayNormal * 1000.0,
		GodotVisualAdapterScript.MONSTER_PICK_COLLISION_LAYER
	)
	var hit = retro_renderer.world_root.get_world_3d().direct_space_state.intersect_ray(query)
	var collider = hit.get("collider")
	if is_instance_valid(collider) and collider.has_meta("monster_id"):
		return int(collider.get_meta("monster_id"))
	return -1


func _handle_click_selection(pos: Vector2i) -> void:
	if sim == null or not sim.state.withinBounds(pos):
		return
	var monster = sim.state.getMonsterAt(pos)
	if monster:
		visual_adapter.highlight_monster(monster.uniqueID)
		_update_selection_ui(monster.uniqueID)
	else:
		visual_adapter.highlight_monster(-1)
		_update_selection_ui(-1)


func _update_selection_ui(monsterID: int) -> void:
	if monsterID == -1:
		left_ui_label.text = "Waiting for turn..."
		return
	var monster = sim.state.getMonster(monsterID)
	if monster == null:
		return
	left_ui_label.text = "[ %s ]\nHP: %d/%d\nATK: %d | DEF: %d\nSPD: %d | MOV: %d\nElements: %s" % [
		monster.name, monster.hitpoints, monster.max_hitpoints,
		monster.atk, monster.def, monster.speed, monster.move,
		", ".join(monster.elements) if not monster.elements.is_empty() else "None"
	]


func _on_screenshot_pressed() -> void:
	DirAccess.make_dir_absolute("res://debug")
	get_viewport().get_texture().get_image().save_png("res://debug/screenshot.png")
	print("Screenshot saved to debug/screenshot.png")


func _on_dump_state_pressed() -> void:
	if sim == null:
		return
	DirAccess.make_dir_absolute("res://debug")
	var file = FileAccess.open("res://debug/state_dump.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(sim.createReplaySnapshot(), "\t"))
		file.close()
		print("Replay snapshot saved to debug/state_dump.json")
