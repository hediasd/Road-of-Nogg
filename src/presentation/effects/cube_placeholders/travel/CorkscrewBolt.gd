## Study 03, Corkscrew bolt: a lead cube drives straight ahead while seven tiny
## cubes wind around its path like a drilling wake.
##
## Sketch:
##   if(t<.67){q=smooth(phase(t,.16,.64)); cube(mix(C,T,q),.9,0,.36*sizeIn(t,.02,.14),q*14);
##     for(i<7){p=clamp(q-i*.035), a=t*32-i*.8;
##       cube(mix(C,T,p)-.15,.9+sin(a)*.3,cos(a)*.3,.11*sizeIn(t,.08,.2),a);}}
##   debris(t,.64,T,0,16,1.5,.1);
##
## The wake trails the lead by a fixed share of the path, as drawn; its helix
## radius is a property of the drill, not the path, so it keeps the plain unit.
extends "res://src/presentation/effects/cube_placeholders/travel/TravelComposition.gd"


func profileID() -> String:
	return "cube_corkscrew_bolt"


func displayName() -> String:
	return "Cube Corkscrew Bolt"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Wind up", "start": 0.0, "end": 0.16, "travel": false},
		{"name": "Bore forward", "start": 0.16, "end": 0.64, "travel": true},
		{"name": "Burst", "start": 0.64, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["bolt", "wake", "burst"]


func peakCubes() -> int:
	return 24


func impactTime() -> float:
	return 0.64


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	if t < 0.67:
		var q := smooth(phase(t, 0.16, 0.64))
		frame.cube(0, lifted(frame, pathPoint(frame, q), 0.9), 0.36 * sizeIn(t, 0.02, 0.14), q * 14.0, 0)
		for i: int in range(7):
			var p := clamp01(q - i * 0.035)
			var a := t * 32.0 - i * 0.8
			var ground := pathPoint(frame, p) - frame.forward * (0.15 * frame.unit)
			var position := (
				ground
				+ frame.up * ((0.9 + sin(a) * 0.3) * frame.unit)
				+ frame.side * (cos(a) * 0.3 * frame.unit)
			)
			frame.cube(1 + i, position, 0.11 * sizeIn(t, 0.08, 0.2), a, 1)
	debris(frame, t, 0.64, targetPoint(frame), 16, 1.5, 0.1, 0.27, 100, 2)
