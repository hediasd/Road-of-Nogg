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
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const PROP_SHADER = preload("res://assets/shaders/worldmap_prop.gdshader")

const U_ATLAS := "atlas"
const U_SPRITE_RECT := "sprite_rect"
const U_BILLBOARD_MODE := "billboard_mode"
const U_PROP_HEIGHT := "prop_height"
const U_LIGHT_TINT := "light_tint"

## Shader values for the three drawable modes, in the shader's branch order.
const SHADER_MODE := {
	Uniforms.BILLBOARD_WORLD: 0,
	Uniforms.BILLBOARD_GAIN: 1,
	Uniforms.BILLBOARD_FACE: 2,
}

var _structures: Array = []
## Solid, hole-filled outlines of each structure, for the shadows they cast.
var _silhouette: Image
var _shadows := WorldMapShadowMask.new()
## The region's own answer to "what is a building here", from `regions.json`. Empty means the
## region declares none, which is the honest state for a map whose palette is not disjoint.
var _rule: Dictionary = {}
var _spriteSheet: ImageTexture
var _tilePixels := Uniforms.DEFAULT_TILE_PIXELS
var _mapSize := Vector2i.ZERO
var _mode := Uniforms.BILLBOARD_OFF


## Rebuilds from a region. Returns the ground texture the caller should hand to
## `WorldMapGround` -- the source with the structures painted out -- plus a count for the
## readout. Returns the source texture unchanged when the mode is off, so nothing about the
## shipped ground rig changes until structures are explicitly asked for.
func rebuild(source: Texture2D, regionID: String, mode: String) -> Dictionary:
	_clearSprites()
	_structures.clear()
	_rule = RegionCatalog.structureRuleFor(regionID)
	_tilePixels = maxi(1, RegionCatalog.tilePixelsFor(regionID))
	_mode = mode
	if source == null or mode == Uniforms.BILLBOARD_OFF:
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}
	# A region that declares no structure colours has none to find. Saying so here rather than
	# running a component pass that returns nothing keeps "this map has no props" distinct
	# from "the detector failed".
	if not RegionCatalog.hasStructureRule(regionID):
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}

	var image := source.get_image()
	if image == null:
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)

	_mapSize = Vector2i(image.get_width(), image.get_height())
	_structures = _findStructures(image)
	if _structures.is_empty():
		return {"ground": source, "count": 0, "houses": 0, "towers": 0}

	var ground := _patchGround(image)
	var sheet := _buildSpriteSheet(image)
	_spriteSheet = ImageTexture.create_from_image(sheet)
	_silhouette = _buildSilhouette(sheet)
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


## Applies a framing to every prop. Cheap and allocation-free: the billboard modes all live in
## the shader now, so nothing here walks geometry or rescales a node.
##
## `updateGain`'s per-frame CPU pass is gone with it. It existed only because Sprite3D's own
## material could not be replaced without losing its billboarding, so the one mode that needed
## maths had to do it on the CPU.
func applyFraming(framing: Dictionary) -> void:
	var f := Uniforms.complete(framing)
	var mode := str(f[Uniforms.K_BILLBOARD])
	_mode = mode
	if not SHADER_MODE.has(mode):
		return
	var sun := WorldMapSun.at(f)
	_rebuildShadows(f, sun)
	var tint: Color = sun["tint"]
	var strength: float = f[Uniforms.K_LIGHT_TINT]
	# light_tint blends out to neutral so the day cycle can be taken back out without
	# unpicking it, the same way the sketch's Light tint slider does.
	var light := Vector3(
		1.0 + (tint.r - 1.0) * strength,
		1.0 + (tint.g - 1.0) * strength,
		1.0 + (tint.b - 1.0) * strength
	)
	for child in get_children():
		var quad := child as MeshInstance3D
		if quad == null:
			continue
		var material := quad.material_override as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter(U_BILLBOARD_MODE, int(SHADER_MODE[mode]))
		material.set_shader_parameter(U_LIGHT_TINT, light)
		material.set_shader_parameter(Uniforms.U_FOG_START, f[Uniforms.K_FOG_START])
		material.set_shader_parameter(Uniforms.U_FOG_END, f[Uniforms.K_FOG_END])
		material.set_shader_parameter(Uniforms.U_FOG_CURVE, f[Uniforms.K_FOG_CURVE])
		material.set_shader_parameter(
			Uniforms.U_FOG_COLOR, f.get(Uniforms.K_FOG_COLOR, Color.WHITE)
		)


## The cast-shadow mask, in map-pixel space, or null when nothing casts one.
func shadowTexture() -> ImageTexture:
	return _shadows.texture()


## The shadow mask as an Image, for probes. See `WorldMapShadowMask.image()`.
func shadowImage() -> Image:
	return _shadows.image()


## Read-only views for probes. The shadow decisions live in map-pixel space, so measuring them
## means reading these rather than a render.
func silhouetteImage() -> Image:
	return _silhouette


func spriteSheetImage() -> Image:
	return _spriteSheet.get_image() if _spriteSheet != null else null


func structureAt(index: int) -> Dictionary:
	return _structures[index] if index >= 0 and index < _structures.size() else {}


func structureCount() -> int:
	return _structures.size()


## A structure's PAINTED height-to-width ratio -- what its on-screen box should measure if the
## billboard is doing its job. 0.875 for temp2's houses, 1.500 for its towers.
func artAspect(index: int) -> float:
	if index < 0 or index >= _structures.size():
		return 0.0
	var s: Dictionary = _structures[index]
	return float(s["rows"]) / float(s["w"])


## Redraws the cast-shadow mask and hands it to the ground, which is where a shadow lands.
##
## Pushed to the sibling Ground rather than routed through whoever owns the scene: the shadow
## belongs to the props that cast it, the ground is only the surface it falls on, and a caller
## in between would have to know about both for no reason.
func _rebuildShadows(framing: Dictionary, sun: Dictionary) -> void:
	var strength: float = framing[Uniforms.K_SHADOW_STRENGTH]
	var step: Vector2 = sun["shadow_step"] if bool(sun["up"]) else Vector2.ZERO
	if strength <= 0.0:
		step = Vector2.ZERO
	_shadows.rebuild(
		_structures, _silhouette, _mapSize, step, float(framing[Uniforms.K_SHADOW_SPREAD])
	)
	var ground := get_parent().get_node_or_null("Ground") as WorldMapGround if get_parent() != null else null
	if ground != null:
		ground.setShadowMask(_shadows.texture(), strength)


func _clearSprites() -> void:
	for child in get_children():
		child.queue_free()
		remove_child(child)


# --- extraction ----------------------------------------------------------------------

## Channel distance rather than equality: the PNG round-trips through import, so a colour
## comes back near its authored value rather than exactly on it.
func _matches(r: int, g: int, b: int, palette: Array, tolerance: float) -> bool:
	for entry in palette:
		var c: Color = entry
		if (
			absf(float(r) - c.r * 255.0) < tolerance
			and absf(float(g) - c.g * 255.0) < tolerance
			and absf(float(b) - c.b * 255.0) < tolerance
		):
			return true
	return false


func _isBuilt(r: int, g: int, b: int) -> bool:
	return _matches(r, g, b, _rule.get("KEY_COLORS", []), float(_rule.get("KEY_TOLERANCE", 45.0)))


## A door colour is one a structure shares with the terrain, so it cannot be part of the key --
## on temp2 the door orange is also a terrain colour. It counts as structure only INSIDE a
## bounding box the key already found. Keying alone left a door-shaped hole in every house and
## a door-shaped smudge on the ground where the house used to be.
func _isDoor(r: int, g: int, b: int) -> bool:
	return _matches(r, g, b, _rule.get("DOOR_COLORS", []), float(_rule.get("DOOR_TOLERANCE", 42.0)))


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
		if count < int(_rule.get("MIN_PIXELS", 8)):
			continue
		var bw := maxx - minx + 1
		var bh := maxy - miny + 1
		var kind := "tower" if float(bh) / float(bw) > float(_rule.get("TOWER_ASPECT", 1.2)) else "house"
		var trim: int = int(_rule.get("TOWER_TRIM_ROWS", 0)) if kind == "tower" else 0
		found.append({
			"x": minx, "y": miny, "w": bw, "h": bh, "kind": kind,
			# Rows the region asks to be dropped from a tower's foot: temp2 paints a ground
			# shadow there, and standing it up puts a dark band under the tower's feet.
			"rows": maxi(1, bh - trim),
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


## A SOLID outline per structure, for its shadow. Deliberately not the sprite's alpha:
## transparent pixels INSIDE a structure -- the tower's open belfry, the gap beside a doorway --
## must not punch holes in its shadow, because a building has a solid door and glazed windows
## and light does not pour through the middle of it. Taking the alpha directly gave the tower a
## shadow with a hole through it.
##
## Background is found by flooding IN FROM THE BOUNDING BOX EDGE, four-connected; anything the
## flood cannot reach is solid whatever colour it was. Four-connected rather than eight on
## purpose: it is the conservative direction, and filling a pixel that should have been open
## costs less here than leaking through a diagonal gap and hollowing the shadow out.
func _buildSilhouette(sheet: Image) -> Image:
	var w := sheet.get_width()
	var h := sheet.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_R8)
	out.fill(Color(0.0, 0.0, 0.0, 1.0))
	for s in _structures:
		var sx: int = s["x"]
		var sy: int = s["y"]
		var bw: int = s["w"]
		var bh: int = s["rows"]
		var outside := PackedByteArray()
		outside.resize(bw * bh)
		var queue := PackedInt32Array()
		for lx in bw:
			for ly in [0, bh - 1]:
				_seedFlood(sheet, outside, queue, sx, sy, bw, bh, lx, ly)
		for ly in bh:
			for lx in [0, bw - 1]:
				_seedFlood(sheet, outside, queue, sx, sy, bw, bh, lx, ly)
		while not queue.is_empty():
			var q: int = queue[queue.size() - 1]
			queue.remove_at(queue.size() - 1)
			var qx := q % bw
			var qy := q / bw
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_seedFlood(sheet, outside, queue, sx, sy, bw, bh, qx + d.x, qy + d.y)
		for ly in bh:
			for lx in bw:
				if outside[ly * bw + lx] == 0:
					out.set_pixel(sx + lx, sy + ly, Color(1.0, 0.0, 0.0, 1.0))
	return out


func _seedFlood(
	sheet: Image, outside: PackedByteArray, queue: PackedInt32Array,
	sx: int, sy: int, bw: int, bh: int, lx: int, ly: int
) -> void:
	if lx < 0 or ly < 0 or lx >= bw or ly >= bh:
		return
	var index := ly * bw + lx
	if outside[index] == 1:
		return
	if sheet.get_pixel(sx + lx, sy + ly).a >= 0.5:
		return
	outside[index] = 1
	queue.push_back(index)


# --- sprites -------------------------------------------------------------------------

func _buildSprites() -> void:
	# One tile is one world unit, so a map pixel is 1/tile_pixels of a unit. This is the only
	# place a region's tile PIXEL size is allowed to matter; the camera never sees it.
	var pixelSize := 1.0 / float(_tilePixels)
	var atlasSize := Vector2(float(_spriteSheet.get_width()), float(_spriteSheet.get_height()))
	for s in _structures:
		var worldW := float(s["w"]) * pixelSize
		var worldH := float(s["rows"]) * pixelSize

		var quad := QuadMesh.new()
		quad.size = Vector2(worldW, worldH)
		# Anchored at its FOOT. The shader's billboard turns the quad about the model origin
		# and the gain mode scales VERTEX.y from it, so both keep the base planted only
		# because the origin IS the base.
		quad.center_offset = Vector3(0.0, worldH * 0.5, 0.0)

		var material := ShaderMaterial.new()
		material.shader = PROP_SHADER
		material.set_shader_parameter(U_ATLAS, _spriteSheet)
		material.set_shader_parameter(U_SPRITE_RECT, Vector4(
			float(s["x"]) / atlasSize.x,
			float(s["y"]) / atlasSize.y,
			float(s["w"]) / atlasSize.x,
			float(s["rows"]) / atlasSize.y
		))
		material.set_shader_parameter(U_PROP_HEIGHT, worldH)
		material.set_shader_parameter(U_BILLBOARD_MODE, int(SHADER_MODE.get(_mode, 2)))

		var instance := MeshInstance3D.new()
		instance.mesh = quad
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.set_meta("prop_height", worldH)
		instance.set_meta("prop_rows", int(s["rows"]))
		instance.set_meta("prop_kind", str(s["kind"]))
		instance.set_meta("prop_rect", Rect2(
			float(s["x"]), float(s["y"]), float(s["w"]), float(s["rows"])
		))
		instance.position = Vector3(
			(float(s["x"]) + float(s["w"]) * 0.5) * pixelSize,
			0.0,
			float(s["y"] + s["h"]) * pixelSize
		)
		add_child(instance)
