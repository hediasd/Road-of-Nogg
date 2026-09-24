## Study 21, Siphon: small cubes peel away from the target in a staggered
## stream and travel back into a growing cube above the caster.
##
## Sketch:
##   for(i<9){a=.07+i*.04, b=a+.36, q=phase(t,a,b);
##     if(t>=a&&t<b){p=ballistic(q,T,C,(rnd(i)-.5)*.8,0,.38);
##       cube(...p,.15*sizeIn(t,a,a+.04)*(1-q*.6),q*4+i);}}
##   cube(C,1.1,0,(.15+.29*phase(t,.38,.76))*sizeIn(t,.12,.25)*tail(t,.84,.98),t*2);
##
## Direction is the whole meaning: every stream cube leaves the target and
## ends at the caster, and the caster's cube only grows.
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"


func profileID() -> String:
	return "cube_siphon"


func displayName() -> String:
	return "Cube Siphon"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Loosen", "start": 0.0, "end": 0.07, "travel": false},
		{"name": "Pull to caster", "start": 0.07, "end": 0.79, "travel": true},
		{"name": "Absorb", "start": 0.79, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["stream", "absorber"]


func peakCubes() -> int:
	return 10


func impactTime() -> float:
	return 0.43


static func absorberSize(t: float) -> float:
	return (0.15 + 0.29 * phase(t, 0.38, 0.76)) * sizeIn(t, 0.12, 0.25) * tail(t, 0.84, 0.98)


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var lateral := pathScale(frame)
	for i: int in range(9):
		var a := 0.07 + i * 0.04
		var b := a + 0.36
		if t < a or t >= b:
			continue
		var q := phase(t, a, b)
		var ground := frame.target.lerp(frame.source, q) + frame.side * (mix((frame.rnd(i) - 0.5) * 0.8, 0.0, q) * lateral)
		var lift := mix(0.8, 0.7, q) * frame.unit + 4.0 * 0.38 * q * (1.0 - q) * lateral
		frame.cube(i, ground + frame.up * lift, 0.15 * sizeIn(t, a, a + 0.04) * (1.0 - q * 0.6), q * 4.0 + i, 0)
	frame.cube(20, frame.source + frame.up * (1.1 * frame.unit), absorberSize(t), t * 2.0, 1)
