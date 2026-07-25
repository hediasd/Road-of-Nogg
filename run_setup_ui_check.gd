extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")
const CursorScript = preload("res://src/presentation/BattleCursorController.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://scenes/Battle25D.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_PS1_CLASSIC, false)
	scene._sync_rendering_options()

	if scene.retro_renderer.world_viewport.size != Vector2i(320, 240):
		_fail("PS1 mode did not use the 320x240 world render target")
		return
	if scene.setup_ui["canvas"].get_viewport() == scene.retro_renderer.world_viewport:
		_fail("setup UI was rendered inside the low-resolution world viewport")
		return
	var mappedCenter = scene.retro_renderer.screen_to_world(
		scene.retro_renderer.world_to_screen(Vector2(160, 120))
	)
	if not mappedCenter.is_equal_approx(Vector2(160, 120)):
		_fail("letterboxed screen/world coordinate conversion is inconsistent")
		return

	if scene.sim != null:
		_fail("simulation spawned before setup confirmation")
		return
	if not scene.setup_ui["canvas"].visible or scene.battle_ui["canvas"].visible:
		_fail("setup and battle UI visibility is incorrect before confirmation")
		return
	if scene.setup_ui["mode_option"].get_item_metadata(0) != BattleSetupConfigScript.MODE_CPU_VS_CPU:
		_fail("CPU vs CPU is not the default mode")
		return
	if scene.setup_ui["map_option"].get_item_metadata(0) != "Meadow":
		_fail("Meadow is not the default map")
		return
	if scene._read_roster(1) != BattleSetupPresetsScript.DEFAULT_TEAM_1:
		_fail("Team 1 defaults are incorrect")
		return
	if scene._read_roster(2) != BattleSetupPresetsScript.DEFAULT_TEAM_2:
		_fail("Team 2 defaults are incorrect")
		return

	var hasSky = false
	for child in scene.retro_renderer.world_viewport.get_children():
		if child is CanvasLayer and child.layer == -1:
			hasSky = true
	if not hasSky:
		_fail("sky background was not created before setup")
		return

	scene._select_option_by_metadata(
		scene.setup_ui["mode_option"],
		BattleSetupConfigScript.MODE_PLAYER_VS_CPU
	)
	scene._on_setup_confirmed()
	await process_frame
	await physics_frame

	if scene.sim == null or scene.sim.state.getAliveMonsterIDs().size() != 8:
		_fail("confirm did not load the configured battle")
		return
	if scene.setup_ui["canvas"].visible or not scene.battle_ui["canvas"].visible:
		_fail("UI did not transition from setup to battle")
		return
	if scene.visual_adapter._monster_visuals.size() != 8:
		_fail("monster visuals were not loaded after confirmation")
		return
	if scene.camera.get_viewport() != scene.retro_renderer.world_viewport:
		_fail("3D camera is not isolated in the world viewport")
		return
	var firstTile = scene.visual_adapter.grid_node.get_child(0) as MeshInstance3D
	var retroMaterial = firstTile.material_override as ShaderMaterial
	if retroMaterial == null:
		_fail("world geometry did not receive the retro-capable material")
		return
	if not retroMaterial.get_shader_parameter("vertex_snap_enabled"):
		_fail("vertex jitter was not enabled independently")
		return
	if not retroMaterial.get_shader_parameter("affine_mapping_enabled"):
		_fail("affine texture mapping was not enabled independently")
		return

	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_CLEAN, false)
	await process_frame
	var nativeSize = Vector2i(scene.get_viewport().get_visible_rect().size)
	if scene.retro_renderer.world_viewport.size != nativeSize:
		_fail("clean mode did not restore native world resolution")
		return
	if retroMaterial.get_shader_parameter("vertex_snap_enabled"):
		_fail("clean mode did not disable vertex jitter")
		return
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_CRT, false)
	await process_frame
	if scene.retro_renderer.world_viewport.size != Vector2i(640, 480):
		_fail("CRT preset did not use its lighter 640x480 render target")
		return
	if not scene.retro_renderer.crt_overlay.visible:
		_fail("CRT preset did not enable the CRT display pass")
		return
	scene.retro_renderer.set_preset(scene.retro_renderer.PRESET_PS1_CLASSIC, false)
	await process_frame
	if scene.battle_ui["canvas"].find_children("*", "OptionButton", true, false).size() != 1:
		_fail("battle HUD contains rendering dropdowns beyond the spell selector")
		return
	if scene.battle_ui["play_button"] is CheckButton:
		_fail("battle playback still uses the old auto-play check button")
		return
	if scene.battle_ui["play_button"].text != "Pause" or not scene.battle_ui["play_button"].button_pressed:
		_fail("battle did not start playing with a Pause button")
		return
	if scene.turn_timer.is_stopped():
		_fail("CPU turns did not begin after battle setup")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(false)
	scene._on_play_toggled(false)
	if scene.battle_ui["play_button"].text != "Play" or not scene.turn_timer.is_stopped():
		_fail("Pause did not stop CPU turns and change to Play")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(true)
	scene._on_play_toggled(true)
	if scene.battle_ui["play_button"].text != "Pause" or scene.turn_timer.is_stopped():
		_fail("Play did not resume CPU turns and change to Pause")
		return
	scene.battle_ui["play_button"].set_pressed_no_signal(false)
	scene._on_play_toggled(false)

	var pickID = scene.sim.state.getAliveMonsterIDs()[0]
	var pickVisual: Node3D = scene.visual_adapter._monster_visuals[pickID]
	var selectionBody = pickVisual.get_node_or_null("SelectionBody")
	if selectionBody == null:
		_fail("monster visual has no whole-model selection body")
		return
	var collision = selectionBody.get_node_or_null("WholeModelBounds")
	if collision == null or not collision.shape is BoxShape3D or collision.shape.size.y < 1.0:
		_fail("monster selection bounds do not cover the complete model")
		return
	var upperBodyPoint = pickVisual.to_global(
		collision.position + Vector3(0, collision.shape.size.y * 0.3, 0)
	)
	var upperBodyWorldPoint = scene.camera.unproject_position(upperBodyPoint)
	var upperBodyScreenPoint = scene.retro_renderer.world_to_screen(upperBodyWorldPoint)
	if scene._mouse_to_monster_id(upperBodyScreenPoint) != pickID:
		_fail("clicking the upper model did not select its entity")
		return

	for _step in range(12):
		if scene.active_player_id != -1:
			break
		scene._advance_battle()
	if scene.active_player_id == -1:
		_fail("Player vs CPU did not reach a player-controlled turn")
		return
	if scene.player_state != scene.PlayerState.MOVE_PREVIEW:
		_fail("player turn did not enter movement preview")
		return
	if scene.visual_adapter._cursor_controller.owner != CursorScript.Owner.PLAYER:
		_fail("player did not own the cursor")
		return
	if not scene.battle_ui["action_panel"].visible:
		_fail("player action controls are hidden")
		return

	scene._on_player_end_turn()
	if scene.active_player_id != -1:
		_fail("end turn did not release player control")
		return

	var previousAdapter = scene.visual_adapter
	scene._on_new_battle_pressed()
	await process_frame
	if scene.sim != null or not scene.setup_ui["canvas"].visible:
		_fail("new battle did not return to setup")
		return
	if previousAdapter._connectedEvents != null:
		_fail("return to setup left the visual adapter connected")
		return

	scene.queue_free()
	await process_frame
	scene = null
	await process_frame
	print("PLAYABLE_BATTLE_UI_OK")
	quit(0)


func _fail(reason: String) -> void:
	push_error("PLAYABLE_BATTLE_UI_FAILED: %s" % reason)
	quit(1)
