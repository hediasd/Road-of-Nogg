## Study 11, Rolling avalanche: two large cubes tumble toward and through the
## target, followed by a low trail of smaller rubble.
##
## Sketch:
##   for(i<12){a=.08+i*.014, b=.67+i*.013, q=phase(t,a,b), s=i<2?.67:.13+rnd(i)*.18;
##     if(t>=a&&t<b)cube(mix(C-.2,T+.7,q),s*.6+abs(sin(q*14+i))*.23,(rnd(i+11)-.5)*1.3,s,t*13+i);}
##   debris(t,.64,T,0,18,1.6,.14,.29);
##
## A lane from just behind the caster to just beyond the target. The footprint
## is collision truth for the break-apart rubble, which stays on the affected
## cells; the lane itself is never bent to follow the cells, because a rush
## that swerves stops reading as a rush.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_BOULDERS := 0
const ROLE_TRAIL := 1
const ROLE_RUBBLE := 2


func profileID() -> String:
	return "cube_rolling_avalanche"


func displayName() -> String:
	return "Cube Rolling Avalanche"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Rumble", "start": 0.0, "end": 0.08, "travel": false},
		{"name": "Roll through", "start": 0.08, "end": 0.64, "travel": true},
		{"name": "Break apart", "start": 0.64, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["boulders", "trail", "rubble"]


func peakCubes() -> int:
	return 30


func impactTime() -> float:
	return 0.6


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var laneStart := frame.source - frame.forward * (0.2 * frame.unit)
	var laneEnd := frame.target + frame.forward * (0.7 * frame.unit)
	for i: int in range(12):
		var a := 0.08 + i * 0.014
		var b := 0.67 + i * 0.013
		if t < a or t >= b:
			continue
		var q := phase(t, a, b)
		var s := 0.67 if i < 2 else 0.13 + frame.rnd(i) * 0.18
		var ground := laneStart.lerp(laneEnd, q) + frame.side * ((frame.rnd(i + 11) - 0.5) * 1.3 * frame.unit)
		var lift := s * 0.6 + absf(sin(q * 14.0 + i)) * 0.23
		frame.cube(i, ground + frame.up * (lift * frame.unit), s, t * 13.0 + i, ROLE_BOULDERS if i < 2 else ROLE_TRAIL)
	areaDebris(frame, t, 0.64, frame.target, 18, 1.6, 0.14, 0.29, 100, ROLE_RUBBLE)
