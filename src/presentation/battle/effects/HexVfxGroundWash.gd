## The ground silhouette a hex cast burns into the floor: the affected cells themselves, drawn.
##
## WHY THIS EXISTS RATHER THAN A CALL INTO `VfxTextures`. The shared generator offers DIAMOND,
## DISC and CROSS masks, and its own header says why: `ShapeCaster.getCircle` was a Manhattan
## diamond, so a diamond was the honest silhouette of a circle spell. HXB-7 made that function a
## hex disc, and a generated diamond now draws a shape the simulation no longer resolves. The
## shared file is a donor this item may not mutate, so the hex silhouette is generated here.
##
## IT IS THE FOOTPRINT, NOT A SHAPE NAMED AFTER IT. Rather than picking a mask from an
## `AREA_SHAPE` string and hoping it matches, this rasterises the resolved cells directly. A disc,
## a ring, a cross, a line and an irregular set clipped by a wall all come out correct with no
## per-shape code, and the failure the item names -- "a cast hits seven cells but draws five" --
## cannot happen, because the drawing IS the seven cells.
##
## Cached by footprint identity: the same set of cells at the same metrics yields the same texture
## rather than a new image per cast.

class_name HexVfxGroundWash
extends RefCounted

## Texture edge in pixels. Large enough that a hex edge reads as a straight line rather than a
## staircase at the sizes a storm's ground wash is drawn, small enough to rasterise per distinct
## footprint without a visible hitch.
const TEXTURE_SIZE := 192

## Fraction of a cell over which the silhouette fades out at its rim. A hard edge reads as a decal
## someone placed; a short falloff reads as light on the ground, which is what every donor wash
## already does.
const EDGE_SOFTNESS := 0.28

static var _cache: Dictionary = {}


## The silhouette for `footprint`, white with the affected cells opaque.
##
## Tinting is the caller's job through its own material, exactly as the donors already tint the
## shared wash: one white mask serves every element rather than one texture per colour.
static func forFootprint(footprint: HexVfxFootprint) -> Texture2D:
	if footprint == null or footprint.isEmpty():
		return _blank()
	var key := _keyFor(footprint)
	if _cache.has(key):
		return _cache[key]
	var texture := _rasterise(footprint)
	_cache[key] = texture
	return texture


## The square world extent the returned texture maps onto -- what a consumer sizes its wash mesh
## to. Square because the texture is square: a hex footprint's X and Z spans differ, and stretching
## the mask to a non-square quad would skew every hexagon in it.
static func worldExtentFor(footprint: HexVfxFootprint) -> float:
	if footprint == null or footprint.isEmpty():
		return 0.0
	return footprint.worldDiameter()


static func clearCache() -> void:
	_cache.clear()


static func cachedCount() -> int:
	return _cache.size()


static func _keyFor(footprint: HexVfxFootprint) -> String:
	var parts: Array[String] = []
	for cell: Vector2i in footprint.cells:
		parts.append("%d,%d" % [cell.x, cell.y])
	return "%.3f:%.3f:%s" % [footprint.cell_width, footprint.cell_height, ";".join(parts)]


## Walks the texture's pixels, maps each back into world space over the footprint's own square
## extent, and asks the footprint whether that point is on an affected cell.
##
## Softness is measured as distance past the cell boundary in the same normalised space the
## containment test uses, so the fade is the same width on a slanted edge as on a flat one --
## measuring it in pixels would make the diagonal edges look thinner than the horizontal ones.
static func _rasterise(footprint: HexVfxFootprint) -> Texture2D:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	var extent := maxf(footprint.worldDiameter(), 0.001)
	var centre := footprint.center()
	var origin := Vector2(centre.x - extent * 0.5, centre.z - extent * 0.5)
	var step := extent / float(TEXTURE_SIZE)

	for py in range(TEXTURE_SIZE):
		var worldZ := origin.y + (float(py) + 0.5) * step
		for px in range(TEXTURE_SIZE):
			var worldX := origin.x + (float(px) + 0.5) * step
			var coverage := _coverageAt(footprint, worldX, worldZ)
			if coverage > 0.0:
				image.set_pixel(px, py, Color(1.0, 1.0, 1.0, coverage))
	return ImageTexture.create_from_image(image)


## How much of the wash lands on a point: 1 inside a cell, falling to 0 across `EDGE_SOFTNESS`
## just outside it, 0 beyond. Uses the nearest cell only -- cells tile without overlapping, so no
## point is inside two, and the nearest is the only one that can cover it.
static func _coverageAt(footprint: HexVfxFootprint, worldX: float, worldZ: float) -> float:
	var halfWidth := footprint.cell_width * 0.5
	var halfHeight := footprint.cell_height * 0.5
	var best := INF
	for centre: Vector3 in footprint.world_positions:
		var x := absf(worldX - centre.x) / halfWidth
		var z := absf(worldZ - centre.z) / halfHeight
		# How far outside the hexagon this point is, as the worst of its two bounding conditions.
		var outside := maxf(z - 1.0, (2.0 * x + z - 2.0) * 0.5)
		best = minf(best, outside)
		if best <= 0.0:
			return 1.0
	if best >= EDGE_SOFTNESS:
		return 0.0
	return clampf(1.0 - best / EDGE_SOFTNESS, 0.0, 1.0)


static func _blank() -> Texture2D:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	return ImageTexture.create_from_image(image)
