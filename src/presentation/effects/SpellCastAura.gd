## SpellCastAura — Spawns a transient, element-tinted ground aura burst
## when a monster casts a spell.
##
## Composition:
##   1. Ground decal  — flat PlaneMesh + spell_aura.gdshader.
##                      A single `lifetime_progress` tween (0→1) drives the
##                      entire animation: center flash → ring expansion → fade.
##   2. Rising wisps  — GPUParticles3D with a soft vertically-blurred glow
##                      texture. Small number of particles, additive billboard.
##
## Usage (unchanged):
##   SpellCastAura.spawn(parent_node, world_position, element_color)
##
## The container auto-frees after CLEANUP_DELAY seconds.

class_name SpellCastAura

const _SPELL_AURA_SHADER = preload("res://assets/shaders/spell_aura.gdshader")

## How long the aura is actually *visible* — the `lifetime_progress` tween and
## the wisp particles both run for this long. Public because the animation
## queue has to know how long this effect occupies the screen; it spawns
## outside the caster's own tween, so the tween's duration says nothing about
## it.
const VISIBLE_DURATION := 1.1

## Total duration before the container frees itself. Must stay ≥
## VISIBLE_DURATION so cleanup never cuts the animation short.
const _CLEANUP_DELAY := 1.4

## Shared noise texture — created once across all aura instances.
static var _noise_tex: NoiseTexture2D = null

## Shared wisp glow texture — a vertically elongated radial gradient.
static var _wisp_tex: GradientTexture2D = null


static func spawn(parent: Node3D, world_pos: Vector3, element_color: Color) -> void:
	_ensure_shared_resources()

	var container := Node3D.new()
	container.name = "SpellCastAura"
	container.position = world_pos
	parent.add_child(container)

	_add_ground_decal(container, element_color)
	_add_rising_wisps(container, element_color)

	container.get_tree().create_timer(_CLEANUP_DELAY).timeout.connect(
		func() -> void:
			if is_instance_valid(container):
				container.queue_free()
	)


# ---------------------------------------------------------------------------
# Shared resource init
# ---------------------------------------------------------------------------

static func _ensure_shared_resources() -> void:
	# Noise texture — simplex for organic, cloud-like distortion.
	if _noise_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 2.8
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3

		var tex := NoiseTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.seamless = true
		tex.noise = noise
		_noise_tex = tex

	# Wisp texture — a tall, narrow radial gradient for soft elongated particles.
	if _wisp_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))  # opaque center
		grad.add_point(0.55, Color(1.0, 1.0, 1.0, 0.4))
		grad.set_color(2, Color(1.0, 1.0, 1.0, 0.0))  # transparent edge

		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 32
		tex.height = 64  # taller than wide = elongated wisp shape
		_wisp_tex = tex


# ---------------------------------------------------------------------------
# Layer 1: Ground decal
# ---------------------------------------------------------------------------

static func _add_ground_decal(parent: Node3D, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GroundDecal"

	# Flat plane laid at ground level. Size 2×2 world units covers one tile.
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mesh_inst.mesh = plane
	mesh_inst.position.y = 0.025  # just above the tile surface

	# Shader material.
	var mat := ShaderMaterial.new()
	mat.shader = _SPELL_AURA_SHADER
	mat.set_shader_parameter("aura_color", color)
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mat.set_shader_parameter("lifetime_progress", 0.0)
	mat.set_shader_parameter("intensity", 6.0)
	mat.set_shader_parameter("ring_width", 0.13)
	mat.set_shader_parameter("edge_distortion", 0.07)
	mat.set_shader_parameter("scroll_speed", 0.4)
	mesh_inst.material_override = mat

	parent.add_child(mesh_inst)

	# Tween lifetime_progress from 0 → 1 over the aura's lifespan.
	# The shader handles everything: flash → ring expand → fade.
	var tween := parent.create_tween()
	tween.tween_property(mat, "shader_parameter/lifetime_progress", 1.0, VISIBLE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Layer 2: Rising wisps
# ---------------------------------------------------------------------------

static func _add_rising_wisps(parent: Node3D, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "RisingWisps"
	particles.amount = 7
	particles.lifetime = VISIBLE_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.5
	particles.randomness = 0.6

	var mat := ParticleProcessMaterial.new()
	# Emit from a ring at ground level to match where the aura ring appears.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 0.38
	mat.emission_ring_inner_radius = 0.18
	mat.emission_ring_height = 0.04
	mat.emission_ring_axis = Vector3(0.0, 1.0, 0.0)

	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 15.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0.0, 0.2, 0.0)  # slight upward drift
	mat.damping_min = 0.2
	mat.damping_max = 0.6

	# Scale variation for visual diversity.
	mat.scale_min = 0.7
	mat.scale_max = 1.5

	# Colour: element tint at full brightness → transparent.
	var bright := color.lightened(0.5)
	bright.a = 1.0
	mat.color = bright

	# Fade out over lifetime via color_ramp.
	var grad := Gradient.new()
	var c0 := bright; c0.a = 1.0
	var c1 := bright; c1.a = 0.0
	grad.set_color(0, c0)
	grad.add_point(0.55, Color(c0.r, c0.g, c0.b, 0.6))
	grad.set_color(2, c1)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = grad
	mat.color_ramp = ramp_tex

	particles.process_material = mat

	# Draw with the elongated wisp glow texture.
	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.10, 0.22)
	particles.draw_pass_1 = draw_mesh

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	draw_mat.albedo_texture = _wisp_tex
	draw_mat.emission_enabled = true
	draw_mat.emission = color.lightened(0.4)
	draw_mat.emission_energy_multiplier = 3.0
	draw_mat.emission_texture = _wisp_tex
	particles.material_override = draw_mat

	parent.add_child(particles)
	particles.emitting = true
