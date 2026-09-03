## The world map's light masks, in MAP-PIXEL space: cast shadows in R, lamp light in G.
##
## They share one texture because they are the same mechanism seen twice. Both modulate a
## per-pixel light level on the ground; the palette decides what a level looks like. Building
## them as two parallel systems that happen to agree is the failure mode here, and packing them
## into one image makes that impossible rather than merely discouraged.
##
## (The file is named for the shadow because that came first. The class owns both.)
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
## The lamp field is a distance field that depends only on where the structures are and how far
## the light reaches, so it survives every change the clock makes. Rebuilding it per frame while
## a day runs would be the most expensive thing in the pipeline for no result.
var _lampDistance: PackedFloat32Array = PackedFloat32Array()
## Which pixels a lamp reaches at all. Shading only these is the difference between touching
## a few thousand pixels and all 44k of them, on a path that runs every frame while the clock
## is running.
var _lampTouched: PackedInt32Array = PackedInt32Array()
## The mask is written through a flat byte buffer rather than set_pixel. Per-pixel Image calls
## are fast enough for a one-off build and far too slow for a per-frame one -- it was the
## difference between this finishing and a probe timing out at five minutes.
var _buffer: PackedByteArray = PackedByteArray()
var _lampKey := ""
var _lampDirty := true
var _silhouetteBits: PackedByteArray = PackedByteArray()
var _silhouetteSource: Image


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
	structures: Array, silhouette: Image, mapSize: Vector2i, step: Vector2, spread: float,
	lamp: Dictionary, edge: Dictionary
) -> void:
	_ensure(mapSize)
	if _image == null:
		return
	_buffer.fill(0)

	_ensureLampDistance(structures, float(lamp.get("reach", 0.0)))
	if not structures.is_empty() and silhouette != null and step.length() > 0.0001:
		_silhouetteBits = _packSilhouette(silhouette)
		for s in structures:
			_drawOne(s, _quantise(step, int(edge.get("steps", 0))), spread, edge)
	_writeLamps(lamp)

	_image.set_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, _buffer)
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)


## The silhouette as one byte per pixel, so the rasteriser reads an array instead of calling
## into Image for every pixel it tests.
func _packSilhouette(silhouette: Image) -> PackedByteArray:
	if _silhouetteSource == silhouette and not _silhouetteBits.is_empty():
		return _silhouetteBits
	_silhouetteSource = silhouette
	var bits := PackedByteArray()
	bits.resize(_size.x * _size.y)
	for y in mini(_size.y, silhouette.get_height()):
		for x in mini(_size.x, silhouette.get_width()):
			bits[y * _size.x + x] = 1 if silhouette.get_pixel(x, y).r > 0.5 else 0
	return bits


## The raw falloff, 1 at a lamp and 0 at its reach. Rebuilt only when the structures or the
## reach change; the SHAPE of the light is applied per frame in `_writeLamps`, which is cheap.
func _ensureLampDistance(structures: Array, reachTiles: float) -> void:
	var key := "%d:%.3f:%d" % [structures.size(), reachTiles, _size.x * _size.y]
	if not _lampDirty and _lampKey == key:
		return
	_lampKey = key
	_lampDirty = false
	_lampDistance = PackedFloat32Array()
	_lampDistance.resize(_size.x * _size.y)
	_lampTouched = PackedInt32Array()
	if reachTiles <= 0.0 or structures.is_empty():
		return
	# The reach is in TILES; the field is in map pixels. One tile is `tilePixels` map pixels,
	# and a structure is `w` map pixels wide across one tile, so `w` is the conversion.
	for s in structures:
		var sw: int = s["w"]
		var radius := reachTiles * float(sw)
		if radius < 0.5:
			continue
		var cx := float(s["x"]) + float(sw) * 0.5
		var cy := float(int(s["y"]) + int(s["rows"]))
		var x0 := maxi(0, int(floorf(cx - radius)))
		var x1 := mini(_size.x - 1, int(ceilf(cx + radius)))
		var y0 := maxi(0, int(floorf(cy - radius)))
		var y1 := mini(_size.y - 1, int(ceilf(cy + radius)))
		for my in range(y0, y1 + 1):
			for mx in range(x0, x1 + 1):
				var d := Vector2(float(mx) + 0.5 - cx, float(my) + 0.5 - cy).length() / radius
				if d >= 1.0:
					continue
				var index := my * _size.x + mx
				if _lampDistance[index] <= 0.0:
					_lampTouched.push_back(index)
				# MAX, not sum. Two lamps together light a wider area, not a brighter one, and
				# summing is exactly what blows a cluster of houses out to white.
				_lampDistance[index] = maxf(_lampDistance[index], 1.0 - d)


func _writeLamps(lamp: Dictionary) -> void:
	var amount: float = lamp.get("amount", 0.0)
	var mode: String = lamp.get("mode", "off")
	if amount <= 0.0 or mode == "off" or _lampDistance.is_empty():
		return
	var levels: int = maxi(1, int(lamp.get("levels", 3)))
	var core: float = lamp.get("core", 0.0)
	var band: float = maxf(0.02, float(lamp.get("dither", 0.5)))
	for index in _lampTouched:
		var raw := _lampDistance[index]
		if raw <= 0.0:
			continue
		var mx := index % _size.x
		var my := index / _size.x
		var lit := _shapeLamp(raw, mode, levels, core, band, mx, my) * amount
		if lit <= 0.0:
			continue
		_buffer[index * 4 + 1] = int(clampf(lit, 0.0, 1.0) * 255.0)


## Ordered dither, anchored to MAP pixels so the pattern belongs to the terrain rather than to
## the screen. Anchored to the screen it crawls the moment the camera pans.
const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## How lit one map pixel is, 0 to 1. The modes differ ONLY in how the raw falloff is shaped;
## the mechanism underneath is identical, which is why they are one function.
func _shapeLamp(
	raw: float, mode: String, levels: int, core: float, band: float, mx: int, my: int
) -> float:
	if mode == "hard":
		return 1.0
	if mode == "smooth":
		return raw
	# RING SIZING. The falloff is linear in distance, so quantising it directly gives rings of
	# equal width and no way to ask for a bigger bright middle. `core` carves out a fraction of
	# the RADIUS held at full brightness and the remaining levels split what is left. The
	# light's outer boundary does not move: raw still reaches 0 at the same distance whatever
	# the core is, so growing it trades width away from the middle rings, not from the reach.
	var shaped := raw
	if core > 0.001:
		var dn := 1.0 - raw
		if dn <= core:
			return 1.0
		var u := (dn - core) / maxf(0.0001, 1.0 - core)
		shaped = (1.0 - u) * float(levels - 1) / float(levels)
	if mode == "band":
		# round, not ceil: ceil biases the whole lit area outward by half a level, which leaves
		# the outermost ring one step brighter than the falloff says it should be.
		return roundf(shaped * float(levels)) / float(levels)
	# Dither ONLY in a narrow band where two levels meet. A plain Bayer threshold across the
	# whole falloff puts a checkerboard over every pixel of the light rather than only at its
	# rings, and reads as noise instead of softness -- measured on one house it alternated on
	# almost every pixel. A ring boundary sits at frac = 0.5, so the band is centred there.
	var scaled := shaped * float(levels)
	var base := floorf(scaled)
	var frac := scaled - base
	var half := band * 0.5
	if frac < 0.5 - half:
		return base / float(levels)
	if frac > 0.5 + half:
		return minf(1.0, (base + 1.0) / float(levels))
	var threshold := (float(BAYER4[(my & 3) * 4 + (mx & 3)]) + 0.5) / 16.0
	var local := (frac - (0.5 - half)) / (2.0 * half)
	return minf(1.0, (base + (1.0 if local > threshold else 0.0)) / float(levels))


func _ensure(mapSize: Vector2i) -> void:
	if mapSize.x <= 0 or mapSize.y <= 0:
		return
	if _image != null and _size == mapSize:
		return
	_size = mapSize
	# RGBA8 rather than R8: R carries the shadow, G the lamp light. See the class note.
	_image = Image.create_empty(mapSize.x, mapSize.y, false, Image.FORMAT_RGBA8)
	_buffer = PackedByteArray()
	_buffer.resize(mapSize.x * mapSize.y * 4)
	_texture = null
	_lampDirty = true


## Snaps the sun's direction to one of `steps` headings, keeping its length. A continuously
## rotating sun drags a hard pixel edge across the map one pixel at a time and the boundary
## flickers as it goes -- the shadow crawls, which is invisible in a still and the first thing
## the eye catches in motion. Stepping the heading makes the mask jump between stable shapes.
## The LENGTH is deliberately left continuous: it changes slowly and quantising it would make
## shadows visibly pop in and out as the sun climbs.
func _quantise(step: Vector2, steps: int) -> Vector2:
	if steps <= 0 or step.length() < 0.0001:
		return step
	var angle := step.angle()
	var quantum := TAU / float(steps)
	return Vector2.RIGHT.rotated(roundf(angle / quantum) * quantum) * step.length()


func _drawOne(s: Dictionary, step: Vector2, spread: float, edge: Dictionary) -> void:
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

	var dithered: bool = str(edge.get("edge", "hard")) == "dither"
	# Band width as a FRACTION of the shadow, so a small shadow does not end up entirely
	# dither. Expressed in map pixels by the caller and normalised here against the shadow's
	# own extent, which is what keeps it looking the same on a house and on a tower.
	var bandWidth := clampf(float(edge.get("band", 1.5)) / maxf(1.0, float(rows)), 0.02, 0.9)

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
			if _silhouetteBits[srcY * _size.x + srcX] == 0:
				continue
			# The EDGE. At map-pixel resolution "hard" is already a pixel edge, which is a much
			# stronger position than it was in screen space -- there are no gradients anywhere
			# else in this art. `dither` feathers the outer boundary instead, with an ordered
			# pattern anchored to MAP pixels so it belongs to the terrain and cannot swim as the
			# camera pans. It dithers only near the border: applied across the whole shadow it
			# would checkerboard the entire thing and read as noise.
			if dithered:
				var edgeness := minf(minf(u, 1.0 - u), 1.0 - v) / bandWidth
				if edgeness < 1.0:
					var threshold := (float(BAYER4[(my & 3) * 4 + (mx & 3)]) + 0.5) / 16.0
					if edgeness < threshold:
						continue
			# Written at full value, never accumulated: that is what makes crossing shadows a
			# union rather than a darker patch.
			_buffer[(my * _size.x + mx) * 4] = 255
