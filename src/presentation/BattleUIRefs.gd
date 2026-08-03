## Typed references to the stable in-battle UI constructed by BattleUIBuilder.
class_name BattleUIRefs
extends RefCounted

var game_canvas: CanvasLayer
var dev_canvas: CanvasLayer
var turn_timer: Timer
var play_button: Button
var anim_speed_slider: HSlider
var graphics_button: Button
var graphics: BattleGraphicsMenuRefs
var actor_window: NoggWindow
var target_window: NoggWindow
var turn_order_window: NoggWindow
var log_label: RichTextLabel
var log_panel: PanelContainer
var action_panel: Control
var command_menu: PlayerCommandMenu
var screenshot_button: Button
var dump_button: Button
