## Study 14, Closing cage: four cube columns assemble around the target. Their
## upper cubes close inward over the head to suggest confinement.
##
## Sketch:
##   for(i<4){a=i*TAU/4+PI/4; for(j<4){q=sizeIn(t,.05+j*.055,.23+j*.055),
##     r=j===3?mix(.85,.3,smooth(phase(t,.42,.65))):.85;
##     cube(T+cos(a)*r,(.18+j*.46)*q,sin(a)*r,.3*q*tail(t,.84,.99),0);}}
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const POST_RADIUS := 0.85
const CLOSED_RADIUS := 0.3


func profileID() -> String:
	return "cube_closing_cage"


func displayName() -> String:
	return "Cube Closing Cage"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Corner posts", "start": 0.0, "end": 0.42, "travel": false},
		{"name": "Close overhead", "start": 0.42, "end": 0.65, "travel": false},
		{"name": "Hold", "start": 0.65, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["posts", "lid"]


func peakCubes() -> int:
	return 16


## The posts' ground radius, which an area spread widens to the footprint.
func areaReferenceRadius() -> float:
	return POST_RADIUS


func impactTime() -> float:
	return 0.65


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var closing := smooth(phase(t, 0.42, 0.65))
	for i: int in range(4):
		var a := i * TAU / 4.0 + PI / 4.0
		for j: int in range(4):
			var q := sizeIn(t, 0.05 + j * 0.055, 0.23 + j * 0.055)
			var r := mix(POST_RADIUS, CLOSED_RADIUS, closing) if j == 3 else POST_RADIUS
			var position := around(frame, cos(a) * r, (0.18 + j * 0.46) * q, sin(a) * r)
			frame.cube(i * 4 + j, position, 0.3 * q * tail(t, 0.84, 0.99), 0.0, 1 if j == 3 else 0)
