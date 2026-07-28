## Ported from run_setup_ui_check.gd. Drives the full setup-to-battle UI flow
## on the real default scene: rendering presets/letterboxing, setup defaults,
## confirmation, dual-element visuals, camera drag ownership, terrain checker,
## graphics menu live-tuning, battle playback controls, whole-model selection
## and picking, the player-turn state machine, and return-to-setup cleanup.
extends "res://tests/TestCase.gd"

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")
const CursorScript = preload("res://src/presentation/BattleCursorController.gd")


func describe() -> String:
	return "setup overlay, confirmation, and battle UI flow behave correctly on the default scene"


func run() -> void:
	var scene = load("res://scenes/Battle25D.tscn").instantiate()
	root.add_child(scene)
	await nextFrame()
	await nextFrame()
	scene.retro_renderer.set_look_parameter(scene.retro_renderer.LOOK_RENDER_SCALE, 1.0, false)
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_DITHERED_HORIZON, false)
	scene._sync_rendering_options()

	if scene.retro_renderer.world_viewport.size != Vector2i(320, 240):
		fail("Dithered Horizon did not use the 320x240 world render target")
		return
	if scene.setup_ui["canvas"].get_viewport() == scene.retro_renderer.world_viewport:
		fail("setup UI was rendered inside the low-resolution world viewport")
		return
	var mappedCenter = scene.retro_renderer.screen_to_world(
		scene.retro_renderer.world_to_screen(Vector2(160, 120))
	)
	if not mappedCenter.is_equal_approx(Vector2(160, 120)):
		fail("letterboxed screen/world coordinate conversion is inconsistent")
		return

	if scene.sim != null:
		fail("simulation spawned before setup confirmation")
		return
	if not scene.setup_ui["canvas"].visible or scene.battle_ui["canvas"].visible:
		fail("setup and battle UI visibility is incorrect before confirmation")
		return
	if scene.setup_ui["mode_option"].get_item_metadata(0) != BattleSetupConfigScript.MODE_CPU_VS_CPU:
		fail("CPU vs CPU is not the default mode")
		return
	if scene.setup_ui["render_mode_option"].get_item_metadata(0) != scene.retro_renderer.PRESET_NONE:
		fail("None is not the first rendering preset")
		return
	if scene.setup_ui["render_mode_option"].item_count != 10:
		fail("rendering catalog does not expose all presets plus Custom")
		return
	if scene.setup_ui["map_option"].get_item_metadata(0) != "Meadow":
		fail("Meadow is not the default map")
		return
	if scene._read_roster(1) != BattleSetupPresetsScript.DEFAULT_TEAM_1:
		fail("Team 1 defaults are incorrect")
		return
	if scene._read_roster(2) != BattleSetupPresetsScript.DEFAULT_TEAM_2:
		fail("Team 2 defaults are incorrect")
		return

	var hasSky = false
	for child in scene.retro_renderer.world_viewport.get_children():
		if child is CanvasLayer and child.layer == -1:
			hasSky = true
	if not hasSky:
		fail("sky background was not created before setup")
		return

	scene._select_option_by_metadata(
		scene.setup_ui["mode_option"],
		BattleSetupConfigScript.MODE_PLAYER_VS_CPU
	)
	scene._on_setup_confirmed()
	await nextFrame()
	await physics_frame

	if scene.sim == null or scene.sim.state.getAliveMonsterIDs().size() != 8:
		fail("confirm did not load the configured battle")
		return
	if scene.setup_ui["canvas"].visible or not scene.battle_ui["canvas"].visible:
		fail("UI did not transition from setup to battle")
		return
	var spacePress = InputEventKey.new()
	spacePress.keycode = KEY_SPACE
	spacePress.pressed = true
	scene._input(spacePress)
	if scene.battle_ui["canvas"].visible:
		fail("Space did not hide the battle UI")
		return
	scene._input(spacePress)
	if not scene.battle_ui["canvas"].visible:
		fail("Space did not restore the battle UI")
		return
	if scene.visual_adapter._monster_visuals.size() != 8:
		fail("monster visuals were not loaded after confirmation")
		return
	var dualElementID = -1
	for monsterID in scene.sim.state.getAliveMonsterIDs():
		if scene.sim.state.getMonster(monsterID).elements.size() >= 2:
			dualElementID = monsterID
			break
	if dualElementID == -1:
		fail("default battle has no dual-element visual fixture")
		return
	var dualVisual: Node3D = scene.visual_adapter._monster_visuals[dualElementID]
	var dualBody = dualVisual.get_child(1) as Node3D
	var splitMeshes = dualBody.find_children("*", "MeshInstance3D", true, false)
	var minimumSplitY = INF
	var maximumSplitY = -INF
	for splitMesh in splitMeshes:
		var splitOrigin = splitMesh.get_instance_shader_parameter("split_model_origin")
		if splitOrigin is Vector3:
			minimumSplitY = minf(minimumSplitY, splitOrigin.y)
			maximumSplitY = maxf(maximumSplitY, splitOrigin.y)
	if maximumSplitY - minimumSplitY < 0.5:
		fail("dual-element components do not share whole-model coordinates")
		return
	var firstSplitMesh = splitMeshes[0] as MeshInstance3D
	var splitMaterial = firstSplitMesh.material_override as ShaderMaterial
	var splitBoundsSize = splitMaterial.get_shader_parameter("split_bounds_size")
	if not splitBoundsSize is Vector2 or splitBoundsSize.y < 1.0:
		fail("dual-element shader does not use the complete model bounds")
		return
	if scene.camera.get_viewport() != scene.retro_renderer.world_viewport:
		fail("3D camera is not isolated in the world viewport")
		return
	var orbitPress = InputEventMouseButton.new()
	orbitPress.button_index = MOUSE_BUTTON_MIDDLE
	orbitPress.pressed = true
	if not scene.camera.handle_input(orbitPress) or not scene.camera.isDragging():
		fail("middle mouse did not acquire camera drag ownership")
		return
	var yawBeforeDrag = scene.camera.current_yaw
	var orbitMotion = InputEventMouseMotion.new()
	orbitMotion.relative = Vector2(24.0, -8.0)
	if not scene.camera.handle_input(orbitMotion):
		fail("owned camera drag did not consume motion")
		return
	if is_equal_approx(scene.camera.current_yaw, yawBeforeDrag):
		fail("camera drag still depends on global mouse-button polling")
		return
	var orbitRelease = InputEventMouseButton.new()
	orbitRelease.button_index = MOUSE_BUTTON_MIDDLE
	orbitRelease.pressed = false
	scene.camera.handle_input(orbitRelease)
	var yawAfterRelease = scene.camera.current_yaw
	if scene.camera.isDragging() or scene.camera.handle_input(orbitMotion):
		fail("middle mouse release did not relinquish camera drag ownership")
		return
	if not is_equal_approx(scene.camera.current_yaw, yawAfterRelease):
		fail("camera continued moving after drag release")
		return
	var firstTile = scene.visual_adapter.getTileSurface(Vector2i.ZERO)
	var retroMaterial = firstTile.material_override as ShaderMaterial
	var grassColors: Array[Color] = []
	for y in range(scene.sim.state.boardSize.y):
		for x in range(scene.sim.state.boardSize.x):
			var coord = Vector2i(x, y)
			if scene.sim.state.terrainBoard.at(coord) != 0:
				continue
			var grassTile = scene.visual_adapter.getTileSurface(coord)
			var grassMaterial = grassTile.material_override as ShaderMaterial
			var grassColor: Color = grassMaterial.get_shader_parameter("color_a")
			var alreadyFound = false
			for existingColor in grassColors:
				if existingColor.is_equal_approx(grassColor):
					alreadyFound = true
					break
			if not alreadyFound:
				grassColors.append(grassColor)
	if grassColors.size() != 2:
		fail("grass tiles do not use exactly two checker tones")
		return
	var sampledColor = scene.visual_adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(2, 3), 0)
	if not sampledColor.is_equal_approx(
		scene.visual_adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(2, 3), 0)
	):
		fail("tile color variance is not deterministic")
		return
	if absf(sampledColor.v - Color(0.2, 0.8, 0.2).v) > 0.12:
		fail("tile checker contrast is too strong")
		return
	if retroMaterial == null:
		fail("world geometry did not receive the retro-capable material")
		return
	if not retroMaterial.get_shader_parameter("vertex_snap_enabled"):
		fail("vertex jitter was not enabled independently")
		return
	if not retroMaterial.get_shader_parameter("affine_mapping_enabled"):
		fail("affine texture mapping was not enabled independently")
		return

	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_NONE, false)
	await nextFrame()
	var nativeSize = Vector2i(scene.get_viewport().get_visible_rect().size)
	if scene.retro_renderer.world_viewport.size != nativeSize:
		fail("None did not restore native world resolution")
		return
	if retroMaterial.get_shader_parameter("vertex_snap_enabled"):
		fail("None did not disable vertex jitter")
		return
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_SATURATED_CRT, false)
	await nextFrame()
	if scene.retro_renderer.world_viewport.size != Vector2i(640, 480):
		fail("Saturated CRT did not use its 640x480 render target")
		return
	if not scene.retro_renderer.crt_overlay.visible:
		fail("Saturated CRT did not enable the CRT display pass")
		return
	scene.retro_renderer.set_look_parameter(scene.retro_renderer.LOOK_RENDER_SCALE, 1.0, false)
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_DITHERED_HORIZON, false)
	await nextFrame()
	if scene.battle_ui["canvas"].find_children("*", "OptionButton", true, false).size() != 4:
		fail("battle HUD does not contain the spell selector and three graphics dropdowns")
		return
	var timerWasStopped = scene.turn_timer.is_stopped()
	scene.battle_ui["graphics_button"].button_pressed = true
	await nextFrame()
	if not scene.battle_ui["graphics_panel"].visible:
		fail("Graphics button did not show the live translucent menu")
		return
	if scene.battle_ui["graphics_look_sliders"].size() != 7:
		fail("Any Look tab does not expose all general tuning controls")
		return
	if scene.battle_ui["graphics_crt_sliders"].size() != 9:
		fail("CRT tab does not expose all CRT tuning controls")
		return
	if scene.turn_timer.is_stopped() != timerWasStopped:
		fail("opening Graphics changed battle playback state")
		return
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_SATURATED_CRT, false)
	scene.retro_renderer.set_look_parameter(scene.retro_renderer.LOOK_BRIGHTNESS, 1.2, false)
	if scene.retro_renderer.render_preset != scene.retro_renderer.PRESET_CUSTOM:
		fail("manual graphics tuning did not mark the preset as Custom")
		return
	scene.retro_renderer.set_crt_parameter(scene.retro_renderer.CRT_SCANLINE, 0.4, false)
	scene.retro_renderer.set_crt_parameter(scene.retro_renderer.CRT_NOISE, 0.12, false)
	scene._sync_rendering_options()
	var selectedLook = scene.battle_ui["graphics_look_option"].get_item_metadata(
		scene.battle_ui["graphics_look_option"].selected
	)
	if selectedLook != scene.retro_renderer.PRESET_CUSTOM:
		fail("manual graphics tuning did not update the dropdown to Custom")
		return
	var scanlineData: Dictionary = scene.battle_ui["graphics_crt_sliders"]["scanline"]
	if not scanlineData["slider"].editable:
		fail("CRT sliders did not enable for the CRT preset")
		return
	if not is_equal_approx(
		scene.retro_renderer.crt_material.get_shader_parameter("scanline_strength"),
		0.4
	):
		fail("CRT slider value did not reach the live display material")
		return
	if not is_equal_approx(
		scene.retro_renderer.crt_material.get_shader_parameter("brightness"),
		1.2
	):
		fail("Any Look tuning did not reach the live display material")
		return
	if not is_equal_approx(
		scene.retro_renderer.crt_material.get_shader_parameter("noise_strength"),
		0.12
	):
		fail("expanded CRT tuning did not reach the live display material")
		return
	scene.retro_renderer.reset_defaults(false)
	scene._sync_rendering_options()
	if scene.retro_renderer.render_preset != scene.retro_renderer.PRESET_NONE:
		fail("graphics reset did not restore the default None look")
		return
	if not is_equal_approx(scene.retro_renderer.brightness, 1.0):
		fail("graphics reset did not restore general tuning defaults")
		return
	if not is_equal_approx(scene.retro_renderer.crt_noise_strength, 0.03):
		fail("graphics reset did not restore CRT tuning defaults")
		return
	scene.battle_ui["graphics_button"].button_pressed = false
	await nextFrame()
	if scene.battle_ui["graphics_panel"].visible:
		fail("Graphics button did not hide the live menu")
		return
	scene.retro_renderer.set_look_parameter(scene.retro_renderer.LOOK_RENDER_SCALE, 1.0, false)
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_DITHERED_HORIZON, false)
	scene._sync_rendering_options()
	if scene.battle_ui["play_button"] is CheckButton:
		fail("battle playback still uses the old auto-play check button")
		return
	if scene.battle_ui["play_button"].text != "Pause" or not scene.battle_ui["play_button"].button_pressed:
		fail("battle did not start playing with a Pause button")
		return
	if scene.turn_timer.is_stopped():
		fail("CPU turns did not begin after battle setup")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(false)
	scene._on_play_toggled(false)
	if scene.battle_ui["play_button"].text != "Play" or not scene.turn_timer.is_stopped():
		fail("Pause did not stop CPU turns and change to Play")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(true)
	scene._on_play_toggled(true)
	if scene.battle_ui["play_button"].text != "Pause" or scene.turn_timer.is_stopped():
		fail("Play did not resume CPU turns and change to Pause")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(false)
	scene._on_play_toggled(false)

	var pickID = scene.sim.state.getAliveMonsterIDs()[0]
	var pickVisual: Node3D = scene.visual_adapter._monster_visuals[pickID]
	var selectionBody = pickVisual.get_node_or_null("SelectionBody")
	if selectionBody == null:
		fail("monster visual has no whole-model selection body")
		return
	var collision = selectionBody.get_node_or_null("WholeModelBounds")
	if collision == null or not collision.shape is BoxShape3D or collision.shape.size.y < 1.0:
		fail("monster selection bounds do not cover the complete model")
		return
	var upperBodyPoint = pickVisual.to_global(
		collision.position + Vector3(0, collision.shape.size.y * 0.3, 0)
	)
	var upperBodyWorldPoint = scene.camera.unproject_position(upperBodyPoint)
	var upperBodyScreenPoint = scene.retro_renderer.world_to_screen(upperBodyWorldPoint)
	if scene._mouse_to_monster_id(upperBodyScreenPoint) != pickID:
		fail("clicking the upper model did not select its entity")
		return

	for _step in range(12):
		if scene.active_player_id != -1:
			break
		scene._advance_battle()
	if scene.active_player_id == -1:
		fail("Player vs CPU did not reach a player-controlled turn")
		return
	if scene.player_state != scene.PlayerState.MOVE_PREVIEW:
		fail("player turn did not enter movement preview")
		return
	if scene.visual_adapter._cursor_controller.owner != CursorScript.Owner.PLAYER:
		fail("player did not own the cursor")
		return
	if not scene.battle_ui["action_panel"].visible:
		fail("player action controls are hidden")
		return

	scene._on_player_end_turn()
	if scene.active_player_id != -1:
		fail("end turn did not release player control")
		return

	var previousAdapter = scene.visual_adapter
	scene._on_new_battle_pressed()
	await nextFrame()
	if scene.sim != null or not scene.setup_ui["canvas"].visible:
		fail("new battle did not return to setup")
		return
	if previousAdapter._connectedEvents != null:
		fail("return to setup left the visual adapter connected")
		return

	scene.queue_free()
	await nextFrame()
