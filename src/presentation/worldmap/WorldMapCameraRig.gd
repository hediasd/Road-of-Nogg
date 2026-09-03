## The world map camera: fixed yaw, steep pitch, framing driven entirely by a dictionary.
##
## Yaw is pinned to 0 and is deliberately not a parameter. A painted map has one baked
## light direction and upright icons, and a fixed yaw is what lets roads and settlements be
## composited into the region PNG rather than existing as meshes. See
## `docs/WORLDMAP_DESIGN.md` section 3.
##
## The rig also owns the derived numbers -- tiles across the frame, buffer pixels per tile,
## near-to-far depth ratio, and the region width the current framing demands -- because
## they fall out of the same trigonometry that places the camera, and because the debug
## scene and final validation both need to read them rather than re-derive them.

class_name WorldMapCameraRig
extends Camera3D

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## The ground point at the centre of the frame. The camera sits above and behind it.
var focus := Vector2.ZERO

var _framing: Dictionary = Uniforms.DEFAULTS.duplicate(true)


func applyFraming(framing: Dictionary) -> void:
	_framing = Uniforms.complete(framing)
	# KEEP_HEIGHT makes `fov` the VERTICAL field of view, which is what every number in the
	# framing was derived against. Setting it explicitly rather than trusting the default
	# is cheap insurance: the horizontal reading would silently rescale the whole rig.
	keep_aspect = Camera3D.KEEP_HEIGHT
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = _framing[Uniforms.K_FOV]
	rotation_degrees = Vector3(-float(_framing[Uniforms.K_PITCH]), 0.0, 0.0)
	_place()


## Moves the frame's centre. Pass the region rect to clamp against it; omit it to pan free.
func panTo(ground_xz: Vector2, region := Rect2()) -> void:
	focus = ground_xz if region.size == Vector2.ZERO else _clampFocus(ground_xz, region)
	_place()


## Every number the debug readout and final validation check, for a given output size.
## `viewport_size` is the window; the internal buffer is that scaled by the framing's
## render scale, and buffer size is what decides pixels per tile.
func framingReadout(viewport_size: Vector2i) -> Dictionary:
	var scale: float = _framing[Uniforms.K_RENDER_SCALE]
	var buffer := Vector2(
		max(1.0, round(float(viewport_size.x) * scale)),
		max(1.0, round(float(viewport_size.y) * scale))
	)
	var near := _rayAt(-buffer.y * 0.5, buffer.y)
	var far := _rayAt(buffer.y * 0.5, buffer.y)

	# At one tile per world unit the horizontal world span IS the tile count, so tiles across
	# is just the buffer width times the near ray's parameter. A region's tile PIXEL size
	# never enters this: an 8 px-tile map and a 16 px-tile map at the same framing show the
	# same tile count, differing only in how many texels each tile gets.
	var near_t: float = near["t"]
	var near_depth: float = near["depth"]
	var far_depth: float = far["depth"]
	var tiles_across: float = buffer.x * near_t
	var ratio: float = far_depth / near_depth if near_depth > 0.0 else 0.0

	return {
		"tiles_across": tiles_across,
		"buffer_px_per_tile": buffer.x / tiles_across if tiles_across > 0.0 else 0.0,
		"near_depth": near_depth,
		"far_depth": far_depth,
		"near_far_ratio": ratio,
		# The constraint that sizes the art: the frame's far edge is `ratio` times wider
		# than its near edge, so a region has to be that much wider than the near span or
		# its plane edge shows. This multiplies; it is not a margin. WORLDMAP_DESIGN.md §3.
		"region_tiles_needed": ceil(tiles_across * ratio),
		"buffer_size": buffer,
		"horizon_on_screen": _framing[Uniforms.K_PITCH] < float(_framing[Uniforms.K_FOV]) * 0.5,
		# How much of the frame the curve eats. The ground falls by k*d^2 in VIEW depth, so
		# across one frame it drops by the difference between its near and far ends -- and once
		# that exceeds the frame's own vertical reach the map folds away and leaves the frame
		# showing void. Buildings go first, because they sit at mid-distance, which is exactly
		# what "the buildings disappeared" looks like from the outside.
		"curve_fold": _curveFold(near_depth, far_depth),
	}


## Curve drop across the visible depth range, as a multiple of the frame's vertical world span.
## Below 1 the curve bends the ground within the frame; above 1 it carries it out.
func _curveFold(near_ground: float, far_ground: float) -> float:
	var k: float = _framing[Uniforms.K_CURVATURE]
	if k <= 0.0:
		return 0.0
	var height: float = _framing[Uniforms.K_HEIGHT]
	var near_view := sqrt(height * height + near_ground * near_ground)
	var far_view := sqrt(height * height + far_ground * far_ground)
	var drop_span := k * (far_view * far_view - near_view * near_view)
	var centre_view := height / maxf(0.0001, sin(deg_to_rad(float(_framing[Uniforms.K_PITCH]))))
	var frame_span := 2.0 * centre_view * tan(deg_to_rad(float(_framing[Uniforms.K_FOV])) * 0.5)
	return drop_span / maxf(0.0001, frame_span)


## Ground footprint of the frame: the near and far world-Z bounds and the half-width at
## each. The far half-width is the one that matters -- it is always the larger.
func groundFootprint(viewport_size: Vector2i) -> Dictionary:
	var readout := framingReadout(viewport_size)
	var buffer: Vector2 = readout["buffer_size"]
	var near := _rayAt(-buffer.y * 0.5, buffer.y)
	var far := _rayAt(buffer.y * 0.5, buffer.y)
	var near_t: float = near["t"]
	var far_t: float = far["t"]
	return {
		"near_depth": near["depth"],
		"far_depth": far["depth"],
		"near_half_width": buffer.x * 0.5 * near_t,
		"far_half_width": buffer.x * 0.5 * far_t,
	}


func _place() -> void:
	var height: float = _framing[Uniforms.K_HEIGHT]
	var pitch: float = _framing[Uniforms.K_PITCH]
	# Depth from the camera to the ground point it is looking at. The camera sits that far
	# along +Z from the focus, because forward is -Z.
	var centre_depth := height / tan(deg_to_rad(pitch))
	position = Vector3(focus.x, height - _curveDropAtFocus(), focus.y + centre_depth)


## How far the ground has fallen at the point the camera is aiming at.
##
## The ground shader bends the world by `curvature_k * d^2` where d is VIEW depth, so the
## surface drops away from the camera rather than from the origin. Nothing told the rig, so it
## went on aiming at the flat y = 0 plane while the ground sank beneath it. At the shipped
## framings the error is small -- 2.3 units at Curved Close, lost inside the frame -- and it
## grows with the square of distance: at height 70 and k = 0.006 the ground is 59 units below
## where the camera is looking, and the entire map leaves the frame. Buildings go first,
## because they sit at mid-distance, which is why this reads as "the buildings disappeared".
##
## Matching the drop keeps the focus framed. It is not solved to a fixed point -- moving the
## camera changes view depths, which changes the drop -- but one step takes the error from
## tens of units to a fraction of one, and iterating would make the camera's position depend
## on itself for no visible gain.
func _curveDropAtFocus() -> float:
	var k: float = _framing[Uniforms.K_CURVATURE]
	if k <= 0.0:
		return 0.0
	var pitch := deg_to_rad(float(_framing[Uniforms.K_PITCH]))
	var sin_pitch := sin(pitch)
	if sin_pitch < 0.0001:
		return 0.0
	# View depth of the focus: the camera looks down the hypotenuse, not along the ground.
	var view_depth := float(_framing[Uniforms.K_HEIGHT]) / sin_pitch
	return k * view_depth * view_depth


## Ray parameters for one screen row, in the same form the HTML explorer uses: `t` scales
## screen offsets into world units at that row, `depth` is the planar distance ahead.
## `screen_y` is measured up from the buffer's centre.
func _rayAt(screen_y: float, buffer_height: float) -> Dictionary:
	var pitch := deg_to_rad(float(_framing[Uniforms.K_PITCH]))
	var focal := (buffer_height * 0.5) / tan(deg_to_rad(float(_framing[Uniforms.K_FOV])) * 0.5)
	var dir_y := screen_y * cos(pitch) - focal * sin(pitch)
	var dir_z := -screen_y * sin(pitch) - focal * cos(pitch)
	if dir_y > -0.000001:
		# Above the horizon: this row never meets the ground. Only reachable when pitch
		# drops below fov/2, which the reference framing never does.
		return {"t": 0.0, "depth": 0.0, "hits": false}
	var t := float(_framing[Uniforms.K_HEIGHT]) / -dir_y
	return {"t": t, "depth": -t * dir_z, "hits": true}


## Clamping the camera POSITION into the region is not enough: the frame's far edge is
## nearly three times wider than its near edge, so a camera well inside the region can
## still show void at the top corners. This clamps the footprint instead. When the
## footprint is simply larger than the region on an axis -- which is the normal case for a
## region smaller than the framing wants -- no position hides the edge, so it centres on
## that axis and lets the edge show rather than pretending.
func _clampFocus(wanted: Vector2, region: Rect2) -> Vector2:
	var viewport := get_viewport()
	var size := Vector2i(1920, 1080)
	if viewport != null:
		size = Vector2i(viewport.get_visible_rect().size)
	var footprint := groundFootprint(size)
	var half_width: float = footprint["far_half_width"]
	var centre_depth := float(_framing[Uniforms.K_HEIGHT]) / tan(
		deg_to_rad(float(_framing[Uniforms.K_PITCH]))
	)

	var result := wanted
	if half_width * 2.0 >= region.size.x:
		result.x = region.position.x + region.size.x * 0.5
	else:
		result.x = clamp(
			wanted.x,
			region.position.x + half_width,
			region.position.x + region.size.x - half_width
		)

	# The footprint runs from `focus.z + centre_depth - far_depth` to
	# `focus.z + centre_depth - near_depth`.
	var back_offset: float = centre_depth - float(footprint["near_depth"])
	var front_offset: float = float(footprint["far_depth"]) - centre_depth
	if front_offset + back_offset >= region.size.y:
		result.y = region.position.y + region.size.y * 0.5
	else:
		result.y = clamp(
			wanted.y,
			region.position.y + front_offset,
			region.position.y + region.size.y - back_offset
		)
	return result
