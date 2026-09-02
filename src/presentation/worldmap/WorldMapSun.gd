## The world map's sun: a time of day turned into a direction, a colour and a shadow shear.
##
## Pure derivation, no nodes and no state. Everything here was settled by measurement in
## `debug/worldmap/standing-structures.html` and is recorded in `docs/WORLDMAP_DESIGN.md` §10;
## `debug/worldmap/probe_sun.gd` reproduces the tables.
##
## THE SUN KEEPS TWO ELEVATIONS, and they are not interchangeable.
##
## `lit` is the honest one. It reaches zero at both ends of the day and drives the light
## colour, the lamps, and how strongly a shadow reads.
##
## `elevation` is the one the shadow GEOMETRY uses, and it never drops below `sun_low`.
## `cot(elevation)` runs away as the sun touches the horizon, and a shadow twenty tiles long
## and one tile wide reads as a scratch on the lens rather than as a building. Holding the
## geometric elevation in a flattering band costs nothing legible, because the reading of
## "what time is it" comes from the direction the shadows point, not from their length.

class_name WorldMapSun
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Daylight hours. Outside them the sun is down: no cast shadow, lamps at full.
const DAWN := 6.0
const DUSK := 18.0

## Light colour through the day, as `[hour, r, g, b]` multipliers -- warm at the ends, plain at
## noon, cold and dim at night. Interpolated linearly. This is a MODEL, not a measurement:
## unlike the projection maths there is nothing to check it against except whether it reads.
const SKY_KEYS := [
	[0.0, 0.34, 0.41, 0.68], [4.5, 0.40, 0.46, 0.72], [5.8, 0.62, 0.56, 0.74],
	[6.8, 1.26, 0.88, 0.66], [9.0, 1.06, 1.01, 0.95], [12.0, 1.00, 1.00, 1.00],
	[15.0, 1.06, 1.00, 0.94], [17.2, 1.30, 0.82, 0.58], [18.6, 0.74, 0.58, 0.76],
	[20.5, 0.44, 0.47, 0.72], [24.0, 0.34, 0.41, 0.68],
]

## What a lamp-lit pixel is tinted by. Not white: a lamp is warm, and holding it slightly warm
## keeps a lit circle from reading as a hole punched in the night.
const LAMP_LIT := Color(1.06, 0.98, 0.84)

## The colour a lit window takes after dark. Emissive: it REPLACES the night tint rather than
## being multiplied by it, because multiplying a window by a blue night and adding warmth back
## gives a muddy grey-green instead of "there is a light in there".
const LAMP_EMISSIVE := Color(1.0, 0.839, 0.541)


## Everything about the sun at one moment, from a completed framing.
##
## `direction` points from the ground toward the sun. `shadow_step` is the ground offset a
## shadow takes per unit of caster height, already clamped.
static func at(framing: Dictionary) -> Dictionary:
	var f := Uniforms.complete(framing)
	var hour: float = fposmod(float(f[Uniforms.K_TIME_OF_DAY]), 24.0)
	var high := deg_to_rad(float(f[Uniforms.K_SUN_HIGH]))
	var low := deg_to_rad(float(f[Uniforms.K_SUN_LOW]))
	var arc := deg_to_rad(float(f[Uniforms.K_SUN_ARC]))

	var day := (hour - DAWN) / (DUSK - DAWN)
	if day <= 0.0 or day >= 1.0:
		return {
			"up": false, "hour": hour, "elevation": 0.0, "lit": 0.0, "azimuth": 0.0,
			"direction": Vector3(0.0, -1.0, 0.0),
			"shadow_step": Vector2.ZERO, "shadow_reach": 0.0, "clamped": false,
			"night": 1.0, "tint": tintAt(hour),
		}

	var curve := sin(day * PI)
	var lit := curve * high
	var elevation: float = low + (high - low) * curve
	# Azimuth sweeps a NARROW ARC centred on due north rather than the full east-to-west
	# semicircle. A full sweep puts the sun on the horizon due east at dawn, and a shadow cast
	# from due east points due WEST -- straight across the screen with no northward component
	# at all. 90 degrees puts the sun at +Z, the camera's own side, which throws the shadow to
	# -Z: away from the viewer, up-screen. Shadows in front cover the ground the player is
	# walking into and read as grime; shadows behind read as depth.
	var azimuth := PI * 0.5 + arc * (2.0 * day - 1.0)
	var direction := Vector3(
		cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth)
	)

	var step := Vector2.ZERO
	var reach := 0.0
	var clamped := false
	if direction.y > 0.0001:
		step = Vector2(-direction.x / direction.y, -direction.z / direction.y)
		reach = step.length()
		var limit := float(f[Uniforms.K_SUN_REACH])
		if reach > limit and reach > 0.0:
			step *= limit / reach
			reach = limit
			clamped = true

	return {
		"up": true, "hour": hour, "elevation": elevation, "lit": lit, "azimuth": azimuth,
		"direction": direction,
		"shadow_step": step, "shadow_reach": reach, "clamped": clamped,
		"night": nightAt(lit), "tint": tintAt(hour),
	}


## How "on" the lamps are, from the HONEST elevation. Driven off the sun's height rather than
## the clock so the lights come up as the sun goes down instead of snapping at a fixed hour.
static func nightAt(lit: float) -> float:
	return clampf(1.0 - sin(lit) * 4.0, 0.0, 1.0)


## The day's light as a colour multiplier. Applied to the ground, the fog, the void and the
## sprites alike: tinting the ground alone and leaving a pale teal horizon behind a
## midnight-blue map is what makes a day cycle look broken.
static func tintAt(hour: float) -> Color:
	var h: float = fposmod(hour, 24.0)
	var a: Array = SKY_KEYS[0]
	var b: Array = SKY_KEYS[SKY_KEYS.size() - 1]
	for i in SKY_KEYS.size() - 1:
		var lo: Array = SKY_KEYS[i]
		var hi: Array = SKY_KEYS[i + 1]
		if h >= float(lo[0]) and h <= float(hi[0]):
			a = lo
			b = hi
			break
	var span := float(b[0]) - float(a[0])
	var u := 0.0 if span <= 0.0 else (h - float(a[0])) / span
	return Color(
		lerpf(float(a[1]), float(b[1]), u),
		lerpf(float(a[2]), float(b[2]), u),
		lerpf(float(a[3]), float(b[3]), u)
	)


## Blends a tint toward the lamp-lit value. One function so the ground and the standing sprites
## cannot disagree: a building lit to one value while the grass under it is lit to another is
## the seam the subtractive lamp model exists to remove, and it is invisible in a thumbnail.
static func litTint(tint: Color, k: float) -> Color:
	if k <= 0.0:
		return tint
	return Color(
		tint.r + (LAMP_LIT.r - tint.r) * k,
		tint.g + (LAMP_LIT.g - tint.g) * k,
		tint.b + (LAMP_LIT.b - tint.b) * k
	)


## `HH:MM`, for readouts.
static func clockText(hour: float) -> String:
	var h: float = fposmod(hour, 24.0)
	return "%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)]
