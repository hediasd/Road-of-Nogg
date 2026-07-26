class_name BattleCameraController
extends Camera3D

enum DragMode {
	NONE,
	ORBIT,
	PAN
}

var default_yaw: float
var default_pitch: float
var default_size: float
var default_focus_point: Vector3

var current_yaw: float
var current_pitch: float
var radius: float = 18.0
var focus_point: Vector3 = Vector3(8, 0, 4)

var min_zoom: float = 2.0
var max_zoom: float = 30.0
var zoom_step: float = 1.0
var _dragMode: DragMode = DragMode.NONE

func _ready() -> void:
	# Calculate initial spherical coords from starting position relative to focus
	var offset = position - focus_point
	radius = offset.length()
	current_yaw = atan2(offset.x, offset.z)
	current_pitch = asin(offset.y / radius)
	
	default_yaw = current_yaw
	default_pitch = current_pitch
	default_size = size
	default_focus_point = focus_point

	_update_camera_transform()


func _process(_delta: float) -> void:
	# We update transform every frame so that Tweens on yaw/pitch automatically apply
	_update_camera_transform()


func handle_input(event: InputEvent, motionScale: Vector2 = Vector2.ONE) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(-zoom_step)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(zoom_step)
			return true
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed and event.double_click:
			cancelDrag()
			_reset_camera()
			return true
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragMode = DragMode.ORBIT
			elif _dragMode == DragMode.ORBIT:
				_dragMode = DragMode.NONE
			return true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_dragMode = DragMode.PAN
			elif _dragMode == DragMode.PAN:
				_dragMode = DragMode.NONE
			return true

	elif event is InputEventMouseMotion:
		var scaledRelative = event.relative * motionScale
		if _dragMode == DragMode.ORBIT:
			_pan_camera(scaledRelative)
			return true
		elif _dragMode == DragMode.PAN:
			_pan_focus(scaledRelative)
			return true
	return false


func isDragging() -> bool:
	return _dragMode != DragMode.NONE


func cancelDrag() -> void:
	_dragMode = DragMode.NONE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancelDrag()


func _update_camera_transform() -> void:
	# Spherical to Cartesian conversion
	var x = radius * cos(current_pitch) * sin(current_yaw)
	var y = radius * sin(current_pitch)
	var z = radius * cos(current_pitch) * cos(current_yaw)
	
	position = focus_point + Vector3(x, y, z)
	look_at(focus_point, Vector3.UP)


func _zoom_camera(amount: float) -> void:
	if projection != Camera3D.PROJECTION_ORTHOGONAL: return
	var new_size = clamp(size + amount, min_zoom, max_zoom)
	size = new_size


func _pan_camera(relative: Vector2) -> void:
	var orbit_speed = 0.005
	current_yaw -= relative.x * orbit_speed
	# Up/down mouse drag changes pitch (angle from ground). 
	current_pitch += relative.y * orbit_speed
	
	# Clamp pitch so we don't flip over or go below ground
	current_pitch = clamp(current_pitch, 0.1, PI/2 - 0.1)

func _pan_focus(relative: Vector2) -> void:
	var viewport_rect = get_viewport().get_visible_rect()
	var drag_factor = size / viewport_rect.size.y
	
	var right = transform.basis.x
	var up = transform.basis.y
	
	focus_point -= right * relative.x * drag_factor
	focus_point += up * relative.y * drag_factor

func _reset_camera() -> void:
	var tween = create_tween().set_parallel(true)
	
	# Calculate shortest angular path for yaw so it doesn't spin wildly
	var target_yaw = default_yaw
	while target_yaw - current_yaw > PI: target_yaw -= TAU
	while target_yaw - current_yaw < -PI: target_yaw += TAU
	
	# Tween the logical angles so the camera smoothly orbits back
	tween.tween_property(self, "current_yaw", target_yaw, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "current_pitch", default_pitch, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "size", default_size, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "focus_point", default_focus_point, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
