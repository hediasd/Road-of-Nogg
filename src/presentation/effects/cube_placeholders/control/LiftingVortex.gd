## Study 16, Lifting vortex: a wide skirt of cubes narrows into a rising spiral
## and flings its topmost cubes outward.
##
## Sketch:
##   for(i<28){p=phase(t,.015+i*.009,.58+i*.009), a=i*2.4+p*7,
##     r=mix(1.65,.38,p)+(p>.8?(p-.8)*3:0);
##     cube(T+cos(a)*r,.08+p*2.45,sin(a)*r,
##       .13*sizeIn(t,.015+i*.009,.085+i*.009)*tail(t,.7+i*.006,.83+i*.006),a);}
##
## A target-centred volume. The release is the last fifth of each cube's
## climb, where its radius turns outward again (the `p > .8` term): cubes are
## flung off the top before they fade, rather than fading in place.
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const SKIRT_RADIUS := 1.65


func profileID() -> String:
	return "cube_lifting_vortex"


func displayName() -> String:
	return "Cube Lifting Vortex"


func binding() -> String:
	return BINDING_VOLUME


func beats() -> Array[Dictionary]:
	return [
		{"name": "Sweep inward", "start": 0.0, "end": 0.3, "travel": false},
		{"name": "Spiral upward", "start": 0.3, "end": 0.7, "travel": false},
		{"name": "Release", "start": 0.7, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["vortex"]


func peakCubes() -> int:
	return 28


func areaReferenceRadius() -> float:
	return SKIRT_RADIUS


func impactTime() -> float:
	return 0.6


## The radius cube `i` has reached at sketch time `t`.
static func radiusAt(i: int, t: float) -> float:
	var p := phase(t, 0.015 + i * 0.009, 0.58 + i * 0.009)
	return mix(SKIRT_RADIUS, 0.38, p) + ((p - 0.8) * 3.0 if p > 0.8 else 0.0)


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	for i: int in range(28):
		var start := 0.015 + i * 0.009
		var p := phase(t, start, 0.58 + i * 0.009)
		var a := i * 2.4 + p * 7.0
		var r := radiusAt(i, t)
		var size := 0.13 * sizeIn(t, start, 0.085 + i * 0.009) * tail(t, 0.7 + i * 0.006, 0.83 + i * 0.006)
		frame.cube(i, around(frame, cos(a) * r, 0.08 + p * 2.45, sin(a) * r), size, a, 0)
