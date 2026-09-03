## Cast shadows for standing structures, rendered as a mask in MAP-PIXEL space.
##
## THE REPRESENTATION IS THE POINT. The obvious implementation is a screen-space quad per
## shadow, which is what a 3D engine makes easy -- and it cannot be made to read as pixel art
## at any edge treatment, because its edge lands at arbitrary sub-pixel positions and angles
## that do not align to the map's grid, and it crawls under camera motion. No amount of
## dithering or softening repairs that; the alignment has to come first.
##
## A shadow lies on the ground plane, and **map space IS the ground plane**. So the shear is a
## plain 2D affine in map pixels with no 3D projection anywhere, and four properties fall out
## rather than needing to be engineered:
##
##  - Edges land on exact map pixels, aligned with the terrain's own grid.
##  - Fog, curvature and filtering come free: the ground already does all three, and the mask
##    rides the same sample.
##  - Union compositing is free. Every shadow writes the same buffer at full value, so two
##    crossing shadows cannot double-darken. Ground in shadow twice over is just ground in
##    shadow.
##  - The mask is tiny -- 44k pixels for temp2 -- and only changes when the sun moves.
##
## Rasterised on the CPU rather than through a SubViewport. At this size it is a few thousand
## pixel writes, it is deterministic, and it can be measured headlessly, which a viewport
## render cannot.

class_name WorldMapShadowMask
extends RefCounted

var _image: Image
var _texture: ImageTexture
var _size := Vector2i.ZERO


## The mask's texture, or null before the first rebuild. Safe to hand to a material every
## frame; the texture object is reused and only its contents change.
func texture() -> ImageTexture:
	return _texture


## The mask's own Image. Probes read this rather than `texture().get_image()`: the texture is
## updated in place and its read-back does not reliably reflect the latest contents, which
## silently makes a measurement describe the previous frame.
func image() -> Image:
	return _image


func mapSize() -> Vector2i:
	return _size


## Clears and redraws every structure's shadow. `silhouette` is a solid, hole-filled mask in
## the region's own coordinates; `step` is the ground offset per unit of caster height, in
## WORLD units, straight from `WorldMapSun`.
##
## `spread` widens the tip relative to the foot. Physically that is the penumbra opening with
## distance from the caster; practically it is what stops a shadow reading as a dash, because
## a shadow lying flat and receding is foreshortened by the camera far harder than the upright
## sprite beside it.
func rebuild(
	structures: Array, silhouette: Image, mapSize: Vector2i, step: Vector2, spread: float
) -> void:
	_ensure(mapSize)
	if _image == null:
		return
	_image.fill(Color(0.0, 0.0, 0.0, 1.0))

	if not structures.is_empty() and silhouette != null and step.length() > 0.0001:
		for s in structures:
			_drawOne(s, silhouette, step, spread)

	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)


func _ensure(mapSize: Vector2i) -> void:
	if mapSize.x <= 0 or mapSize.y <= 0:
		return
	if _image != null and _size == mapSize:
		return
	_size = mapSize
	_image = Image.create_empty(mapSize.x, mapSize.y, false, Image.FORMAT_R8)
	_texture = null


func _drawOne(s: Dictionary, silhouette: Image, step: Vector2, spread: float) -> void:
	var sx: int = s["x"]
	var sy: int = s["y"]
	var sw: int = s["w"]
	var rows: int = s["rows"]
	if sw <= 0 or rows <= 0:
		return

	# One map pixel is 1/tile_pixels of a world unit and the caster is `rows` map pixels tall,
	# so a world-unit offset becomes `step * rows` map pixels. The tile pixel size cancels: it
	# appears once converting the height into world units and once converting the offset back
	# into map pixels.
	var offX := step.x * float(rows)
	var offY := step.y * float(rows)
	if absf(offY) < 0.0001:
		return

	# The foot edge is the sprite's bottom row, where it meets the ground.
	var footY := float(sy + rows)
	var halfExtra := float(sw) * (maxf(1.0, spread) - 1.0) * 0.5

	# Both the foot edge and the tip edge run along X, so every row of the shear is an
	# axis-aligned scanline and no general polygon rasteriser is needed.
	var y0 := int(floorf(minf(footY, footY + offY)))
	var y1 := int(ceilf(maxf(footY, footY + offY)))
	for my in range(maxi(0, y0), mini(_size.y, y1 + 1)):
		var v := (float(my) + 0.5 - footY) / offY
		if v < 0.0 or v > 1.0:
			continue
		var left := lerpf(float(sx), float(sx) + offX - halfExtra, v)
		var right := lerpf(float(sx + sw), float(sx + sw) + offX + halfExtra, v)
		if right <= left:
			continue
		# v runs foot to tip, so it reads the sprite bottom-up: v = 0 is the sprite's last row.
		var srcY: int = sy + int(round((1.0 - v) * float(rows - 1)))
		srcY = clampi(srcY, sy, sy + rows - 1)
		var span := right - left
		for mx in range(maxi(0, int(floorf(left))), mini(_size.x, int(ceilf(right)))):
			var u := (float(mx) + 0.5 - left) / span
			if u < 0.0 or u > 1.0:
				continue
			var srcX: int = sx + int(u * float(sw))
			srcX = clampi(srcX, sx, sx + sw - 1)
			if silhouette.get_pixel(srcX, srcY).r < 0.5:
				continue
			# Written at full value, never accumulated: that is what makes crossing shadows a
			# union rather than a darker patch.
			_image.set_pixel(mx, my, Color(1.0, 0.0, 0.0, 1.0))
