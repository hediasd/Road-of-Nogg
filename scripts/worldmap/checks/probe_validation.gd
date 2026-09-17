## MAP-6 final validation harness. Renders the real rig through a SubViewport and reads
## frames back, so every claim below is checked against pixels rather than against the
## maths that produced them.
##
## Checks, one per "adds to final validation" line in the cycle plan:
##   MAP-1  haze, void, curvature and cloud shadows each independently switchable
##   MAP-2  all seven presets load and none produces a black frame
##   MAP-3  panning to each region corner in the fit preset never shows void
##   MAP-4  the region loads by id and its tile dimensions match the texture
## MAP-5's dropdown/command-line parity is checked outside this file, by running the
## debug scene once per preset and diffing the printed settings blocks.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")

const OUT_DIR := "user://probe_scratch/worldmap"
const BUFFER := Vector2i(384, 216)
## Void is recoloured to a value the map art cannot contain, so "is there void on screen"
## is an exact pixel test rather than a judgement about dark green.
const VOID_PROBE := Color(1.0, 0.0, 1.0, 1.0)

var _viewport: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _tiles: Vector2
var _failures: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = BUFFER
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var map: Node3D = load("res://scenes/WorldMap.tscn").instantiate()
	_viewport.add_child(map)
	_ground = map.get_node("Ground")
	_camera = map.get_node("Camera")
	_camera.current = true

	# MAP-4
	var region := RegionCatalog.loadRegion("temp")
	if region.is_empty():
		_fail("MAP-4", "region 'temp' did not load")
		quit(1)
		return
	_tiles = region["tiles"]
	var texture: Texture2D = region["texture"]
	var expected := Vector2(_tiles.x * 16, _tiles.y * 16)
	if texture.get_size() != expected:
		_fail("MAP-4", "texture %s != declared %s" % [texture.get_size(), expected])
	else:
		_pass("MAP-4", "region 'temp' loads, %s px matches %s tiles" % [texture.get_size(), _tiles])

	_ground.configure(_tiles, texture, FramingCatalog.framingFor(FramingCatalog.TILE_EXACT))

	await _run()
	_report()
	if _failures.is_empty():
		print("WORLD MAP VALIDATION OK")
	quit(1 if _failures.size() > 0 else 0)


func _run() -> void:
	await _checkPresets()
	await _checkSwitchable()
	await _checkCornersForVoid()


## MAP-2: every preset loads and renders something. A frame that is uniformly one colour
## means the camera is looking at nothing, which is the failure a preset table can
## plausibly produce and which no amount of arithmetic would catch.
func _checkPresets() -> void:
	for id in FramingCatalog.values():
		if id == FramingCatalog.CUSTOM:
			continue
		var framing := FramingCatalog.framingFor(id)
		_apply(framing)
		var image := await _grab()
		image.save_png("%s/preset_%s.png" % [OUT_DIR, id])
		var spread := _colourSpread(image)
		var readout := _camera.framingReadout(Vector2i(960, 540))
		if spread < 8:
			_fail("MAP-2", "preset '%s' renders a flat frame (spread %d)" % [id, spread])
		else:
			_pass("MAP-2", "preset %-11s spread %-3d  tiles %.1f  px/tile %.1f  need %d" % [
				id, spread, readout["tiles_across"], readout["buffer_px_per_tile"],
				readout["region_tiles_needed"]
			])


## MAP-1: each ground feature changes the frame on its own, and none of it involves a
## WorldEnvironment -- this viewport has own_world_3d and nothing ever adds one.
func _checkSwitchable() -> void:
	var base := FramingCatalog.framingFor(FramingCatalog.TILE_EXACT)
	_apply(base)
	var plain := await _grab()
	plain.save_png("%s/feature_base.png" % OUT_DIR)

	for feature in [
		[Uniforms.K_CURVATURE, 0.01, "curvature"],
		[Uniforms.K_CLOUD_STRENGTH, 0.5, "cloud shadows"],
		[Uniforms.K_FOG_START, 0.0, "haze"],
	]:
		var framing := base.duplicate(true)
		framing[feature[0]] = feature[1]
		_apply(framing)
		var image := await _grab()
		image.save_png("%s/feature_%s.png" % [OUT_DIR, str(feature[2]).replace(" ", "_")])
		var difference := _meanDifference(plain, image)
		if difference < 1.0:
			_fail("MAP-1", "%s changed nothing (mean diff %.2f)" % [feature[2], difference])
		else:
			_pass("MAP-1", "%-14s changes the frame, mean diff %.1f" % [feature[2], difference])

	if _worldHasEnvironment():
		_fail("MAP-1", "a WorldEnvironment reached the world map scene")
	else:
		_pass("MAP-1", "no WorldEnvironment in the scene")


## MAP-3: the fit preset exists precisely because it is the widest framing this 48-tile
## region can fill. Panning to all four corners is what proves the clamp actually holds it
## there, and recolouring the void makes the test exact.
func _checkCornersForVoid() -> void:
	var framing := _voidProbeFraming(FramingCatalog.FIT)
	_apply(framing)

	var corners := [
		Vector2(0.0, 0.0),
		Vector2(float(_tiles.x), 0.0),
		Vector2(0.0, float(_tiles.y)),
		Vector2(float(_tiles.x), float(_tiles.y)),
		Vector2(float(_tiles.x) * 0.5, float(_tiles.y) * 0.5),
	]
	for corner in corners:
		_camera.panTo(corner, _ground.regionRect())
		var image := await _grab()
		var voidPixels := _countNear(image, VOID_PROBE)
		if voidPixels > 0:
			image.save_png("%s/void_at_%d_%d.png" % [OUT_DIR, int(corner.x), int(corner.y)])
			_fail("MAP-3", "fit preset shows %d void px panning to %s" % [voidPixels, corner])
		else:
			_pass("MAP-3", "fit preset clean at corner %s" % corner)

	# The negative control: the same test at tile_exact SHOULD show void, because this
	# region is a third of what that framing needs. A void test that cannot fail is not a
	# test, and the plan records these edges as expected rather than as a defect.
	var wide := _voidProbeFraming(FramingCatalog.TILE_EXACT)
	_apply(wide)
	_camera.panTo(Vector2(_tiles.x * 0.5, _tiles.y * 0.5), _ground.regionRect())
	var image := await _grab()
	image.save_png("%s/void_control_tile_exact.png" % OUT_DIR)
	var voidPixels := _countNear(image, VOID_PROBE)
	if voidPixels > 0:
		_pass("MAP-3", "negative control: tile_exact shows %d void px, as the plan predicts" % voidPixels)
	else:
		_fail("MAP-3", "negative control found no void at tile_exact, so the test proves nothing")


## Recolours the void to something the art cannot contain AND pushes the fog past the far
## plane. Without the second part this test does not measure what it claims: the shader
## blends void toward the fog colour, so at a fogged framing the void arrives on screen as
## pale haze and an exact colour match finds nothing. The first run of this harness passed
## its own negative control for exactly that reason.
func _voidProbeFraming(presetID: String) -> Dictionary:
	var framing := FramingCatalog.framingFor(presetID)
	framing[Uniforms.K_VOID_COLOR] = VOID_PROBE
	framing[Uniforms.K_FOG_START] = 9000.0
	framing[Uniforms.K_FOG_END] = 9001.0
	return framing


func _apply(framing: Dictionary) -> void:
	_ground.applyFraming(framing)
	_camera.applyFraming(framing)
	_camera.panTo(Vector2(_tiles.x * 0.5, _tiles.y * 0.5), _ground.regionRect())


func _grab() -> Image:
	await process_frame
	await process_frame
	await process_frame
	return _viewport.get_texture().get_image()


func _worldHasEnvironment() -> bool:
	for node in root.get_children():
		if node is WorldEnvironment:
			return true
	for node in _viewport.get_children():
		if node is WorldEnvironment:
			return true
		for child in node.get_children():
			if child is WorldEnvironment:
				return true
	return false


## Difference between the darkest and brightest pixel, as a cheap "is anything there".
func _colourSpread(image: Image) -> int:
	var low := 255
	var high := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var value := int(image.get_pixel(x, y).get_luminance() * 255.0)
			low = mini(low, value)
			high = maxi(high, value)
	return high - low


func _meanDifference(a: Image, b: Image) -> float:
	var total := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			samples += 1
	return (total / float(samples)) * 255.0


func _countNear(image: Image, colour: Color) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if (
				absf(pixel.r - colour.r) < 0.08
				and absf(pixel.g - colour.g) < 0.08
				and absf(pixel.b - colour.b) < 0.08
			):
				count += 1
	return count


func _pass(item: String, message: String) -> void:
	print("  PASS  %s  %s" % [item, message])


func _fail(item: String, message: String) -> void:
	_failures.append("%s  %s" % [item, message])
	print("  FAIL  %s  %s" % [item, message])


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("VALIDATION PASSED")
	else:
		print("VALIDATION FAILED (%d)" % _failures.size())
		for failure in _failures:
			print("  " + failure)
