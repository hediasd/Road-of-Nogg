## Structures lifted out of a region's ground art and stood back up as billboarded sprites.
##
## A region PNG has its buildings painted flat into the terrain. This finds them, paints the
## ground back in underneath, and re-renders each one as an upright sprite, so a house reads
## as standing on the map rather than lying on it. Prototyped in
## `debug/worldmap/standing-structures.html`; the reasoning is `docs/WORLDMAP_DESIGN.md`.
##
## HOW STRUCTURES ARE FOUND, AND WHY THAT IS TEMPORARY. temp2 has a seven-colour palette in
## which three colours -- near-white, near-black and dark teal -- appear nowhere except on
## buildings, so a colour key plus connected components finds all nine exactly. That is a
## property of ONE MAP'S PALETTE, not a method, and it was measured rather than assumed:
## `debug/worldmap/probe_segmentation_limits.gd` runs the identical rule over temp and gets
## 302 components of which 94% are four pixels or smaller, because temp is dithered and no
## colour in it is exclusive to anything. Trees are worse again and cannot work at all --
## `probe_tree_key.gd` shows tree-green and grass-green are one continuous population with no
## trough to threshold at, because a tree is made of the same pigment as what it stands in.
##
## So this extractor is a BOOTSTRAP for temp2, not the pipeline. The pipeline is a per-region
## prop layer: a second image the same size, transparent except where props sit, with the
## ground painted complete underneath it. That makes extraction exact instead of inferred,
## works for trees, and deletes the ground-patch guesswork entirely. Everything below the
## extraction -- the billboard maths, the anchoring, the atlas -- is indifferent to where the
## sprite list came from and survives that change unaltered.

class_name WorldMapProps
extends Node3D

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Anything smaller than this is dithering noise rather than a building. It is a guard on a
## detector already known not to generalise, not a claim that it now does.
const MIN_COMPONENT_PX := 8

## Structures taller than they are wide are towers. On temp2 that is 8x13 against 8x7, which
## is not close enough to need anything cleverer.
const TOWER_ASPECT := 1.2

var _structures: Array = []
var _spriteSheet: ImageTexture
var _tilePixels := Uniforms.DEFAULT_TILE_PIXELS
var _mode := Uniforms.BILLBOARD_OFF


## Rebuilds from a region. Returns the ground texture the caller should hand to
## `WorldMapGround` -- the source with the structures painted out -- plus a count for the
## readout. Returns the source texture unchanged when the mode is off, so nothing about the
## shipped ground rig changes until structures are explicitly asked for.
func rebuild(source: Texture2D, tilePixels: int, mode: String) -> Dictionary:
	_clearSprites()
	_structures.clear()
	_tilePixels = maxi(1, tilePixels)
	_mode = mode
	if source == null or mode == Uniforms.BILLBOARD_OFF:
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}

	var image := source.get_image()
	if image == null:
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)

	_structures = _findStructures(image)
	if _structures.is_empty():
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}

	var ground := _patchGround(image)
	_spriteSheet = ImageTexture.create_from_image(_buildSpriteSheet(image))
	_buildSprites()

	var towers := 0
	for s in _structures:
		if s["kind"] == "tower":
			towers += 1
	return {
		"ground": ImageTexture.create_from_image(ground),
		"count": _structures.size(),
		"houses": _structures.size() - towers,
		"towers": towers,
	}


## Applies the billboard mode. `gain` is the only one that needs the camera, because its
## correction is per-sprite and depends on how far away each sprite is.
func applyMode(mode: String, camera: WorldMapCameraRig) -> void:
	_mode = mode
	for child in get_children():
		var sprite := child as Sprite3D
		if sprite == null:
			continue
		# Godot's own full billboard IS the lambda = 1 case: with yaw pinned, facing the
		# camera plane is exactly rotating the quad's up-axis onto the camera's. That is
		# why this mode needs no maths here -- the engine already does it, correctly, and
		# for free. See WORLDMAP_DESIGN.md for the derivation it matches.
		sprite.billboard = (
			BaseMaterial3D.BILLBOARD_ENABLED
			if mode == Uniforms.BILLBOARD_FACE
			else BaseMaterial3D.BILLBOARD_DISABLED
		)
		if mode != Uniforms.BILLBOARD_GAIN:
			sprite.scale.y = 1.0
	if mode == Uniforms.BILLBOARD_GAIN:
		updateGain(camera)


## Per-sprite height correction for the world-vertical mode, recomputed as the camera moves.
##
## A world-vertical quad is squashed by `f / D` -- ground distance over view depth -- which
## is NOT cos(pitch): that value holds only at the exact centre of the frame, and across one
## frame at the reference framing the squash runs 0.33 near to 0.76 far. So the correction
## has to be per sprite, from that sprite's own distance, and it is a closed-form solve
## rather than a fudge:
##
##     h = h0 * D / (f + h0 * sin(pitch))
##
## which is the general `h0*D / (A*D + yb*B + h0*B)` with the up-axis world-vertical, where
## `A*D + yb*B` collapses to `f` exactly.
func updateGain(camera: WorldMapCameraRig) -> void:
	if camera == null or _mode != Uniforms.BILLBOARD_GAIN:
		return
	# Worked in the rig's own terms -- pitch and position -- rather than through
	# `global_transform`. Props and camera are siblings under an origin-parented map, so the
	# two agree, and this cannot be caught out by node order or by a probe that drives the
	# rig before the tree is live.
	var pitch := deg_to_rad(-camera.rotation_degrees.x)
	var cs := cos(pitch)
	var sn := sin(pitch)
	var camPos := camera.position
	for child in get_children():
		var sprite := child as Sprite3D
		if sprite == null:
			continue
		var base := sprite.position
		var depth := -((base.y - camPos.y) * sn + (base.z - camPos.z) * cs)
		var forward := camPos.z - base.z
		var h0: float = sprite.get_meta("prop_height", 1.0)
		var denom := forward + h0 * sn
		# The correction is NOT bounded below by 1. Past the frame centre a vertical quad is
		# magnified rather than squashed -- the factor f/D passes through cos(pitch) at the
		# centre and keeps climbing to 1/cos(pitch) -- so far sprites are corrected DOWNWARD.
		# Clamping at 1.0 would silently leave everything beyond the middle of the frame too
		# tall, which is the same defect this mode exists to remove.
		sprite.scale.y = clampf(depth / denom, 0.1, 8.0) if denom > 0.001 else 1.0


func structureCount() -> int:
	return _structures.size()


func _clearSprites() -> void:
	for child in get_children():
		child.queue_free()
		remove_child(child)


# --- extraction ----------------------------------------------------------------------

func _isBuilt(r: int, g: int, b: int) -> bool:
	var white := r > 200 and g > 200 and b > 200
	var black := r < 60 and g < 70 and b < 60
	var teal := absi(r - 11) < 45 and absi(g - 105) < 45 and absi(b - 106) < 45
	return white or black or teal


## Orange is a TERRAIN colour on this map, so it cannot be part of the key -- but inside a
## structure's bounding box it is the door. Keying alone left a door-shaped hole in every
## house and a door-shaped smudge on the ground where the house used to be.
func _isDoor(r: int, g: int, b: int) -> bool:
	return absi(r - 230) < 40 and absi(g - 153) < 45 and b < 80


func _findStructures(image: Image) -> Array:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			var hit := _isBuilt(int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0))
			mask[y * w + x] = 1 if hit else 0

	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	var found: Array = []
	for start in w * h:
		if mask[start] == 0 or seen[start] == 1:
			continue
		stack.clear()
		stack.push_back(start)
		seen[start] = 1
		var minx := w
		var maxx := 0
		var miny := h
		var maxy := 0
		var count := 0
		while not stack.is_empty():
			var q: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var qx := q % w
			var qy := q / w
			count += 1
			minx = mini(minx, qx)
			maxx = maxi(maxx, qx)
			miny = mini(miny, qy)
			maxy = maxi(maxy, qy)
			for dy in range(-1, 2):
				var ny := qy + dy
				if ny < 0 or ny >= h:
					continue
				for dx in range(-1, 2):
					var nx := qx + dx
					if nx < 0 or nx >= w:
						continue
					var np := ny * w + nx
					if mask[np] == 1 and seen[np] == 0:
						seen[np] = 1
						stack.push_back(np)
		if count < MIN_COMPONENT_PX:
			continue
		var bw := maxx - minx + 1
		var bh := maxy - miny + 1
		var kind := "tower" if float(bh) / float(bw) > TOWER_ASPECT else "house"
		found.append({
			"x": minx, "y": miny, "w": bw, "h": bh, "kind": kind,
			# The tower's bottom row is a painted ground shadow, not part of the building.
			# Standing it up puts a dark band under the tower's feet.
			"rows": bh - 1 if kind == "tower" else bh,
		})
	# Far to near, so painter's order is correct without a depth sort at draw time.
	found.sort_custom(func(a, b): return int(a["y"]) < int(b["y"]))
	return found


## Paints each structure out with the commonest terrain colour in a ring around it, so a
## house on sand gets sand and one on grass gets grass. Inferring what is underneath is
## exactly the guesswork a prop layer removes; the seam is visible if looked for.
func _patchGround(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(image, Rect2i(0, 0, w, h), Vector2i.ZERO)
	for s in _structures:
		var sx: int = s["x"]
		var sy: int = s["y"]
		var sw: int = s["w"]
		var sh: int = s["h"]
		var tally := {}
		for y in range(sy - 2, sy + sh + 2):
			for x in range(sx - 2, sx + sw + 2):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				if x >= sx and x < sx + sw and y >= sy and y < sy + sh:
					continue
				var c := image.get_pixel(x, y)
				var r := int(c.r * 255.0)
				var g := int(c.g * 255.0)
				var b := int(c.b * 255.0)
				if _isBuilt(r, g, b):
					continue
				var key := (r << 16) | (g << 8) | b
				tally[key] = int(tally.get(key, 0)) + 1
		var best := 0
		var bestN := -1
		for k in tally:
			if int(tally[k]) > bestN:
				bestN = int(tally[k])
				best = int(k)
		var fill := Color8((best >> 16) & 255, (best >> 8) & 255, best & 255)
		# The whole bounding box, not the keyed pixels: see `_isDoor`.
		for y in range(sy, sy + sh):
			for x in range(sx, sx + sw):
				if x >= 0 and y >= 0 and x < w and y < h:
					out.set_pixel(x, y, fill)
	return out


## The sprite atlas: every structure's bounding box, minus the terrain showing through its
## corners. Kept at the region's own coordinates so a sprite's region_rect is simply where
## the structure was found, with no packing step to keep in sync.
func _buildSpriteSheet(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for s in _structures:
		for y in range(s["y"], s["y"] + s["rows"]):
			for x in range(s["x"], s["x"] + s["w"]):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var c := image.get_pixel(x, y)
				var r := int(c.r * 255.0)
				var g := int(c.g * 255.0)
				var b := int(c.b * 255.0)
				if not _isBuilt(r, g, b) and not _isDoor(r, g, b):
					continue
				out.set_pixel(x, y, c)
	return out


# --- sprites -------------------------------------------------------------------------

func _buildSprites() -> void:
	# One tile is one world unit, so a map pixel is 1/tile_pixels of a unit. This is the only
	# place a region's tile PIXEL size is allowed to matter; the camera never sees it.
	var pixelSize := 1.0 / float(_tilePixels)
	for s in _structures:
		var sprite := Sprite3D.new()
		sprite.texture = _spriteSheet
		sprite.region_enabled = true
		sprite.region_rect = Rect2(s["x"], s["y"], s["w"], s["rows"])
		sprite.pixel_size = pixelSize
		sprite.shaded = false
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Discard rather than blend: these are hard-edged pixel sprites, and an alpha-blended
		# sprite is drawn in the transparent pass where it neither writes depth nor sorts
		# against its neighbours reliably.
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		# Anchored at its FOOT. `offset` is in texture pixels and lifts the image so the node
		# origin sits on the bottom edge, which is what keeps the base planted when the gain
		# mode scales Y or the billboard mode spins the quad.
		sprite.centered = true
		sprite.offset = Vector2(0.0, float(s["rows"]) * 0.5)
		var worldH := float(s["rows"]) * pixelSize
		sprite.set_meta("prop_height", worldH)
		sprite.position = Vector3(
			(float(s["x"]) + float(s["w"]) * 0.5) * pixelSize,
			0.0,
			float(s["y"] + s["h"]) * pixelSize
		)
		add_child(sprite)
