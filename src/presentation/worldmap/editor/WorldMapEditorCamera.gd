## The world map EDITOR's camera: orbit, pan, dolly and a top-down orthographic mode.
##
## None of this ships. `WorldMapCameraRig` is the shipping contract -- yaw pinned to 0, pitch and
## FOV solved together against a near-to-far depth ratio, every framing preset varying only
## height -- and it is not loosened to serve authoring. This subclass adds freedoms *beside* that
## contract and can hand the camera back to it exactly.
##
## IT IS A SUBCLASS ON PURPOSE. "Snap back to what ships" has to be the shipping placement, not a
## second implementation of it that agrees today and drifts later. In contract mode `_place()`
## defers to `super`, so the two rigs are the same code and `probe_editor_camera.gd` can assert
## they are identical rather than merely close.
##
## WHAT THE ORBIT IS FOR. It is an authoring aid for reading elevation, occlusion and where a
## prop actually stands -- not a preview. The art has one baked light direction and its icons are
## upright, so a rotated view is **wrong on purpose**: it shows the map lit from a direction it
## was never painted for. `offContractReason()` is what the editor HUD puts on screen so nobody
## judges a look from one, and nothing about how the map *looks* may be decided from a view this
## rig reports as off-contract.
##
## Zoom dollies and never touches FOV. FOV is one half of the framing contract's near-to-far
## ratio `R = (u·sin + cos)(sin + u·cos) / ((cos − u·sin)(sin − u·cos))`, so moving it silently
## rescales the thing every preset was solved for. See `docs/WORLDMAP_DESIGN.md` section 3.

class_name WorldMapEditorCamera
extends WorldMapCameraRig

## Free pitch is bounded well short of vertical: at 90 degrees the yaw axis and the view axis
## coincide and orbit stops meaning anything. Straight down is reachable, but only through the
## orthographic mode, where it is the point.
const PITCH_MIN := 15.0
const PITCH_MAX := 89.0

const DISTANCE_MIN := 2.0
const DISTANCE_MAX := 4000.0
## Wheel notches are multiplicative so a step feels the same close in and far out.
const DOLLY_STEP := 1.12

const YAW_SNAP_DEGREES := 45.0

## Radians of orbit per pixel of drag, and world units of pan per pixel at unit distance.
const ORBIT_SENSITIVITY := 0.35
const PAN_SENSITIVITY := 0.0016
## Keyboard rates, per second.
const KEY_ORBIT_RATE := 60.0
const KEY_PAN_RATE := 0.45

enum Mode {
	## Exactly what ships: the parent rig places the camera from the framing.
	CONTRACT,
	## Free orbit, pan and dolly, still in perspective.
	FREE,
	## Straight down, orthographic, axis aligned. The precision view.
	ORTHO,
}

var mode: int = Mode.CONTRACT
## Degrees. 0 is the shipping yaw; the map's baked light direction assumes it.
var yaw := 0.0
## Degrees below horizontal.
var pitch := 60.0
## Distance from the camera to the focus point ON THE DRAWN GROUND.
var distance := 72.0
## Orthographic half-height in world units, kept separate from `distance` so switching to the
## top-down view and back does not disturb the perspective framing.
var orthoSize := 64.0
## Set false to leave input to something else; the rig still places on demand.
var inputEnabled := true

## The region the editor last asked to be framed, so F can repeat without the caller passing it
## again. Zero until `rememberRegion`; `frameRegion` ignores a zero rect.
var _lastRegion := Rect2()

var _framingCopy: Dictionary = Uniforms.DEFAULTS.duplicate(true)
var _orbiting := false
var _panning := false


func _ready() -> void:
	set_process(true)


## Records the framing so the contract can be restored exactly, then defers entirely to the
## parent. Seeds the free-look angles from the framing too, so engaging orbit starts from where
## the shipping camera was rather than snapping somewhere else first.
func applyFraming(framing: Dictionary) -> void:
	_framingCopy = Uniforms.complete(framing)
	if mode == Mode.CONTRACT:
		pitch = float(_framingCopy[Uniforms.K_PITCH])
		yaw = 0.0
		distance = _contractDistance()
	super.applyFraming(framing)


## The one key back to what ships. Restores projection, FOV, pitch and yaw together by replaying
## the framing through the parent, because restoring them one at a time is how a "restored"
## camera ends up one field short.
func snapToContract() -> void:
	mode = Mode.CONTRACT
	applyFraming(_framingCopy)


func setFree() -> void:
	if mode == Mode.FREE:
		return
	if mode == Mode.CONTRACT:
		pitch = float(_framingCopy[Uniforms.K_PITCH])
		distance = _contractDistance()
	mode = Mode.FREE
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = _framingCopy[Uniforms.K_FOV]
	_place()


## Straight down and orthographic. Yaw returns to 0 because the value of this view is that it is
## axis aligned -- a rotated top-down grid is harder to author on, not easier.
func toggleOrtho() -> void:
	if mode == Mode.ORTHO:
		setFree()
		return
	mode = Mode.ORTHO
	yaw = 0.0
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = orthoSize
	_place()


## Why the view is not what ships, or "" when it is. The editor HUD shows this; an empty string
## is the only state in which the map's appearance may be judged.
func offContractReason() -> String:
	match mode:
		Mode.ORTHO:
			return "OFF-CONTRACT  orthographic, straight down"
		Mode.FREE:
			var parts := PackedStringArray()
			if absf(yaw) > 0.001:
				parts.append("yaw %+.0f" % yaw)
			if absf(pitch - float(_framingCopy[Uniforms.K_PITCH])) > 0.001:
				parts.append("pitch %.0f" % pitch)
			if absf(distance - _contractDistance()) > 0.001:
				parts.append("dollied")
			if parts.is_empty():
				return ""
			return "OFF-CONTRACT  %s" % ", ".join(parts)
		_:
			return ""


func orbitBy(deltaYaw: float, deltaPitch: float) -> void:
	setFree()
	yaw = wrapf(yaw + deltaYaw, -180.0, 180.0)
	pitch = clampf(pitch + deltaPitch, PITCH_MIN, PITCH_MAX)
	_place()


func snapYaw() -> void:
	setFree()
	yaw = wrapf(round(yaw / YAW_SNAP_DEGREES) * YAW_SNAP_DEGREES, -180.0, 180.0)
	_place()


## Dollies along the view axis. Multiplicative, and it never touches FOV -- see the class note.
func dollyBy(notches: float) -> void:
	if mode == Mode.ORTHO:
		orthoSize = clampf(orthoSize * pow(DOLLY_STEP, -notches), 1.0, DISTANCE_MAX)
		size = orthoSize
		_place()
		return
	setFree()
	distance = clampf(distance * pow(DOLLY_STEP, -notches), DISTANCE_MIN, DISTANCE_MAX)
	_place()


## Moves the focus across the ground in the direction the view is facing, so a drag feels the
## same at any yaw. DELIBERATELY UNCLAMPED, like the debug scene's own pan and unlike the
## shipping `panTo(focus, rect)`: an authoring tool has to be able to look at the map's edge,
## which is exactly what the shipping clamp exists to prevent. See WORLDMAP_DESIGN.md section 3
## and the debug controller's DRAG TO PAN note.
func panBy(screenDelta: Vector2) -> void:
	var span := orthoSize if mode == Mode.ORTHO else distance
	panByWorld(screenDelta * PAN_SENSITIVITY * span)


## `panBy` in world units rather than screen pixels, which is what the keyboard and any
## programmatic caller actually have.
func panByWorld(scaled: Vector2) -> void:
	if mode == Mode.CONTRACT:
		setFree()
	var yawRad := deg_to_rad(yaw)
	# Screen right and screen "up the map" in ground XZ, rotated by the current yaw.
	var right := Vector2(cos(yawRad), -sin(yawRad))
	var forward := Vector2(sin(yawRad), cos(yawRad))
	focus += right * -scaled.x + forward * -scaled.y
	_place()


## Fits a region rect in view without clamping to it, so the edges and the void beyond them stay
## visible -- which is the whole reason an editor looks at a region at all.
func frameRegion(region: Rect2) -> void:
	if region.size == Vector2.ZERO:
		return
	focus = region.position + region.size * 0.5
	var span := maxf(region.size.x, region.size.y)
	if mode == Mode.ORTHO:
		orthoSize = span * 0.6
		size = orthoSize
		_place()
		return
	setFree()
	# Half the span over the tangent of half the vertical FOV, with room to spare so the edge is
	# inside the frame rather than on it.
	var halfFov := deg_to_rad(maxf(1.0, float(_framingCopy[Uniforms.K_FOV]))) * 0.5
	distance = clampf(span * 0.6 / tan(halfFov), DISTANCE_MIN, DISTANCE_MAX)
	_place()


## The distance from the camera to the drawn focus under the SHIPPING placement, so free-look can
## start exactly where the contract left off. The parent sits `height` above the drawn focus and
## `height / tan(pitch)` behind it, and the hypotenuse of those is `height / sin(pitch)`.
func _contractDistance() -> float:
	var pitchRad := deg_to_rad(float(_framingCopy[Uniforms.K_PITCH]))
	var sinPitch := sin(pitchRad)
	if sinPitch < 0.0001:
		return DISTANCE_MAX
	return clampf(float(_framingCopy[Uniforms.K_HEIGHT]) / sinPitch, DISTANCE_MIN, DISTANCE_MAX)


## The world point the camera orbits: the focus AS THE SHADER DRAWS IT.
##
## The ground shader bends the world by `curvature_k * d^2` in VIEW depth, so the surface under
## the focus is not at y = 0 -- it has fallen by the drop belonging to its own distance. Orbiting
## around y = 0 instead makes the map slide under the cursor as yaw changes, by an error that
## grows with the square of distance and so is invisible close in and gross far out.
##
## This needs no fixed-point solve, unlike the parent's `_curveDropAtFocus()`. The parent is
## given a HEIGHT and has to discover the view depth that settles with it; here the view depth of
## the focus IS `distance`, by definition of an orbit, so the drop is one multiplication.
func _drawnFocus() -> Vector3:
	var k: float = maxf(0.0, float(_framingCopy[Uniforms.K_CURVATURE]))
	var span := orthoSize if mode == Mode.ORTHO else distance
	return Vector3(focus.x, -k * span * span, focus.y)


## Places the camera. In contract mode this IS the shipping rig -- see the class note.
func _place() -> void:
	if mode == Mode.CONTRACT:
		super._place()
		return

	var pitchUsed := 90.0 if mode == Mode.ORTHO else pitch
	var pitchRad := deg_to_rad(pitchUsed)
	var yawRad := deg_to_rad(yaw)
	# Unit vector from the focus toward the camera: up by the pitch, swung by the yaw. Godot's
	# default YXZ rotation order applies yaw then pitch, which is the same composition.
	var offset := Vector3(
		sin(yawRad) * cos(pitchRad),
		sin(pitchRad),
		cos(yawRad) * cos(pitchRad)
	)
	var span := orthoSize if mode == Mode.ORTHO else distance
	rotation_degrees = Vector3(-pitchUsed, yaw, 0.0)
	position = _drawnFocus() + offset * span


func _process(delta: float) -> void:
	if not inputEnabled:
		return
	var orbitStep := 0.0
	if Input.is_key_pressed(KEY_Q):
		orbitStep -= KEY_ORBIT_RATE * delta
	if Input.is_key_pressed(KEY_E):
		orbitStep += KEY_ORBIT_RATE * delta
	if absf(orbitStep) > 0.0:
		orbitBy(orbitStep, 0.0)

	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		var span := orthoSize if mode == Mode.ORTHO else distance
		panByWorld(pan.normalized() * KEY_PAN_RATE * span * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not inputEnabled:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_MIDDLE:
				_orbiting = button.pressed
				if not button.pressed and Input.is_key_pressed(KEY_SHIFT):
					snapYaw()
			MOUSE_BUTTON_RIGHT:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					dollyBy(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					dollyBy(-1.0)
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			orbitBy(motion.relative.x * ORBIT_SENSITIVITY, -motion.relative.y * ORBIT_SENSITIVITY)
		elif _panning:
			panBy(motion.relative)
		return

	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				snapToContract()
			KEY_TAB:
				toggleOrtho()
			KEY_F:
				frameRegion(_lastRegion)


func rememberRegion(region: Rect2) -> void:
	_lastRegion = region
