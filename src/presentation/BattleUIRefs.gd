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
## Restyles the actor/target windows and the rail for the current skin, then
## repositions all three. Split from `reposition_windows` because a skin
## switch changes `.size` on windows a mere viewport resize never touches, so
## bundling both into every `resized` firing would rebuild chrome on a plain
## window drag.
var restyle_windows: Callable
## The themed root under `game_canvas`. A `Theme`'s font and styleboxes are
## copied in at `build_game_theme()` time rather than read live, so a skin
## switch has to build a fresh one and reassign it here — not just recompute
## `NoggTheme`'s tokens.
var game_theme_root: Control
## The themed root on `NoggTheme.PROMPT_LAYER`, a sibling of `game_canvas`
## rather than a descendant (see `BattleUIBuilder`'s note on why the prompt
## has its own layer). Needs the same theme reassignment, separately, because
## it is not part of `game_theme_root`'s tree.
var prompt_theme_root: Control
var log_label: RichTextLabel
var log_panel: PanelContainer
var action_panel: Control
var command_menu: PlayerCommandMenu
var screenshot_button: Button
var dump_button: Button
