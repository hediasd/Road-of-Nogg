## Do the lamps behave like light in a flat palette, rather than like paint on top of it?
##
## Four claims, each of which was a design decision rather than an accident:
##  - a lamp WITHHOLDS the night rather than adding light, so it can never brighten a pixel
##    past what full daylight would have given it;
##  - overlapping lamps combine with max rather than sum, so a cluster does not blow out;
##  - the buildings inside a lit circle are lit too, not left as the one dark thing in it;
##  - lamps rise as the sun goes down, driven by the sun's own height and not by an hour.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

var _vp: SubViewport
var _ground: WorldMapGround
var _camera: WorldMapCameraRig
var _props: WorldMapProps
var _region: Dictionary
var _framing: Dictionary


func _initialize() -> void:
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

	_region = RegionCatalog.loadRegion("temp2")
	_framing = Uniforms.completeForRegion(
		FramingCatalog.framingFor(FramingCatalog.CURVED_CLOSE),
		_region["fog_color"], _region["void_color"]
	)
	_framing[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	_framing[Uniforms.K_LIGHT_TINT] = 1.0
	_framing[Uniforms.K_HEIGHT] = 30.0
	_framing[Uniforms.K_CURVATURE] = 0.0
	_framing[Uniforms.K_FOG_START] = 400.0

	var built: Dictionary = _props.rebuild(_region["texture"], "temp2", Uniforms.BILLBOARD_FACE)
	_ground.configure(
		_region["tiles"], built["ground"], _framing, _region["fog_color"], _region["void_color"]
	)
	var failures := 0

	# --- lamps rise with the sun, not with the clock ---------------------------------
	print("hour   night   lit map px")
	for hour in [10.0, 16.0, 17.5, 18.5, 22.0]:
		_framing[Uniforms.K_TIME_OF_DAY] = hour
		_framing[Uniforms.K_LAMP_MODE] = Uniforms.LAMP_BAND
		await _apply()
		var mask: Image = _props.shadowImage()
		var lit := 0
		for y in mask.get_height():
			for x in mask.get_width():
				if mask.get_pixel(x, y).g > 0.02:
					lit += 1
		var night: float = WorldMapSun.at(_framing)["night"]
		print("%s  %.2f    %d" % [WorldMapSun.clockText(hour), night, lit])
		if hour <= 16.0 and lit > 0:
			print("  FAIL lamps are on in daylight")
			failures += 1
		if hour >= 18.5 and lit == 0:
			print("  FAIL lamps are off after dark")
			failures += 1

	# --- a lamp never brightens past daylight, and a cluster does not clip -------------
	# Props HIDDEN for this comparison. A lit window is emissive and is supposed to be brighter
	# than the same building in daylight -- that is what "lit from inside" means -- so leaving
	# the props in reports 777 px over daylight for every mode alike, including the additive
	# control, and the check stops separating anything. The claim under test is about the
	# GROUND.
	for child in _props.get_children():
		var hidden := child as MeshInstance3D
		if hidden != null:
			hidden.visible = false
	_framing[Uniforms.K_TIME_OF_DAY] = 12.0
	_framing[Uniforms.K_LAMP_MODE] = Uniforms.LAMP_OFF
	await _apply()
	var noon := _vp.get_texture().get_image()

	_framing[Uniforms.K_TIME_OF_DAY] = 22.0
	var shapes := {}
	for mode in [Uniforms.LAMP_HARD, Uniforms.LAMP_BAND, Uniforms.LAMP_DITHER, Uniforms.LAMP_SMOOTH]:
		_framing[Uniforms.K_LAMP_MODE] = mode
		await _apply()
		# PER PIXEL against the same pixel at noon. The frame's maximum saturates on the
		# near-white building art and stops discriminating: every mode reported 1.000, which
		# proved nothing. What separates subtractive from additive is whether a lamp can push a
		# pixel PAST what full daylight gave it.
		var over := _brighterThanDaylight(_vp.get_texture().get_image(), noon)
		print("22:00 %-7s  %d px brighter than noon, %d clipped" % [
			mode, int(over["count"]), int(over["clipped"])
		])
		# EVERY mode must fail to exceed daylight: they are all subtractive and there is no
		# additive mode in the engine by design. The discriminator is the row below instead --
		# without it this whole block would pass just as well if the lamps did nothing at all.
		if int(over["count"]) > 0:
			print("  FAIL %s pushed %d px past daylight -- that is additive behaviour" % [
				mode, int(over["count"])
			])
			failures += 1
		if int(over["clipped"]) > 0:
			print("  FAIL %s clipped %d px to white" % [mode, int(over["clipped"])])
			failures += 1
		shapes[mode] = _litArea()

	# The shapes must actually differ. "Nothing exceeded daylight" is satisfied by a lamp that
	# does nothing, so without this the section above proves only that the code is inert.
	print("lit ground area per shape: ", shapes)
	var distinct := {}
	for key in shapes:
		distinct[shapes[key]] = true
	if distinct.size() < 3:
		print("  FAIL the lamp shapes are not producing different lit areas")
		failures += 1

	for child in _props.get_children():
		var shown := child as MeshInstance3D
		if shown != null:
			shown.visible = true

	# --- the buildings are lit too ----------------------------------------------------
	var lampsOff := await _spriteMean(Uniforms.LAMP_OFF, 22.0)
	var lampsOn := await _spriteMean(Uniforms.LAMP_BAND, 22.0)
	var daylight := await _spriteMean(Uniforms.LAMP_OFF, 12.0)
	print("")
	print("mean building colour   22:00 no lamps %.3f   22:00 lamps %.3f   12:00 %.3f" % [
		lampsOff, lampsOn, daylight
	])
	if lampsOn < lampsOff * 1.2:
		print("  FAIL buildings are not lit by their own lamps")
		failures += 1

	print("")
	print("LAMPS: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP LAMPS OK")
	quit(1 if failures > 0 else 0)


## How many map pixels the lamp mask actually lights, for the current shape.
func _litArea() -> int:
	var mask: Image = _props.shadowImage()
	var lit := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).g > 0.5:
				lit += 1
	return lit


func _apply() -> void:
	_ground.applyFraming(_framing)
	_camera.applyFraming(_framing)
	var rect := _ground.regionRect()
	_camera.panTo(rect.position + rect.size * 0.5)
	_props.applyFraming(_framing)
	for _f in 8:
		await process_frame


## Pixels a lamp has pushed past what full daylight gave that same pixel. A subtractive lamp
## cannot: at most it withholds the whole night and lands on `art * lamp_lit`, a shade above
## neutral. An additive one adds on top of that and runs away.
func _brighterThanDaylight(night: Image, noon: Image) -> Dictionary:
	var count := 0
	var clipped := 0
	for y in night.get_height():
		for x in night.get_width():
			var a := night.get_pixel(x, y)
			var b := noon.get_pixel(x, y)
			if (a.r + a.g + a.b) > (b.r + b.g + b.b) * 1.15 + 0.02:
				count += 1
			if a.r > 0.995 and a.g > 0.995 and a.b > 0.995:
				clipped += 1
	return {"count": count, "clipped": clipped}


## Mean brightness of the building-coloured pixels. Keyed loosely, because at night every
## colour has been dragged toward the tint and a key tuned on daylight art stops matching.
func _spriteMean(mode: String, hour: float) -> float:
	_framing[Uniforms.K_LAMP_MODE] = mode
	_framing[Uniforms.K_TIME_OF_DAY] = hour
	await _apply()
	var withProps := _vp.get_texture().get_image()
	for child in _props.get_children():
		var quad := child as MeshInstance3D
		if quad != null:
			quad.visible = false
	for _f in 6:
		await process_frame
	var without := _vp.get_texture().get_image()
	for child in _props.get_children():
		var quad2 := child as MeshInstance3D
		if quad2 != null:
			quad2.visible = true
	var total := 0.0
	var count := 0
	for y in withProps.get_height():
		for x in withProps.get_width():
			var a := withProps.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) <= 0.02:
				continue
			total += (a.r + a.g + a.b) / 3.0
			count += 1
	return total / float(maxi(1, count))
