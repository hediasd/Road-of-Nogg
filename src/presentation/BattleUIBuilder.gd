## Constructs the in-battle HUD and player command controls.
##
## Splits across two canvases: `game_canvas` for player-facing HUD —
## command menu, actor/target panels, battle log — and `dev_canvas` for
## developer tooling — pause/speed, graphics menu, screenshot, save replay.
## Each canvas carries its own themed root Control from `NoggTheme`, so every
## Label/PanelContainer added beneath it inherits fonts and styling
## automatically. `BattlePresentationController` toggles the two canvases
## independently: F1 affects `dev_canvas` only.

class_name BattleUIBuilder

const BattleGraphicsMenuScript = preload("res://src/presentation/BattleGraphicsMenu.gd")
const BattleUIRefsScript = preload("res://src/presentation/BattleUIRefs.gd")
const PlayerCommandMenuScript = preload("res://src/presentation/PlayerCommandMenu.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const TurnOrderRailScript = preload("res://src/presentation/TurnOrderRail.gd")

## docs/UI_DESIGN.md §8: 6 rows (heading + HP + ATK/DEF + SPD/MOV, with two
## spare rows). Width is `NoggThemeScript.STATUS_WINDOW_WIDTH`, not redeclared
## here — a local const of a literal number could never track
## `NoggTheme.ui_scale` (see NoggTheme.gd's "Window widths" block).
const STATUS_WINDOW_CAPACITY := 6
## Upper-left, below the prompt and above the centred command window.
## Three rows show the active unit plus the next two queued units. Width is
## `NoggThemeScript.TURN_ORDER_WIDTH` and its top offset is
## `NoggThemeScript.TURN_ORDER_TOP`, for the same reason.
const TURN_ORDER_CAPACITY := 3


static func build(root: Node, callbacks: Dictionary) -> BattleUIRefs:
	var refs: BattleUIRefs = BattleUIRefsScript.new()
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

	# A second, independent pacing control: `speedSlider` above paces how often
	# a CPU turn begins, not how long any one action's animation takes to play.
	var animSpeedLabel = Label.new()
	animSpeedLabel.text = "  Anim:"
	topRow.add_child(animSpeedLabel)
	var animSpeedSlider = HSlider.new()
	animSpeedSlider.custom_minimum_size = Vector2(100, 20)
	animSpeedSlider.min_value = 0.25
	animSpeedSlider.max_value = 4.0
	animSpeedSlider.step = 0.25
	animSpeedSlider.value = 1.0
	animSpeedSlider.tooltip_text = "Action/spell/defeat animation playback speed."
	animSpeedSlider.value_changed.connect(callbacks["anim_speed_changed"])
	topRow.add_child(animSpeedSlider)

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
			"crt_parameter_changed": callbacks["crt_parameter_changed"],
			"ui_through_crt_toggled": callbacks["ui_through_crt_toggled"]
		}
	)
	graphicsButton.toggled.connect(func(pressed):
		graphicsMenu.panel.visible = pressed
		if pressed:
			logButton.button_pressed = false
	)
	logButton.toggled.connect(func(pressed):
		logPanel.visible = pressed
		if pressed:
			graphicsButton.button_pressed = false
	)

	# Docked bottom-left/bottom-right per §8, fixed size — they never resize or
	# reflow with content (item 4). Positioned directly rather than via an
	# HBoxContainer: a NoggWindow already has its own fixed size and a flex
	# container would fight that the moment the two windows' widths differ,
	# which they do not today but item 4 forbids relying on that.
	var status_window_size := Vector2(
		NoggThemeScript.STATUS_WINDOW_WIDTH, NoggThemeScript.window_height(STATUS_WINDOW_CAPACITY)
	)

	var actorWindow: NoggWindow = NoggWindowScript.new()
	game_root.add_child(actorWindow)
	actorWindow.name = "ActorWindow"
	actorWindow.set_row_capacity(STATUS_WINDOW_CAPACITY)
	actorWindow.size = status_window_size
	# Readout only. Between them these two windows cover the bottom third of the
	# viewport, including the near edge of the board where team 1 deploys, and a
	# Control consumes clicks by default — leaving those units unselectable.
	actorWindow.set_input_transparent(true)

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

	var targetWindow: NoggWindow = NoggWindowScript.new()
	game_root.add_child(targetWindow)
	targetWindow.name = "TargetWindow"
	targetWindow.set_row_capacity(STATUS_WINDOW_CAPACITY)
	targetWindow.size = status_window_size
	targetWindow.set_input_transparent(true)

	# The turn order is a top-docked portrait rail, not a docked window. It owns
	# the top band and the prompt sits below it: the rail is persistent and the
	# prompt is transient, so the persistent element holds the stable position
	# (docs/UI_DESIGN.md §8).
	var turnOrderRail: TurnOrderRailScript = TurnOrderRailScript.new()
	turnOrderRail.name = "TurnOrderRail"
	turnOrderRail.visible = false
	game_root.add_child(turnOrderRail)

	# Positioned from the viewport size on `resized` rather than read once at
	# build time: `game_root.get_viewport_rect()` immediately after the canvas
	# is built is not reliably the final displayed size — the same class of
	# layout-not-settled-yet timing this codebase has hit repeatedly this
	# session (see docs/LEARNINGS.md, Process behavior). A one-shot read left
	# both windows sitting well above the true bottom margin. Mirrors
	# PlayerCommandMenu's own resized-driven `_layout_windows()`.
	var reposition_status_windows := func() -> void:
		var viewport_size = game_root.get_viewport_rect().size
		actorWindow.position = Vector2(
			NoggThemeScript.SCREEN_MARGIN, viewport_size.y - status_window_size.y - NoggThemeScript.SCREEN_MARGIN
		)
		targetWindow.position = Vector2(
			viewport_size.x - status_window_size.x - NoggThemeScript.SCREEN_MARGIN,
			viewport_size.y - status_window_size.y - NoggThemeScript.SCREEN_MARGIN
		)
		# Centred, because a rail that grows and shrinks with the queue would
		# otherwise shift its whole contents every time a unit dies.
		turnOrderRail.position = Vector2(
			round((viewport_size.x - turnOrderRail.size.x) * 0.5),
			NoggThemeScript.TURN_RAIL_TOP
		)
	game_root.resized.connect(reposition_status_windows)
	reposition_status_windows.call()

	refs.game_canvas = game_canvas
	refs.dev_canvas = dev_canvas
	refs.turn_timer = turnTimer
	refs.play_button = playButton
	refs.anim_speed_slider = animSpeedSlider
	refs.graphics_button = graphicsButton
	refs.graphics = graphicsMenu
	refs.actor_window = actorWindow
	refs.target_window = targetWindow
	refs.turn_order_rail = turnOrderRail
	refs.reposition_windows = reposition_status_windows
	refs.log_label = logLabel
	refs.log_panel = logPanel
	refs.action_panel = actionPanel
	refs.command_menu = commandMenu
	refs.screenshot_button = screenshotButton
	refs.dump_button = dumpButton
	return refs


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
