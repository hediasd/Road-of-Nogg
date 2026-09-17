## Do the billboard modes still land on painted proportions now that the shader does them?
##
## This is a RENDERED measurement, not a property read. When the modes lived on the CPU the
## probe could ask a sprite for its scale; the shader gives nothing back, and re-deriving the
## formula here would only test that the same arithmetic is written twice. So it renders the
## scene with props off and with props on, diffs the two, and measures the boxes the props
## actually occupy on screen.
##
## The bar is the one the sketch set: a prop's on-screen h/w equals its PAINTED h/w, at every
## distance. `world` is expected to fail it -- that mode is the uncorrected baseline and is
## kept because it is what the defect looks like.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

const REGION := "temp2"
const SIZE := Vector2i(900, 560)

var _vp: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _props: WorldMapProps
var _region: Dictionary
var _framing: Dictionary


## Every structure stands on the centre of a map tile, and the move did not resize it.
##
## Separate from the rendered measurement below and deliberately so: this part needs no
## renderer, so it still reports under `--headless` where the capture path cannot run at all.
##
## THE SECOND HALF IS THE POINT. Tile-centring moves a sprite's ORIGIN; the billboard modes
## agree with each other because they force the same `h/w` from the same width and height, none
## of which the move touches. Asserting the proportions are untouched is what says the rendered
## agreement below cannot have been disturbed by the move -- rather than re-deriving it here,
## which would only check that the same arithmetic is written twice.
func _checkTileCentring() -> void:
	var tile := Uniforms.TILE_PIXELS
	var offCentre := 0
	var resized := 0
	for i in _props.structureCount():
		var s: Dictionary = _props.structureAt(i)
		var baseZ := float(int(s["y"]) + int(s["h"])) / float(tile)
		var tileY: int = (int(s["y"]) + int(s["h"]) - 1) / tile
		if absf(baseZ - (float(tileY) + 0.5)) > 0.001:
			offCentre += 1
		var centreX := (float(s["x"]) + float(s["w"]) * 0.5) / float(tile)
		var tileX: int = int(floorf(centreX))
		if absf(centreX - (float(tileX) + 0.5)) > 0.001:
			offCentre += 1
		# The painted proportions the billboard modes are measured against. Unchanged by the
		# move, because `_standOnTiles` writes only x and y.
		var aspect := _props.artAspect(i)
		var expected := 1.5 if str(s["kind"]) == "tower" else 0.875
		if absf(aspect - expected) > 0.001:
			resized += 1
	print("tile centring: %d of %d structures off centre, %d resized by the move" % [
		offCentre, _props.structureCount(), resized
	])
	if offCentre > 0:
		print("  FAIL a structure does not stand on a tile centre")
	if resized > 0:
		print("  FAIL the move changed a structure's painted proportions")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var map: Node3D = WorldMapScene.instantiate()
	_vp.add_child(map)
	_ground = map.get_node("Ground")
	_camera = map.get_node("Camera")
	_props = map.get_node("Props")
	_camera.current = true

	_region = RegionCatalog.loadRegion(REGION)
	_framing = Uniforms.completeForRegion(
		FramingCatalog.framingFor(FramingCatalog.CURVED_CLOSE),
		_region["fog_color"], _region["void_color"]
	)
	# Pulled back and flat so all nine structures are on screen and separated. Overlapping
	# boxes would merge into one component and quietly measure the wrong thing.
	# Height is what decides whether all nine fit. 22 framed them before structures stood on
	# their tile centres; that move carries the northernmost tower half a tile further north,
	# which pushed its top off the frame and silently cropped the measurement.
	_framing[Uniforms.K_HEIGHT] = 26.0
	_framing[Uniforms.K_CURVATURE] = 0.0
	_framing[Uniforms.K_FOG_START] = 400.0
	# SHADOWS OFF, both kinds, and this is load-bearing rather than tidiness. `_propBox` finds a
	# prop by keying on building colours, on the stated assumption that the patched ground
	# contains none of them. A shadow breaks that assumption: shadows are palette-SNAPPED, and
	# the palette is read from the whole region, so a darkened ground pixel can legitimately snap
	# onto one of the three colours that are otherwise unique to buildings. It then reads as prop.
	#
	# This did not matter while shadow_strength defaulted to 0. It does now that it defaults to
	# 0.5, and the symptom is loud: every mode, `world` included, reported an identical 718.8%
	# error with a house measured 303 px tall against an expected 37 -- the box had swallowed the
	# shadow. Identical numbers across modes that are supposed to differ is the tell.
	_framing[Uniforms.K_SHADOW_STRENGTH] = 0.0
	_framing[Uniforms.K_CLOUDS] = Uniforms.CLOUDS_OFF

	# Learn the count before the baseline: `off` clears the structure list, so asking after it
	# reports zero and the loop below silently measures nothing.
	_props.rebuild(_region["texture"], REGION, Uniforms.BILLBOARD_FACE)
	_checkTileCentring()
	var total := _props.structureCount()
	# The baseline must carry the PATCHED ground with the props merely hidden. Taken in `off`
	# mode it carries the original art with all nine buildings still painted flat, so every
	# patch site differs and the diff swells to the whole frame.
	var baseline := await _shot(Uniforms.BILLBOARD_FACE, -1)
	# What one tile measures on screen, so a prop's width can be checked rather than assumed:
	# every structure here is exactly 1 tile wide.
	# Dump one structure per mode so the box can be looked at rather than inferred.
	for m in [Uniforms.BILLBOARD_WORLD, Uniforms.BILLBOARD_FACE]:
		var s := await _shot(m, 1)
		s.save_png("user://probe_scratch/worldmap/mode_%s.png" % m)
	var readout := _camera.framingReadout(SIZE)
	print("one tile = %.1f px across at this framing; every structure is 1 tile wide" % [
		float(readout["buffer_px_per_tile"])
	])
	var failures := 0
	for mode in [Uniforms.BILLBOARD_WORLD, Uniforms.BILLBOARD_GAIN, Uniforms.BILLBOARD_FACE]:
		var worst := 0.0
		var measured := 0
		var lines: Array = []
		# ONE structure at a time. Rendered together they merge into single components at any
		# framing that fits them all, and a merged box measures nothing.
		for index in total:
			var shot := await _shot(mode, index)
			var box := _propBox(shot)
			if box.size.y <= 0:
				continue
			# A box touching the frame edge has been CUT, and a cut box under-measures
			# silently -- which is exactly what happened when tile-centring moved the
			# northernmost tower half a tile further north: its top left the frame, it
			# measured 50 px against 63, and it read as a billboard regression that did not
			# exist. Fail loudly instead of quietly reporting the crop.
			if box.position.y <= 0 or box.position.y + box.size.y >= SIZE.y:
				print("      FAIL #%d is clipped by the frame (top %d, bottom %d of %d) --"
					% [index, box.position.y, box.position.y + box.size.y - 1, SIZE.y]
					+ " the framing is too tight to measure against")
				failures += 1
				break
			# The sprite's on-screen HEIGHT is what the billboard decides, and it is the one
			# measurement pixels give reliably. Its width is taken from the projection instead:
			# a tower's foot row is `?DWWWWD?`, so its outer pixels are sand and orange and a
			# colour key sees only the middle four -- measuring width from pixels reports a
			# correct tower as half as wide as it is.
			var expectedW := _tileWidthAt(index)
			var art: float = _props.artAspect(index)
			var expectedH := expectedW * art
			var err := absf(float(box.size.y) - expectedH) / maxf(1.0, expectedH)
			worst = maxf(worst, err)
			measured += 1
			if index < 3:
				lines.append("  #%d  %d px tall, expected %.1f   (%.1f px tile, art %.3f)   err %.1f%%" % [
					index, box.size.y, expectedH, expectedW, art, err * 100.0
				])
		print("%-6s  measured %d/%d   worst aspect error %.1f%%" % [
			mode, measured, total, worst * 100.0
		])
		for line in lines:
			print(line)
		if measured == 0:
			print("      FAIL %s drew nothing" % mode)
			failures += 1
			continue
		# world is the uncorrected baseline and is SUPPOSED to be wrong; the others are not.
		if mode != Uniforms.BILLBOARD_WORLD and worst > 0.10:
			print("      FAIL %s should hold painted proportions" % mode)
			failures += 1
		if mode == Uniforms.BILLBOARD_WORLD and worst < 0.10:
			print("      FAIL world should NOT hold them -- the baseline stopped showing the defect")
			failures += 1

	print("")
	print("BILLBOARD MODES: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP PROPS OK")
	quit(1 if failures > 0 else 0)


## One tile's width in screen pixels at a given prop's base, from the camera itself. Every
## structure on temp2 is exactly one tile wide, so this is the width its sprite should have.
func _tileWidthAt(index: int) -> float:
	var quads: Array = []
	for child in _props.get_children():
		if child is MeshInstance3D:
			quads.append(child)
	if index < 0 or index >= quads.size():
		return 0.0
	var base: Vector3 = (quads[index] as MeshInstance3D).position
	var a := _camera.unproject_position(base)
	var b := _camera.unproject_position(base + Vector3(1.0, 0.0, 0.0))
	return absf(b.x - a.x)


func _shot(mode: String, only: int) -> Image:
	_framing[Uniforms.K_BILLBOARD] = mode
	var built: Dictionary = _props.rebuild(_region["texture"], REGION, mode)
	_ground.configure(
		_region["tiles"], built["ground"], _framing,
		_region["fog_color"], _region["void_color"]
	)
	_camera.applyFraming(_framing)
	var rect := _ground.regionRect()
	_camera.panTo(rect.position + rect.size * 0.5)
	_props.applyFraming(_framing)
	# `only` of -1 hides every prop, which is what the baseline needs.
	var shown := 0
	for child in _props.get_children():
		var quad := child as MeshInstance3D
		if quad != null:
			quad.visible = shown == only
			shown += 1
	for _f in 8:
		await process_frame
	return _vp.get_texture().get_image()


## The box of BUILDING-COLOURED pixels in a frame. No baseline and no diff: the patched ground
## provably contains none of these colours (probe_patch_dump.gd measures zero), so any pixel
## carrying one belongs to the prop. Diffing against a baseline instead made the measurement
## depend on the ground texture being byte-identical between shots, which is a second thing to
## get right for no gain.
##
## Only white, black and dark teal are keyed. The door orange is deliberately left out: it is
## also a terrain colour, so it cannot distinguish a prop from the ground it stands on.
func _propBox(shot: Image) -> Rect2i:
	var w := shot.get_width()
	var h := shot.get_height()
	var minx := w
	var maxx := -1
	var miny := h
	var maxy := -1
	var count := 0
	for y in h:
		for x in w:
			var c := shot.get_pixel(x, y)
			var r := c.r * 255.0
			var g := c.g * 255.0
			var b := c.b * 255.0
			var white: bool = r > 200.0 and g > 200.0 and b > 200.0
			var black: bool = r < 60.0 and g < 70.0 and b < 60.0
			var teal: bool = absf(r - 11.0) < 45.0 and absf(g - 105.0) < 45.0 and absf(b - 106.0) < 45.0
			if not (white or black or teal):
				continue
			count += 1
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
	if count < 20 or maxx < 0:
		return Rect2i(0, 0, 0, 0)

	# Width is taken at the FOOT, not across the bounding box. A world-vertical quad seen from
	# above has its top edge NEARER the camera, so the top projects wider than the base; the
	# box width is then the TOP width, and comparing that against the vertical extent measures
	# the lean as well as the proportions and makes a correct sprite look wrong. The sketch's
	# hpx/wpx used the base width, and this has to mean the same thing to be comparable.
	var footMin := w
	var footMax := -1
	for x in w:
		var c := shot.get_pixel(x, maxy)
		var r := c.r * 255.0
		var g := c.g * 255.0
		var b := c.b * 255.0
		var white: bool = r > 200.0 and g > 200.0 and b > 200.0
		var black: bool = r < 60.0 and g < 70.0 and b < 60.0
		var teal: bool = absf(r - 11.0) < 45.0 and absf(g - 105.0) < 45.0 and absf(b - 106.0) < 45.0
		if white or black or teal:
			footMin = mini(footMin, x)
			footMax = maxi(footMax, x)
	var footWidth: int = (footMax - footMin + 1) if footMax >= 0 else (maxx - minx + 1)
	return Rect2i(minx, miny, footWidth, maxy - miny + 1)
