## Study 08, Ground teeth: five narrow cube stacks grow upward from the ground
## in sequence, lift into jagged teeth, and crumble.
##
## Sketch:
##   for(i<5){a=.18+i*.045, x=T+(i-2)*.43, z=(i%2)*.4-.2, q=phase(t,a,a+.17),
##     h=smooth(q)*(1.4+rnd(i)*.8);
##     if(t>.07&&t<a)cube(x,.08,z,.085,sin(t*110+i)*.4);
##     for(j<4)cube(x,.12+j*h/3,z,(.34-j*.04)*sizeIn(t,a,a+.06)*tail(t,.65+i*.015,.84+i*.015),0);
##     debris(t,.71+i*.015,x,z,5,.6,.08,.23);}
##
## The row runs along the cast direction. On a one-cell target it stays within
## the cell; spread over an area it reaches across it, still one row of five.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_TREMBLE := 0
const ROLE_TEETH := 1
const ROLE_CRUMBS := 2


func profileID() -> String:
	return "cube_ground_teeth"


func displayName() -> String:
	return "Cube Ground Teeth"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Tremble", "start": 0.0, "end": 0.18, "travel": false},
		{"name": "Punch upward", "start": 0.18, "end": 0.65, "travel": false},
		{"name": "Crumble", "start": 0.65, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["tremble", "teeth", "crumbs"]


func peakCubes() -> int:
	return 45


## The row's end tooth: 0.86 forward and 0.2 aside.
func areaReferenceRadius() -> float:
	return 0.89


func impactTime() -> float:
	return 0.35


## When tooth `index` starts to punch up.
static func riseStart(index: int) -> float:
	return 0.18 + index * 0.045


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	for i: int in range(5):
		var a := riseStart(i)
		var q := phase(t, a, a + 0.17)
		var h := smooth(q) * (1.4 + frame.rnd(i) * 0.8)
		var ground := areaPoint(frame, (i - 2) * 0.43, (i % 2) * 0.4 - 0.2)
		if t > 0.07 and t < a:
			frame.cube(i, above(frame, ground, 0.08), 0.085, sin(t * 110.0 + i) * 0.4, ROLE_TREMBLE)
		var life := sizeIn(t, a, a + 0.06) * tail(t, 0.65 + i * 0.015, 0.84 + i * 0.015)
		for j: int in range(4):
			frame.cube(10 + i * 4 + j, above(frame, ground, 0.12 + j * h / 3.0), (0.34 - j * 0.04) * life, 0.0, ROLE_TEETH)
		areaDebris(frame, t, 0.71 + i * 0.015, ground, 5, 0.6, 0.08, 0.23, 100 + i * 5, ROLE_CRUMBS)
