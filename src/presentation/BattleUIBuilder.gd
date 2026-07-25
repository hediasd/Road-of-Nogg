## Constructs the in-battle HUD and player command controls.

class_name BattleUIBuilder


static func build(root: Node, callbacks: Dictionary) -> Dictionary:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	canvas.visible = false
	root.add_child(canvas)

	var topPanel = PanelContainer.new()
	topPanel.position = Vector2(20, 20)
	canvas.add_child(topPanel)
	var topRow = HBoxContainer.new()
	topPanel.add_child(topRow)

	var playButton = CheckButton.new()
	playButton.text = "Auto-Play CPU"
	playButton.button_pressed = true
	playButton.tooltip_text = "Pause or resume computer-controlled turns."
	playButton.toggled.connect(callbacks["play_toggled"])
	topRow.add_child(playButton)

	var speedLabel = Label.new()
	speedLabel.text = "  Speed:"
	topRow.add_child(speedLabel)
	var speedSlider = HSlider.new()
	speedSlider.custom_minimum_size = Vector2(100, 20)
	speedSlider.min_value = 0.5
	speedSlider.max_value = 10.0
	speedSlider.step = 0.5
	speedSlider.value = 1.25
	speedSlider.tooltip_text = "CPU turn pacing."
	speedSlider.value_changed.connect(callbacks["speed_changed"])
	topRow.add_child(speedSlider)

	var newBattleButton = Button.new()
	newBattleButton.text = "New Battle"
	newBattleButton.tooltip_text = "Return to setup and discard the current battle."
	newBattleButton.pressed.connect(callbacks["new_battle_pressed"])
	topRow.add_child(newBattleButton)

	var turnTimer = Timer.new()
	turnTimer.wait_time = 1.0 / speedSlider.value
	turnTimer.timeout.connect(callbacks["turn_timeout"])
	root.add_child(turnTimer)

	var logPanel = PanelContainer.new()
	logPanel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	logPanel.position = Vector2(-320, 60)
	logPanel.size = Vector2(300, 400)
	logPanel.visible = false
	var logStyle = StyleBoxFlat.new()
	logStyle.bg_color = Color(0, 0, 0, 0.78)
	logPanel.add_theme_stylebox_override("panel", logStyle)
	var logLabel = RichTextLabel.new()
	logLabel.scroll_following = true
	logPanel.add_child(logLabel)
	canvas.add_child(logPanel)

	var logButton = CheckButton.new()
	logButton.text = "Show Battle Log"
	logButton.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	logButton.position = Vector2(-210, 20)
	logButton.toggled.connect(func(pressed): logPanel.visible = pressed)
	canvas.add_child(logButton)

	var claynessButton = OptionButton.new()
	claynessButton.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	claynessButton.position = Vector2(-210, 60)
	claynessButton.add_item("Clayness: Default")
	for index in range(1, 11):
		claynessButton.add_item("Clayness Profile %d" % index)
	claynessButton.item_selected.connect(callbacks["clayness_selected"])
	canvas.add_child(claynessButton)

	var materialButton = OptionButton.new()
	materialButton.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	materialButton.position = Vector2(-210, 100)
	for item in [
		"0: Default / Reset", "1: Hologram", "2: Ghostly Apparition",
		"3: Toon Outline", "4: Molten Core", "5: Dissolve",
		"6: Matrix Rain", "7: Prismatic Glass", "8: Shadow Demon",
		"9: Petrified", "10: Golden Idol"
	]:
		materialButton.add_item(item)
	materialButton.item_selected.connect(callbacks["material_selected"])
	canvas.add_child(materialButton)

	var leftPanel = PanelContainer.new()
	leftPanel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	leftPanel.position = Vector2(20, -170)
	leftPanel.size = Vector2(280, 150)
	var leftLabel = Label.new()
	leftLabel.text = "Waiting for turn..."
	leftLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leftPanel.add_child(leftLabel)
	canvas.add_child(leftPanel)

	var rightPanel = PanelContainer.new()
	rightPanel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	rightPanel.position = Vector2(-300, -170)
	rightPanel.size = Vector2(280, 150)
	var rightLabel = Label.new()
	rightLabel.text = "No target"
	rightLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rightPanel.add_child(rightLabel)
	canvas.add_child(rightPanel)

	var actionPanel = PanelContainer.new()
	actionPanel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	actionPanel.position = Vector2(-335, -125)
	actionPanel.custom_minimum_size = Vector2(670, 105)
	actionPanel.visible = false
	canvas.add_child(actionPanel)
	var actionColumn = VBoxContainer.new()
	actionPanel.add_child(actionColumn)
	var actionStatus = Label.new()
	actionStatus.text = "Select a destination."
	actionStatus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actionColumn.add_child(actionStatus)
	var actionRow = HBoxContainer.new()
	actionColumn.add_child(actionRow)

	var moveButton = _addActionButton(actionRow, "Move", "Choose another reachable destination.", callbacks["player_move"])
	var attackButton = _addActionButton(actionRow, "Attack", "Choose an adjacent enemy.", callbacks["player_attack"])
	var spellOption = OptionButton.new()
	spellOption.custom_minimum_size.x = 170
	spellOption.tooltip_text = "Available spells, range, and remaining cooldown."
	spellOption.item_selected.connect(callbacks["spell_selected"])
	actionRow.add_child(spellOption)
	var castButton = _addActionButton(actionRow, "Cast", "Target the selected spell.", callbacks["player_spell"])
	var waitButton = _addActionButton(actionRow, "Wait", "Prepare a wait command for confirmation.", callbacks["player_wait"])
	var confirmButton = _addActionButton(actionRow, "Confirm", "Execute the previewed command.", callbacks["player_confirm"])
	var cancelButton = _addActionButton(actionRow, "Cancel", "Return to the previous selection state.", callbacks["player_cancel"])
	var endTurnButton = _addActionButton(actionRow, "End Turn", "Immediately finish with the selected movement and no action.", callbacks["player_end_turn"])

	var debugPanel = PanelContainer.new()
	debugPanel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	debugPanel.position = Vector2(-120, 20)
	canvas.add_child(debugPanel)
	var debugRow = HBoxContainer.new()
	debugPanel.add_child(debugRow)
	var screenshotButton = _addActionButton(debugRow, "Screenshot", "Save debug/screenshot.png.", callbacks["screenshot_pressed"])
	var dumpButton = _addActionButton(debugRow, "Dump Replay", "Save setup, state, and command history.", callbacks["dump_state_pressed"])

	return {
		"canvas": canvas,
		"turn_timer": turnTimer,
		"play_button": playButton,
		"left_ui_label": leftLabel,
		"right_ui_label": rightLabel,
		"log_label": logLabel,
		"log_panel": logPanel,
		"action_panel": actionPanel,
		"action_status": actionStatus,
		"move_button": moveButton,
		"attack_button": attackButton,
		"spell_option": spellOption,
		"cast_button": castButton,
		"wait_button": waitButton,
		"confirm_button": confirmButton,
		"cancel_button": cancelButton,
		"end_turn_button": endTurnButton,
		"screenshot_button": screenshotButton,
		"dump_button": dumpButton
	}


static func _addActionButton(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
