## Cached procedural textures and immutable shared materials for area VFX layers.
##
## Callers may share the returned resources but must not mutate them. Per-layer
## tint and fade should be supplied through vertex colors.
##
## The shape masks here are alpha-only silhouettes with no colour baked into
## their geometry, which is what lets the ice and fire storms share them and
## apply their own palettes on their own duplicated materials.

class_name VfxTextures
extends RefCounted

## Ground-wash footprint silhouettes, matching the area shapes
## `CombatResolver._spellAffectedPositions` actually casts.
enum GroundWashShape {
	## Manhattan diamond — what `ShapeCaster.getCircle` casts, and the shape of
	## every area spell that does not explicitly set `AREA_SHAPE`.
	DIAMOND,
	## Plus/cross arms — `ShapeCaster.getCross`, used by `AREA_SHAPE: "cross"`.
	CROSS,
	## Radial falloff, matching no gameplay shape. Retained as the neutral
	## fallback for shapes without a dedicated mask (currently `line`).
	DISC,
}

const _SOFT_FLAKE_SIZE := 16
const _SHARD_MASK_SIZE := 32
const _CANOPY_PUFF_SIZE := 64
const _FROST_VEIN_SIZE := 128
const _GROUND_WASH_SIZE := 64
const _SHARD_VARIANT_COUNT := 4
## The lance is the one non-square texture here, and deliberately so: it is
## mapped onto a quad that is itself long and thin, so a square source would
## spend most of its pixels being squashed.
const _LANCE_STREAK_WIDTH := 64
const _LANCE_STREAK_HEIGHT := 16
## Where along the lance the head sits, in UV `u`. Past this the silhouette
## closes to a point so the tip reads as a tip rather than as a cut end.
const _LANCE_HEAD_FRACTION := 0.93
## How far the tail fades in from nothing, in UV `u`.
const _LANCE_TAIL_FRACTION := 0.40
## Exponent on the lance's half-width against `u`. Below 1.0 the wedge opens
## quickly behind the head and then holds, which reads as a lance; at 1.0 it is
## a plain triangle.
const _LANCE_TAPER_EXPONENT := 0.55
## Fraction of the local half-width that stays fully opaque before the edge
## falloff starts. This is what makes the lance *crisp*: a solid core with a
## short ramp, rather than the radial gradient of `softFlake()`, which has no
## solid region at all and is why a flake cannot be stretched into a streak.
const _LANCE_CORE_FRACTION := 0.45

## A bolt segment is a link in a chained lightning path, so unlike the lance it
## must be uniform along its length — any taper would show up as a pinch at
## every joint.
##
## Deliberately coarse. These are sampled with NEAREST and drawn at a size where
## a texel covers more than one screen pixel, so the grid is meant to be visible
## — a larger source would only average the steps away again.
const _BOLT_SEGMENT_WIDTH := 16
const _BOLT_SEGMENT_HEIGHT := 8
## Fraction of the half-width that stays fully opaque.
##
## Raised from 0.30, and paired with a *binary* posterize below, so the segment
## is a hard bar with no sheath at all. The earlier hot-filament-in-a-sheath
## cross-section was the single largest source of softness in the discharge:
## under additive blending the sheath's partial alpha is exactly a glow, and a
## glow is the opposite of a sharp line. The texture now contributes only the
## line's width; every pixel it covers is fully opaque.
const _BOLT_CORE_FRACTION := 0.80

## Small hard dot — the plainest sprite here, and the one to reach for when a
## field needs to be *countable*. `softFlake()` at the same size is a soft haze
## whose edge is impossible to locate; this has an edge.
const _PIXEL_DOT_SIZE := 8

## Frames in `sparkleFrames()`. Public because a consumer has to drive the
## animation phase itself and needs to know how many frames it is driving.
const SPARKLE_FRAME_COUNT := 4
## Authored art rather than generated — see `sparkleFrames()`. Imported with
## VRAM compression and alpha border-fixing both off; `detect_3d/compress_to`
## in particular defaults to re-importing 3D-used textures as VRAM compressed,
## which would put block-compression artefacts through four flat colours.
const _SPARKLE_FRAMES = preload(
		"res://assets/textures/effects/sparkle_frames.png")

## Alpha posterization: how many hard levels each sprite is snapped to, and the
## level below which it is cut to nothing. Fewer levels and a higher cutoff read
## as more deliberately pixelated.
const _POSTERIZE_LEVELS := 3
## Must sit **below** the lowest non-zero level a sprite uses, or that level is
## silently deleted. At 0.34 against three levels it clipped everything at 1/3
## (0.333), which erased the spikes of a since-replaced procedural star sprite
## and left a bare core, with nothing in the code looking wrong. Keep a clear
## margin under `1.0 / _POSTERIZE_LEVELS` when either changes.
const _POSTERIZE_CUTOFF := 0.28
## One level: fully on or fully off, no intermediate. See `_BOLT_CORE_FRACTION`.
const _BOLT_POSTERIZE_LEVELS := 1
const _DOT_POSTERIZE_LEVELS := 2

static var _softFlake: ImageTexture
static var _shardMasks: Array[ImageTexture] = []
static var _canopyPuff: ImageTexture
static var _frostVein: ImageTexture
static var _lanceStreak: ImageTexture
static var _boltSegment: ImageTexture
static var _pixelDot: ImageTexture
static var _groundWashByShape: Dictionary = {}

static var _flurryMaterial: StandardMaterial3D
static var _shardMaterials: Array[StandardMaterial3D] = []
static var _canopyMaterial: StandardMaterial3D
static var _frostVeinMaterial: StandardMaterial3D
static var _lanceStreakMaterial: StandardMaterial3D
static var _boltSegmentMaterial: StandardMaterial3D
static var _sparkleFramesMaterial: StandardMaterial3D
static var _pixelDotMaterial: StandardMaterial3D
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


## Directional streak for effects that need a lance rather than a sprite: a
## solid bright core running along `u`, closing to a point at the head and
## tapering to nothing at the tail.
##
## This exists because the radial sprites above cannot do the job. Stretching
## `softFlake()` across a long thin quad puts its only opaque pixel in the
## middle of the streak and fades both ends to zero, so the lance renders as an
## invisible speck — silently, with correct transforms and correct alpha. Reach
## for this whenever a layer's silhouette has a direction.
static func lanceStreak() -> Texture2D:
	if _lanceStreak == null:
		_lanceStreak = _createLanceStreak()
	return _lanceStreak


## One link of a chained lightning path: a hot filament running the full length
## of the quad inside a dimmer sheath, with **no taper along its length**.
##
## That last part is the whole difference from `lanceStreak()`. A jagged bolt is
## drawn as a run of these laid end to end, so any lengthwise taper would pinch
## the silhouette at every joint and turn a continuous bolt into a row of
## separate darts.
static func boltSegment() -> Texture2D:
	if _boltSegment == null:
		_boltSegment = _createBoltSegment()
	return _boltSegment


## Hand-authored four-frame sparkle animation: a star that pops and shrinks away
## to a single pixel.
##
## **The one authored texture in this file**, and a deliberate exception to its
## procedural premise. Everything else here is generated because it has to scale
## with a footprint or vary per seed; a sparkle does neither, and drawn pixel art
## carries shading choices — a white core, a warm mid, a cool rim — that a
## formula would only approximate.
##
## Repacked from `sparkle_strip.png`, whose frames sit at uneven spacing, onto
## the even grid `particles_anim_h_frames` requires. The strip is kept in the
## repo as the source of truth; regenerate the grid from it rather than editing
## the packed file.
static func sparkleFrames() -> Texture2D:
	return _SPARKLE_FRAMES


## A small dot with a hard edge, posterized to two levels on an 8x8 grid.
##
## The counterpart to `softFlake()`, not a replacement for it: the flake's
## radial gradient makes a soft cloud, which is right for a snow field and wrong
## for a field of individually countable specks. Where a mote has to be *seen*
## rather than felt, this is the sprite.
static func pixelDot() -> Texture2D:
	if _pixelDot == null:
		_pixelDot = _createPixelDot()
	return _pixelDot


## Footprint silhouette for the ground wash, cached per shape.
##
## `footprintRadiusTiles` only affects `CROSS`, whose arms are one tile wide
## regardless of how far they reach — so the arm's *proportion* of the texture
## changes with radius, unlike the diamond and disc, which are self-similar at
## every size. Passing a different radius for a cross therefore yields a
## different cached texture; that is intended, not a cache miss.
static func groundWash(
		shape: GroundWashShape = GroundWashShape.DIAMOND,
		footprintRadiusTiles: int = 1) -> Texture2D:
	var key := (
			"%d" % shape
			if shape != GroundWashShape.CROSS
			else "%d:%d" % [shape, maxi(footprintRadiusTiles, 1)])
	if not _groundWashByShape.has(key):
		_groundWashByShape[key] = _createGroundWash(shape, maxi(footprintRadiusTiles, 1))
	return _groundWashByShape[key]


## Maps a `data/spells.json` `AREA_SHAPE` string onto a mask. Mirrors
## `CombatResolver._spellAffectedPositions`'s own match: only `cross` and
## `line` are special-cased there, and everything else — including `circle` and
## any unrecognized value — falls through to `ShapeCaster.getCircle`, which is a
## Manhattan diamond rather than a Euclidean circle. `line` has no dedicated
## mask because its footprint depends on the cast direction, which the ground
## wash does not receive; it falls back to the neutral disc.
static func groundWashShapeFor(areaShape: String) -> GroundWashShape:
	match areaShape:
		"cross":
			return GroundWashShape.CROSS
		"line":
			return GroundWashShape.DISC
		_:
			return GroundWashShape.DIAMOND


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


## Linear-filtered, unlike the nearest-filtered flake and shard masks: a lance is
## stretched and rotated to an arbitrary screen angle, and nearest sampling
## stair-steps its long edge badly. The crispness comes from the texture's own
## solid core (`_LANCE_CORE_FRACTION`), not from the filter.
##
## Built white. Like the shape masks, this carries no palette — the caller's
## shader owns the colour.
static func lanceStreakMaterial() -> StandardMaterial3D:
	if _lanceStreakMaterial == null:
		_lanceStreakMaterial = _createMaterial(
				"LanceStreakMaterial",
				lanceStreak(),
				Color.WHITE,
				true,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	return _lanceStreakMaterial


## Nearest-filtered and white. The caller's shader owns the palette.
##
## Nearest throughout this sprite family is deliberate: bilinear sampling was
## what made the first pixel pass look airbrushed. It resamples every texel
## boundary into a gradient, so a posterized source arrives on screen smoothed
## back out and the hard steps the texture was built for never survive. Rotation
## does make a nearest-sampled edge step visibly — that *is* the look.
static func boltSegmentMaterial() -> StandardMaterial3D:
	if _boltSegmentMaterial == null:
		_boltSegmentMaterial = _createMaterial(
				"BoltSegmentMaterial",
				boltSegment(),
				Color.WHITE,
				true,
				BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	return _boltSegmentMaterial


## Animated sparkle, set up for `GPUParticles3D` frame animation.
##
## `BILLBOARD_PARTICLES` is what makes the frame selection work at all: it is the
## only billboard mode whose generated shader reads `INSTANCE_CUSTOM.z` and
## offsets `UV` into the grid. A process shader writing `CUSTOM.z` under any
## other mode animates nothing, silently.
##
## Looping is off so a spark plays the strip once and is gone, rather than
## re-popping for as long as it lives.
static func sparkleFramesMaterial() -> StandardMaterial3D:
	if _sparkleFramesMaterial == null:
		_sparkleFramesMaterial = _createMaterial(
				"SparkleFramesMaterial",
				sparkleFrames(),
				Color.WHITE,
				true,
				BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		_sparkleFramesMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_sparkleFramesMaterial.particles_anim_h_frames = SPARKLE_FRAME_COUNT
		_sparkleFramesMaterial.particles_anim_v_frames = 1
		_sparkleFramesMaterial.particles_anim_loop = false
	return _sparkleFramesMaterial


## Nearest-filtered; see `boltSegmentMaterial()`.
static func pixelDotMaterial() -> StandardMaterial3D:
	if _pixelDotMaterial == null:
		_pixelDotMaterial = _createMaterial(
				"PixelDotMaterial",
				pixelDot(),
				Color.WHITE,
				true,
				BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	return _pixelDotMaterial


static func frostVeinMaterial() -> StandardMaterial3D:
	if _frostVeinMaterial == null:
		_frostVeinMaterial = _createMaterial(
				"IceFrostVeinMaterial",
				frostVein(),
				IceStormProfile.VEIN_COLOR,
				true,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	return _frostVeinMaterial


## Built once with the diamond texture, since that is the shape a freshly
## constructed effect starts with before its real footprint is known. The
## effect swaps `albedo_texture`/`emission_texture` on its own duplicate via
## `groundWash()` directly once `setFootprint` reports the actual area shape.
##
## The construction-time colour is likewise only a default: both storms
## duplicate this material and drive `albedo_color`/`emission` from their own
## profile every frame, so the ice tint baked in here never reaches the screen.
static func groundWashMaterial() -> StandardMaterial3D:
	if _groundWashMaterial == null:
		_groundWashMaterial = _createMaterial(
				"AreaGroundWashMaterial",
				groundWash(GroundWashShape.DIAMOND),
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


## `u` runs 0 at the tail to 1 at the head, matching `QuadMesh`'s local +X, so a
## caller that maps local X onto its travel direction gets a lance pointing the
## way it is going. `v` is folded to a 0..1 distance from the centreline.
static func _createLanceStreak() -> ImageTexture:
	var image := Image.create(
			_LANCE_STREAK_WIDTH, _LANCE_STREAK_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(_LANCE_STREAK_HEIGHT):
		for x: int in range(_LANCE_STREAK_WIDTH):
			var u := (float(x) + 0.5) / float(_LANCE_STREAK_WIDTH)
			var v := absf(
					(float(y) + 0.5) / float(_LANCE_STREAK_HEIGHT) - 0.5) * 2.0
			var halfWidth := pow(u, _LANCE_TAPER_EXPONENT)
			# Solid core, then a short ramp to the edge. The ramp is what keeps a
			# rotated lance from aliasing; the core is what keeps it crisp.
			var across := 1.0 - smoothstep(
					halfWidth * _LANCE_CORE_FRACTION, halfWidth, v)
			var tail := smoothstep(0.0, _LANCE_TAIL_FRACTION, u)
			var tip := 1.0 - smoothstep(_LANCE_HEAD_FRACTION, 1.0, u)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, across * tail * tip))
	return ImageTexture.create_from_image(image)


## Snaps an alpha ramp to a few hard levels and cuts the faint tail to nothing.
##
## This is what makes a procedural sprite read as pixel art rather than as an
## airbrushed blob, and it matters more than the filter setting does. A
## `smoothstep` falloff spends most of its range at very low alpha, spreading a
## long dim tail across many texels; under additive blending that tail *is* the
## soft halo that hides the pixel grid. Rounding to a handful of levels and
## discarding everything under the cutoff leaves edges you can count.
static func _posterizeAlpha(value: float, levels: int, cutoff: float) -> float:
	var steps := float(maxi(levels, 1))
	# `roundf` rather than `round`: the untyped global returns Variant, which
	# makes the inferred type of `level` ambiguous and fails the parse.
	var level := roundf(clampf(value, 0.0, 1.0) * steps) / steps
	return 0.0 if level < cutoff else level


## Uniform along `u`, so a chain of these reads as one continuous bolt. Only the
## cross-section is shaped: a solid filament with one hard step to the sheath.
static func _createBoltSegment() -> ImageTexture:
	var image := Image.create(
			_BOLT_SEGMENT_WIDTH, _BOLT_SEGMENT_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(_BOLT_SEGMENT_HEIGHT):
		for x: int in range(_BOLT_SEGMENT_WIDTH):
			var v := absf(
					(float(y) + 0.5) / float(_BOLT_SEGMENT_HEIGHT) - 0.5) * 2.0
			var alpha := _posterizeAlpha(
					1.0 - smoothstep(_BOLT_CORE_FRACTION, 1.0, v),
					_BOLT_POSTERIZE_LEVELS,
					_POSTERIZE_CUTOFF)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


## A hard round dot on a small grid, two levels only.
static func _createPixelDot() -> ImageTexture:
	var image := Image.create(
			_PIXEL_DOT_SIZE, _PIXEL_DOT_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_PIXEL_DOT_SIZE):
		for x: int in range(_PIXEL_DOT_SIZE):
			var point := _normalizedPoint(x, y, _PIXEL_DOT_SIZE)
			var alpha := _posterizeAlpha(
					clampf(1.0 - point.length(), 0.0, 1.0),
					_DOT_POSTERIZE_LEVELS,
					_POSTERIZE_CUTOFF)
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


## One generator for every footprint silhouette. Each branch produces a
## normalized distance that reaches 1.0 exactly on its shape's boundary, so the
## shared falloff and opacity below apply identically to all of them and the
## shapes cannot drift apart in weight as they are tuned.
static func _createGroundWash(
		shape: GroundWashShape, footprintRadiusTiles: int) -> ImageTexture:
	var image := Image.create(
			_GROUND_WASH_SIZE, _GROUND_WASH_SIZE, false, Image.FORMAT_RGBA8)
	# The texture spans the footprint's bounding box, `2 * radius + 1` tiles
	# across, mapped to [-1, 1]. A cross arm is one tile wide, so its half-width
	# in normalized units is 0.5 tiles over the half-span of `radius + 0.5`.
	var armHalfWidth := 0.5 / (float(footprintRadiusTiles) + 0.5)
	for y: int in range(_GROUND_WASH_SIZE):
		for x: int in range(_GROUND_WASH_SIZE):
			var point := _normalizedPoint(x, y, _GROUND_WASH_SIZE)
			var distance := 0.0
			match shape:
				GroundWashShape.CROSS:
					# Union of a horizontal and a vertical bar: each bar's
					# distance is whichever runs out first, its width or its
					# reach, and the union takes the nearer of the two bars.
					var horizontal := maxf(absf(point.y) / armHalfWidth, absf(point.x))
					var vertical := maxf(absf(point.x) / armHalfWidth, absf(point.y))
					distance = minf(horizontal, vertical)
				GroundWashShape.DISC:
					point.y *= 1.18
					distance = point.length()
				_:
					distance = absf(point.x) + absf(point.y)
			var falloff := clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff * falloff * 0.24))
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
