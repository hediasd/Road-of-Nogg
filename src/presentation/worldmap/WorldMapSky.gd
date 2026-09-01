## The world map's backdrop: a quad parented to the camera, filling the frustum at a distance
## far beyond the ground plane, so wherever the ground stops the sky shows through.
##
## Not a `WorldEnvironment` sky, and deliberately so. Godot 4 skips environment fog on
## unshaded materials, which is why the ground computes its own haze; adding an environment
## purely for a background would couple the two for nothing. It also keeps the world map's
## background independent of whatever the battle scene wants.
##
## A flat backdrop rather than a dome is sufficient because yaw is pinned to 0 and the camera
## never rolls -- the sky can only ever be seen from one direction.

class_name WorldMapSky
extends MeshInstance3D

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const SKY_SHADER = preload("res://assets/shaders/worldmap_sky.gdshader")

## Far enough to sit behind any ground plane the rig builds (those reach a few hundred units
## at the widest fog band) while staying well inside the camera's 4000 unit far plane.
const DISTANCE := 2000.0
## The quad is made wider than the frustum needs so a change of window aspect cannot reveal
## its edge before the next framing is applied.
const WIDTH_MARGIN := 1.6

var _material: ShaderMaterial


## `camera` supplies the vertical FOV the quad is sized against; `viewport_size` its aspect.
func applyFraming(framing: Dictionary, camera: Camera3D, viewport_size: Vector2) -> void:
	var complete := Uniforms.complete(framing)
	var skyID := str(complete[Uniforms.K_SKY])
	visible = skyID != Uniforms.SKY_OFF
	if not visible:
		return

	_ensureMaterial()
	var texture := WorldMapSkyCatalog.textureFor(skyID)
	if texture == null:
		visible = false
		return
	_material.set_shader_parameter("sky_texture", texture)
	_material.set_shader_parameter("sky_offset", complete[Uniforms.K_SKY_OFFSET])
	_material.set_shader_parameter("sky_scale", complete[Uniforms.K_SKY_SCALE])
	_material.set_shader_parameter("sky_tint", complete[Uniforms.K_SKY_TINT])

	var height := 2.0 * DISTANCE * tan(deg_to_rad(camera.fov) * 0.5)
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var plane := mesh as QuadMesh
	plane.size = Vector2(height * aspect * WIDTH_MARGIN, height)
	# Local to the camera, so it follows every pan without any per-frame work.
	position = Vector3(0.0, 0.0, -DISTANCE)
	rotation = Vector3.ZERO


func _ensureMaterial() -> void:
	if mesh == null:
		mesh = QuadMesh.new()
	if _material != null:
		return
	_material = ShaderMaterial.new()
	_material.shader = SKY_SHADER
	material_override = _material
