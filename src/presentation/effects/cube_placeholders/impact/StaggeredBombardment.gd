## Study 12, Staggered bombardment: mixed-size cubes rain diagonally onto
## different points in an area, ending with a larger final strike.
##
## Sketch:
##   for(i<9){a=.03+i*.062, b=a+.24, q=phase(t,a,b), x=T+(rnd(i+40)-.5)*1.9,
##     z=(rnd(i+14)-.5)*1.8, s=i===8?.64:.2+rnd(i)*.23;
##     if(t>=a&&t<b)cube(x-.9*(1-q),mix(3.15,.14,q*q),z,s*sizeIn(t,a,a+.035),q*3+i);
##     debris(t,b,x,z,i===8?14:5,i===8?1.25:.55,.085,.21);}
##
## The diagonal comes in from the caster's side. The ninth strike is both the
## largest cube and the last to land, which is the study's climax and the
## action's impact.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_STRIKES := 0
const ROLE_RUBBLE := 1
const STRIKES := 9


func profileID() -> String:
	return "cube_staggered_bombardment"


func displayName() -> String:
	return "Cube Staggered Bombardment"


func beats() -> Array[Dictionary]:
	return [
		{"name": "First drops", "start": 0.0, "end": 0.27, "travel": false},
		{"name": "Uneven impacts", "start": 0.27, "end": 0.766, "travel": false},
		{"name": "Last heavy hit", "start": 0.766, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["strikes", "rubble"]


func peakCubes() -> int:
	return 29


## The farthest corner of the authored rectangle (0.95 by 0.9).
func areaReferenceRadius() -> float:
	return 1.31


func impactTime() -> float:
	return 0.766


static func landingTime(index: int) -> float:
	return 0.03 + index * 0.062 + 0.24


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	for i: int in range(STRIKES):
		var a := 0.03 + i * 0.062
		var b := a + 0.24
		var q := phase(t, a, b)
		var ground := areaPoint(frame, (frame.rnd(i + 40) - 0.5) * 1.9, (frame.rnd(i + 14) - 0.5) * 1.8)
		var s := 0.64 if i == STRIKES - 1 else 0.2 + frame.rnd(i) * 0.23
		if t >= a and t < b:
			var incoming := ground - frame.forward * (0.9 * (1.0 - q) * frame.cubeScale())
			frame.cube(i, above(frame, incoming, mix(3.15, 0.14, q * q)), s * sizeIn(t, a, a + 0.035), q * 3.0 + i, ROLE_STRIKES)
		var last := i == STRIKES - 1
		areaDebris(frame, t, b, ground, 14 if last else 5, 1.25 if last else 0.55, 0.085, 0.21, 100 + i * 14, ROLE_RUBBLE)
