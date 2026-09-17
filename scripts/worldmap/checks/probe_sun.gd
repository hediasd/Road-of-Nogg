## Does the engine's sun agree with the sketch it was derived from?
##
## Reproduces the tables in docs/WORLDMAP_DESIGN.md section 10. Two of these are assertions
## rather than reports, because both were defects once:
##  - the northward component must never go negative, or shadows fall toward the viewer;
##  - the geometric elevation must never drop below sun_low, or cot() runs away at the horizon.
extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

func _initialize() -> void:
	var failures := 0
	var framing := Uniforms.DEFAULTS.duplicate(true)

	print("hour   elev   lit    north   side   off-north  reach")
	for i in 9:
		var hour := 6.0 + float(i) * 1.5
		framing[Uniforms.K_TIME_OF_DAY] = hour
		var sun := WorldMapSun.at(framing)
		if not bool(sun["up"]):
			print("%s   sun down" % WorldMapSun.clockText(hour))
			continue
		var step: Vector2 = sun["shadow_step"]
		# The shadow runs opposite the sun. North is -Z, away from the camera.
		var north := -step.y
		var offNorth := rad_to_deg(atan2(absf(step.x), north)) if north > 0.0 else 999.0
		print("%s  %5.1f  %5.1f  %6.2f  %6.2f  %7.0f  %5.2f%s" % [
			WorldMapSun.clockText(hour), rad_to_deg(sun["elevation"]), rad_to_deg(sun["lit"]),
			north, step.x, offNorth, float(sun["shadow_reach"]),
			"  CLAMPED" if bool(sun["clamped"]) else ""
		])
		if north <= 0.0:
			print("  FAIL shadow has no northward component at %s" % WorldMapSun.clockText(hour))
			failures += 1
		if rad_to_deg(sun["elevation"]) < float(framing[Uniforms.K_SUN_LOW]) - 0.01:
			print("  FAIL geometric elevation fell below sun_low")
			failures += 1

	# Ring sizing, measured the way the sketch measured it: the longest shadow a 1.00-tile-wide
	# house throws, against the floor on the geometric elevation.
	print("")
	print("sun_low   longest shadow for a 0.88-tile-tall house")
	for low in [10.0, 18.0, 22.0, 27.0, 32.0, 40.0]:
		framing[Uniforms.K_SUN_LOW] = low
		var worst := 0.0
		for i in 48:
			framing[Uniforms.K_TIME_OF_DAY] = 6.05 + float(i) * 0.25
			var s := WorldMapSun.at(framing)
			if bool(s["up"]):
				worst = maxf(worst, float(s["shadow_reach"]) * 0.875)
		print("  %4.0f deg   %.2f tiles" % [low, worst])
	framing[Uniforms.K_SUN_LOW] = 27.0

	# Night rises as the sun sets, and is total once it is down.
	print("")
	print("hour    night   tint")
	for hour in [6.0, 8.0, 12.0, 17.0, 18.5, 22.0]:
		framing[Uniforms.K_TIME_OF_DAY] = hour
		var s := WorldMapSun.at(framing)
		var tint: Color = s["tint"]
		print("%s   %.2f    %.2f %.2f %.2f" % [
			WorldMapSun.clockText(hour), float(s["night"]), tint.r, tint.g, tint.b
		])

	print("")
	print("SUN: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP SUN OK")
	quit(1 if failures > 0 else 0)
