## WMC-5: a cloud passing over a structure darkens it too, by exactly what the shader
## computes at its base, and the ground beside its foot moves the same direction.
##
## The structure's own foot pixel on screen is occluded by the sprite standing on it, so
## "the ground at its foot" is measured two ways: the numeric coverage the shader itself reads
## at the exact base map pixel (the mask, before any rendering), and the rendered ground colour
## a short, unoccluded distance beside the foot, which is a real screen sample rather than a
## number pulled out of the pipeline that produced it.
##
## PLACEMENT IS BY SEED SWEEP, NOT BY ANIMATING THE WIND. `WorldMapCloudField.at()` is
## deterministic in (seed, clock); holding clock at 0 and varying the seed gives independent
## trials of "does a single cloud's shadow cover this point" without touching WorldMapClouds'
## internal clock, which is not in this item's Touches and should not need to be.

extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const CloudField = preload("res://src/presentation/worldmap/WorldMapCloudField.gd")
const CloudCatalog = preload("res://src/presentation/worldmap/WorldMapCloudCatalog.gd")

const SIZE := Vector2i(480, 270)
const STRUCTURE_INDEX := 0
const SHADE := 0.4

var _viewport: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _clouds: WorldMapClouds
var _props: WorldMapProps
var _tiles: Vector2
var _mapPx: Vector2i
var _failures: Array[String] = []


func _check(label: String, ok: bool, detail: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label + "  " + detail)
	if not ok:
		_failures.append(label)


func _initialize() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = SIZE
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


func _base(seed_: int) -> Dictionary:
	var f := FramingCatalog.framingFor(FramingCatalog.TILE_EXACT).duplicate(true)
	f[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	f[Uniforms.K_SHADOW_STRENGTH] = 0.0  # cast shadows off -- isolating the cloud alone
	f[Uniforms.K_TIME_OF_DAY] = 10.0
	f[Uniforms.K_HEIGHT] = 30.0
	f[Uniforms.K_FOG_START] = 400.0
	f[Uniforms.K_CURVATURE] = 0.0
	f[Uniforms.K_CLOUD_COUNT] = 1.0
	f[Uniforms.K_CLOUD_SEED] = float(seed_)
	f[Uniforms.K_WIND_SPEED] = 0.0
	f[Uniforms.K_CLOUD_SHADOW] = SHADE
	f[Uniforms.K_CLOUD_SOFTNESS] = 0.0
	f[Uniforms.K_CLOUD_OPACITY] = 1.0
	return f


func _apply(framing: Dictionary, region: Dictionary) -> void:
	var built: Dictionary = _props.rebuild(region["texture"], "temp2", str(framing[Uniforms.K_BILLBOARD]))
	_ground.configure(_tiles, built["ground"], framing, region["fog_color"], region["void_color"])
	_camera.applyFraming(framing)
	_camera.panTo(Vector2(_tiles.x * 0.5, _tiles.y * 0.5))
	_props.applyFraming(framing)
	_clouds.configure(_mapPx, framing)
	_ground.configureCloudShadows(_mapPx, str(framing[Uniforms.K_CLOUDS]))
	_ground.setCloudField(_clouds.field())
	_props.setCloudShadows(_ground.cloudShadowTexture(), _ground.regionRect().position, _ground.regionRect().size)


func _quads() -> Array:
	var out: Array = []
	for child in _props.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


## Renders with only ONE structure's quad visible, following probe_props.gd's own pattern:
## rendered together, structures merge into one component and a merged measurement means
## nothing.
##
## THE CLOUD SPRITES ARE HIDDEN TOO, not just the other structures. A cloud's shadow is offset
## from the cloud itself by the sun's own shear, so a shadow placed over the tower does not mean
## the CLOUD is anywhere near it in screen space -- but at this camera angle it can still
## project onto the same pixels, and a bright cloud sprite sitting in front of a "shadowed"
## tower is exactly what turned the first run of this probe into "the prop got BRIGHTER under a
## shadow", which was the cloud's own white silhouette painted over it, not the shadow.
func _isolatedShot() -> Image:
	var quads := _quads()
	for i in quads.size():
		(quads[i] as MeshInstance3D).visible = i == STRUCTURE_INDEX
	for child in _clouds.get_children():
		(child as MeshInstance3D).visible = false
	for _f in 10:
		await process_frame
	return _viewport.get_texture().get_image()


func _coverageAt(mapPos: Vector2i) -> float:
	var texture := _ground.cloudShadowTexture()
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null:
		return 0.0
	var x := clampi(mapPos.x, 0, image.get_width() - 1)
	var y := clampi(mapPos.y, 0, image.get_height() - 1)
	return image.get_pixel(x, y).r


## The engine tonemaps ALBEDO (linear) to the sRGB image `get_pixel` reads back -- both prop and
## ground shaders convert to gamma space and back for their fog blend, which is what says so.
## `predicted` is computed directly from the shader's own linear multiply, so the READ-BACK has
## to be converted back to linear before the two numbers mean the same thing. Comparing sRGB
## pixel values to a linear prediction is why this check first came back wrong by a wide,
## consistent margin -- 0.6711 observed against 0.5046 predicted at coverage 1.0 -- for every
## trial at once, which is the signature of a colour-space mismatch rather than a shader defect.
func _srgbToLinear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _meanLuminance(image: Image, mask: PackedVector2Array) -> float:
	var total := 0.0
	for p in mask:
		var c := image.get_pixel(int(p.x), int(p.y))
		total += 0.2126 * _srgbToLinear(c.r) + 0.7152 * _srgbToLinear(c.g) + 0.0722 * _srgbToLinear(c.b)
	return 0.0 if mask.is_empty() else total / float(mask.size())


## The prop's own pixels, found once from an UNSHADOWED render via the same white/black/teal key
## probe_props.gd uses, so the same pixel set is compared across every seed rather than
## re-derived from a colour test that shadow would perturb.
##
## `PackedVector2Array`, not `PackedByteArray`: the shot is 480 px wide and a screen X
## coordinate does not fit in a byte. Packing coordinates as bytes silently wraps every X past
## 255 (mod 256), which does not error -- it quietly produces a mask pointing at the wrong
## pixels, and the first version of this probe measured exactly that mask for several minutes
## before the corruption was traced.
func _propMask(shot: Image) -> PackedVector2Array:
	var mask := PackedVector2Array()
	for y in shot.get_height():
		for x in shot.get_width():
			var c := shot.get_pixel(x, y)
			var r := c.r * 255.0
			var g := c.g * 255.0
			var b := c.b * 255.0
			var white: bool = r > 200.0 and g > 200.0 and b > 200.0
			var black: bool = r < 60.0 and g < 70.0 and b < 60.0
			var teal: bool = absf(r - 11.0) < 45.0 and absf(g - 105.0) < 45.0 and absf(b - 106.0) < 45.0
			if white or black or teal:
				mask.append(Vector2(x, y))
	return mask


func _run(region: Dictionary) -> void:
	print("probe_cloud_on_props")

	# Baseline: no cloud set at all, so the prop's own pixels can be found without a shadow's
	# darkening perturbing the colour key.
	var off := _base(0)
	off[Uniforms.K_CLOUDS] = Uniforms.CLOUDS_OFF
	_apply(off, region)
	var baselineShot: Image = await _isolatedShot()
	var mask := _propMask(baselineShot)
	_check("the isolated structure was found", mask.size() >= 20,
		"%d pixels keyed" % mask.size())
	var baselineLuminance := _meanLuminance(baselineShot, mask)

	var structure := _props.structureAt(STRUCTURE_INDEX)
	var quads := _quads()
	var base: Vector3 = (quads[STRUCTURE_INDEX] as MeshInstance3D).position
	var mapBase := Vector2i(roundi(base.x * float(Uniforms.TILE_PIXELS)), roundi(base.z * float(Uniforms.TILE_PIXELS)))
	print("  structure #%d '%s', base map pixel %s, baseline luminance %.4f"
		% [STRUCTURE_INDEX, structure.get("kind", "?"), mapBase, baselineLuminance])

	# A ground point beside the foot, not under the sprite's own screen footprint, so it can be
	# sampled without the prop occluding it.
	var besideWorld := base + Vector3(1.5, 0.0, 0.0)
	var besideMap := Vector2i(roundi(besideWorld.x * float(Uniforms.TILE_PIXELS)), roundi(besideWorld.z * float(Uniforms.TILE_PIXELS)))

	# --- pick seeds by CALCULATION rather than luck --------------------------------------
	#
	# `WorldMapCloudField.at()` is pure and cheap; the scene render is not. With a single
	# cloud placed in one of fifteen lattice cells, most seeds miss a given point entirely --
	# scanning a wide range with the pure function first, and rendering only the seeds that
	# land where they are needed, is what makes twelve renders answer the same question two
	# hundred would.
	var sun := WorldMapSun.at(_base(0))
	var config := {
		CloudField.K_FIELD: _mapPx,
		CloudField.K_CLOUD: CloudCatalog.pieceMapPixels("temp2", 0),
		CloudField.K_SHADOW: CloudCatalog.pieceMapPixels("temp2", 0),
		CloudField.K_PIECES: CloudCatalog.pieceCount("temp2"),
		CloudField.K_COUNT: 1,
		CloudField.K_ALTITUDE: 6.0,
		CloudField.K_WIND_SPEED: 0.0,
		CloudField.K_WIND_ANGLE: 0.0,
		CloudField.K_SEED: 0,
		CloudField.K_PIXELS_PER_UNIT: float(Uniforms.TILE_PIXELS),
	}
	var coveringSeeds: Array[int] = []
	var clearSeeds: Array[int] = []
	for seed_ in range(400):
		if coveringSeeds.size() >= 6 and clearSeeds.size() >= 6:
			break
		config[CloudField.K_SEED] = seed_
		var field := CloudField.at(config, sun, 0.0)
		if field.is_empty():
			continue
		var entry: Dictionary = field[0]
		var shadowRect := Rect2i(
			entry["shadow"], CloudCatalog.pieceAt("temp2", int(entry["piece"]))["shadow"].size
		)
		if shadowRect.has_point(mapBase):
			if coveringSeeds.size() < 6:
				coveringSeeds.append(seed_)
		elif clearSeeds.size() < 6:
			clearSeeds.append(seed_)
	_check("the search found both a covering and a clear seed",
		not coveringSeeds.is_empty() and not clearSeeds.is_empty(),
		"%d covering candidates, %d clear candidates" % [coveringSeeds.size(), clearSeeds.size()])

	var coverages: Array[float] = []
	var observed: Array[float] = []
	var predicted: Array[float] = []
	var groundBeside: Array[float] = []

	for seed_ in coveringSeeds + clearSeeds:
		var f := _base(seed_)
		_apply(f, region)
		# The coverage read comes AFTER the screenshot's own awaited frames, not before. Reading
		# it right after `_apply()` returns caught the cloud shadow viewport one frame behind
		# the ground and prop materials it feeds -- the shot and the coverage disagreed about
		# which seed they were even describing, which is what produced results that looked
		# like noise on the first run of this probe.
		var shot: Image = await _isolatedShot()
		var coverage := _coverageAt(mapBase)
		var luminance := _meanLuminance(shot, mask)
		coverages.append(coverage)
		observed.append(luminance)
		predicted.append(baselineLuminance * (1.0 - SHADE * coverage))
		print("    seed %3d  coverage %.3f  observed %.4f  predicted %.4f"
			% [seed_, coverage, luminance, baselineLuminance * (1.0 - SHADE * coverage)])

		# The screen point beside the foot, from the SAME shot -- this is the isolated render,
		# so nothing but the ground and this one structure can be at that pixel.
		var screen := _camera.unproject_position(besideWorld)
		var px := clampi(int(screen.x), 0, shot.get_width() - 1)
		var py := clampi(int(screen.y), 0, shot.get_height() - 1)
		# sRGB luminance is fine here: this feeds only a DIRECTIONAL comparison (covered
		# group mean vs clear group mean), and sRGB is monotonic in linear luminance.
		groundBeside.append(shot.get_pixel(px, py).get_luminance())

	var covered := 0
	var clear := 0
	for c in coverages:
		if c > 0.5:
			covered += 1
		elif c < 0.05:
			clear += 1
	_check("the sweep produced both a covered and a clear trial", covered > 0 and clear > 0,
		"%d covered, %d clear, of %d seeds" % [covered, clear, coverages.size()])

	# Tolerant of ONE outlier, not zero. The shader samples `cloud_mask` by UV -- a continuous
	# world position converted to a texel -- while this check reads the mask at an INTEGER map
	# pixel directly. The two agree everywhere except within roughly one texel of a shadow's own
	# edge, where floating-point UV rounding can land the GPU's sample on the texel next door
	# from the one this check inspected. That is a property of testing a discrete boundary from
	# outside the shader, not a defect in it -- and it is why the search above collects several
	# covering seeds rather than stopping at the first: a boundary miss should not be able to
	# hide behind having no other trial to be outvoted by.
	var mismatches: Array[String] = []
	for i in coverages.size():
		var err := absf(observed[i] - predicted[i])
		if err >= 0.02:
			mismatches.append("seed with coverage %.2f: |%.4f - %.4f| = %.4f"
				% [coverages[i], observed[i], predicted[i], err])
	_check("the prop darkens by what the shader computes at its base, allowing one edge case",
		mismatches.size() <= 1,
		"%d of %d seeds mismatched%s"
			% [mismatches.size(), coverages.size(),
				"" if mismatches.is_empty() else "  " + str(mismatches)])

	# The ground beside the foot: split trials into covered vs clear and compare MEANS, since
	# any one beside-point can sit right at a shadow's dithered edge.
	var coveredGround: Array[float] = []
	var clearGround: Array[float] = []
	for i in coverages.size():
		if coverages[i] > 0.5:
			coveredGround.append(groundBeside[i])
		elif coverages[i] < 0.05:
			clearGround.append(groundBeside[i])
	var meanCoveredGround := 0.0
	for v in coveredGround:
		meanCoveredGround += v
	meanCoveredGround /= maxf(1.0, float(coveredGround.size()))
	var meanClearGround := 0.0
	for v in clearGround:
		meanClearGround += v
	meanClearGround /= maxf(1.0, float(clearGround.size()))
	_check("the ground beside the foot is darker on covered trials too",
		meanCoveredGround < meanClearGround,
		"covered mean %.4f vs clear mean %.4f" % [meanCoveredGround, meanClearGround])

	# The prop and the ground beside it must at least AGREE ON DIRECTION between the two group
	# means -- "move together", the plan's own phrase -- even though one is palette-snapped and
	# the other is not, which is the tolerance the plan names.
	var meanCoveredProp := 0.0
	var meanClearProp := 0.0
	var coveredN := 0
	var clearN := 0
	for i in coverages.size():
		if coverages[i] > 0.5:
			meanCoveredProp += observed[i]
			coveredN += 1
		elif coverages[i] < 0.05:
			meanClearProp += observed[i]
			clearN += 1
	meanCoveredProp /= maxf(1.0, float(coveredN))
	meanClearProp /= maxf(1.0, float(clearN))
	var propDrop := meanClearProp - meanCoveredProp
	var groundDrop := meanClearGround - meanCoveredGround
	_check("the prop's drop and the ground's drop move the same direction",
		propDrop > 0.0 and groundDrop > 0.0,
		"prop drop %.4f, ground drop %.4f" % [propDrop, groundDrop])

	# --- one more thing: does the structure itself sit where the sweep assumed? -------------
	# Sanity on the geometry the whole probe is built from, not a look-decision.
	_check("the sampled 'beside' point is not the base itself",
		besideMap.distance_to(mapBase) > 5.0, "%s vs %s" % [besideMap, mapBase])

	print("probe_cloud_on_props: %s (%d failures)"
		% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	if _failures.is_empty():
		print("WORLD MAP CLOUD ON PROPS OK")
	quit(0 if _failures.is_empty() else 1)
