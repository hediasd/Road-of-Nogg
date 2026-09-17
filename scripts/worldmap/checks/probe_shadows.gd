## Do the cast shadows land where they should, stay solid, and refuse to double-darken?
##
## All three were defects in the sketch, and none of them announces itself in a screenshot:
##  - a shadow whose foot is a pixel off its caster reads as "detached" without looking wrong;
##  - a silhouette taken from the sprite's alpha has a hole through the tower's belfry;
##  - two shadows drawn at partial alpha darken where they cross, which is invisible on nine
##    well-spaced structures and obvious the moment a village is dense.
##
## Measured on the MASK, in map-pixel space, because that is the space the decision lives in.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")

func _initialize() -> void:
	var props := WorldMapProps.new()
	get_root().add_child(props)
	var region := RegionCatalog.loadRegion("temp2")
	var failures := 0

	var framing := Uniforms.completeForRegion(
		Uniforms.DEFAULTS.duplicate(true), region["fog_color"], region["void_color"]
	)
	framing[Uniforms.K_BILLBOARD] = Uniforms.BILLBOARD_FACE
	framing[Uniforms.K_SHADOW_STRENGTH] = 0.55
	props.rebuild(region["texture"], "temp2", Uniforms.BILLBOARD_FACE)

	# --- the silhouette is solid ------------------------------------------------------
	var solid: Image = props.silhouetteImage()
	var sheet: Image = props.spriteSheetImage()
	var filled := 0
	var sprite := 0
	for y in solid.get_height():
		for x in solid.get_width():
			if solid.get_pixel(x, y).r > 0.5:
				filled += 1
			if sheet.get_pixel(x, y).a > 0.5:
				sprite += 1
	print("silhouette %d px vs sprite %d px  (+%d filled interior)" % [
		filled, sprite, filled - sprite
	])
	if filled <= sprite:
		print("  FAIL the silhouette filled no interior -- the tower's belfry would show through")
		failures += 1

	# --- the foot sits on the caster --------------------------------------------------
	for hour in [8.0, 12.0, 16.0]:
		framing[Uniforms.K_TIME_OF_DAY] = hour
		props.applyFraming(framing)
		var mask: Image = props.shadowImage()
		var sun := WorldMapSun.at(framing)
		var step: Vector2 = sun["shadow_step"]
		var worstGap := 0
		for i in props.structureCount():
			var s: Dictionary = props.structureAt(i)
			# The sprite stands on the LINE below its last row, and the shadow runs north from
			# there -- so the first shadow row is the caster's own last row, not the one after
			# it. Checking `y + rows` looks for the shadow on the wrong side of the building.
			var footRow: int = int(s["y"]) + int(s["rows"]) - 1
			var hit := false
			for x in range(int(s["x"]), int(s["x"]) + int(s["w"])):
				if x < 0 or x >= mask.get_width():
					continue
				for row in [footRow, footRow - 1]:
					if row >= 0 and row < mask.get_height() and mask.get_pixel(x, row).r > 0.5:
						hit = true
			if not hit:
				worstGap += 1
		var lit := 0
		for y in mask.get_height():
			for x in mask.get_width():
				if mask.get_pixel(x, y).r > 0.5:
					lit += 1
		# Vertical extent of one structure's shadow, to catch a mask that is not being rebuilt:
		# area scales with the shear, so a higher sun must cover fewer rows.
		var s0: Dictionary = props.structureAt(0)
		var rowsHit := 0
		for y in mask.get_height():
			for x in range(int(s0["x"]) - 4, int(s0["x"]) + int(s0["w"]) + 4):
				if x >= 0 and x < mask.get_width() and mask.get_pixel(x, y).r > 0.5:
					rowsHit += 1
					break
		print("      structure 0 shadow spans %d rows; step.y %.3f, rows %d -> offY %.1f px" % [
			rowsHit, step.y, int(s0["rows"]), step.y * float(s0["rows"])
		])
		print("%s  shadow covers %d map px, north %.2f, %d/%d feet planted" % [
			WorldMapSun.clockText(hour), lit, -step.y,
			props.structureCount() - worstGap, props.structureCount()
		])
		if worstGap > 0:
			print("  FAIL %d shadows do not start under their caster" % worstGap)
			failures += 1
		# North is -Z, which is decreasing map y: the shadow must sit ABOVE its caster.
		if step.y >= 0.0:
			print("  FAIL shadow points toward the viewer at %s" % WorldMapSun.clockText(hour))
			failures += 1

	# --- crossing shadows form a union ------------------------------------------------
	# Every mask value is 0 or 1 by construction, so overlap cannot accumulate. Assert it
	# rather than trust it: this is the property a later "optimisation" would quietly break.
	framing[Uniforms.K_TIME_OF_DAY] = 8.0
	framing[Uniforms.K_SUN_LOW] = 8.0    # long shadows, so the cluster's three overlap
	props.applyFraming(framing)
	var overlapMask: Image = props.shadowImage()
	var values := {}
	for y in overlapMask.get_height():
		for x in overlapMask.get_width():
			var v := snappedf(overlapMask.get_pixel(x, y).r, 0.01)
			values[v] = int(values.get(v, 0)) + 1
	print("mask values present: ", values.keys())
	if values.keys().size() > 2:
		print("  FAIL mask carries intermediate values -- shadows are accumulating")
		failures += 1

	print("")
	print("CAST SHADOWS: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP SHADOWS OK")
	quit(1 if failures > 0 else 0)
