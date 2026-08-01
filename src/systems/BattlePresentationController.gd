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

const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const PlayerTurnControllerScript = preload("res://src/systems/PlayerTurnController.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const ResonanceBarScript = preload("res://src/presentation/theme/ResonanceBar.gd")
enum Lifecycle { SETUP, BATTLE, COMPLETE }

## How far the simulation may run ahead of visual playback before it waits for
## room. Well under VisualActionQueue.MAX_QUEUED_ACTIONS so overflow recovery
## never competes with a deliberate pause, and large enough that ordinary
## playback lag never throttles a battle nobody has paused.
const RUN_AHEAD_LIMIT := 180

## How much of each frame a CPU decision may consume. A turn may take as long as
## it needs; a frame may not — see docs/ARCHITECTURE.md, "Frame budget:
## deliberation must not block presentation". Roughly a quarter of a 16.7ms
## frame, which leaves room for rendering and the visual queue on the same
## frame. Raising it trades smoothness for turns that resolve in fewer frames;
## tune it against debug/verify_frame_pacing.gd, not by feel.
const DELIBERATION_BUDGET_MSEC := 4.0

var sim: BattleSimulator
var visual_adapter: GodotVisualAdapter
var turn_timer: Timer
var camera: BattleCameraController
var retro_renderer

var actor_window: NoggWindow
var target_window: NoggWindow
var log_label: RichTextLabel
var log_panel: PanelContainer

var battle_ui: BattleUIRefs
var setup_ui: BattleSetupUIRefs
var current_config
var lifecycle: Lifecycle = Lifecycle.SETUP
## Owns the player-turn phase machine. Null outside a battle. This controller
## routes input to it and reacts to its signals; it does not track phases.
var player_turn: PlayerTurnControllerScript
var _pending_player_turn_id: int = -1
## The CPU decision currently being computed across frames, and whose turn it
## belongs to. While this is set the turn is already open — startNextTurn() has
## run — so no other turn may begin until it resolves or is cancelled.
var _deliberation: CommandDeliberation = null
var _deliberating_monster_id: int = -1


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
		"ui_through_crt_toggled": Callable(self, "_on_ui_through_crt_toggled")
	})
	turn_timer = battle_ui.turn_timer
	actor_window = battle_ui.actor_window
	target_window = battle_ui.target_window
	log_label = battle_ui.log_label
	log_panel = battle_ui.log_panel
	_sync_rendering_options()
	battle_ui.command_menu.entry_activated.connect(_on_command_menu_entry)
	battle_ui.command_menu.spell_activated.connect(_on_command_menu_spell)


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


func _setup_team_preset(team: int) -> OptionButton:
	return setup_ui.team_1_preset if team == 1 else setup_ui.team_2_preset


func _setup_team_slots(team: int) -> Array[OptionButton]:
	return setup_ui.team_1_slots if team == 1 else setup_ui.team_2_slots


func _show_setup() -> void:
	if camera:
		camera.cancelDrag()
	lifecycle = Lifecycle.SETUP
	player_turn = null
	_cancel_deliberation()
	if turn_timer:
		turn_timer.stop()
	if battle_ui != null:
		battle_ui.graphics_button.set_pressed_no_signal(false)
		battle_ui.graphics.panel.visible = false
		battle_ui.play_button.set_pressed_no_signal(true)
		battle_ui.play_button.text = "Pause"
		battle_ui.play_button.tooltip_text = "Pause computer-controlled turns."
		battle_ui.play_button.disabled = false
	if visual_adapter:
		visual_adapter.dispose()
	visual_adapter = null
	sim = null
	battle_ui.game_canvas.visible = false
	battle_ui.dev_canvas.visible = false
	battle_ui.action_panel.visible = false
	setup_ui.canvas.visible = true
	setup_ui.error_label.text = ""
	setup_ui.confirm_button.call_deferred("grab_focus")


func _on_preset_selected(index: int, team: int) -> void:
	var presetOption: OptionButton = _setup_team_preset(team)
	var presetName: String = presetOption.get_item_metadata(index)
	_apply_preset(team, presetName)


func _apply_preset(team: int, presetName: String) -> void:
	if presetName == BattleSetupPresetsScript.PRESET_CUSTOM:
		return
	var roster = BattleSetupPresetsScript.getRoster(presetName, team, int(setup_ui.seed_input.value))
	var slots: Array[OptionButton] = _setup_team_slots(team)
	for index in range(min(roster.size(), slots.size())):
		_select_option_by_metadata(slots[index], roster[index])
	_update_duplicate_note()


func _on_monster_selected(_selectedIndex: int, team: int, _slotIndex: int) -> void:
	var preset: OptionButton = _setup_team_preset(team)
	_select_option_by_metadata(preset, BattleSetupPresetsScript.PRESET_CUSTOM)
	_update_duplicate_note()


func _sync_rendering_options() -> void:
	if setup_ui != null:
		_select_option_by_metadata(
			setup_ui.render_mode_option,
			retro_renderer.render_preset
		)
		_select_option_by_metadata(
			setup_ui.geometry_option,
			"jitter" if retro_renderer.vertex_snap_enabled else "stable"
		)
		_select_option_by_metadata(
			setup_ui.upscale_option,
			"nearest" if retro_renderer.nearest_filter_enabled else "linear"
		)

	if battle_ui == null:
		return
	_select_option_by_metadata(
		battle_ui.graphics.look_option,
		retro_renderer.render_preset
	)
	battle_ui.graphics.preset_description.text = (
		RenderPresetCatalogScript.description(retro_renderer.render_preset)
	)
	_select_option_by_metadata(
		battle_ui.graphics.geometry_option,
		"jitter" if retro_renderer.vertex_snap_enabled else "stable"
	)
	_select_option_by_metadata(
		battle_ui.graphics.upscale_option,
		"nearest" if retro_renderer.nearest_filter_enabled else "linear"
	)
	for parameter in battle_ui.graphics.look_sliders:
		var lookSliderData: Dictionary = battle_ui.graphics.look_sliders[parameter]
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
	battle_ui.graphics.crt_hint.modulate = (
		Color(0.82, 0.9, 1.0) if crtActive else Color(0.48, 0.54, 0.64)
	)
	battle_ui.graphics.ui_through_crt_button.set_pressed_no_signal(
		retro_renderer.ui_through_crt
	)
	for parameter in battle_ui.graphics.crt_sliders:
		var sliderData: Dictionary = battle_ui.graphics.crt_sliders[parameter]
		var slider: HSlider = sliderData["slider"]
		var value = retro_renderer.get_crt_parameter(parameter)
		slider.set_value_no_signal(value)
		slider.editable = crtActive
		sliderData["value_label"].text = "%.2f" % value


func _on_rendering_preset_selected(_index: int) -> void:
	var renderMode: OptionButton = setup_ui.render_mode_option
	retro_renderer.set_preset(renderMode.get_item_metadata(renderMode.selected))
	_sync_rendering_options()


func _on_rendering_feature_selected(_index: int) -> void:
	var geometry: OptionButton = setup_ui.geometry_option
	var upscale: OptionButton = setup_ui.upscale_option
	retro_renderer.set_features(
		geometry.get_item_metadata(geometry.selected) == "jitter",
		upscale.get_item_metadata(upscale.selected) == "nearest"
	)
	_sync_rendering_options()


func _on_graphics_reset_pressed() -> void:
	retro_renderer.reset_defaults()
	_sync_rendering_options()


func _on_battle_rendering_preset_selected(_index: int) -> void:
	var option: OptionButton = battle_ui.graphics.look_option
	retro_renderer.set_preset(option.get_item_metadata(option.selected))
	_sync_rendering_options()


func _on_battle_rendering_feature_selected(_index: int) -> void:
	var geometry: OptionButton = battle_ui.graphics.geometry_option
	var upscale: OptionButton = battle_ui.graphics.upscale_option
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


func _on_ui_through_crt_toggled(enabled: bool) -> void:
	retro_renderer.set_ui_through_crt(enabled)
	_sync_rendering_options()


func _on_seed_changed(_value: float) -> void:
	for team in [1, 2]:
		var preset: OptionButton = _setup_team_preset(team)
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
	for option in _setup_team_slots(team):
		roster.append(option.get_item_metadata(option.selected))
	return roster


func _update_duplicate_note() -> void:
	if setup_ui == null:
		return
	var hasDuplicates = false
	for roster in [_read_roster(1), _read_roster(2)]:
		var seen: Dictionary = {}
		for monsterName in roster:
			if seen.has(monsterName):
				hasDuplicates = true
			seen[monsterName] = true
	setup_ui.duplicate_note.text = (
		"Duplicates selected — allowed, but varied teams are recommended."
		if hasDuplicates else
		"Duplicates are allowed, but varied teams are recommended."
	)


func _read_setup_config():
	var config = BattleSetupConfigScript.new()
	var modeOption: OptionButton = setup_ui.mode_option
	var mapOption: OptionButton = setup_ui.map_option
	config.battleMode = modeOption.get_item_metadata(modeOption.selected)
	config.mapName = mapOption.get_item_metadata(mapOption.selected)
	config.seed = int(setup_ui.seed_input.value)
	config.team1 = _read_roster(1)
	config.team2 = _read_roster(2)
	return config


func _on_setup_confirmed() -> void:
	var config = _read_setup_config()
	var validation = config.validate()
	if not validation["success"]:
		setup_ui.error_label.text = "\n".join(validation["errors"])
		return
	_start_battle(config)


func _start_battle(config) -> void:
	current_config = config
	_pending_player_turn_id = -1
	_cancel_deliberation()
	setup_ui.canvas.visible = false
	battle_ui.game_canvas.visible = true
	battle_ui.dev_canvas.visible = true
	lifecycle = Lifecycle.BATTLE
	log_label.text = ""
	_renderStatusWindow(actor_window, -1)
	_renderStatusWindow(target_window, -1)
	battle_ui.graphics_button.set_pressed_no_signal(false)
	battle_ui.graphics.panel.visible = false
	battle_ui.play_button.set_pressed_no_signal(true)
	battle_ui.play_button.text = "Pause"
	battle_ui.play_button.tooltip_text = "Pause computer-controlled turns."
	battle_ui.play_button.disabled = false

	sim = BattleSetupFactoryScript.createSimulator(config, Callable(self, "_create_visual_adapter"))
	player_turn = PlayerTurnControllerScript.new(
		sim,
		visual_adapter,
		Callable(visual_adapter, "isAnimationBusy"),
		visual_adapter.animation_queue_drained
	)
	player_turn.menu_changed.connect(_on_player_menu_changed)
	player_turn.status_changed.connect(_set_action_status)
	player_turn.forecast_changed.connect(battle_ui.command_menu.setForecast)
	player_turn.turn_finished.connect(_on_player_turn_finished)
	var size = sim.state.boardSize
	visual_adapter.animation_queue_drained.connect(_on_animation_queue_drained)
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
	battle_ui.play_button.text = "Pause" if buttonPressed else "Play"
	battle_ui.play_button.tooltip_text = "Pause or resume visual playback; simulation continues with bounded run-ahead."
	if visual_adapter != null:
		visual_adapter.setVisualPaused(not buttonPressed)
	if not buttonPressed:
		return
	_try_begin_pending_player_turn()
	if lifecycle == Lifecycle.BATTLE and not _player_turn_active() and _pending_player_turn_id == -1 and turn_timer.is_stopped():
		turn_timer.start()

func _on_speed_changed(value: float) -> void:
	turn_timer.wait_time = 1.0 / value
	if not turn_timer.is_stopped():
		turn_timer.start()


func _on_turn_timer_timeout() -> void:
	_advance_battle()


func _advance_battle() -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or _player_turn_active():
		return
	# A decision in flight already owns an open turn. Starting another here
	# would run two turns at once and resolve them out of order.
	if _deliberation != null:
		return
	# Backpressure. Pausing playback does not pause the simulation, so without a
	# bound a paused queue would run to the end of the battle and overflow
	# MAX_QUEUED_ACTIONS, whose recover() discards exactly the animations the
	# player paused to watch.
	#
	# The timer keeps running and re-checks each tick rather than stopping here:
	# stopping would leave the restart to the `drained` signal, which only fires
	# when the queue reaches zero, so the simulation would stall for a full
	# playback of the backlog instead of resuming as soon as there is room.
	if visual_adapter != null and visual_adapter.queuedAnimationCount() >= RUN_AHEAD_LIMIT:
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
		sim.executeCommand(monsterID, BattleCommand.wait(), "system")
		sim.turnManager.endTurn(monsterID)
		return
	if current_config.controllerForTeam(monster.team) == "player":
		if _presentation_ready_for_player_turn():
			_begin_player_turn(monsterID)
		else:
			_pending_player_turn_id = monsterID
			turn_timer.stop()
		return

	# Deliberation is deferred to _process() under a frame budget; the turn is
	# closed on the frame it finishes.
	var deliberation := sim.beginTurnDeliberation(monsterID)
	if deliberation == null:
		# Nothing can act. Close the turn exactly as executeTurn()'s false
		# return required of its caller.
		sim.turnManager.endTurn(monsterID)
		_check_battle_finished()
		return
	_deliberation = deliberation
	_deliberating_monster_id = monsterID


func _process(_delta: float) -> void:
	_step_deliberation()


## Spends one frame's budget on the decision in flight and closes the turn when
## it finishes. Deliberately not gated on RUN_AHEAD_LIMIT or playback pause:
## those gate whether a *new* turn may start, and this turn is already open —
## abandoning it half-computed would strand turnManager mid-turn.
func _step_deliberation() -> void:
	if _deliberation == null:
		return
	if lifecycle != Lifecycle.BATTLE or sim == null:
		_cancel_deliberation()
		return
	if not _deliberation.step(DELIBERATION_BUDGET_MSEC):
		return
	var monsterID := _deliberating_monster_id
	var finished := _deliberation
	# Cleared before applying: applyDeliberatedTurn() emits events that can
	# reach back into this controller, and they must not see a stale in-flight
	# decision.
	_deliberation = null
	_deliberating_monster_id = -1
	sim.applyDeliberatedTurn(monsterID, finished)
	sim.turnManager.endTurn(monsterID)
	_check_battle_finished()


func _check_battle_finished() -> void:
	var winner = sim.checkWinCondition()
	if winner != -1:
		_finish_battle(winner)


## Discards a decision in flight without applying it. A discarded deliberation
## writes no history: the `decision` event and the command both belong to
## applyDeliberatedTurn(), which never runs.
func _cancel_deliberation() -> void:
	_deliberation = null
	_deliberating_monster_id = -1


func _presentation_ready_for_player_turn() -> bool:
	return visual_adapter == null or (
		not visual_adapter.isAnimationBusy() and not visual_adapter.isVisualPaused()
	)


func _try_begin_pending_player_turn() -> void:
	if _pending_player_turn_id == -1 or lifecycle != Lifecycle.BATTLE:
		return
	if not _presentation_ready_for_player_turn():
		return
	var monster_id = _pending_player_turn_id
	_pending_player_turn_id = -1
	_begin_player_turn(monster_id)

func _finish_battle(winner: int) -> void:
	lifecycle = Lifecycle.COMPLETE
	camera.cancelDrag()
	_pending_player_turn_id = -1
	_cancel_deliberation()
	turn_timer.stop()
	battle_ui.play_button.set_pressed_no_signal(false)
	battle_ui.play_button.text = "Play"
	battle_ui.play_button.tooltip_text = "Battle complete."
	battle_ui.play_button.disabled = true
	player_turn = null
	battle_ui.action_panel.visible = false
	visual_adapter.clear_tactical_overlays()
	visual_adapter.release_player_cursor()
	# The adapter queues the victory message after every preceding visual action;
	# simulation completion itself remains immediate and independent.
	sim.events.battle_ended.emit(winner)


func _begin_player_turn(monsterID: int) -> void:
	turn_timer.stop()
	battle_ui.play_button.disabled = false
	battle_ui.action_panel.visible = true
	player_turn.beginTurn(monsterID)


func _on_player_turn_finished(_monsterID: int) -> void:
	## The phase controller has closed the turn out. Everything from here is
	## scene-level: turn order, win condition, and CPU pacing.
	sim.turnManager.endTurn(_monsterID)
	battle_ui.action_panel.visible = false
	battle_ui.play_button.disabled = false
	var winner = sim.checkWinCondition()
	if winner != -1:
		_finish_battle(winner)
	elif battle_ui.play_button.button_pressed:
		turn_timer.start()


func _set_action_status(text: String) -> void:
	battle_ui.command_menu.setStatus(text)


func _on_player_menu_changed() -> void:
	if player_turn == null:
		return
	var command_menu = battle_ui.command_menu
	if player_turn.phase == PlayerTurnControllerScript.Phase.MENU and not command_menu.isShowingSpells():
		command_menu.showRoot(player_turn.menuEntries())
	elif player_turn.phase != PlayerTurnControllerScript.Phase.MENU:
		command_menu.showPromptOnly()


func _input(event: InputEvent) -> void:
	# Space: toggle developer UI visibility only. Game UI (command menu,
	# actor/target panels, battle log) is lifecycle-driven and stays visible.
	if (
		lifecycle in [Lifecycle.BATTLE, Lifecycle.COMPLETE] and
		event is InputEventKey and
		event.pressed and
		not event.echo and
		(event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE)
	):
		battle_ui.dev_canvas.visible = not battle_ui.dev_canvas.visible
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
	if (
			event is InputEventMouseButton and
			event.button_index == MOUSE_BUTTON_RIGHT and
			event.pressed and
			_player_turn_active()
	):
		var command_menu = battle_ui.command_menu
		if command_menu.closeSpells():
			get_viewport().set_input_as_handled()
			return
		if player_turn.phase != PlayerTurnControllerScript.Phase.MENU:
			player_turn.cancel()
			get_viewport().set_input_as_handled()
			return
	if camera.handle_input(event, retro_renderer.screen_motion_scale()):
		get_viewport().set_input_as_handled()
		return
	if _player_turn_active():
		var command_menu = battle_ui.command_menu
		if player_turn.phase == PlayerTurnControllerScript.Phase.MENU:
			if event.is_action_pressed("ui_cancel") and command_menu.closeSpells():
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("ui_up"):
				command_menu.moveSelection(-1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("ui_down"):
				command_menu.moveSelection(1)
				get_viewport().set_input_as_handled()
				return
			# Paging (§7a). A no-op when the spell column is not
			# open or has only one page; always consumed either way, matching
			# every other branch here — before this, ui_left/right fell through
			# to the acceptsGridInput() block below, which is gated false during
			# MENU, so this changes nothing observable when there is no page.
			if event.is_action_pressed("ui_left"):
				command_menu.pageSpells(-1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("ui_right"):
				command_menu.pageSpells(1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("ui_accept"):
				command_menu.acceptSelection()
				get_viewport().set_input_as_handled()
				return
		if player_turn.phase == PlayerTurnControllerScript.Phase.CONFIRM_ACTION and event.is_action_pressed("ui_accept"):
			player_turn.confirmSelection()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			player_turn.cancel()
			get_viewport().set_input_as_handled()
			return
		# Grid keys only mean something while a tile or target is being aimed.
		# The menu owns keyboard navigation before grid input begins.
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


	if event is InputEventMouseMotion and _player_turn_active() and player_turn.acceptsGridInput():
		var hover_pos = _mouse_to_battle_coord(event.position)
		if player_turn.setCursor(hover_pos):
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


func _mouse_to_battle_coord(mousePos: Vector2) -> Vector2i:
	if visual_adapter == null or sim == null:
		return Vector2i(-1, -1)
	var hit = _world_pick(mousePos)
	var collider = hit.get("collider")
	if is_instance_valid(collider) and collider.has_meta("monster_id"):
		var monster_pos = sim.state.getMonsterPosition(int(collider.get_meta("monster_id")))
		if sim.state.withinBounds(monster_pos):
			return monster_pos
	if is_instance_valid(collider) and collider.has_meta("battle_coord"):
		var coord = collider.get_meta("battle_coord")
		if coord is Vector2i and sim.state.withinBounds(coord):
			return coord
	return Vector2i(-1, -1)

## Clicking the board is a free-look inspector, independent of whose turn it
## is: ally goes to the actor (left) window, enemy to the target (right) one,
## "ally" meaning same team as whoever's turn is active. Outside an active
## player turn there is no ally/enemy frame of reference, so it always goes to
## the actor window — the single-inspector behaviour this replaces.
##
## This is one of two writers of these windows; the other is the live
## attacker/target push from GodotVisualAdapter (`_setActorPanelMonster` /
## `_setTargetPanelMonster`) as combat actually plays out. Whichever fires most
## recently wins — the same last-write-wins relationship these two paths
## already had before the status readout was split into two windows.
func _handle_click_selection(pos: Vector2i) -> void:
	if sim == null or not sim.state.withinBounds(pos):
		return
	var monster = sim.state.getMonsterAt(pos)
	if monster == null:
		visual_adapter.highlight_monster(-1)
		_renderStatusWindow(actor_window, -1)
		_renderStatusWindow(target_window, -1)
		return
	visual_adapter.highlight_monster(monster.uniqueID)
	var active_team := -1
	if _player_turn_active():
		var active_monster = sim.state.getMonster(player_turn.activeMonsterID)
		if active_monster:
			active_team = active_monster.team
	if active_team != -1 and monster.team != active_team:
		_renderStatusWindow(target_window, monster.uniqueID)
	else:
		_renderStatusWindow(actor_window, monster.uniqueID)


func _setActorPanelMonster(monsterID: int) -> void:
	_renderStatusWindow(actor_window, monsterID)


func _setTargetPanelMonster(monsterID: int) -> void:
	_renderStatusWindow(target_window, monsterID)


## The single renderer for both docked status windows (item 2/3). `-1` leaves
## the window empty rather than showing placeholder text — an empty frame
## reads as "nothing selected" without inventing a second visual language for
## the same idea (item 4).
func _renderStatusWindow(window: NoggWindow, monsterID: int) -> void:
	window.clear_rows()
	if monsterID == -1 or sim == null:
		return
	var monster = sim.state.getMonster(monsterID)
	if monster == null:
		return
	window.add_row(monster.name)
	if monster.elements.size() > NoggThemeScript.STATUS_CELL_OFFSETS.size():
		push_warning("BattlePresentationController: status window shows only the first three elements for %s" % monster.name)

	var hp_cells: Array[Dictionary] = [
		{"label": "HP", "value": "%d / %d" % [monster.hitpoints, monster.max_hitpoints]}
	]
	_append_resonance_cell(hp_cells, monster, 0)
	var hp_handles := window.add_stat_row(hp_cells)
	# TEXT_ACCENT (gold) only below one third: healthy HP should blend in as an
	# unremarkable stat, not compete with it for the eye every single turn.
	_tint_value_label(
		hp_handles[0]["value"] as Label,
		NoggThemeScript.TEXT_ACCENT if monster.hitpoints * 3 < monster.max_hitpoints
		else NoggThemeScript.TEXT_PRIMARY
	)
	var attack_cells: Array[Dictionary] = [
		{"label": "ATK", "value": str(monster.atk)},
		{"label": "DEF", "value": str(monster.def)}
	]
	_append_resonance_cell(attack_cells, monster, 1)
	window.add_stat_row(attack_cells)
	var movement_cells: Array[Dictionary] = [
		{"label": "SPD", "value": str(monster.speed)},
		{"label": "MOV", "value": str(monster.move)}
	]
	_append_resonance_cell(movement_cells, monster, 2)
	window.add_stat_row(movement_cells)


func _append_resonance_cell(cells: Array[Dictionary], monster: Monster, element_index: int) -> void:
	if element_index >= monster.elements.size():
		return
	var element := str(monster.elements[element_index])
	cells.append({
		"column": 2,
		"label": ElementReferencesScript.code(element),
		"control": ResonanceBarScript.new(element, monster.get_resonance(element))
	})


func _tint_value_label(value_label: Label, colour: Color) -> void:
	value_label.add_theme_color_override("font_color", colour)


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

func _on_command_menu_entry(entryID: String) -> void:
	if not _player_turn_active():
		return
	if entryID == PlayerTurnControllerScript.ENTRY_MAGIC:
		battle_ui.command_menu.openSpells(player_turn.spellEntries())
		return
	player_turn.selectMenuEntry(entryID)


func _on_command_menu_spell(setIndex: int, spellIndex: int) -> void:
	if not _player_turn_active():
		return
	player_turn.selectSpell(setIndex, spellIndex)
	battle_ui.command_menu.closeSpells()
	player_turn.selectMenuEntry(PlayerTurnControllerScript.ENTRY_MAGIC)

func _on_animation_queue_drained() -> void:
	if lifecycle != Lifecycle.BATTLE:
		return
	_try_begin_pending_player_turn()
	if _pending_player_turn_id != -1 or _player_turn_active():
		return
	if battle_ui.play_button.button_pressed and turn_timer.is_stopped():
		turn_timer.start()

func _world_pick(mousePos: Vector2) -> Dictionary:
	if not camera or visual_adapter == null:
		return {}
	var world_mouse_pos = retro_renderer.screen_to_world(mousePos)
	if world_mouse_pos.x < 0.0:
		return {}
	var ray_origin = camera.project_ray_origin(world_mouse_pos)
	var ray_normal = camera.project_ray_normal(world_mouse_pos)
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_normal * 1000.0,
		GodotVisualAdapterScript.MONSTER_PICK_COLLISION_LAYER | GodotVisualAdapterScript.TILE_PICK_COLLISION_LAYER
	)
	return retro_renderer.world_root.get_world_3d().direct_space_state.intersect_ray(query)
