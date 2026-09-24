## Study 06, Flanking volley: four cubes leave the caster, curl around both
## flanks, and strike the target together from different angles.
##
## Sketch:
##   if(t<.7){q=phase(t,.14,.7); for(i<4){sign=i<2?-1:1;
##     cube(mix(C,T,q),.8+sin(q*PI)*(.4+(i%2)*.55),sin(q*PI)*sign*(1.1+(i%2)*.55),.28*sizeIn(t,.02,.13),q*7+i);}}
##   debris(t,.7,T,0,18,1.3,.1);
##
## All four share one progress, so they converge on the target at the same
## instant; the swing out and the rise use the path scale.
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"


func profileID() -> String:
	return "cube_flanking_volley"


func displayName() -> String:
	return "Cube Flanking Volley"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Separate", "start": 0.0, "end": 0.14, "travel": false},
		{"name": "Curve around", "start": 0.14, "end": 0.7, "travel": true},
		{"name": "Converge", "start": 0.7, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["volley", "burst"]


func peakCubes() -> int:
	return 18


func impactTime() -> float:
	return 0.7


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	if t < 0.7:
		var q := phase(t, 0.14, 0.7)
		var swing := sin(q * PI)
		for i: int in range(4):
			var sign := -1.0 if i < 2 else 1.0
			var ground := pathPoint(frame, q, swing * sign * (1.1 + (i % 2) * 0.55))
			var lift := 0.8 * frame.unit + swing * (0.4 + (i % 2) * 0.55) * pathScale(frame)
			frame.cube(i, ground + frame.up * lift, 0.28 * sizeIn(t, 0.02, 0.13), q * 7.0 + i, 0)
	debris(frame, t, 0.7, targetPoint(frame), 18, 1.3, 0.1, 0.27, 100, 1)
