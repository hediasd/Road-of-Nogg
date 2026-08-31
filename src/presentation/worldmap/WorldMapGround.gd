## The world map's ground plane: a subdivided quad carrying the region texture.
##
## Sized from a region's tile dimensions at one tile to one world unit, and made
## deliberately LARGER than the region so the fog has somewhere to close before the art
## runs out. Where the plane extends past the art the shader substitutes the void colour;
## see `docs/WORLDMAP_DESIGN.md` §4.
##
## This node owns geometry and material only. Framing lives in `WorldMapCameraRig`, and
## the two are kept apart so the rig can be driven without a material and the material
## previewed without a camera.

class_name WorldMapGround
extends MeshInstance3D

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const GROUND_SHADER = preload("res://assets/shaders/worldmap_ground.gdshader")

## Curvature is a quadratic, so it needs far fewer segments than its span suggests to look
## smooth -- 64 holds up at the explorer's maximum k of 0.02 across a 250-unit plane. This
## is the only thing subdivision is for; a flat plane would be fine at 1.
const PLANE_SUBDIVISIONS := 64

## How far past the region the plane extends, as a multiple of the framing's fog end. One
## full fog length on each side guarantees geometry everywhere the fog has not yet closed,
## which is what stops the plane's own edge from appearing before the void colour can.
const FOG_MARGIN_FACTOR := 1.0

var region_tiles := Vector2i(48, 64)
var region_origin := Vector2.ZERO
var region_size := Vector2(48.0, 64.0)

var _material: ShaderMaterial


## Builds the plane for a region and applies a framing. Safe to call again with a
## different region or framing; the mesh is rebuilt only when the size actually changes.
func configure(tiles: Vector2i, texture: Texture2D, framing: Dictionary) -> void:
	var complete := Uniforms.complete(framing)
	region_tiles = tiles
	# One tile is one world unit, so the region's world size IS its tile count. Going
	# through units_per_map_pixel rather than asserting that keeps the convention in one
	# place -- see WORLDMAP_DESIGN.md section 1.
	var units_per_pixel: float = complete[Uniforms.K_UNITS_PER_MAP_PIXEL]
	region_size = Vector2(
		float(tiles.x * Uniforms.TILE_PIXELS) * units_per_pixel,
		float(tiles.y * Uniforms.TILE_PIXELS) * units_per_pixel
	)
	region_origin = Vector2.ZERO

	var margin: float = float(complete[Uniforms.K_FOG_END]) * FOG_MARGIN_FACTOR
	_rebuildMesh(region_size + Vector2(margin, margin) * 2.0)

	_ensureMaterial()
	for sampler in Uniforms.REGION_SAMPLERS:
		_material.set_shader_parameter(sampler, texture)
	Uniforms.applyToMaterial(_material, complete, region_origin, region_size)


## Re-applies framing without touching the mesh or the texture. This is the call the debug
## scene makes on every control change, so it must stay allocation-free.
func applyFraming(framing: Dictionary) -> void:
	_ensureMaterial()
	Uniforms.applyToMaterial(_material, framing, region_origin, region_size)


## World-space rectangle the region art occupies, for the camera rig's pan clamp.
func regionRect() -> Rect2:
	return Rect2(region_origin, region_size)


func _rebuildMesh(plane_size: Vector2) -> void:
	var plane := mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		mesh = plane
	elif plane.size.is_equal_approx(plane_size):
		return
	plane.size = plane_size
	plane.subdivide_width = PLANE_SUBDIVISIONS
	plane.subdivide_depth = PLANE_SUBDIVISIONS
	# PlaneMesh is centred on its origin; the shader locates the region in world space from
	# region_origin, so the plane is placed to keep the region centred within its margin.
	position = Vector3(
		region_origin.x + region_size.x * 0.5, 0.0, region_origin.y + region_size.y * 0.5
	)


func _ensureMaterial() -> void:
	if _material != null:
		return
	_material = ShaderMaterial.new()
	_material.shader = GROUND_SHADER
	material_override = _material
