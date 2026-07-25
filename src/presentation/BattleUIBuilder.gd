## BattleUIBuilder — Constructs the runtime battle controls and information panels.

class_name BattleUIBuilder


static func build(root: Node, callbacks: Dictionary) -> Dictionary:
	var log_panel: PanelContainer
	var canvas = CanvasLayer.new()
	root.add_child(canvas)

	# Top Left Controls
	var top_panel = PanelContainer.new()
	top_panel.position = Vector2(20, 20)
	canvas.add_child(top_panel)

	var hbox = HBoxContainer.new()
	top_panel.add_child(hbox)

	var play_btn = CheckButton.new()
	play_btn.text = "Auto-Play"
	play_btn.toggled.connect(callbacks["play_toggled"])
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
	speed_slider.value_changed.connect(callbacks["speed_changed"])
	hbox.add_child(speed_slider)

	var turn_timer = Timer.new()
	turn_timer.wait_time = 1.0 / speed_slider.value
	turn_timer.timeout.connect(callbacks["turn_timeout"])
	root.add_child(turn_timer)

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
	clayness_btn.item_selected.connect(callbacks["clayness_selected"])
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
	mat_btn.item_selected.connect(callbacks["material_selected"])
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

	var log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_panel.add_child(log_label)
	canvas.add_child(log_panel)

	# Bottom Left Info
	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left_panel.position = Vector2(20, -150)
	left_panel.size = Vector2(250, 130)
	var left_ui_label = Label.new()
	left_ui_label.text = "Waiting for turn..."
	left_panel.add_child(left_ui_label)
	canvas.add_child(left_panel)

	# Bottom Right Info
	var right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_panel.position = Vector2(-270, -150)
	right_panel.size = Vector2(250, 130)
	var right_ui_label = Label.new()
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
	screenshot_btn.pressed.connect(callbacks["screenshot_pressed"])
	debug_hbox.add_child(screenshot_btn)

	var dump_btn = Button.new()
	dump_btn.text = "💾 Dump AI State"
	dump_btn.pressed.connect(callbacks["dump_state_pressed"])
	debug_hbox.add_child(dump_btn)
	return {
		"turn_timer": turn_timer,
		"left_ui_label": left_ui_label,
		"right_ui_label": right_ui_label,
		"log_label": log_label,
		"log_panel": log_panel
	}
