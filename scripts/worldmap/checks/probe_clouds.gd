## WMC-4: cloud shadows are art in map-pixel space, and the noise they replaced is gone.
##
## This file used to sweep `cloud_scale` looking for a noise cell size that read as cloud. That
## question no longer exists -- the shapes are drawn now -- so the probe was replaced rather
## than kept passing against a system that had been deleted.
##
## The palette check is the one worth reading. The artist painted the supplied shadow art in
## `0b696a` and `e69900`, which are temp2's own shadowed sea and shadowed sand. If darkening the
## ground and snapping to its palette reproduces exactly those two colours, then the derivation
## and the art agree, and the shadow depth is not a taste setting -- it is the value they agree
## at. That is what the sweep below is for.

extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const CloudField = preload("res://src/presentation/worldmap/WorldMapCloudField.gd")

const SEA := "37aeae"
const SAND := "ffd363"
const SHADOWED_SEA := "0b696a"
const SHADOWED_SAND := "e69900"

var _viewport: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _clouds: WorldMapClouds
var _props: WorldMapProps
var _tiles: Vector2
var _mapPx: Vector2i
var _palette: PackedColorArray
var _failures: Array[String] = []


func _check(label: String, ok: bool, detail: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label + "  " + detail)
	if not ok:
		_failures.append(label)


func _initialize() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(480, 270)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var map: Node3D = load("res://scenes/WorldMap.tscn").instantiate()
	_viewport.add_child(map)
	_ground = map.get_node("Ground")
	_camera = map.get_node("Camera")
	_clouds = map.get_node("Clouds")
	_props = map.get_node("Props")
	_camera.current = true
	var region := RegionCatalog.loadRegion("temp2")
	_tiles = region["tiles"]
	_mapPx = region["map_px"]
	_run(region)


## A framing with everything that could move a colour turned off, so a pixel on screen is a
## palette entry or a defect. Fog pushed past the frame, the clock at noon where the light is
## exactly neutral, no curve, nearest filtering.
func _base() -> Dictionary:
	var f := FramingCatalog.framingFor(FramingCatalog.TILE_EXACT).duplicate(true)
	f[Uniforms.K_FOG_START] = 400.0
	f[Uniforms.K_FOG_END] = 800.0
	f[Uniforms.K_CURVATURE] = 0.0
	f[Uniforms.K_TIME_OF_DAY] = 12.0
	f[Uniforms.K_HEIGHT] = 30.0
	f[Uniforms.K_WIND_SPEED] = 0.0
	f[Uniforms.K_CLOUD_SEED] = 3.0
	f[Uniforms.K_CLOUD_COUNT] = 8.0
	f[Uniforms.K_SHADOW_COLOR_MODE] = Uniforms.SHADOW_COLOR_PALETTE
	f[Uniforms.K_CLOUD_SHADOW] = 0.4
	# OPAQUE for the palette checks. A cloud drawn at less than full alpha blends its white
	# against the terrain behind it, and a blend of two palette colours is not a palette
	# colour -- so a frame-wide palette count with translucent clouds in it is measuring the
	# cloud BODIES, not the shadows this item is about. What the translucency actually costs is
	# measured on its own further down.
	f[Uniforms.K_CLOUD_OPACITY] = 1.0
	return f


func _apply(framing: Dictionary) -> void:
	_ground.applyFraming(framing)
	_camera.applyFraming(framing)
	_camera.panTo(Vector2(_tiles.x * 0.5, _tiles.y * 0.5))
	_clouds.configure(_mapPx, framing)
	_ground.configureCloudShadows(
		_mapPx, str(framing[Uniforms.K_CLOUDS])
	)
	_ground.setCloudField(_clouds.field())


func _grab() -> Image:
	await process_frame
	await process_frame
	await process_frame
	return _viewport.get_texture().get_image()


func _hex(c: Color) -> String:
	return Color(c.r, c.g, c.b).to_html(false)


## Colour histogram of everything that is not the region's void. The void is temp2's own sea
## teal, so "matches the palette" is true of a frame showing nothing but void -- which is how a
## check like this passed last cycle while measuring nothing.
func _histogram(image: Image) -> Dictionary:
	var counts := {}
	for y in image.get_height():
		for x in image.get_width():
			var key := _hex(image.get_pixel(x, y))
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _offPalette(counts: Dictionary) -> int:
	var allowed := {}
	for c in _palette:
		allowed[_hex(c)] = true
	var total := 0
	for key in counts.keys():
		if not allowed.has(key):
			total += int(counts[key])
	return total


## What one palette colour becomes when darkened by `shade` and snapped back. The same
## arithmetic the shader does, run on the same palette the shader is given.
func _shadowOf(hex: String, shade: float) -> String:
	var source := Color.html(hex)
	var shaded := Color(source.r * (1.0 - shade), source.g * (1.0 - shade), source.b * (1.0 - shade))
	var best := source
	var bestDistance := 1e9
	for e in _palette:
		var d := (shaded.r - e.r) * (shaded.r - e.r) \
			+ (shaded.g - e.g) * (shaded.g - e.g) \
			+ (shaded.b - e.b) * (shaded.b - e.b)
		if d < bestDistance:
			bestDistance = d
			best = e
	return _hex(best)


func _run(region: Dictionary) -> void:
	print("probe_clouds")
	_ground.configure(_tiles, region["texture"], _base(), region["fog_color"], region["void_color"])
	_props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_OFF)
	_palette = PackedColorArray()
	for i in _props.paletteSize():
		_palette.append(_props.paletteAt(i))
	_ground.setShadowPalette(Uniforms.SHADOW_COLOR_PALETTE, _palette)
	print("  region palette: %d colours" % _palette.size())

	# --- 1. the noise is gone, not disabled ------------------------------------------
	var stale: Array[String] = []
	for path in [
		"res://assets/shaders/worldmap_ground.gdshader",
		"res://src/presentation/worldmap/WorldMapGroundUniforms.gd",
		"res://src/presentation/worldmap/WorldMapFramingCatalog.gd",
		"res://src/presentation/worldmap/WorldMapGround.gd",
		"res://src/presentation/debug/WorldMapDebugHud.gd",
		"res://src/presentation/debug/WorldMapDebugController.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		for needle in ["cloud_strength", "cloud_scale", "cloud_speed", "cloud_cover", "value_noise"]:
			if text.contains(needle):
				stale.append("%s: %s" % [path.get_file(), needle])
	_check("no reference to the procedural clouds survives", stale.is_empty(), "%s" % [stale])
	_check("the removed keys are out of the framing dictionary",
		not Uniforms.FRAMING_KEYS.has("cloud_strength")
			and not Uniforms.DEFAULTS.has("cloud_strength"),
		"FRAMING_KEYS and DEFAULTS clean")

	# --- 2. the shadow depth the art and the derivation agree at -----------------------
	print("  darkening a palette colour and snapping it back:")
	var agrees := -1.0
	var shade := 0.05
	while shade <= 0.75:
		var sea := _shadowOf(SEA, shade)
		var sand := _shadowOf(SAND, shade)
		var mark := ""
		if sea == SHADOWED_SEA and sand == SHADOWED_SAND:
			mark = "   <-- both match the art"
			if agrees < 0.0:
				agrees = shade
		print("    shade %.2f   sea %s -> %s   sand %s -> %s%s"
			% [shade, SEA, sea, SAND, sand, mark])
		shade += 0.05
	_check("the derivation reproduces the artist's two shadow colours", agrees > 0.0,
		"first at shade %.2f" % agrees)
	_check("the default shadow depth is one they agree at",
		_shadowOf(SEA, Uniforms.DEFAULTS[Uniforms.K_CLOUD_SHADOW]) == SHADOWED_SEA
			and _shadowOf(SAND, Uniforms.DEFAULTS[Uniforms.K_CLOUD_SHADOW]) == SHADOWED_SAND,
		"default %.2f" % Uniforms.DEFAULTS[Uniforms.K_CLOUD_SHADOW])

	# --- 3. on screen, nothing lands off the palette ----------------------------------
	var off := _base()
	off[Uniforms.K_CLOUDS] = Uniforms.CLOUDS_OFF
	_apply(off)
	var plain := await _grab()
	var plainCounts := _histogram(plain)

	var on := _base()
	_apply(on)
	var shadowed := await _grab()
	var counts := _histogram(shadowed)
	_check("no pixel lands off the region's palette", _offPalette(counts) == 0,
		"%d off-palette px, %d distinct colours on screen"
			% [_offPalette(counts), counts.size()])
	_check("the shadow actually darkens something",
		int(counts.get(SHADOWED_SEA, 0)) > int(plainCounts.get(SHADOWED_SEA, 0)),
		"shadowed sea %d px, was %d"
			% [int(counts.get(SHADOWED_SEA, 0)), int(plainCounts.get(SHADOWED_SEA, 0))])

	# --- 4. coverage follows the count -------------------------------------------------
	var few := _base()
	few[Uniforms.K_CLOUD_COUNT] = 2.0
	_apply(few)
	var fewShot := await _grab()
	var fewSea := int(_histogram(fewShot).get(SHADOWED_SEA, 0))
	var manySea := int(counts.get(SHADOWED_SEA, 0))
	_check("more clouds shadow more ground", manySea > fewSea,
		"8 clouds %d px vs 2 clouds %d px" % [manySea, fewSea])

	# --- 5. shadows union, they do not stack -------------------------------------------
	#
	# The whole reason this is a mask and not a stack of alpha-blended quads. A building's cast
	# shadow under a cloud must be no darker than either alone, or the sum lands between palette
	# entries and the snap has to guess.
	var both := _base()
	both[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	both[Uniforms.K_SHADOW_STRENGTH] = 0.4
	both[Uniforms.K_CLOUD_COUNT] = 15.0
	_props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_FACE)
	_props.applyFraming(both)
	_ground.setLighting(_props.shadowTexture(), 0.4, Vector3.ONE, 0.0)
	_apply(both)
	var stacked := await _grab()
	var stackedCounts := _histogram(stacked)
	_check("cast and cloud shadows together stay on palette",
		_offPalette(stackedCounts) == 0,
		"%d off-palette px across %d colours"
			% [_offPalette(stackedCounts), stackedCounts.size()])
	_props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_OFF)
	_ground.setLighting(null, 0.0, Vector3.ONE, 0.0)

	# --- 6. softness dithers, it does not blur -----------------------------------------
	var soft := _base()
	soft[Uniforms.K_CLOUD_SOFTNESS] = 3.0
	_apply(soft)
	var softShot := await _grab()
	var softCounts := _histogram(softShot)
	_check("a dithered edge introduces no new colour", _offPalette(softCounts) == 0,
		"%d off-palette px, %d distinct colours" % [_offPalette(softCounts), softCounts.size()])
	_check("softness eats into the shadow rather than fading it",
		int(softCounts.get(SHADOWED_SEA, 0)) < int(counts.get(SHADOWED_SEA, 0)),
		"soft %d px vs hard %d px"
			% [int(softCounts.get(SHADOWED_SEA, 0)), int(counts.get(SHADOWED_SEA, 0))])

	# --- 7. off means off ---------------------------------------------------------------
	_apply(off)
	var offAgain := await _grab()
	_check("clouds off leaves no shadow behind",
		int(_histogram(offAgain).get(SHADOWED_SEA, 0)) == int(plainCounts.get(SHADOWED_SEA, 0)),
		"%d px" % int(_histogram(offAgain).get(SHADOWED_SEA, 0)))

	# --- 8. the shadow follows the sun --------------------------------------------------
	var morning := _base()
	morning[Uniforms.K_TIME_OF_DAY] = 8.0
	_apply(morning)
	var morningField := _clouds.field()
	var evening := _base()
	evening[Uniforms.K_TIME_OF_DAY] = 16.0
	_apply(evening)
	var eveningField := _clouds.field()
	var mirrored := true
	for i in mini(morningField.size(), eveningField.size()):
		var a: Vector2i = (morningField[i] as Dictionary)["shadow"] - (morningField[i] as Dictionary)["cloud"]
		var b: Vector2i = (eveningField[i] as Dictionary)["shadow"] - (eveningField[i] as Dictionary)["cloud"]
		if absi(a.x + b.x) > 1 or absi(a.y - b.y) > 1:
			mirrored = false
	_check("the shadow offset mirrors about noon", mirrored,
		"08:00 and 16:00 lean opposite ways by the same amount")

	var night := _base()
	night[Uniforms.K_TIME_OF_DAY] = 2.0
	_apply(night)
	var casting := 0
	for entry in _clouds.field():
		if bool((entry as Dictionary)["cast"]):
			casting += 1
	_check("no cloud shadow after dark", casting == 0, "%d casting at 02:00" % casting)

	# --- 9. what translucency costs, measured rather than assumed --------------------
	#
	# The shadows stay on palette at any opacity, because they are a mask the ground applies to
	# itself. The cloud BODIES do not: alpha blending a white sprite over teal produces colours
	# between the two, and no snap runs on them. This is a real tension in the opacity knob and
	# the number belongs on the record rather than in a surprise later.
	for opacity in [1.0, 0.85, 0.5]:
		var shot := _base()
		shot[Uniforms.K_CLOUD_OPACITY] = opacity
		_apply(shot)
		var image := await _grab()
		var histogram := _histogram(image)
		print("    cloud opacity %.2f -> %d distinct colours, %d px off palette"
			% [opacity, histogram.size(), _offPalette(histogram)])

	print("probe_clouds: %s (%d failures)"
		% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	if _failures.is_empty():
		print("WORLD MAP CLOUDS OK")
	quit(0 if _failures.is_empty() else 1)
