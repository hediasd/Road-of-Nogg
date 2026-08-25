## Typed references to the stable in-battle UI constructed by BattleUIBuilder.
class_name BattleUIRefs
extends RefCounted

const TurnOrderRailScript = preload("res://src/presentation/TurnOrderRail.gd")
const DeepCardScript = preload("res://src/presentation/DeepCard.gd")

var game_canvas: CanvasLayer
var dev_canvas: CanvasLayer
var turn_timer: Timer
var play_button: Button
var anim_speed_slider: HSlider
var graphics_button: Button
var graphics: BattleGraphicsMenuRefs
var actor_window: NoggWindow
var target_window: NoggWindow
var turn_order_rail: TurnOrderRailScript
## The held-key reference readout. Transient and self-positioning, so unlike the
## docked windows it is absent from `reposition_windows`.
var deep_card: DeepCardScript
## The rail is centred on the viewport and resizes with the queue, so its layout
## has to rerun whenever its width changes rather than only on `resized`.
var reposition_windows: Callable
var log_label: RichTextLabel
var log_panel: PanelContainer
var action_panel: Control
var command_menu: PlayerCommandMenu
var screenshot_button: Button
var dump_button: Button
