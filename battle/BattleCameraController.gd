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

## Turn-start framing pan. Tweens `focus_point` only — never `current_yaw`,
## `current_pitch`, or `size` — so a pan can never rotate or zoom the camera,
## per the rule that the camera may guarantee visibility but never take
## authorship of the view. `_update_camera_transform()` re-derives `position`
## from `focus_point` every frame, so this is a plain translation.
const FOCUS_PAN_DURATION := 0.35
var _focusPanTween: Tween

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


func _process(delta: float) -> void:
	# Integrated here rather than tweened: see the field comment on
	# _orbit_rate_deg for why an orbit has no end angle to tween toward.
	if not is_zero_approx(_orbit_rate_deg):
		current_yaw += deg_to_rad(_orbit_rate_deg) * delta
	# We update transform every frame so that Tweens on yaw/pitch automatically apply
	_update_camera_transform()


func handle_input(event: InputEvent, motionScale: Vector2 = Vector2.ONE) -> bool:
	## Any event this function recognizes as its own — zoom, orbit, pan, or a
	## reset — is player-authored camera input, and the settled rule is that
	## every authorship-taking motion (a framing pan, a director frameTo(), an
	## orbit, or an in-flight settle) abandons immediately in favour of it.
	## Hover and grid clicks fall through to `false` below and must not cancel
	## anything; wrapping the original logic here, rather than scattering
	## cancellation at each `return true`, keeps that distinction in one place.
	var handled := _handle_camera_input(event, motionScale)
	if handled:
		_cancelDirectorMotion()
	return handled


func _handle_camera_input(event: InputEvent, motionScale: Vector2) -> bool:
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


## Pans the orbit's focus point to `target`, keeping yaw, pitch, and zoom
## exactly as they are. Position only — see the field comment above
## `_focusPanTween`.
func panFocusTo(target: Vector3, duration: float = FOCUS_PAN_DURATION) -> void:
	cancelPanFocus()
	_focusPanTween = create_tween()
	_focusPanTween.tween_property(self, "focus_point", target, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func cancelPanFocus() -> void:
	if _focusPanTween != null and _focusPanTween.is_valid():
		_focusPanTween.kill()
	_focusPanTween = null


func isPanningFocus() -> bool:
	return _focusPanTween != null and _focusPanTween.is_valid()


## --- Director framing --------------------------------------------------
#
# This controller now serves two rules instead of one, and which applies
# depends on which of these two groups a caller reaches for:
#
# - `panFocusTo()` above is PLAYER-VIEW-PRESERVING: it moves `focus_point`
#   only, so it can never rotate or zoom a view the player set. This is the
#   original rule the field comment on `_focusPanTween` describes.
# - Everything below is AUTHORSHIP-TAKING: `frameTo()`, `orbitBy()`, and
#   `settleToQuadrant()` are how a director explicitly owns the view for as
#   long as it is driving. A caller reaching for these has decided the
#   director owns the camera; a caller that must respect whatever the player
#   last set uses `panFocusTo()` instead.
#
# `snapshotFreeView()` / `restoreFreeView()` are what makes taking authorship
# reversible: entering director mode snapshots exactly where the player left
# the free camera, and leaving it restores that exact yaw, pitch, zoom, and
# focus — the player's own framing, not a reset to `default_*`.

var _free_view_yaw: float
var _free_view_pitch: float
var _free_view_size: float
var _free_view_focus: Vector3
## Degrees per second. Continuous rather than tweened to an end angle: a CPU
## turn's length is not known when deliberation starts — it depends on how
## many actions the AI ends up queuing — so nothing here has a duration to
## tween toward. `_process` integrates this every frame until `stopOrbit()` or
## `settleToQuadrant()` zeroes it.
var _orbit_rate_deg: float = 0.0
var _frame_tween: Tween
var _orbit_settle_tween: Tween


## Captures the current view so `restoreFreeView()` can return to it exactly.
## Call once, on the frame director mode is entered.
func snapshotFreeView() -> void:
	_free_view_yaw = current_yaw
	_free_view_pitch = current_pitch
	_free_view_size = size
	_free_view_focus = focus_point


## Reverses `snapshotFreeView()`: tweens back to the player's own last
## framing, not to `default_*` — leaving director mode should feel like
## getting the camera back, not like a reset. Shortest-path on yaw, since an
## orbit may have carried `current_yaw` several turns away from where it was
## snapshotted.
func restoreFreeView(duration: float = FOCUS_PAN_DURATION) -> void:
	_cancelDirectorMotion()
	var target_yaw: float = _shortest_yaw_target(_free_view_yaw)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "current_yaw", target_yaw, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "current_pitch", _free_view_pitch, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "size", _free_view_size, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "focus_point", _free_view_focus, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Takes authorship: tweens focus and zoom to frame `target_focus` at
## `target_size`. Yaw and pitch are untouched — framing moves and zooms, it
## does not rotate; only `orbitBy()` rotates the view, and only while a CPU is
## deliberating.
func frameTo(target_focus: Vector3, target_size: float, duration: float = FOCUS_PAN_DURATION) -> void:
	cancelPanFocus()
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = create_tween().set_parallel(true)
	_frame_tween.tween_property(self, "focus_point", target_focus, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_frame_tween.tween_property(self, "size", clampf(target_size, min_zoom, max_zoom), duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func cancelFrameTo() -> void:
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = null


func isFraming() -> bool:
	return _frame_tween != null and _frame_tween.is_valid()


## Begins a constant angular drift, in degrees per second (either sign).
func orbitBy(degrees_per_second: float) -> void:
	_orbit_rate_deg = degrees_per_second


func stopOrbit() -> void:
	_orbit_rate_deg = 0.0


func isOrbiting() -> bool:
	return not is_zero_approx(_orbit_rate_deg)


## Stops any drift and tweens yaw to the nearest 90-degree quadrant, by
## whichever way is already closer — `current_yaw` is unbounded (a drift can
## carry it through many full turns), so "nearest multiple of 90 degrees to
## the current value" is the shortest path by construction; no separate
## wrapping is needed the way `restoreFreeView()` needs one against a fixed
## remembered target.
##
## This is what makes rotating during deliberation safe rather than merely
## possible: a player only ever aims a tile cursor from an exact quadrant, so
## `nearestQuadrantYaw()` — read once the settle finishes — is exact by
## construction instead of an approximation across an arbitrary yaw.
func settleToQuadrant(duration: float = FOCUS_PAN_DURATION) -> void:
	stopOrbit()
	if _orbit_settle_tween != null and _orbit_settle_tween.is_valid():
		_orbit_settle_tween.kill()
	var target_yaw: float = round(current_yaw / (PI * 0.5)) * (PI * 0.5)
	_orbit_settle_tween = create_tween()
	_orbit_settle_tween.tween_property(self, "current_yaw", target_yaw, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func isSettlingToQuadrant() -> bool:
	return _orbit_settle_tween != null and _orbit_settle_tween.is_valid()


## The current yaw's nearest quadrant, normalized to [0, TAU). What tile-aim
## input snapping reads to decide which board axis is currently "left" on
## screen.
func nearestQuadrantYaw() -> float:
	return fposmod(round(current_yaw / (PI * 0.5)) * (PI * 0.5), TAU)


## Shortest path from `current_yaw` to an angle congruent to `target` — i.e.
## the equivalent of `target` nearest `current_yaw`, so a tween never spins
## the long way around. Shared by `_reset_camera()` and `restoreFreeView()`.
func _shortest_yaw_target(target: float) -> float:
	var result := target
	while result - current_yaw > PI:
		result -= TAU
	while result - current_yaw < -PI:
		result += TAU
	return result


## Cancels every authorship-taking motion: a framing pan, a `frameTo()`, an
## active orbit, and an in-flight settle. Called both when the player's own
## input is recognized (`handle_input()`) and when director mode is ending
## (`restoreFreeView()`), so "the player just grabbed the camera" and "the
## director is handing it back" return control through the same one path.
func _cancelDirectorMotion() -> void:
	cancelPanFocus()
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = null
	stopOrbit()
	if _orbit_settle_tween != null and _orbit_settle_tween.is_valid():
		_orbit_settle_tween.kill()
	_orbit_settle_tween = null


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

	# Shortest angular path for yaw so it doesn't spin wildly.
	var target_yaw: float = _shortest_yaw_target(default_yaw)

	# Tween the logical angles so the camera smoothly orbits back
	tween.tween_property(self, "current_yaw", target_yaw, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "current_pitch", default_pitch, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "size", default_size, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "focus_point", default_focus_point, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
