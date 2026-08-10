## Deterministic, previewable magenta implosion composed from procedural layers.
##
## Forked from `FireStormEffect`, which is itself a sibling of `IceStormEffect`:
## same `VfxPlayback` contract, same seed/scrub/dispose lifecycle, same
## build-time budget asserts. `MagentaReductionProfile`'s header records why this
## is a third forked file rather than the shared resource `docs/VFX_DESIGN.md` §4
## schedules for the third effect, and `BACKLOG_LONGTERM.md` carries the restated
## trigger.
##
## What differs from the fire storm: the motion runs inward instead of outward,
## on a four-beat timeline (gather, spiral, charge, discharge) rather than one
## continuous arc; the smoke crown has no equivalent here and is gone, which is
## what frees the node budget for the core and the discharge; and the discharge
## streaks are laid flat in the ground plane rather than billboarded, because a
## quad cannot be both aligned to its travel direction and facing the camera.

class_name MagentaReductionEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _IMPLOSION_SHADER = preload("res://assets/shaders/effects/magenta_implosion.gdshader")

const LAYER_GROUND_WASH := "ground_wash"
const LAYER_MOTES := "motes"
const LAYER_CORE := "core"
const LAYER_DISCHARGE := "discharge"
const LAYER_SPARKS := "sparks"
const LAYER_SPIRAL := "spiral"
const LAYER_WINDUP := "windup"
const LAYER_TWINKLE := "twinkle"

## Mirrors the shader's `layer_mode` uniform.
const _MODE_MOTES := 0.0
const _MODE_DISCHARGE := 1.0
const _MODE_SPARKS := 2.0

var _elapsedTime := 0.0
var _totalDuration := MagentaReductionProfile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 1
var _mode := MODE_BATTLE
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _intensityScale := 1.0
var _footprintRadius := MagentaReductionProfile.REFERENCE_CARRIER_RADIUS_TILES
var _groundSpan := 0.0
## Matches `Spell.area_shape` / `data/spells.json`'s `AREA_SHAPE`. Defaults to
## "circle", the same default `SpellReferences` normalizes onto every spell
## reference, which `ShapeCaster.getCircle` actually renders as a Manhattan
## diamond. See `_isDiamondShape()`.
var _areaShape := "circle"

var _groundWash: MeshInstance3D
var _groundMesh: CylinderMesh
var _groundMaterial: StandardMaterial3D
var _coreNodes: Array[MeshInstance3D] = []
var _coreMeshes: Array[QuadMesh] = []
var _coreMaterials: Array[StandardMaterial3D] = []
var _motes: GPUParticles3D
var _motesMaterial: ShaderMaterial
var _discharge: GPUParticles3D
var _dischargeMaterial: ShaderMaterial
var _sparks: GPUParticles3D
var _sparksMaterial: ShaderMaterial
var _layerVisibility := {
	LAYER_GROUND_WASH: true,
	LAYER_MOTES: true,
	LAYER_CORE: true,
	LAYER_DISCHARGE: true,
	LAYER_SPARKS: true,
	LAYER_SPIRAL: true,
	LAYER_WINDUP: true,
	LAYER_TWINKLE: true,
}


static func spawn(
		parent: Node3D,
		worldPosition: Vector3,
		seed: int,
		mode: String = MODE_BATTLE) -> MagentaReductionEffect:
	var playback := createPlayback(parent, worldPosition, Color.WHITE)
	playback._autoDispose = true
	playback.play(seed, mode)
	return playback


## `_elementColor` is accepted to satisfy the catalog's factory signature and
## deliberately ignored, exactly as both storms do: this profile owns its own
## palette. That matters more here than for them — the carrier's elements are
## water and fire, and tinting by either would produce the blue-half/orange-half
## split the design explicitly rules out. The spell is named for the colour its
## reaction makes, not for its inputs.
static func createPlayback(
		parent: Node3D,
		worldPosition: Vector3,
		_elementColor: Color) -> MagentaReductionEffect:
	var playback := MagentaReductionEffect.new()
	playback.name = "MagentaReductionEffect"
	playback.position = worldPosition
	parent.add_child(playback)
	playback._buildLayers()
	return playback


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed MagentaReductionEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_mode = mode
	_totalDuration = (
			MagentaReductionProfile.REFERENCE_DURATION_SECONDS
			if mode == MODE_REFERENCE
			else MagentaReductionProfile.BATTLE_DURATION_SECONDS)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_configureSeed(seed)
	_updateVisuals(0.0)
	_restartEmittersAt(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)
	var emitterScale := _playbackScale if _playing else 0.0
	if _motes != null:
		_motes.speed_scale = emitterScale
	if _discharge != null:
		_discharge.speed_scale = emitterScale


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * _totalDuration
	_finished = normalizedTime >= 1.0
	_playing = not _finished
	_updateVisuals(normalizedTime)
	_restartEmittersAt(_elapsedTime)
	if _finished:
		_finishPlayback()


func skip_to_settle() -> void:
	seek_normalized(MagentaReductionProfile.SETTLE_START_FRACTION)


func get_normalized_time() -> float:
	return clampf(_elapsedTime / maxf(_totalDuration, 0.001), 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return _totalDuration


func is_finished() -> bool:
	return _finished


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_playing = false
	set_process(false)
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.emitting = false
		emitter.speed_scale = 0.0
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		free()


func get_layer_names() -> Array[String]:
	return [
		LAYER_GROUND_WASH,
		LAYER_MOTES,
		LAYER_CORE,
		LAYER_DISCHARGE,
		LAYER_SPARKS,
		LAYER_SPIRAL,
		LAYER_WINDUP,
		LAYER_TWINKLE,
	]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if not _layerVisibility.has(layerName):
		push_warning("Unknown MagentaReductionEffect layer: %s" % layerName)
		return
	_layerVisibility[layerName] = visible
	match layerName:
		LAYER_GROUND_WASH:
			_groundWash.visible = visible
		LAYER_MOTES:
			_motes.visible = visible
		LAYER_DISCHARGE:
			_discharge.visible = visible
		LAYER_SPARKS:
			_sparks.visible = visible
		LAYER_CORE:
			for core: MeshInstance3D in _coreNodes:
				core.visible = visible
		LAYER_SPIRAL, LAYER_WINDUP, LAYER_TWINKLE:
			_updateEmitterUniforms()
	_updateVisuals(get_normalized_time())


## Reported against the beats rather than against one global fade, because the
## two emitters are live over different spans: the motes dissipate through the
## first part of the discharge beat, and the discharge itself does not exist
## before it.
func get_live_particle_count() -> int:
	if _finished:
		return 0
	var normalizedTime := get_normalized_time()
	var total := 0
	if _motes != null and _motes.visible:
		var moteDensity := 1.0 - _smoothstep(
				MagentaReductionProfile.CHARGE_END_FRACTION,
				lerpf(
						MagentaReductionProfile.CHARGE_END_FRACTION,
						1.0,
						MagentaReductionProfile.MOTE_DISSIPATE_FRACTION),
				normalizedTime)
		total += roundi(float(_motes.amount) * moteDensity)
	var released := (
			1.0 if normalizedTime >= MagentaReductionProfile.CHARGE_END_FRACTION
			else 0.0)
	if _discharge != null and _discharge.visible:
		total += roundi(float(_discharge.amount) * released)
	if _sparks != null and _sparks.visible:
		total += roundi(float(_sparks.amount) * released)
	return total


func get_live_node_count() -> int:
	return 0 if _disposed else _countNodes(self)


func is_particle_seek_exact() -> bool:
	return true


func setIntensityScale(scale: float) -> void:
	_intensityScale = clampf(scale, 0.0, 1.0)
	_updateVisuals(get_normalized_time())


func getIntensityScale() -> float:
	return _intensityScale


func setFootprint(radius: int, groundSpan: float, areaShape: String = "circle") -> void:
	_footprintRadius = maxi(radius, 1)
	_groundSpan = maxf(groundSpan, 0.0)
	_areaShape = areaShape
	_updateFootprintGeometry()
	_configureSeed(_activeSeed)
	_updateVisuals(get_normalized_time())


func getFootprintRadius() -> int:
	return _footprintRadius


func getGroundSpan() -> float:
	return _groundSpan


func getDrawCallBudgetEstimate() -> int:
	return 1 + _liveEmitters().size() + _coreNodes.size()


func _process(delta: float) -> void:
	if not _playing or _playbackScale <= 0.0:
		return
	_elapsedTime = minf(_elapsedTime + delta * _playbackScale, _totalDuration)
	_updateVisuals(get_normalized_time())
	if _elapsedTime >= _totalDuration:
		_finishPlayback()


func _finishPlayback() -> void:
	_finished = true
	_playing = false
	set_process(false)
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.emitting = false
		emitter.speed_scale = 0.0
	if _autoDispose and not _disposed:
		call_deferred("dispose")


func _liveEmitters() -> Array[GPUParticles3D]:
	var emitters: Array[GPUParticles3D] = []
	if _motes != null:
		emitters.append(_motes)
	if _discharge != null:
		emitters.append(_discharge)
	if _sparks != null:
		emitters.append(_sparks)
	return emitters


func _buildLayers() -> void:
	_buildGroundWash()
	_buildCore()
	_buildEmitters()
	_updateFootprintGeometry()
	_configureSeed(_activeSeed)
	_updateVisuals(0.0)
	set_process(false)
	assert(get_live_node_count() <= MagentaReductionProfile.MAX_EFFECT_NODES)
	assert(getDrawCallBudgetEstimate() <= MagentaReductionProfile.MAX_DRAW_CALLS)
	assert(
			_motes.amount + _discharge.amount + _sparks.amount
			<= MagentaReductionProfile.MAX_LIVE_PARTICLES)
	# The shader splits INDEX into a bolt and a segment along it, so an amount
	# that is not exactly bolts x segments would leave a partial chain dangling
	# off the end of the field.
	assert(
			_discharge.amount
			== (MagentaReductionProfile.BOLT_TOTAL_COUNT
					* MagentaReductionProfile.BOLT_SEGMENTS))
	# The accumulation loop in `magenta_implosion.gdshader` is bounded at compile
	# time; a longer chain would silently stop walking partway and every bolt
	# would break at the same segment.
	assert(MagentaReductionProfile.BOLT_SEGMENTS <= 8)


func _buildGroundWash() -> void:
	_groundWash = MeshInstance3D.new()
	_groundWash.name = "GroundWash"
	_groundMesh = CylinderMesh.new()
	_groundMesh.radial_segments = 32
	_groundMesh.rings = 1
	_groundWash.mesh = _groundMesh
	_groundMaterial = VfxTextures.groundWashMaterial().duplicate() as StandardMaterial3D
	# Nearest on this effect's *duplicate* only. The shared factory stays linear
	# because both storms use it and neither is a pixel-art effect — changing it
	# there would quietly restyle them.
	_groundMaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_groundWash.material_override = _groundMaterial
	add_child(_groundWash)


## Index 0 is the core proper and index 1 the halo around it. The two use
## different shared textures on purpose: the core takes the nearest-filtered
## flake, whose hard edge is the reference language's, and the halo takes the
## linear-filtered puff, so the blow-out has something soft to bloom into
## instead of ending on a hard rim.
func _buildCore() -> void:
	for index: int in range(MagentaReductionProfile.CORE_QUAD_COUNT):
		var core := MeshInstance3D.new()
		core.name = "Core%d" % index
		var mesh := QuadMesh.new()
		core.mesh = mesh
		var material := (
				VfxTextures.flurryMaterial().duplicate() as StandardMaterial3D
				if index == 0
				else VfxTextures.canopyMaterial().duplicate() as StandardMaterial3D)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Nearest on the duplicates only; see `_buildGroundWash()`. The halo's
		# canopy texture is linear-filtered at source and would otherwise be the
		# one soft-edged thing left in the effect.
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		core.material_override = material
		_coreNodes.append(core)
		_coreMeshes.append(mesh)
		_coreMaterials.append(material)
		add_child(core)


func _buildEmitters() -> void:
	# Hard dots rather than stars. The star sprite spends most of its area on
	# thin spikes, so at mote size it read as a faint smudge — countable specks
	# need an edge, and `pixelDot()` is two hard levels on an 8x8 grid. The stars
	# survive on the sparks layer, where they are large enough to resolve.
	_motes = _createEmitter(
			"Motes",
			MagentaReductionProfile.MOTE_PARTICLE_AMOUNT,
			VfxTextures.pixelDotMaterial(),
			BaseMaterial3D.BILLBOARD_ENABLED)
	_motesMaterial = _motes.process_material as ShaderMaterial
	_discharge = _createEmitter(
			"Discharge",
			MagentaReductionProfile.DISCHARGE_PARTICLE_AMOUNT,
			VfxTextures.boltSegmentMaterial(),
			BaseMaterial3D.BILLBOARD_DISABLED)
	_dischargeMaterial = _discharge.process_material as ShaderMaterial
	# BILLBOARD_PARTICLES, not BILLBOARD_ENABLED: it is the only mode whose
	# generated shader reads `INSTANCE_CUSTOM.z` and offsets `UV` into the
	# animation grid. Under any other mode the shader's `CUSTOM.z` is ignored and
	# every spark freezes on frame 0, with nothing reporting a problem.
	_sparks = _createEmitter(
			"Sparks",
			MagentaReductionProfile.SPARK_PARTICLE_AMOUNT,
			VfxTextures.sparkleFramesMaterial(),
			BaseMaterial3D.BILLBOARD_PARTICLES)
	_sparksMaterial = _sparks.process_material as ShaderMaterial
	# The two camera-plane layers ignore depth. Both are built in the plane the
	# viewer sees rather than in the world, and a bolt heading *downward* on
	# screen passes below the board and gets depth-tested away by terrain in
	# front of it — which ate close to half the burst, asymmetrically, chosen by
	# whatever happened to be standing nearby. Depth testing buys nothing for a
	# layer that already has no spatial grounding, and costs the release its
	# shape. The motes, core and ground wash keep theirs; they are world-space
	# and are supposed to sit among the terrain.
	_disableDepthTest(_discharge)
	_disableDepthTest(_sparks)


static func _disableDepthTest(emitter: GPUParticles3D) -> void:
	var drawMesh := emitter.draw_pass_1 as QuadMesh
	var drawMaterial := drawMesh.material as StandardMaterial3D
	drawMaterial.no_depth_test = true


## `billboardMode` is DISABLED for the discharge alone. Its shader builds an
## oriented basis laying each bolt segment flat in the ground plane along its
## travel direction, and any billboard mode overwrites that basis outright —
## which would collapse every segment back into a camera-facing square and throw
## away the whole point of a directional texture.
func _createEmitter(
		emitterName: String,
		amount: int,
		baseMaterial: StandardMaterial3D,
		billboardMode: BaseMaterial3D.BillboardMode) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = emitterName
	emitter.amount = amount
	emitter.lifetime = 1.0
	emitter.preprocess = 1.0
	emitter.randomness = 0.0
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.fract_delta = true
	emitter.local_coords = true
	emitter.use_fixed_seed = true
	emitter.visibility_aabb = _footprintAabb()
	var shaderMaterial := ShaderMaterial.new()
	shaderMaterial.shader = _IMPLOSION_SHADER
	emitter.process_material = shaderMaterial
	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2.ONE
	var drawMaterial := baseMaterial.duplicate() as StandardMaterial3D
	# The shared flurry material is built ice-tinted, and `_createMaterial` sets
	# `vertex_color_use_as_albedo`, so its albedo would multiply against the
	# per-particle colour this shader writes to COLOR and drag the whole magenta
	# palette blue. Neutralising albedo and emission to white lets the shader own
	# the palette outright. The lance material is already white, but it is
	# neutralised on the same path rather than trusted to stay that way.
	drawMaterial.albedo_color = Color.WHITE
	drawMaterial.emission = Color.WHITE
	drawMaterial.billboard_mode = billboardMode
	if billboardMode == BaseMaterial3D.BILLBOARD_DISABLED:
		# A shader-oriented quad can end up wound either way depending on the
		# basis it is given, and a backface-culled additive layer fails silently.
		# Nothing here writes depth or lights a surface, so culling buys nothing
		# and costs an invisible layer the next time the basis is edited.
		drawMaterial.cull_mode = BaseMaterial3D.CULL_DISABLED
	drawMesh.material = drawMaterial
	emitter.draw_pass_1 = drawMesh
	add_child(emitter)
	return emitter


## Sized from the footprint so the field is never culled at a large radius, with
## headroom for the core halo above it. The height derives from the mote band's
## own ceiling rather than being a fixed bound, so it cannot be outgrown at a
## radius nobody tested.
func _footprintAabb() -> AABB:
	var diameter := float(_footprintRadius * 2 + 1)
	var bandCeiling := (
			(float(_footprintRadius) + 0.5)
			* MagentaReductionProfile.MOTE_HEIGHT_MAX_FRACTION)
	var height := maxf(bandCeiling, MagentaReductionProfile.FIELD_HEIGHT_U) + 0.6
	return AABB(
			Vector3(-diameter * 0.7, -0.2, -diameter * 0.7),
			Vector3(diameter * 1.4, height, diameter * 1.4))


func _updateFootprintGeometry() -> void:
	if _groundMesh == null:
		return
	var diameter := float(_footprintRadius * 2 + 1)
	_groundMesh.top_radius = diameter * 0.5
	_groundMesh.bottom_radius = diameter * 0.5
	_groundMesh.height = maxf(_groundSpan + 0.06, 0.06)
	_groundWash.position.y = 0.0
	var groundTexture := VfxTextures.groundWash(
			VfxTextures.groundWashShapeFor(_areaShape), _footprintRadius)
	_groundMaterial.albedo_texture = groundTexture
	_groundMaterial.emission_texture = groundTexture
	# Mostly fixed size, with a small footprint-proportional term. See
	# CORE_BASE_SIZE_U: the core is what the charge is read off, so it has to
	# stay legible at radius 1 without vanishing into a radius-5 field.
	var coreSize := (
			MagentaReductionProfile.CORE_BASE_SIZE_U
			+ float(_footprintRadius) * MagentaReductionProfile.CORE_FOOTPRINT_SIZE_FRACTION)
	var coreHeight := (
			(float(_footprintRadius) + 0.5)
			* MagentaReductionProfile.CORE_HEIGHT_FRACTION)
	for index: int in range(_coreMeshes.size()):
		var scale := (
				1.0 if index == 0 else MagentaReductionProfile.CORE_HALO_SCALE)
		_coreMeshes[index].size = Vector2.ONE * coreSize * scale
		_coreNodes[index].position.y = coreHeight
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.visibility_aabb = _footprintAabb()
	_updateEmitterUniforms()


## The camera's right and up axes, expressed in this effect's local basis, which
## is the plane the discharge bolts are built in.
##
## Screen-space angle quantization is the whole reason this is needed: the bolts
## snap their headings to 45-degree steps, and those steps only land on the pixel
## grid if they are measured in the plane the viewer actually sees. Passing the
## basis as a uniform is the only route — a particles process shader has no
## access to the camera matrix.
##
## This does make the bolts' shape depend on where the camera is pointing, which
## is inherent to any camera-facing effect and harmless for a fixed battle
## camera. Determinism is unaffected: the basis is read from scene state, never
## accumulated, so a given camera and timestamp still reproduce exactly — which
## is what golden capture relies on.
##
## Falls back to world axes when there is no camera, which is the case during
## `--import` parsing and in headless harnesses.
func _cameraPlaneBasis() -> Array:
	var camera: Camera3D = null
	if is_inside_tree():
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return [Vector3.RIGHT, Vector3.UP]
	var localise := global_transform.basis.inverse()
	var cameraBasis := camera.global_transform.basis
	return [
		(localise * cameraBasis.x).normalized(),
		(localise * cameraBasis.y).normalized(),
	]


## The mote field, the core and the discharge all derive their variation inside
## the shader from `vfx_seed`, so unlike the storms there is no GDScript-side
## random placement left to configure. Kept as a hook because `play()` and
## `setFootprint()` both call it and the seed still has to reach the emitters.
func _configureSeed(_seed: int) -> void:
	_updateEmitterUniforms()


func _updateVisuals(normalizedTime: float) -> void:
	if _groundMaterial == null:
		return
	var onset := _smoothstep(
			0.0, MagentaReductionProfile.ONSET_FRACTION, normalizedTime)
	var brightness := _coreBrightness(normalizedTime)
	var hotAmount := _smoothstep(
			MagentaReductionProfile.CHARGE_END_FRACTION
			- MagentaReductionProfile.CORE_HOT_ONSET_FRACTION,
			MagentaReductionProfile.CHARGE_END_FRACTION,
			normalizedTime)

	var washFade := 1.0 - _smoothstep(
			MagentaReductionProfile.WASH_FADE_START_FRACTION,
			MagentaReductionProfile.WASH_FADE_END_FRACTION,
			normalizedTime)
	_setMaterialOpacity(
			_groundMaterial,
			MagentaReductionProfile.GROUND_WASH_COLOR,
			onset * washFade)
	# The floor flares with the core rather than sitting flat under it, so the
	# release reads as coming out of the ground the field was gathered from.
	_groundMaterial.emission_energy_multiplier = lerpf(
			1.0,
			MagentaReductionProfile.GROUND_WASH_FLARE_MULTIPLIER,
			clampf(brightness, 0.0, 1.0))

	var coreColor := MagentaReductionProfile.CORE_COLOR.lerp(
			MagentaReductionProfile.CORE_HOT_COLOR, hotAmount)
	for index: int in range(_coreNodes.size()):
		# The halo carries less of the peak than the core does, so the blow-out
		# has a bright centre inside a dimmer bloom rather than reading as one
		# flat disc of light.
		var layerAmount := (
				1.0 if index == 0
				else 1.0 / MagentaReductionProfile.CORE_HALO_SCALE)
		_setMaterialOpacity(
				_coreMaterials[index], coreColor, brightness * layerAmount)
		_coreMaterials[index].emission_energy_multiplier = maxf(brightness, 0.0)

	_updateEmitterUniforms()


## Dim through the gather, ramping late through the charge, blowing out at the
## release and decaying to nothing. Every boundary and every exponent comes from
## the profile so the beat structure can be retimed without touching this.
func _coreBrightness(normalizedTime: float) -> float:
	if normalizedTime <= MagentaReductionProfile.CHARGE_END_FRACTION:
		var chargeProgress := clampf(
				(normalizedTime - MagentaReductionProfile.GATHER_END_FRACTION)
				/ maxf(
						MagentaReductionProfile.CHARGE_END_FRACTION
						- MagentaReductionProfile.GATHER_END_FRACTION,
						0.001),
				0.0, 1.0)
		return lerpf(
				MagentaReductionProfile.CORE_GATHER_BRIGHTNESS,
				MagentaReductionProfile.CORE_CHARGE_BRIGHTNESS,
				pow(chargeProgress, MagentaReductionProfile.CORE_BRIGHTNESS_EXPONENT))
	var dischargeProgress := clampf(
			(normalizedTime - MagentaReductionProfile.CHARGE_END_FRACTION)
			/ maxf(1.0 - MagentaReductionProfile.CHARGE_END_FRACTION, 0.001),
			0.0, 1.0)
	var peak := lerpf(
			MagentaReductionProfile.CORE_CHARGE_BRIGHTNESS,
			MagentaReductionProfile.CORE_DISCHARGE_BRIGHTNESS,
			_smoothstep(0.0, MagentaReductionProfile.CORE_FLASH_RISE_FRACTION, dischargeProgress))
	return peak * (1.0 - _smoothstep(
			MagentaReductionProfile.CORE_FLASH_RISE_FRACTION,
			MagentaReductionProfile.CORE_FLASH_DECAY_FRACTION,
			dischargeProgress))


func _setMaterialOpacity(
		material: StandardMaterial3D,
		baseColor: Color,
		visibility: float) -> void:
	var color := baseColor
	color.a *= clampf(visibility * _intensityScale, 0.0, 1.0)
	material.albedo_color = color
	# `VfxTextures._createMaterial` bakes `emission` once from the material's
	# construction-time colour and never revisits it, so the core's fuchsia-to-hot
	# lerp would otherwise appear only in unlit albedo and not in the additive
	# glow that actually reads as brightness.
	material.emission = Color(baseColor.r, baseColor.g, baseColor.b, 1.0)


func _restartEmittersAt(elapsed: float) -> void:
	_updateEmitterUniforms()
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.speed_scale = 0.0
		emitter.use_fixed_seed = true
		emitter.seed = _activeSeed
		emitter.emitting = true
		emitter.restart(true)
		if elapsed > 0.0:
			emitter.request_particles_process(minf(elapsed, _totalDuration))
		if _finished:
			emitter.emitting = false
		emitter.speed_scale = _playbackScale if _playing else 0.0


func _updateEmitterUniforms() -> void:
	if _motesMaterial == null or _dischargeMaterial == null or _sparksMaterial == null:
		return
	_applyEmitterUniforms(_motesMaterial, _MODE_MOTES)
	_applyEmitterUniforms(_dischargeMaterial, _MODE_DISCHARGE)
	_applyEmitterUniforms(_sparksMaterial, _MODE_SPARKS)


## The two emitters share one shader and differ only in the layer mode passed
## here, so the discharge cannot silently drift out of step with the mote field
## on the footprint clamp, the diamond form, or the beat boundaries.
func _applyEmitterUniforms(material: ShaderMaterial, layerMode: float) -> void:
	# radius_tiles + 0.5, matching the ground wash cylinder's own radius so the
	# field's boundary and the wash's edge agree.
	var footprintRadiusU := float(_footprintRadius) + 0.5
	material.set_shader_parameter("playback_time", _elapsedTime)
	material.set_shader_parameter("total_duration", _totalDuration)
	material.set_shader_parameter("footprint_radius_u", footprintRadiusU)
	material.set_shader_parameter("layer_mode", layerMode)

	material.set_shader_parameter(
			"gather_end_fraction", MagentaReductionProfile.GATHER_END_FRACTION)
	material.set_shader_parameter(
			"spiral_end_fraction", MagentaReductionProfile.SPIRAL_END_FRACTION)
	material.set_shader_parameter(
			"charge_end_fraction", MagentaReductionProfile.CHARGE_END_FRACTION)
	material.set_shader_parameter(
			"onset_fraction", MagentaReductionProfile.ONSET_FRACTION)

	material.set_shader_parameter(
			"swirl_gather_rate", MagentaReductionProfile.SWIRL_GATHER_RATE)
	material.set_shader_parameter(
			"swirl_charge_rate", MagentaReductionProfile.SWIRL_CHARGE_RATE)
	material.set_shader_parameter(
			"windup_start_fraction", MagentaReductionProfile.WINDUP_START_FRACTION)
	material.set_shader_parameter(
			"windup_end_fraction", MagentaReductionProfile.WINDUP_END_FRACTION)
	material.set_shader_parameter(
			"inward_accel_exponent", MagentaReductionProfile.INWARD_ACCEL_EXPONENT)
	material.set_shader_parameter(
			"gather_drift_fraction", MagentaReductionProfile.GATHER_DRIFT_FRACTION)
	material.set_shader_parameter(
			"charge_radius_fraction", MagentaReductionProfile.CHARGE_RADIUS_FRACTION)
	material.set_shader_parameter(
			"charge_compress_fraction", MagentaReductionProfile.CHARGE_COMPRESS_FRACTION)

	material.set_shader_parameter(
			"band_inner_fraction", MagentaReductionProfile.MOTE_BAND_INNER_FRACTION)
	material.set_shader_parameter(
			"phase_spread", MagentaReductionProfile.MOTE_PHASE_SPREAD)

	material.set_shader_parameter("mote_min_size", MagentaReductionProfile.MOTE_MIN_SIZE_U)
	material.set_shader_parameter("mote_max_size", MagentaReductionProfile.MOTE_MAX_SIZE_U)
	material.set_shader_parameter("mote_shrink", MagentaReductionProfile.MOTE_SHRINK)
	material.set_shader_parameter(
			"mote_height_min_fraction",
			MagentaReductionProfile.MOTE_HEIGHT_MIN_FRACTION)
	material.set_shader_parameter(
			"mote_height_max_fraction",
			MagentaReductionProfile.MOTE_HEIGHT_MAX_FRACTION)
	material.set_shader_parameter(
			"mote_sink_fraction", MagentaReductionProfile.MOTE_SINK_FRACTION)
	material.set_shader_parameter(
			"mote_dissipate_fraction", MagentaReductionProfile.MOTE_DISSIPATE_FRACTION)
	material.set_shader_parameter("mote_alpha", MagentaReductionProfile.MOTE_ALPHA)

	material.set_shader_parameter(
			"twinkle_rate_min", MagentaReductionProfile.TWINKLE_RATE_MIN)
	material.set_shader_parameter(
			"twinkle_rate_max", MagentaReductionProfile.TWINKLE_RATE_MAX)
	material.set_shader_parameter(
			"twinkle_sharpness", MagentaReductionProfile.TWINKLE_SHARPNESS)
	material.set_shader_parameter(
			"twinkle_depth", MagentaReductionProfile.TWINKLE_DEPTH)
	material.set_shader_parameter(
			"twinkle_size_depth", MagentaReductionProfile.TWINKLE_SIZE_DEPTH)
	material.set_shader_parameter(
			"bright_fraction", MagentaReductionProfile.MOTE_BRIGHT_FRACTION)
	material.set_shader_parameter(
			"bright_size_scale", MagentaReductionProfile.MOTE_BRIGHT_SIZE_SCALE)
	material.set_shader_parameter(
			"bright_alpha_scale", MagentaReductionProfile.MOTE_BRIGHT_ALPHA_SCALE)
	material.set_shader_parameter(
			"mote_outer_color", MagentaReductionProfile.MOTE_OUTER_COLOR)
	material.set_shader_parameter(
			"mote_inner_color", MagentaReductionProfile.MOTE_INNER_COLOR)

	material.set_shader_parameter(
			"discharge_width", MagentaReductionProfile.DISCHARGE_WIDTH_U)
	material.set_shader_parameter(
			"bolt_angle_steps", float(MagentaReductionProfile.BOLT_ANGLE_STEPS))
	var planeBasis := _cameraPlaneBasis()
	material.set_shader_parameter("camera_right", planeBasis[0])
	material.set_shader_parameter("camera_up", planeBasis[1])
	material.set_shader_parameter(
			"discharge_length_fraction",
			MagentaReductionProfile.DISCHARGE_LENGTH_FRACTION)
	material.set_shader_parameter(
			"discharge_lance_count",
			float(MagentaReductionProfile.DISCHARGE_LANCE_COUNT))
	material.set_shader_parameter(
			"discharge_speed", MagentaReductionProfile.DISCHARGE_SPEED)
	material.set_shader_parameter(
			"discharge_angular_jitter", MagentaReductionProfile.DISCHARGE_ANGULAR_JITTER)
	material.set_shader_parameter(
			"discharge_stagger_fraction",
			MagentaReductionProfile.DISCHARGE_STAGGER_FRACTION)
	material.set_shader_parameter(
			"discharge_height_fraction",
			MagentaReductionProfile.DISCHARGE_HEIGHT_FRACTION)
	material.set_shader_parameter(
			"discharge_alpha", MagentaReductionProfile.DISCHARGE_ALPHA)
	material.set_shader_parameter(
			"discharge_length_variance",
			MagentaReductionProfile.DISCHARGE_LENGTH_VARIANCE)
	material.set_shader_parameter(
			"discharge_alpha_variance",
			MagentaReductionProfile.DISCHARGE_ALPHA_VARIANCE)
	material.set_shader_parameter(
			"discharge_height_variance",
			MagentaReductionProfile.DISCHARGE_HEIGHT_VARIANCE)

	material.set_shader_parameter(
			"bolt_segments", float(MagentaReductionProfile.BOLT_SEGMENTS))
	material.set_shader_parameter(
			"bolt_turn_chance", MagentaReductionProfile.BOLT_TURN_CHANCE)
	material.set_shader_parameter(
			"bolt_straighten", MagentaReductionProfile.BOLT_STRAIGHTEN)
	material.set_shader_parameter(
			"bolt_length_overshoot", MagentaReductionProfile.BOLT_LENGTH_OVERSHOOT)
	material.set_shader_parameter(
			"bolt_color_bias", MagentaReductionProfile.BOLT_COLOR_BIAS)
	material.set_shader_parameter(
			"bolt_tip_width_fraction",
			MagentaReductionProfile.BOLT_TIP_WIDTH_FRACTION)
	material.set_shader_parameter(
			"bolt_strobe_rate", MagentaReductionProfile.BOLT_STROBE_RATE)
	material.set_shader_parameter(
			"bolt_strobe_sharpness", MagentaReductionProfile.BOLT_STROBE_SHARPNESS)
	material.set_shader_parameter(
			"bolt_strobe_depth", MagentaReductionProfile.BOLT_STROBE_DEPTH)
	material.set_shader_parameter(
			"bolt_fork_count", float(MagentaReductionProfile.BOLT_FORK_COUNT))
	material.set_shader_parameter(
			"bolt_fork_length_fraction",
			MagentaReductionProfile.BOLT_FORK_LENGTH_FRACTION)
	material.set_shader_parameter(
			"bolt_fork_width_fraction",
			MagentaReductionProfile.BOLT_FORK_WIDTH_FRACTION)
	material.set_shader_parameter(
			"bolt_fork_deviation", MagentaReductionProfile.BOLT_FORK_DEVIATION)

	material.set_shader_parameter("spark_scatter", MagentaReductionProfile.SPARK_SCATTER)
	material.set_shader_parameter(
			"spark_min_size", MagentaReductionProfile.SPARK_MIN_SIZE_FRACTION)
	material.set_shader_parameter(
			"spark_max_size", MagentaReductionProfile.SPARK_MAX_SIZE_FRACTION)
	material.set_shader_parameter("spark_alpha", MagentaReductionProfile.SPARK_ALPHA)
	material.set_shader_parameter(
			"spark_spawn_window", MagentaReductionProfile.SPARK_SPAWN_WINDOW)
	material.set_shader_parameter(
			"spark_life_fraction", MagentaReductionProfile.SPARK_LIFE_FRACTION)
	material.set_shader_parameter(
			"spark_height_min_fraction",
			MagentaReductionProfile.SPARK_HEIGHT_MIN_FRACTION)
	material.set_shader_parameter(
			"spark_height_max_fraction",
			MagentaReductionProfile.SPARK_HEIGHT_MAX_FRACTION)
	material.set_shader_parameter("spark_tint", MagentaReductionProfile.SPARK_TINT)
	material.set_shader_parameter(
			"discharge_core_color", MagentaReductionProfile.DISCHARGE_CORE_COLOR)
	material.set_shader_parameter(
			"discharge_edge_color", MagentaReductionProfile.DISCHARGE_EDGE_COLOR)

	material.set_shader_parameter("intensity_scale", _intensityScale)
	material.set_shader_parameter(
			"spiral_enabled", 1.0 if bool(_layerVisibility[LAYER_SPIRAL]) else 0.0)
	material.set_shader_parameter(
			"windup_enabled", 1.0 if bool(_layerVisibility[LAYER_WINDUP]) else 0.0)
	material.set_shader_parameter(
			"twinkle_enabled", 1.0 if bool(_layerVisibility[LAYER_TWINKLE]) else 0.0)
	material.set_shader_parameter(
			"circle_radius_fraction",
			MagentaReductionProfile.FIELD_CIRCLE_RADIUS_FRACTION
			if _isDiamondShape(_areaShape)
			else MagentaReductionProfile.FIELD_CIRCLE_CONSERVATIVE_FRACTION)
	material.set_shader_parameter("vfx_seed", float(_activeSeed))


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge1 <= edge0:
		return 1.0 if value >= edge1 else 0.0
	var amount := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)


## Mirrors `CombatResolver._spellAffectedPositions`'s own shape match: only
## `cross` and `line` are special-cased there, and everything else — including
## `circle` and any unrecognized value — falls through to `ShapeCaster.getCircle`,
## which is a Manhattan diamond, not a Euclidean circle.
##
## Unlike the two storms, this effect does not trace that diamond: its field is
## a circle by deliberate choice, and this predicate only selects *which* circle.
## Diamond carriers get the stylized `FIELD_CIRCLE_RADIUS_FRACTION`;
## `cross`/`line`, whose real footprints are far smaller than a diamond of the
## same radius, keep the conservative inscribed one. The ground wash carries the
## true shape in every case.
static func _isDiamondShape(areaShape: String) -> bool:
	return areaShape != "cross" and areaShape != "line"


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
