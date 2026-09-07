## Turns a screen position into the tile and cel under it, against the ground AS THE SHADER
## DRAWS IT -- and drives the shader's grid overlay, which is the same surface seen from the
## other side.
##
## WHY THIS IS NOT `Plane(Vector3.UP, 0).intersects_ray(...)`. The obvious implementation
## intersects the ray with `y = 0`, and it is right only when curvature is zero. The ground
## shader bends the world by `curvature_k * d^2`, so at any non-zero curvature the flat-plane
## answer is correct under the camera and drifts with distance -- exactly the shape of error
## that looks fine while you are testing near the middle of the frame and puts the cursor a
## tile or two off at the far edge, which is where the tiles are smallest and the mistake is
## hardest to see.
##
## SOLVED, NOT ITERATED. `WorldMapCameraRig._curveDropAtFocus` carries the history here: an
## earlier version estimated its curve drop with a single step from a nominal depth and
## overshot badly -- 104.2 units for a real drop of 38.1 at the far end of the debug sliders,
## which put the camera under the ground and rendered an empty frame. The intersection below is
## a quadratic with a closed form, so it is solved exactly.
##
## THE DERIVATION, because the result is short and the reasoning is not. The shader's vertex
## stage is:
##
##     forward_distance = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z
##     VERTEX.y -= curvature_k * forward_distance * forward_distance
##
## Two things about that are load-bearing. The drop is measured along the CAMERA'S forward axis,
## not from the world origin -- so the drawn surface is a paraboloid whose axis follows the
## camera. And `forward_distance` is taken from the UNDISPLACED vertex, so there is no fixed
## point to solve: the drop at a ground point depends only on where that point already was.
##
## Write `C` for the camera position, `r` for the ray direction, `fwd` for the camera's forward
## axis. A point `Q = C + t*r` lies on the drawn surface when its height equals the drop
## belonging to the undisplaced ground point `U = (Q.x, 0, Q.z)` beneath it:
##
##     f(t) = dot(U - C, fwd) = t*(r.x*fwd.x + r.z*fwd.z) - C.y*fwd.y = A*t + B
##     C.y + t*r.y = -k * f(t)^2
##
## which rearranges to a plain quadratic in `t`:
##
##     (k*A^2) t^2 + (2*k*A*B + r.y) t + (k*B^2 + C.y) = 0
##
## At `k = 0` the quadratic term vanishes and it degenerates to `t = -C.y / r.y`, the flat-plane
## intersection -- so the curved and flat paths are the same code rather than two branches that
## have to agree.
##
## ROOM FOR THE HEIGHT FIELD. Phase D adds a per-tile height, which turns the right-hand side
## into `h(U) - k*f^2` and is no longer closed-form, because `h` is a lookup rather than an
## expression. The shape below anticipates that: `solveSmooth()` is the exact solve for the
## smooth surface and `pickTile()` calls it once, so a height term arrives as a refinement pass
## seeded from that root rather than as a rewrite of it.

class_name WorldMapSurfacePick
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Below this the quadratic's leading term is numerically useless and the linear form is both
## exact and better conditioned. Reached whenever curvature is zero, and also when the ray is
## very nearly perpendicular to the camera's forward axis.
const QUADRATIC_EPSILON := 1e-12
## Projection and ray directions pass through 32-bit transform values. A ray that is tangent to
## the curved surface can therefore produce a tiny negative discriminant even when it came from
## a point the renderer just projected. Scale this tolerance to the two terms being subtracted;
## a materially negative value must still report no intersection.
const DISCRIMINANT_REL_EPSILON := 1e-6


## Where a screen position lands on the drawn ground, or `null` if the ray never meets it --
## which happens for a ray aimed above the horizon, and is an ordinary answer rather than an
## error. Returns the world-space point ON the surface, so its `y` is the drop, not zero.
static func surfacePoint(camera: Camera3D, screen: Vector2, curvature: float) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var t := solveSmooth(origin, direction, camera.global_transform.basis.z * -1.0, curvature)
	if t <= 0.0:
		return null
	return origin + direction * t


## The ray parameter where the ray meets the drawn surface, or -1.0 when it does not. `forward`
## is the camera's forward axis as a unit vector. See the class note for the derivation.
static func solveSmooth(origin: Vector3, direction: Vector3, forward: Vector3, curvature: float) -> float:
	var k := maxf(0.0, curvature)
	var a := direction.x * forward.x + direction.z * forward.z
	var b := -origin.y * forward.y

	var quadratic := k * a * a
	var linear := 2.0 * k * a * b + direction.y
	var constant := k * b * b + origin.y

	if quadratic < QUADRATIC_EPSILON:
		# Flat, or as near as makes no difference: one root, and the better-conditioned form.
		if absf(linear) < QUADRATIC_EPSILON:
			return -1.0
		var flat := -constant / linear
		return flat if flat > 0.0 else -1.0

	var linearSquared := linear * linear
	var product := 4.0 * quadratic * constant
	var discriminant := linearSquared - product
	var discriminantTolerance := DISCRIMINANT_REL_EPSILON * maxf(1.0, maxf(absf(linearSquared), absf(product)))
	if discriminant < -discriminantTolerance:
		return -1.0
	discriminant = maxf(0.0, discriminant)
	var root := sqrt(discriminant)
	# Both roots, then the NEAREST positive one. The surface falls away from the camera, so a
	# ray aimed down at it can cross the paraboloid twice; the near crossing is the one that is
	# actually visible, and taking the far one puts the cursor beyond the horizon.
	var first := (-linear - root) / (2.0 * quadratic)
	var second := (-linear + root) / (2.0 * quadratic)
	var near := minf(first, second)
	var far := maxf(first, second)
	if near > 0.0:
		return near
	return far if far > 0.0 else -1.0


## The tile under a screen position, or `null`. Tiles are one world unit, so this is a floor of
## the surface point's horizontal coordinates -- the whole reason the tile law makes that ratio
## a constant.
##
## `region` bounds the answer: a pick that lands off the map returns `null` rather than a
## negative tile, because "no tile there" and "tile -3" are different answers and only one of
## them is true.
## `hex` switches the final mapping from a square floor to hex rounding. It defaults false so the
## square path -- and `temp2_authored`, whose byte-exact bake parity is the sharpest test in the
## project -- is bit-for-bit unaffected.
##
## THE RAY SOLVE IS THE SAME EITHER WAY. `surfacePoint` returns a world point and knows nothing
## about grids, so the hex switch changes one line here and nothing about the curvature maths.
static func pickTile(
	camera: Camera3D, screen: Vector2, curvature: float, region: Rect2, hex := false
) -> Variant:
	var point = surfacePoint(camera, screen, curvature)
	if point == null:
		return null
	var world := point as Vector3
	var local := Vector2(world.x, world.z) - region.position
	if local.x < 0.0 or local.y < 0.0 or local.x >= region.size.x or local.y >= region.size.y:
		return null
	if hex:
		return WorldMapHexGrid.worldToCell(local)
	return Vector2i(int(floor(local.x)), int(floor(local.y)))


## The cel under a screen position, in CEL coordinates -- so a 15x11 tile region indexes cels
## 0..29 by 0..21. Same bounds rule as `pickTile`.
##
## SQUARE MAPS ONLY. Hexagons do not tile into smaller hexagons, so a hex map has no cel grade at
## all; its sub-tile detail is the six triangles a hex fans into, which arrives with WMH-10 and
## is not a coordinate this function could return.
static func pickCel(camera: Camera3D, screen: Vector2, curvature: float, region: Rect2) -> Variant:
	var point = surfacePoint(camera, screen, curvature)
	if point == null:
		return null
	var world := point as Vector3
	var local := Vector2(world.x, world.z) - region.position
	if local.x < 0.0 or local.y < 0.0 or local.x >= region.size.x or local.y >= region.size.y:
		return null
	var perTile := float(Uniforms.CELS_PER_TILE)
	return Vector2i(int(floor(local.x * perTile)), int(floor(local.y * perTile)))


## Drives the shader's grid overlay. `cursor` is a tile or cel coordinate to highlight (a hex
## cell, when `hex` is true), or `null` for none. `celGrade` decides whether the finer lines are
## drawn at all -- on a square map that means cel lines, on a hex map the sub-triangle fan --
## so the lattice on screen is always the one the current tool actually edits.
##
## THE HEX CURSOR IS THE HEX'S OWN SILHOUETTE, not its bounding box. An earlier version of this
## function drew the bounding box, honestly marked provisional, because the shader had no hex
## distance field yet; it now does (`hex_edge_distance` in `worldmap_ground.gdshader`), so the
## cursor and the picked cell are drawn from the SAME geometry rather than an approximation of
## it. `WorldMapHexGrid.cellCentre` is the one function both this and the shader's own
## `hex_axial_centre` compute -- `probe_hex_grid_overlay.gd` asserts the two agree rather than
## trusting a hand port of one into the other.
static func applyGrid(
	material: ShaderMaterial, region: Rect2, cursor: Variant, celGrade: bool, visible := true,
	hex := false
) -> void:
	if material == null:
		return
	if not visible:
		material.set_shader_parameter(Uniforms.U_GRID_MODE, Uniforms.GRID_OFF)
		return
	material.set_shader_parameter(Uniforms.U_GRID_HEX, hex)
	material.set_shader_parameter(
		Uniforms.U_GRID_MODE,
		Uniforms.GRID_TILES_AND_CELS if celGrade else Uniforms.GRID_TILES
	)
	if hex:
		if cursor == null:
			material.set_shader_parameter(Uniforms.U_HEX_CURSOR, Vector3.ZERO)
		else:
			var cell := cursor as Vector2i
			var centre := region.position + WorldMapHexGrid.cellCentre(cell)
			material.set_shader_parameter(
				Uniforms.U_HEX_CURSOR, Vector3(centre.x, centre.y, 1.0)
			)
		# Not read while grid_hex is true -- see the shader's own branch -- but cleared rather
		# than left stale, so nothing downstream can be misled by inspecting it directly.
		material.set_shader_parameter(Uniforms.U_CURSOR_RECT, Vector4.ZERO)
		return

	material.set_shader_parameter(Uniforms.U_HEX_CURSOR, Vector3.ZERO)
	if cursor == null:
		material.set_shader_parameter(Uniforms.U_CURSOR_RECT, Vector4.ZERO)
		return
	var cell := cursor as Vector2i
	var size := 1.0 / float(Uniforms.CELS_PER_TILE) if celGrade else 1.0
	var corner := region.position + Vector2(float(cell.x), float(cell.y)) * size
	material.set_shader_parameter(
		Uniforms.U_CURSOR_RECT, Vector4(corner.x, corner.y, size, size)
	)
