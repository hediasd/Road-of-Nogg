## Study 22, Cleanse: cubes clinging to the target rise briefly, then pop
## outward and shrink, leaving the target clear.
##
## Sketch:
##   for(i<10){a=i*2.4, q=phase(t,.32+i*.014,.72+i*.014), r=.47+q*q*1.35;
##     cube(T+cos(a)*r,.28+(i%3)*.39+sin(q*PI)*.58,sin(a)*r,.21*sizeIn(t,0,.1)*(1-q),q*5+i);}
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"

const CLING_RADIUS := 0.47


func profileID() -> String:
	return "cube_cleanse"


func displayName() -> String:
	return "Cube Cleanse"


func binding() -> String:
	return BINDING_BODY


func beats() -> Array[Dictionary]:
	return [
		{"name": "Cling", "start": 0.0, "end": 0.32, "travel": false},
		{"name": "Lift off", "start": 0.32, "end": 0.52, "travel": false},
		{"name": "Cast away", "start": 0.52, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["attached"]


func peakCubes() -> int:
	return 10


func areaReferenceRadius() -> float:
	return CLING_RADIUS


func impactTime() -> float:
	return 0.52


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var planar := frame.targetScale()
	for i: int in range(10):
		var a := i * 2.4
		var q := phase(t, 0.32 + i * 0.014, 0.72 + i * 0.014)
		var r := CLING_RADIUS + q * q * 1.35
		var position := local(frame, frame.target, frame.forward, cos(a) * r, 0.28 + (i % 3) * 0.39 + sin(q * PI) * 0.58, sin(a) * r, planar)
		frame.cube(i, position, 0.21 * sizeIn(t, 0.0, 0.1) * (1.0 - q), q * 5.0 + i, 0)
