## Constructs the in-battle HUD and player command controls.
##
## Splits across two canvases (UI-2): `game_canvas` for player-facing HUD —
## command menu, actor/target panels, battle log — and `dev_canvas` for
## developer tooling — pause/speed, graphics menu, screenshot, save replay.
## Each canvas carries its own themed root Control from `NoggTheme`, so every
## Label/PanelContainer added beneath it inherits fonts and styling
## automatically. `BattlePresentationController` toggles the two canvases
## independently: SPACEBAR affects `dev_canvas` only.

class_name BattleUIBuilder

const BattleGraphicsMenuScript = preload("res://src/presentation/BattleGraphicsMenu.gd")
const PlayerCommandMenuScript = preload("res://src/presentation/PlayerCommandMenu.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")


static func build(root: Node, callbacks: Dictionary) -> Dictionary:
	var game_canvas = CanvasLayer.new()
	game_canvas.name = "GameCanvas"
	game_canvas.layer = NoggThemeScript.GAME_LAYER
	game_canvas.visible = false
	root.add_child(game_canvas)
	var game_root = _buildThemedRoot(game_canvas, NoggThemeScript.build_game_theme())

	var dev_canvas = CanvasLayer.new()
	dev_canvas.name = "DevCanvas"
	dev_canvas.layer = NoggThemeScript.DEV_LAYER
	dev_canvas.visible = false
	root.add_child(dev_canvas)
	var dev_root = _buildThemedRoot(dev_canvas, NoggThemeScript.build_dev_theme())

	var topHud = HBoxContainer.new()
	topHud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topHud.offset_left = 20
	topHud.offset_top = 20
	topHud.offset_right = -20
	topHud.add_theme_constant_override("separation", 10)
	dev_root.add_child(topHud)

	var topPanel = PanelContainer.new()
	_styleHudPanel(topPanel, 6)
	topHud.add_child(topPanel)
	var topRow = HBoxContainer.new()
	topPanel.add_child(topRow)

	var playButton = Button.new()
	playButton.toggle_mode = true
	playButton.text = "Pause"
	playButton.button_pressed = true
	playButton.tooltip_text = "Pause computer-controlled turns."
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

	var topSpacer = Control.new()
	topSpacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topHud.add_child(topSpacer)

	var debugPanel = PanelContainer.new()
	_styleHudPanel(debugPanel, 6)
	topHud.add_child(debugPanel)
	var debugRow = HBoxContainer.new()
	debugPanel.add_child(debugRow)
	var graphicsButton = Button.new()
	graphicsButton.toggle_mode = true
	graphicsButton.text = "Graphics"
	graphicsButton.tooltip_text = "Show or hide live rendering controls."
	debugRow.add_child(graphicsButton)
	var screenshotButton = _addActionButton(
		debugRow, "Screenshot", "Save debug/screenshot.png.", callbacks["screenshot_pressed"]
	)
	var dumpButton = _addActionButton(
		debugRow, "Save Replay", "Save setup, state, and command history.", callbacks["dump_state_pressed"]
	)

	var logButton = CheckButton.new()
	logButton.text = "Battle Log"
	logButton.tooltip_text = "Show or hide the battle event log."
	var logTogglePanel = PanelContainer.new()
	_styleHudPanel(logTogglePanel, 6)
	topHud.add_child(logTogglePanel)
	logTogglePanel.add_child(logButton)

	var turnTimer = Timer.new()
	turnTimer.wait_time = 1.0 / speedSlider.value
	turnTimer.timeout.connect(callbacks["turn_timeout"])
	root.add_child(turnTimer)

	var logPanel = PanelContainer.new()
	logPanel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	logPanel.offset_left = -380
	logPanel.offset_top = 70
	logPanel.offset_right = -20
	logPanel.offset_bottom = 470
	logPanel.visible = false
	var logStyle = StyleBoxFlat.new()
	logStyle.bg_color = Color(0, 0, 0, 0.82)
	logPanel.add_theme_stylebox_override("panel", logStyle)
	var logLabel = RichTextLabel.new()
	logLabel.scroll_following = true
	logPanel.add_child(logLabel)
	game_root.add_child(logPanel)

	var graphicsMenu = BattleGraphicsMenuScript.build(
		dev_root,
		graphicsButton,
		{
			"reset_pressed": callbacks["graphics_reset_pressed"],
			"preset_selected": callbacks["graphics_preset_selected"],
			"feature_selected": callbacks["graphics_feature_selected"],
			"look_parameter_changed": callbacks["look_parameter_changed"],
			"crt_parameter_changed": callbacks["crt_parameter_changed"]
		}
	)
	graphicsButton.toggled.connect(func(pressed):
		graphicsMenu["panel"].visible = pressed
		if pressed:
			logButton.button_pressed = false
	)
	logButton.toggled.connect(func(pressed):
		logPanel.visible = pressed
		if pressed:
			graphicsButton.button_pressed = false
	)

	var bottomHud = HBoxContainer.new()
	bottomHud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottomHud.offset_left = 20
	bottomHud.offset_top = -170
	bottomHud.offset_right = -20
	bottomHud.offset_bottom = -20
	bottomHud.add_theme_constant_override("separation", 12)
	game_root.add_child(bottomHud)

	var leftPanel = PanelContainer.new()
	leftPanel.custom_minimum_size = Vector2(220, 150)
	_styleHudPanel(leftPanel, 12)
	bottomHud.add_child(leftPanel)
	var leftLabel = Label.new()
	leftLabel.text = "Waiting for turn..."
	leftLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leftLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	leftPanel.add_child(leftLabel)

	# A plain full-rect Control, not a styled PanelContainer: the command menu
	# now draws its own NoggWindow frames and docks its windows itself per
	# docs/UI_DESIGN.md §8. A Container here would force-fit the menu into one
	# rect and a StyleBoxFlat would put a second, competing border around it.
	# Kept as a node (rather than folded away) purely so the controller's
	# existing `action_panel` visibility calls keep working untouched.
	var actionPanel = Control.new()
	actionPanel.name = "ActionPanel"
	actionPanel.set_anchors_preset(Control.PRESET_FULL_RECT)
	actionPanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actionPanel.visible = false
	game_root.add_child(actionPanel)
	var commandMenu: PlayerCommandMenu = PlayerCommandMenuScript.new()
	commandMenu.set_anchors_preset(Control.PRESET_FULL_RECT)
	actionPanel.add_child(commandMenu)

	var rightPanel = PanelContainer.new()
	rightPanel.custom_minimum_size = Vector2(220, 150)
	_styleHudPanel(rightPanel, 12)
	bottomHud.add_child(rightPanel)
	var rightLabel = Label.new()
	rightLabel.text = "No target"
	rightLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rightLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rightPanel.add_child(rightLabel)

	return {
		"game_canvas": game_canvas,
		"dev_canvas": dev_canvas,
		"turn_timer": turnTimer,
		"play_button": playButton,
		"graphics_button": graphicsButton,
		"graphics_panel": graphicsMenu["panel"],
		"graphics_look_option": graphicsMenu["look_option"],
		"graphics_preset_description": graphicsMenu["preset_description"],
		"graphics_geometry_option": graphicsMenu["geometry_option"],
		"graphics_upscale_option": graphicsMenu["upscale_option"],
		"graphics_look_sliders": graphicsMenu["look_sliders"],
		"graphics_crt_hint": graphicsMenu["crt_hint"],
		"graphics_crt_sliders": graphicsMenu["crt_sliders"],
		"left_ui_label": leftLabel,
		"right_ui_label": rightLabel,
		"log_label": logLabel,
		"log_panel": logPanel,
		"action_panel": actionPanel,
		"command_menu": commandMenu,
		"screenshot_button": screenshotButton,
		"dump_button": dumpButton
	}


## A themed root Control under a CanvasLayer. `Theme` lives on `Control`, not
## `CanvasLayer`, so every game/dev panel needs one common ancestor carrying it
## for fonts and styleboxes to cascade. `mouse_filter = IGNORE` keeps the root
## itself out of the way of clicks; children still receive input normally.
static func _buildThemedRoot(canvas: CanvasLayer, theme: Theme) -> Control:
	var root = Control.new()
	root.name = "ThemedRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	canvas.add_child(root)
	return root


static func _addActionButton(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func _styleHudPanel(panel: PanelContainer, padding: int) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.11, 0.86)
	style.border_color = Color(0.2, 0.58, 0.9, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	panel.add_theme_stylebox_override("panel", style)
