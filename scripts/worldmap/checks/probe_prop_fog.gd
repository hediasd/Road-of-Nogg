## Do props fog on the same curve as the ground they stand on?
##
## This is the defect WMP-3 exists to remove: Sprite3D's own material had nowhere to put fog,
## so the ground hazed with distance and the props did not, and a distant structure sat
## un-hazed on ground that had already faded. It did not show at Curved Close only because
## temp2's structures sit at 13-22 units against a fog start of 21.
##
## The check is a comparison, not an absolute: with fog closed hard, a prop's pixels and the
## ground's must both land near the fog colour. A prop that ignores fog stays saturated.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 500)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var map: Node3D = WorldMapScene.instantiate()
	vp.add_child(map)
	var ground: WorldMapGround = map.get_node("Ground")
	var camera: WorldMapCameraRig = map.get_node("Camera")
	var props: WorldMapProps = map.get_node("Props")
	camera.current = true

	var region := RegionCatalog.loadRegion("temp2")
	var fogColor: Color = region["fog_color"]
	var failures := 0
	var openGap := 0.0

	for closed in [false, true]:
		var framing := Uniforms.completeForRegion(
			FramingCatalog.framingFor(FramingCatalog.CURVED_CLOSE),
			fogColor, region["void_color"]
		)
		framing[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
		framing[Uniforms.K_HEIGHT] = 22.0
		framing[Uniforms.K_CURVATURE] = 0.0
		if closed:
			# Fog closing well inside the frame, so everything visible is deep in it.
			framing[Uniforms.K_FOG_START] = 1.0
			framing[Uniforms.K_FOG_END] = 26.0
		else:
			framing[Uniforms.K_FOG_START] = 900.0
			framing[Uniforms.K_FOG_END] = 1000.0

		var built: Dictionary = props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_FACE)
		ground.configure(region["tiles"], built["ground"], framing, fogColor, region["void_color"])
		camera.applyFraming(framing)
		var rect := ground.regionRect()
		camera.panTo(rect.position + rect.size * 0.5)
		props.applyFraming(framing)
		for _f in 10:
			await process_frame

		var withProp := vp.get_texture().get_image()
		# The same frame with the props hidden. Diffing the two isolates the prop's own pixels
		# without a colour key, which matters because fog drags every colour toward the haze
		# and a key tuned on unfogged art stops matching exactly when the test gets interesting.
		for child in props.get_children():
			var quad := child as MeshInstance3D
			if quad != null:
				quad.visible = false
		for _f in 6:
			await process_frame
		var withoutProps := vp.get_texture().get_image()

		var gap := _propVsGround(withProp, withoutProps)
		print("%s  prop-to-ground colour gap: %.3f" % [
			"fog open  " if not closed else "fog closed", gap
		])
		if not closed:
			openGap = gap
		elif gap > openGap * 0.5:
			print("  FAIL props are not fogging with the ground: the gap barely closed")
			failures += 1

	print("")
	print("PROP FOG: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP PROP FOG OK")
	quit(1 if failures > 0 else 0)


## How far a prop's pixels sit from the ground DIRECTLY BEHIND them, averaged. Fog pulls both
## toward the same haze, so if props fog on the ground's curve this gap collapses as fog
## closes; if they ignore fog it stays open while the ground fades around them.
func _propVsGround(withProp: Image, withoutProps: Image) -> float:
	var total := 0.0
	var count := 0
	for y in withProp.get_height():
		for x in withProp.get_width():
			var a := withProp.get_pixel(x, y)
			var b := withoutProps.get_pixel(x, y)
			var d := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if d <= 0.02:
				continue
			total += d
			count += 1
	return total / float(maxi(1, count))
