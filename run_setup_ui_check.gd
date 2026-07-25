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
	for child in scene.get_children():
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
	scene.turn_timer.stop()
	await process_frame

	if scene.sim == null or scene.sim.state.getAliveMonsterIDs().size() != 8:
		_fail("confirm did not load the configured battle")
		return
	if scene.setup_ui["canvas"].visible or not scene.battle_ui["canvas"].visible:
		_fail("UI did not transition from setup to battle")
		return
	if scene.visual_adapter._monster_visuals.size() != 8:
		_fail("monster visuals were not loaded after confirmation")
		return
	if scene.battle_ui["canvas"].find_children("*", "OptionButton", true, false).size() != 1:
		_fail("battle HUD contains rendering dropdowns beyond the spell selector")
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
