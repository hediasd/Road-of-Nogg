## Cached procedural textures and immutable shared materials for ice VFX layers.
##
## Callers may share the returned resources but must not mutate them. Per-layer
## tint and fade should be supplied through vertex colors.

class_name VfxTextures
extends RefCounted

const _SOFT_FLAKE_SIZE := 16
const _SHARD_MASK_SIZE := 32
const _CANOPY_PUFF_SIZE := 64
const _FROST_VEIN_SIZE := 128
const _GROUND_WASH_SIZE := 64
const _SHARD_VARIANT_COUNT := 4

static var _softFlake: ImageTexture
static var _shardMasks: Array[ImageTexture] = []
static var _canopyPuff: ImageTexture
static var _frostVein: ImageTexture
static var _groundWash: ImageTexture

static var _flurryMaterial: StandardMaterial3D
static var _shardMaterials: Array[StandardMaterial3D] = []
static var _canopyMaterial: StandardMaterial3D
static var _frostVeinMaterial: StandardMaterial3D
static var _groundWashMaterial: StandardMaterial3D


static func softFlake() -> Texture2D:
	if _softFlake == null:
		_softFlake = _createSoftFlake()
	return _softFlake


static func shardMask(variant: int) -> Texture2D:
	_ensureShardMasks()
	return _shardMasks[posmod(variant, _SHARD_VARIANT_COUNT)]


static func canopyPuff() -> Texture2D:
	if _canopyPuff == null:
		_canopyPuff = _createCanopyPuff()
	return _canopyPuff


static func frostVein() -> Texture2D:
	if _frostVein == null:
		_frostVein = _createFrostVein()
	return _frostVein


static func groundWash() -> Texture2D:
	if _groundWash == null:
		_groundWash = _createGroundWash()
	return _groundWash


static func flurryMaterial() -> StandardMaterial3D:
	if _flurryMaterial == null:
		_flurryMaterial = _createMaterial(
				"IceFlurryMaterial",
				softFlake(),
				IceStormProfile.FLAKE_COLOR,
				true,
				BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	return _flurryMaterial


static func heroShardMaterial(variant: int) -> StandardMaterial3D:
	_ensureShardMaterials()
	return _shardMaterials[posmod(variant, _SHARD_VARIANT_COUNT)]


static func canopyMaterial() -> StandardMaterial3D:
	if _canopyMaterial == null:
		_canopyMaterial = _createMaterial(
				"IceCanopyMaterial",
				canopyPuff(),
				IceStormProfile.CANOPY_CORE_COLOR,
				true,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	return _canopyMaterial


static func frostVeinMaterial() -> StandardMaterial3D:
	if _frostVeinMaterial == null:
		_frostVeinMaterial = _createMaterial(
				"IceFrostVeinMaterial",
				frostVein(),
				IceStormProfile.VEIN_COLOR,
				true,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	return _frostVeinMaterial


static func groundWashMaterial() -> StandardMaterial3D:
	if _groundWashMaterial == null:
		_groundWashMaterial = _createMaterial(
				"IceGroundWashMaterial",
				groundWash(),
				IceStormProfile.GROUND_WASH_COLOR,
				true,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	return _groundWashMaterial


static func _ensureShardMasks() -> void:
	if not _shardMasks.is_empty():
		return
	for variant: int in range(_SHARD_VARIANT_COUNT):
		_shardMasks.append(_createShardMask(variant))


static func _ensureShardMaterials() -> void:
	if not _shardMaterials.is_empty():
		return
	_ensureShardMasks()
	for variant: int in range(_SHARD_VARIANT_COUNT):
		_shardMaterials.append(_createMaterial(
				"IceHeroShardMaterial%d" % variant,
				_shardMasks[variant],
				Color.WHITE,
				false,
				BaseMaterial3D.TEXTURE_FILTER_NEAREST))


static func _createMaterial(
		resourceName: String,
		texture: Texture2D,
		color: Color,
		additive: bool,
		filter: BaseMaterial3D.TextureFilter) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = resourceName
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = (
			BaseMaterial3D.BLEND_MODE_ADD if additive
			else BaseMaterial3D.BLEND_MODE_MIX)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	material.texture_filter = filter
	material.albedo_color = color
	material.albedo_texture = texture
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 1.0
	material.emission_texture = texture
	return material


static func _createSoftFlake() -> ImageTexture:
	var image := Image.create(
			_SOFT_FLAKE_SIZE, _SOFT_FLAKE_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_SOFT_FLAKE_SIZE):
		for x: int in range(_SOFT_FLAKE_SIZE):
			var point := _normalizedPoint(x, y, _SOFT_FLAKE_SIZE)
			var radial := clampf(1.0 - point.length(), 0.0, 1.0)
			var alpha := radial * radial * (3.0 - 2.0 * radial)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _createShardMask(variant: int) -> ImageTexture:
	var image := Image.create(
			_SHARD_MASK_SIZE, _SHARD_MASK_SIZE, false, Image.FORMAT_RGBA8)
	var polygon := _shardPolygon(variant)
	for y: int in range(_SHARD_MASK_SIZE):
		for x: int in range(_SHARD_MASK_SIZE):
			var point := Vector2(
					(float(x) + 0.5) / float(_SHARD_MASK_SIZE),
					(float(y) + 0.5) / float(_SHARD_MASK_SIZE))
			var alpha := 1.0 if Geometry2D.is_point_in_polygon(point, polygon) else 0.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _shardPolygon(variant: int) -> PackedVector2Array:
	match posmod(variant, _SHARD_VARIANT_COUNT):
		0:
			return PackedVector2Array([
				Vector2(0.48, 0.05), Vector2(0.70, 0.40),
				Vector2(0.55, 0.94), Vector2(0.25, 0.62),
			])
		1:
			return PackedVector2Array([
				Vector2(0.20, 0.12), Vector2(0.82, 0.34),
				Vector2(0.70, 0.86), Vector2(0.34, 0.68),
			])
		2:
			return PackedVector2Array([
				Vector2(0.50, 0.06), Vector2(0.88, 0.48),
				Vector2(0.61, 0.57), Vector2(0.46, 0.93),
				Vector2(0.18, 0.42),
			])
		_:
			return PackedVector2Array([
				Vector2(0.31, 0.08), Vector2(0.70, 0.26),
				Vector2(0.56, 0.48), Vector2(0.76, 0.79),
				Vector2(0.36, 0.91), Vector2(0.43, 0.57),
			])


static func _createCanopyPuff() -> ImageTexture:
	var image := Image.create(
			_CANOPY_PUFF_SIZE, _CANOPY_PUFF_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_CANOPY_PUFF_SIZE):
		for x: int in range(_CANOPY_PUFF_SIZE):
			var point := _normalizedPoint(x, y, _CANOPY_PUFF_SIZE)
			point.x *= 0.82
			var radial := clampf(1.0 - point.length(), 0.0, 1.0)
			var noisePoint := Vector2(float(x), float(y)) * 0.065
			var noiseMask := lerpf(0.42, 1.0, _fbm(noisePoint))
			var alpha := pow(radial, 1.35) * noiseMask
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _createFrostVein() -> ImageTexture:
	var image := Image.create(
			_FROST_VEIN_SIZE, _FROST_VEIN_SIZE, false, Image.FORMAT_RGBA8)
	var segments: Array[Vector4] = [
		Vector4(0.08, 0.68, 0.30, 0.54),
		Vector4(0.30, 0.54, 0.49, 0.49),
		Vector4(0.49, 0.49, 0.69, 0.31),
		Vector4(0.69, 0.31, 0.92, 0.22),
		Vector4(0.31, 0.54, 0.22, 0.33),
		Vector4(0.22, 0.33, 0.11, 0.23),
		Vector4(0.49, 0.49, 0.57, 0.70),
		Vector4(0.57, 0.70, 0.78, 0.86),
		Vector4(0.69, 0.31, 0.76, 0.13),
		Vector4(0.57, 0.70, 0.44, 0.88),
	]
	for y: int in range(_FROST_VEIN_SIZE):
		for x: int in range(_FROST_VEIN_SIZE):
			var point := Vector2(
					(float(x) + 0.5) / float(_FROST_VEIN_SIZE),
					(float(y) + 0.5) / float(_FROST_VEIN_SIZE))
			var alpha := 0.0
			for segment: Vector4 in segments:
				var distance := _distanceToSegment(
						point, Vector2(segment.x, segment.y), Vector2(segment.z, segment.w))
				var core := clampf(1.0 - distance / 0.007, 0.0, 1.0) * 0.30
				var haze := clampf(1.0 - distance / 0.025, 0.0, 1.0) * 0.08
				alpha = maxf(alpha, core + haze)
			var edgeFade := clampf(1.0 - _normalizedPoint(
					x, y, _FROST_VEIN_SIZE).length(), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * edgeFade))
	return ImageTexture.create_from_image(image)


static func _createGroundWash() -> ImageTexture:
	var image := Image.create(
			_GROUND_WASH_SIZE, _GROUND_WASH_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_GROUND_WASH_SIZE):
		for x: int in range(_GROUND_WASH_SIZE):
			var point := _normalizedPoint(x, y, _GROUND_WASH_SIZE)
			point.y *= 1.18
			var radial := clampf(1.0 - point.length(), 0.0, 1.0)
			var alpha := radial * radial * 0.24
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _normalizedPoint(x: int, y: int, size: int) -> Vector2:
	return Vector2(
			((float(x) + 0.5) / float(size) - 0.5) * 2.0,
			((float(y) + 0.5) / float(size) - 0.5) * 2.0)


static func _fbm(point: Vector2) -> float:
	var value := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	var amplitudeSum := 0.0
	for _octave: int in range(4):
		value += _valueNoise(point * frequency) * amplitude
		amplitudeSum += amplitude
		frequency *= 2.03
		amplitude *= 0.5
	return value / amplitudeSum


static func _valueNoise(point: Vector2) -> float:
	var cell := point.floor()
	var fraction := point - cell
	var smooth := fraction * fraction * (Vector2(3.0, 3.0) - 2.0 * fraction)
	var top := lerpf(_hash(cell), _hash(cell + Vector2.RIGHT), smooth.x)
	var bottom := lerpf(
			_hash(cell + Vector2.DOWN), _hash(cell + Vector2.ONE), smooth.x)
	return lerpf(top, bottom, smooth.y)


static func _hash(point: Vector2) -> float:
	return fposmod(sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


static func _distanceToSegment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var lengthSquared := segment.length_squared()
	if lengthSquared <= 0.000001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / lengthSquared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)
