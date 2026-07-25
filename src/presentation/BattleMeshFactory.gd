## BattleMeshFactory — Creates placeholder meshes and elemental materials.

class_name BattleMeshFactory


static func elementColor(element: String) -> Color:
	match element.to_lower():
		"fire": return Color(0.9, 0.2, 0.2)
		"water", "ice": return Color(0.2, 0.7, 0.9)
		"earth", "nature", "wood": return Color(0.2, 0.7, 0.2)
		"electric", "lightning", "thunder": return Color(0.9, 0.9, 0.1)
		"dark", "darkness": return Color(0.4, 0.1, 0.6)
		"light": return Color(0.9, 0.9, 0.8)
		"steel": return Color(0.6, 0.6, 0.75)
		_: return Color(0.5, 0.5, 0.5)


static func createHalfMaterial(color1: Color, color2: Color) -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	uniform vec4 color1 : source_color;
	uniform vec4 color2 : source_color;
	uniform float metallic = 0.0;
	uniform float roughness = 1.0;
	varying vec3 local_pos;
	void vertex() {
		local_pos = VERTEX;
	}
	void fragment() {
		METALLIC = metallic;
		ROUGHNESS = roughness;
		SPECULAR = 0.5;

		if (local_pos.y - local_pos.x < 0.0) {
			ALBEDO = color1.rgb;
		} else {
			ALBEDO = color2.rgb;
		}
	}
	"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("color1", color1)
	material.set_shader_parameter("color2", color2)
	material.set_shader_parameter("metallic", 0.0)
	material.set_shader_parameter("roughness", 1.0)
	return material


static func createMesh(type: String, color: Color) -> MeshInstance3D:
	var meshInstance = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0

	match type:
		"cursor":
			meshInstance.mesh = PlaneMesh.new()
			meshInstance.mesh.size = Vector2(1.1, 1.1)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.emission_enabled = true
			material.emission = color
		"box":
			meshInstance.mesh = BoxMesh.new()
			meshInstance.mesh.size = Vector3(0.9, 0.4, 0.9)
		"plane":
			meshInstance.mesh = PlaneMesh.new()
			meshInstance.mesh.size = Vector2(0.9, 0.9)
		"cylinder":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 1.0
			meshInstance.mesh.top_radius = 0.3
			meshInstance.mesh.bottom_radius = 0.3
		"capsule_base":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 0.2
			meshInstance.mesh.top_radius = 0.45
			meshInstance.mesh.bottom_radius = 0.45
		"shape_sphere":
			meshInstance.mesh = SphereMesh.new()
			meshInstance.mesh.radius = 0.4
		"shape_cube":
			meshInstance.mesh = BoxMesh.new()
			meshInstance.mesh.size = Vector3(0.7, 0.7, 0.7)
		"shape_coin":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 0.2
			meshInstance.mesh.top_radius = 0.4
			meshInstance.mesh.bottom_radius = 0.4
		"shape_capsule":
			meshInstance.mesh = CapsuleMesh.new()
			meshInstance.mesh.radius = 0.3
			meshInstance.mesh.height = 0.8
		"shape_pyramid":
			meshInstance.mesh = PrismMesh.new()
			meshInstance.mesh.size = Vector3(0.7, 0.8, 0.7)

	meshInstance.material_override = material
	return meshInstance
