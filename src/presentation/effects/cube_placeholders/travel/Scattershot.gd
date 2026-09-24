## Study 02, Scattershot: a compact group of eleven small cubes spreads into a
## widening cone and hits several nearby points.
##
## Sketch:
##   for(i<11){a=.16+i*.008, b=.49+i*.012, z=(rnd(i)-.5)*2.6;
##     throwCube(t,a,b,C,T+(rnd(i+24)-.5)*.9,0,z,.15,.13+.035*rnd(i+30));
##     debris(t,b,T+(rnd(i+24)-.5)*.9,z,3,.4,.06,.18);}
##
## The landing points are target-relative, so under `AREA_SCALING: spread` the
## pepper pattern opens to the affected area while the shot still leaves the
## caster as one pack.
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"


func profileID() -> String:
	return "cube_scattershot"


func displayName() -> String:
	return "Cube Scattershot"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Pack", "start": 0.0, "end": 0.16, "travel": false},
		{"name": "Fan out", "start": 0.16, "end": 0.49, "travel": true},
		{"name": "Pepper", "start": 0.49, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["shot", "chips"]


func peakCubes() -> int:
	return 34


## The pepper pattern's half-width in sketch units: `(rnd - .5) * 2.6`.
func areaReferenceRadius() -> float:
	return 1.3


func impactTime() -> float:
	return 0.49


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var source := sourcePoint(frame)
	for i: int in range(11):
		var start := 0.16 + i * 0.008
		var end := 0.49 + i * 0.012
		var z := (frame.rnd(i) - 0.5) * 2.6
		var landing := targetPoint(frame, (frame.rnd(i + 24) - 0.5) * 0.9, z)
		throwCube(frame, t, start, end, source, landing, 0.15, 0.13 + 0.035 * frame.rnd(i + 30), i, 0)
		debris(frame, t, end, landing, 3, 0.4, 0.06, 0.18, 100 + i * 3, 1)
