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

enum Lifecycle { SETUP, BATTLE, COMPLETE }
enum PlayerState { INACTIVE, UNIT_SELECTED, MOVE_PREVIEW, ACTION_MENU, TARGETING, CONFIRM }

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
var player_state: PlayerState = PlayerState.INACTIVE
var active_player_id: int = -1
var player_grid_cursor := Vector2i.ZERO
var reachable_tiles: Array = []
var valid_target_ids: Array = []
var pending_move_path: Array = []
var pending_action: String = "wait"
var pending_target_id: int = -1
var pending_spell_set: int = 0
var pending_spell_index: int = 0


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
		"player_attack": Callable(self, "_on_player_attack"),
		"player_spell": Callable(self, "_on_player_spell"),
		"player_wait": Callable(self, "_on_player_wait"),
		"player_confirm": Callable(self, "_on_player_confirm"),
		"player_cancel": Callable(self, "_on_player_cancel"),
		"player_end_turn": Callable(self, "_on_player_end_turn"),
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
	lifecycle = Lifecycle.SETUP
	player_state = PlayerState.INACTIVE
	active_player_id = -1
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
	player_state = PlayerState.INACTIVE
	active_player_id = -1
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
	var size = sim.state.boardSize
	camera.focus_point = Vector3((size.x - 1) * 0.5, 0, (size.y - 1) * 0.5)
	camera.size = max(size.x, size.y) * 0.95
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
	if lifecycle != Lifecycle.BATTLE or active_player_id != -1:
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
	if lifecycle != Lifecycle.BATTLE or sim == null or active_player_id != -1:
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
	lifecycle = Lifecycle.COMPLETE
	turn_timer.stop()
	battle_ui["play_button"].set_pressed_no_signal(false)
	battle_ui["play_button"].text = "Play"
	battle_ui["play_button"].tooltip_text = "Battle complete."
	battle_ui["play_button"].disabled = true
	active_player_id = -1
	player_state = PlayerState.INACTIVE
	battle_ui["action_panel"].visible = false
	visual_adapter.clear_tactical_overlays()
	visual_adapter.release_player_cursor()
	sim.events.battle_ended.emit(winner)
	right_ui_label.text = "BATTLE COMPLETE\nTeam %d wins.\nChoose New Battle to return to setup." % winner


func _begin_player_turn(monsterID: int) -> void:
	turn_timer.stop()
	battle_ui["play_button"].disabled = true
	active_player_id = monsterID
	pending_move_path = []
	pending_action = "wait"
	pending_target_id = -1
	pending_spell_set = 0
	pending_spell_index = 0
	player_grid_cursor = sim.state.getMonsterPosition(monsterID)
	battle_ui["action_panel"].visible = true
	_populate_spell_options()
	player_state = PlayerState.UNIT_SELECTED
	visual_adapter.show_player_cursor(player_grid_cursor)
	_enter_move_preview()


func _enter_move_preview() -> void:
	if active_player_id == -1:
		return
	player_state = PlayerState.MOVE_PREVIEW
	var currentPos = sim.state.getMonsterPosition(active_player_id)
	reachable_tiles = sim.movementResolver.getReachablePositions(active_player_id)
	if not reachable_tiles.has(currentPos):
		reachable_tiles.append(currentPos)
	pending_move_path = []
	player_grid_cursor = currentPos
	visual_adapter.show_player_cursor(currentPos)
	visual_adapter.show_movement_options(reachable_tiles)
	_set_action_status("MOVE_PREVIEW — select a blue tile, then choose an action.")
	_update_action_buttons()


func _future_position() -> Vector2i:
	if not pending_move_path.is_empty():
		return pending_move_path.back()
	return sim.state.getMonsterPosition(active_player_id)


func _handle_grid_selection(pos: Vector2i) -> void:
	if active_player_id == -1 or not sim.state.withinBounds(pos):
		return
	player_grid_cursor = pos
	if player_state == PlayerState.MOVE_PREVIEW:
		if not reachable_tiles.has(pos):
			_set_action_status("That tile is not reachable.")
			return
		var currentPos = sim.state.getMonsterPosition(active_player_id)
		pending_move_path = [] if pos == currentPos else sim.movementResolver.findPath(currentPos, pos, 100)
		var validation = sim.movementResolver.validateMovePath(active_player_id, pending_move_path)
		if not validation["success"]:
			_set_action_status("Invalid path: %s" % validation["reason"])
			return
		player_state = PlayerState.ACTION_MENU
		visual_adapter.show_player_cursor(pos)
		visual_adapter.show_movement_options(reachable_tiles, pending_move_path)
		_set_action_status("ACTION_MENU — attack, cast, wait, or revise movement.")
		_update_action_buttons()
	elif player_state == PlayerState.TARGETING:
		var target = sim.state.getMonsterAt(pos)
		if target == null or not valid_target_ids.has(target.uniqueID):
			_set_action_status("Choose one of the highlighted targets.")
			return
		pending_target_id = target.uniqueID
		player_state = PlayerState.CONFIRM
		visual_adapter.show_target_cursor(pos)
		_set_action_status("CONFIRM — %s %s." % [pending_action.capitalize(), target.name])
		_update_action_buttons()


func _on_player_move() -> void:
	_enter_move_preview()


func _on_player_attack() -> void:
	if active_player_id == -1:
		return
	pending_action = "attack"
	pending_target_id = -1
	valid_target_ids = sim.combatResolver.getBasicAttackTargetsFrom(active_player_id, _future_position())
	_enter_targeting("ATTACK")


func _on_player_spell() -> void:
	if active_player_id == -1 or battle_ui["spell_option"].item_count == 0:
		return
	var spellOption: OptionButton = battle_ui["spell_option"]
	var metadata = spellOption.get_item_metadata(spellOption.selected)
	if not metadata is Vector2i or metadata.x < 0:
		_set_action_status("No available spell selected.")
		return
	pending_spell_set = metadata.x
	pending_spell_index = metadata.y
	pending_action = "spell"
	pending_target_id = -1
	valid_target_ids = sim.combatResolver.getSpellTargetsFrom(
		active_player_id, pending_spell_set, pending_spell_index, _future_position()
	)
	_enter_targeting("SPELL")


func _enter_targeting(label: String) -> void:
	if valid_target_ids.is_empty():
		player_state = PlayerState.ACTION_MENU
		_set_action_status("No valid %s targets from the previewed destination." % label.to_lower())
		_update_action_buttons()
		return
	player_state = PlayerState.TARGETING
	visual_adapter.show_target_options(valid_target_ids)
	var firstTarget = valid_target_ids[0]
	player_grid_cursor = sim.state.getMonsterPosition(firstTarget)
	visual_adapter.show_target_cursor(player_grid_cursor)
	_set_action_status("TARGETING — choose a highlighted %s target." % label.to_lower())
	_update_action_buttons()


func _on_player_wait() -> void:
	if active_player_id == -1:
		return
	pending_action = "wait"
	pending_target_id = -1
	player_state = PlayerState.CONFIRM
	visual_adapter.clear_tactical_overlays()
	visual_adapter.show_player_cursor(_future_position())
	_set_action_status("CONFIRM — move and wait without acting.")
	_update_action_buttons()


func _on_player_confirm() -> void:
	if player_state == PlayerState.CONFIRM:
		_submit_player_command()


func _on_player_end_turn() -> void:
	if active_player_id == -1:
		return
	pending_action = "wait"
	pending_target_id = -1
	_submit_player_command()


func _submit_player_command() -> void:
	var command = {
		"move_path": pending_move_path,
		"action": pending_action,
		"target_id": pending_target_id,
		"spell_set_index": pending_spell_set,
		"spell_index": pending_spell_index
	}
	var result = sim.executeCommand(active_player_id, command, "player")
	if not result.get("success", false):
		_set_action_status("Command rejected: %s" % result.get("reason", "unknown"))
		return

	var completedID = active_player_id
	visual_adapter.release_player_cursor()
	visual_adapter.clear_tactical_overlays()
	sim.turnManager.endTurn(completedID)
	active_player_id = -1
	player_state = PlayerState.INACTIVE
	battle_ui["action_panel"].visible = false
	battle_ui["play_button"].disabled = false
	var winner = sim.checkWinCondition()
	if winner != -1:
		_finish_battle(winner)
	elif battle_ui["play_button"].button_pressed:
		turn_timer.start()


func _on_player_cancel() -> void:
	if active_player_id == -1:
		return
	match player_state:
		PlayerState.CONFIRM:
			if pending_action in ["attack", "spell"]:
				_enter_targeting(pending_action.to_upper())
			else:
				player_state = PlayerState.ACTION_MENU
		PlayerState.TARGETING:
			player_state = PlayerState.ACTION_MENU
			valid_target_ids = []
			visual_adapter.show_movement_options(reachable_tiles, pending_move_path)
			visual_adapter.show_player_cursor(_future_position())
		PlayerState.ACTION_MENU:
			_enter_move_preview()
		_:
			pass
	if player_state == PlayerState.ACTION_MENU:
		_set_action_status("ACTION_MENU — choose an action or revise movement.")
	_update_action_buttons()


func _populate_spell_options() -> void:
	var option: OptionButton = battle_ui["spell_option"]
	option.clear()
	var monster = sim.state.getMonster(active_player_id)
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
	if active_player_id == -1:
		return
	var option: OptionButton = battle_ui["spell_option"]
	var metadata = option.get_item_metadata(index)
	if metadata is Vector2i and metadata.x >= 0:
		var spell = sim.state.getMonster(active_player_id).spellSets[metadata.x][metadata.y]
		_set_action_status("%s — range %d, minimum %d, cooldown %d." % [
			spell.name, spell.range, spell.min_range, spell.cooldown
		])


func _set_action_status(text: String) -> void:
	battle_ui["action_status"].text = text


func _update_action_buttons() -> void:
	var inActionMenu = player_state == PlayerState.ACTION_MENU
	battle_ui["move_button"].disabled = active_player_id == -1
	battle_ui["attack_button"].disabled = not inActionMenu
	battle_ui["cast_button"].disabled = not inActionMenu
	battle_ui["spell_option"].disabled = not inActionMenu
	battle_ui["wait_button"].disabled = not inActionMenu
	battle_ui["confirm_button"].disabled = player_state != PlayerState.CONFIRM
	battle_ui["cancel_button"].disabled = player_state in [PlayerState.INACTIVE, PlayerState.MOVE_PREVIEW]
	battle_ui["end_turn_button"].disabled = active_player_id == -1


func _unhandled_input(event: InputEvent) -> void:
	if lifecycle != Lifecycle.BATTLE:
		return
	camera.handle_input(event, retro_renderer.screen_motion_scale())
	if active_player_id != -1:
		if event.is_action_pressed("ui_cancel"):
			_on_player_cancel()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			_handle_grid_selection(player_grid_cursor)
			get_viewport().set_input_as_handled()
			return
		var direction = Vector2i.ZERO
		if event.is_action_pressed("ui_left"): direction = Vector2i.LEFT
		elif event.is_action_pressed("ui_right"): direction = Vector2i.RIGHT
		elif event.is_action_pressed("ui_up"): direction = Vector2i.UP
		elif event.is_action_pressed("ui_down"): direction = Vector2i.DOWN
		if direction != Vector2i.ZERO:
			_move_player_cursor(direction)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_M: _on_player_move()
				KEY_A: _on_player_attack()
				KEY_S: _on_player_spell()
				KEY_W: _on_player_wait()
				KEY_E: _on_player_end_turn()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pos = _mouse_to_battle_coord(event.position)
		if active_player_id != -1:
			_handle_grid_selection(pos)
		else:
			_handle_click_selection(pos)


func _move_player_cursor(direction: Vector2i) -> void:
	var next = player_grid_cursor + direction
	next.x = clampi(next.x, 0, sim.state.boardSize.x - 1)
	next.y = clampi(next.y, 0, sim.state.boardSize.y - 1)
	player_grid_cursor = next
	if player_state == PlayerState.TARGETING:
		visual_adapter.show_target_cursor(next)
	else:
		visual_adapter.show_player_cursor(next)


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
