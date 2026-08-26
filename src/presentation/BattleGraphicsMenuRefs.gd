## Typed references to the controls constructed by BattleGraphicsMenu.
##
## Slider maps stay keyed by renderer parameter because those keys are authored
## settings. Everything else is a stable presentation contract and is typed.
class_name BattleGraphicsMenuRefs
extends RefCounted

var panel: PanelContainer
var look_option: OptionButton
var window_skin_option: OptionButton
var preset_description: Label
var geometry_option: OptionButton
var upscale_option: OptionButton
var look_sliders: Dictionary
var crt_hint: Label
var crt_sliders: Dictionary
var ui_through_crt_button: CheckButton
