## The three questions map-space alignment does NOT answer: what colour a shadowed pixel is,
## what happens at its edge, and how it moves.
##
## Alignment buys pixel edges. It says nothing about whether those pixels are colours the
## palette contains, nor whether the shape holds still while the sun turns.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

var _vp: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _props: WorldMapProps
var _framing: Dictionary


## Is a short caster's shadow actually less legible than a tall one's?
##
## Headless-safe and deliberately first: it reads the MASK, so it still reports under
## `--headless` where the capture path below cannot run. The premise it tests -- that a house
## needs a legibility floor a tower does not -- is the one this measurement disproved, so it
## stays here as the thing that would have to change before a floor is reconsidered.
func _shortCasterLegibility() -> void:
	var props := WorldMapProps.new()
	get_root().add_child(props)
	var region := RegionCatalog.loadRegion("temp2")
	props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_FACE)
	var f := Uniforms.completeForRegion(
		Uniforms.DEFAULTS.duplicate(true), region["fog_color"], region["void_color"])
	f[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	for hour in [8.0, 12.0, 16.0]:
		f[Uniforms.K_TIME_OF_DAY] = hour
		props.applyFraming(f)
		var mask: Image = props.shadowImage()
		var step: Vector2 = WorldMapSun.at(f)["shadow_step"]
		var tally := {"house": [0, 0], "tower": [0, 0]}
		for i in props.structureCount():
			var s: Dictionary = props.structureAt(i)
			var reach := int(ceilf(absf(step.y) * float(s["rows"]))) + 4
			var px := 0
			for y in range(maxi(0, int(s["y"]) - reach), int(s["y"]) + int(s["rows"])):
				for x in range(maxi(0, int(s["x"]) - reach),
						mini(mask.get_width(), int(s["x"]) + int(s["w"]) + reach)):
					if y < mask.get_height() and mask.get_pixel(x, y).r > 0.5:
						px += 1
			var row: Array = tally[str(s["kind"])]
			row[0] += px
			row[1] += 1
		var h: Array = tally["house"]
		var t: Array = tally["tower"]
		var hAvg := float(h[0]) / maxf(1.0, float(h[1]))
		var tAvg := float(t[0]) / maxf(1.0, float(t[1]))
		print("  %s  house %.1f px/ea   tower %.1f px/ea   ratio %.2f" % [
			WorldMapSun.clockText(hour), hAvg, tAvg, tAvg / maxf(1.0, hAvg)])
	# A ratio near 1 is the finding: `spread` widens by CASTER WIDTH, so it already gives a short
	# shadow proportionally more area than a long one. See WORLDMAP_DESIGN.md section 10.
	props.queue_free()


func _initialize() -> void:
	_shortCasterLegibility()
	_vp = SubViewport.new()
	_vp.size = Vector2i(820, 500)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var map: Node3D = WorldMapScene.instantiate()
	_vp.add_child(map)
	_ground = map.get_node("Ground")
	_camera = map.get_node("Camera")
	_props = map.get_node("Props")
	_camera.current = true

	var region := RegionCatalog.loadRegion("temp2")
	_framing = Uniforms.completeForRegion(
		FramingCatalog.framingFor(FramingCatalog.CURVED_CLOSE),
		region["fog_color"], region["void_color"]
	)
	_framing[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	_framing[Uniforms.K_SHADOW_STRENGTH] = 0.5
	_framing[Uniforms.K_HEIGHT] = 30.0
	_framing[Uniforms.K_CURVATURE] = 0.0
	_framing[Uniforms.K_FOG_START] = 400.0
	_framing[Uniforms.K_TIME_OF_DAY] = 9.0
	var built: Dictionary = _props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_FACE)
	_ground.configure(
		region["tiles"], built["ground"], _framing, region["fog_color"], region["void_color"]
	)
	var failures := 0
	print("region palette: %d colours" % _props.paletteSize())

	# --- 1. what colour is a shadowed pixel? ------------------------------------------
	# The risk the plan named: snapping may collapse two terrain colours onto ONE shadowed
	# colour and lose the boundary between them. Measured, not assumed.
	for mode in Uniforms.SHADOW_COLOR_IDS:
		_framing[Uniforms.K_SHADOW_COLOR_MODE] = mode
		await _apply()
		var colours := _distinctColours(_vp.get_texture().get_image())
		print("colour mode %-16s -> %d distinct colours on screen" % [mode, colours])
	_framing[Uniforms.K_SHADOW_COLOR_MODE] = Uniforms.SHADOW_COLOR_MULTIPLY

	# Does snapping merge terrain that was distinct? Compare the shadowed result of every
	# palette entry: if two entries land on the same snapped colour, a boundary disappears.
	var collapsed := 0
	var seen := {}
	for i in _props.paletteSize():
		var c := _props.paletteAt(i)
		var shaded := Color(c.r * 0.5, c.g * 0.5, c.b * 0.5)
		var snapped := _nearest(shaded)
		if seen.has(snapped):
			collapsed += 1
		seen[snapped] = true
	print("palette entries collapsing onto a shared shadow colour: %d of %d" % [
		collapsed, _props.paletteSize()
	])

	# --- 2. the edge ------------------------------------------------------------------
	for edge in Uniforms.SHADOW_EDGE_IDS:
		_framing[Uniforms.K_SHADOW_EDGE] = edge
		await _apply()
		var mask: Image = _props.shadowImage()
		var lit := 0
		for y in mask.get_height():
			for x in mask.get_width():
				if mask.get_pixel(x, y).r > 0.5:
					lit += 1
		print("edge %-8s -> %d shadow map px" % [edge, lit])
	_framing[Uniforms.K_SHADOW_EDGE] = Uniforms.SHADOW_EDGE_HARD

	# --- 3. how it moves --------------------------------------------------------------
	# The one that decides whether it looks CONSISTENT, and it has no analogue in a still.
	# Walk the sun in small increments and count how many mask pixels change each step. A
	# continuous sun changes a few pixels every step -- that is the crawl. A quantised one
	# changes nothing at all until it jumps.
	print("")
	print("steps   mask changes per 4-minute tick (mean)   ticks that changed at all")
	for steps in [0, 64, 32, 16]:
		_framing[Uniforms.K_SHADOW_STEPS] = float(steps)
		var previous: Image = null
		var totalChanged := 0
		var movedTicks := 0
		var ticks := 0
		for i in 24:
			_framing[Uniforms.K_TIME_OF_DAY] = 9.0 + float(i) * (4.0 / 60.0)
			await _apply()
			var mask: Image = _props.shadowImage()
			if previous != null:
				var changed := 0
				for y in mask.get_height():
					for x in mask.get_width():
						if (mask.get_pixel(x, y).r > 0.5) != (previous.get_pixel(x, y).r > 0.5):
							changed += 1
				totalChanged += changed
				ticks += 1
				if changed > 0:
					movedTicks += 1
			previous = mask.duplicate()
		print("%5d   %8.1f   %d/%d" % [
			steps, float(totalChanged) / float(maxi(1, ticks)), movedTicks, ticks
		])
		if steps == 0 and movedTicks < ticks / 2:
			print("  FAIL the unquantised control barely moved -- it proves nothing")
			failures += 1
		if steps == 16 and movedTicks >= ticks:
			print("  FAIL quantising to 16 headings did not reduce how often the mask changes")
			failures += 1

	print("")
	print("SHADOW LOOK: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP SHADOW LOOK OK")
	quit(1 if failures > 0 else 0)


func _apply() -> void:
	_ground.applyFraming(_framing)
	_camera.applyFraming(_framing)
	var rect := _ground.regionRect()
	_camera.panTo(rect.position + rect.size * 0.5)
	_props.applyFraming(_framing)
	for _f in 4:
		await process_frame


func _nearest(c: Color) -> int:
	var best := 0
	var bestDistance := 1e9
	for i in _props.paletteSize():
		var e := _props.paletteAt(i)
		var d := (c.r - e.r) * (c.r - e.r) + (c.g - e.g) * (c.g - e.g) + (c.b - e.b) * (c.b - e.b)
		if d < bestDistance:
			bestDistance = d
			best = i
	return best


func _distinctColours(image: Image) -> int:
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			seen[(int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)] = true
	return seen.size()
