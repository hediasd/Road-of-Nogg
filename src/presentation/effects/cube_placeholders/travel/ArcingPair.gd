## Study 01, Arcing pair: two medium cubes leave the caster on staggered high
## arcs with sideways offsets, then break into small impact cubes.
##
## Sketch:
##   throwCube(t,.16,.55,C,T,-.6,-.22,1.3,.36); throwCube(t,.28,.68,C,T,.6,.22,1.55,.46);
##   debris(t,.55,T,-.22,8,.7); debris(t,.68,T,.22,12,1.1);
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"


func profileID() -> String:
	return "cube_arcing_pair"


func displayName() -> String:
	return "Cube Arcing Pair"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Gather", "start": 0.0, "end": 0.16, "travel": false},
		{"name": "Angled arcs", "start": 0.16, "end": 0.68, "travel": true},
		{"name": "Break", "start": 0.68, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["lobs", "chips"]


func peakCubes() -> int:
	return 21


func impactTime() -> float:
	return 0.68


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var firstLanding := targetPoint(frame, 0.0, -0.22)
	var secondLanding := targetPoint(frame, 0.0, 0.22)
	throwCube(frame, t, 0.16, 0.55, sourcePoint(frame, -0.6), firstLanding, 1.3, 0.36, 0, 0)
	throwCube(frame, t, 0.28, 0.68, sourcePoint(frame, 0.6), secondLanding, 1.55, 0.46, 1, 0)
	debris(frame, t, 0.55, firstLanding, 8, 0.7, 0.09, 0.27, 100, 1)
	debris(frame, t, 0.68, secondLanding, 12, 1.1, 0.09, 0.27, 200, 1)
