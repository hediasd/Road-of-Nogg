## Study 15, Climbing coil: a line of little cubes coils up around the target,
## then tightens to imply a snare or binding spell.
##
## Sketch:
##   tighten=smooth(phase(t,.62,.8));
##   for(i<22){a=.04+i*.023, q=sizeIn(t,a,a+.1), ang=i*.67-t*.4, r=mix(.77,.48,tighten);
##     cube(T+cos(ang)*r,.1+i*.075,sin(ang)*r,.15*q*tail(t,.87,.99),ang);}
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const LOOSE_RADIUS := 0.77
const TIGHT_RADIUS := 0.48


func profileID() -> String:
	return "cube_climbing_coil"


func displayName() -> String:
	return "Cube Climbing Coil"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Find feet", "start": 0.0, "end": 0.15, "travel": false},
		{"name": "Climb", "start": 0.15, "end": 0.62, "travel": false},
		{"name": "Tighten", "start": 0.62, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["coil"]


func peakCubes() -> int:
	return 22


func areaReferenceRadius() -> float:
	return LOOSE_RADIUS


func impactTime() -> float:
	return 0.8


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var r := mix(LOOSE_RADIUS, TIGHT_RADIUS, smooth(phase(t, 0.62, 0.8)))
	for i: int in range(22):
		var a := 0.04 + i * 0.023
		var q := sizeIn(t, a, a + 0.1)
		var angle := i * 0.67 - t * 0.4
		frame.cube(i, around(frame, cos(angle) * r, 0.1 + i * 0.075, sin(angle) * r), 0.15 * q * tail(t, 0.87, 0.99), angle, 0)
