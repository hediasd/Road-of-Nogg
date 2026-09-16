class_name SideTurnIconArc
extends Control

signal action_requested(actionID: String)

const ActionIconsScript = preload("res://src/presentation/ActionIcons.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const ACTIONS := ["magic", "item", "status", "wait"]
const LABELS := {"magic": "Magic", "item": "Item", "status": "Status", "wait": "Wait"}
const BUTTON_SIZE := 42.0
const ARC_RADIUS := 60.0
const ENTER_SECONDS := 0.16
const IDLE_SECONDS := 2.4

var _buttons: Dictionary = {}
var _crosses: Dictionary = {}
var _undo: Button
var _idleTween: Tween
var _flipped := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for actionID: String in ACTIONS:
		var button := TextureButton.new()
		button.name = actionID.capitalize()
		button.texture_normal = ActionIconsScript.texture_for(actionID)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2.ONE * BUTTON_SIZE
		button.size = Vector2.ONE * BUTTON_SIZE
		button.tooltip_text = LABELS[actionID]
		button.pressed.connect(func(): action_requested.emit(actionID))
		add_child(button)
		_buttons[actionID] = button
		var cross := ColorRect.new()
		cross.name = "Cross"
		cross.color = Color("d8412f")
		cross.size = Vector2(BUTTON_SIZE * 0.78, 3.0)
		cross.position = Vector2(BUTTON_SIZE * 0.11, BUTTON_SIZE * 0.5)
		cross.rotation = -PI / 4.0
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.visible = false
		button.add_child(cross)
		_crosses[actionID] = cross
	_undo = Button.new()
	_undo.name = "Undo"
	_undo.text = "Undo"
	_undo.custom_minimum_size = Vector2(58.0, 24.0)
	_undo.size = Vector2(58.0, 24.0)
	_undo.add_theme_color_override("font_color", Color("18212b"))
	_undo.add_theme_color_override("font_hover_color", Color("18212b"))
	_undo.pressed.connect(func(): action_requested.emit("undo"))
	add_child(_undo)
	visible = false


func showArc(screenAnchor: Vector2, enabled: Dictionary, crossed: Array = [], undo: bool = false) -> void:
	_flipped = screenAnchor.y < 150.0
	position = screenAnchor
	for index in range(ACTIONS.size()):
		var actionID: String = ACTIONS[index]
		var angle := lerpf(-2.72, -0.42, float(index) / 3.0)
		if _flipped:
			angle = -angle
		var button := _buttons[actionID] as TextureButton
		button.position = Vector2(cos(angle), sin(angle)) * ARC_RADIUS - Vector2.ONE * BUTTON_SIZE * 0.5
		button.disabled = not bool(enabled.get(actionID, false))
		button.modulate = Color.WHITE if not button.disabled else Color(0.45, 0.47, 0.5, 0.7)
		(_crosses[actionID] as ColorRect).visible = crossed.has(actionID)
	_undo.visible = undo
	_undo.position = Vector2(-_undo.size.x * 0.5, 30.0 if not _flipped else -54.0)
	visible = true
	scale = Vector2.ONE * 0.72
	modulate.a = 0.0
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(self, "scale", Vector2.ONE, ENTER_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(self, "modulate:a", 1.0, ENTER_SECONDS)
	_startIdle()


func setAiming(aiming: bool) -> void:
	modulate.a = 0.34 if aiming else 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE if aiming else Control.MOUSE_FILTER_PASS


func hideArc() -> void:
	visible = false
	if _idleTween != null and _idleTween.is_valid():
		_idleTween.kill()
	_idleTween = null


func isFlipped() -> bool:
	return _flipped


func _startIdle() -> void:
	if _idleTween != null and _idleTween.is_valid():
		_idleTween.kill()
	_idleTween = create_tween().set_loops()
	_idleTween.tween_property(self, "rotation", 0.018, IDLE_SECONDS * 0.43) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idleTween.tween_property(self, "rotation", -0.012, IDLE_SECONDS * 0.57) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
