## Study 17, Clapping slabs: two slabs assembled from cubes wait on opposite
## sides of the target and suddenly clap together.
##
## Sketch:
##   q=pow(phase(t,.38,.62),3), r=mix(1.55,.28,q);
##   if(t<.68)for(side of[-1,1])for(j<6)
##     cube(T+side*r,.26+floor(j/2)*.46,(j%2-.5)*.45,.44*sizeIn(t,.04+j*.017,.2+j*.017),0);
##   debris(t,.63,T,0,26,1.45,.13,.31);
##
## The slabs stand on the cast axis, one on the caster's side, one beyond. The
## cubic ease is the slam: they barely move for most of the beat, then meet
## at .62 on the body, and stay pressed together until they shatter at .68.
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const OPEN_RADIUS := 1.55
const CLOSED_RADIUS := 0.28
const SLAB_CUBE := 0.44


func profileID() -> String:
	return "cube_clapping_slabs"


func displayName() -> String:
	return "Cube Clapping Slabs"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Build sides", "start": 0.0, "end": 0.38, "travel": false},
		{"name": "Slam together", "start": 0.38, "end": 0.62, "travel": false},
		{"name": "Chip away", "start": 0.62, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["slabs", "fragments"]


func peakCubes() -> int:
	return 38


func areaReferenceRadius() -> float:
	return OPEN_RADIUS


func impactTime() -> float:
	return 0.62


static func slabRadius(t: float) -> float:
	return mix(OPEN_RADIUS, CLOSED_RADIUS, pow(phase(t, 0.38, 0.62), 3.0))


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	if t < 0.68:
		var r := slabRadius(t)
		for sideIndex: int in range(2):
			var sign := -1.0 if sideIndex == 0 else 1.0
			for j: int in range(6):
				var position := around(frame, sign * r, 0.26 + floorf(j / 2.0) * 0.46, (j % 2 - 0.5) * 0.45)
				frame.cube(sideIndex * 6 + j, position, SLAB_CUBE * sizeIn(t, 0.04 + j * 0.017, 0.2 + j * 0.017), 0.0, 0)
	debris(frame, t, 0.63, frame.target, 26, 1.45, 0.13, 0.31, 100, 1)
