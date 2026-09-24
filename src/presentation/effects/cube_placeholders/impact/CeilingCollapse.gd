## Study 07, Ceiling collapse: tiny cubes fall first like dust. Seven
## differently sized heavy cubes then drop almost together and scatter rubble
## across the target area.
##
## Sketch:
##   for(i<12){a=.04+rnd(i)*.16, q=phase(t,a,a+.3);
##     if(t>=a&&q<1)cube(T+(rnd(i+30)-.5)*2.3,mix(2.8,.05,q*q),(rnd(i+70)-.5)*1.7,.055+.04*rnd(i+50),q*4);}
##   for(i<7){a=.4+rnd(i)*.035, q=phase(t,a,a+.22), s=.38+rnd(i+21)*.44,
##     x=T+(rnd(i+50)-.5)*2.15, z=(rnd(i+85)-.5)*1.6;
##     if(t>=.27&&t<a+.22)cube(x,mix(3.05,s*.5,q*q),z,s*sizeIn(t,.27,.36),q*.7+i*.3);
##     else if(t>=a+.22)cube(x,s*.35,z,s*.72*tail(t,.77,.96),i*.3);
##     debris(t,a+.22,x,z,5,.7,.075,.24);}
##
## The warning is the point: the twelve dust cubes all start before .27, the
## heavies only appear, hanging, from .27, and none lands before .62.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_DUST := 0
const ROLE_HEAVY := 1
const ROLE_RUBBLE := 2


func profileID() -> String:
	return "cube_ceiling_collapse"


func displayName() -> String:
	return "Cube Ceiling Collapse"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Dust warning", "start": 0.0, "end": 0.4, "travel": false},
		{"name": "Heavy fall", "start": 0.4, "end": 0.66, "travel": false},
		{"name": "Rubble", "start": 0.66, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["dust", "heavy", "rubble"]


func peakCubes() -> int:
	return 42


## The farthest corner of the authored rectangle (1.15 by 0.85).
func areaReferenceRadius() -> float:
	return 1.43


func impactTime() -> float:
	return 0.62


## The first heavy cube's landing, for the ordering checks.
func heavyLandingTime(frame: CubePlaceholderFrame, index: int) -> float:
	return 0.4 + frame.rnd(index) * 0.035 + 0.22


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	for i: int in range(12):
		var a := 0.04 + frame.rnd(i) * 0.16
		var q := phase(t, a, a + 0.3)
		if t >= a and q < 1.0:
			var ground := areaPoint(frame, (frame.rnd(i + 30) - 0.5) * 2.3, (frame.rnd(i + 70) - 0.5) * 1.7)
			frame.cube(i, above(frame, ground, mix(2.8, 0.05, q * q)), 0.055 + 0.04 * frame.rnd(i + 50), q * 4.0, ROLE_DUST)
	for i: int in range(7):
		var a := 0.4 + frame.rnd(i) * 0.035
		var q := phase(t, a, a + 0.22)
		var s := 0.38 + frame.rnd(i + 21) * 0.44
		var ground := areaPoint(frame, (frame.rnd(i + 50) - 0.5) * 2.15, (frame.rnd(i + 85) - 0.5) * 1.6)
		if t >= 0.27 and t < a + 0.22:
			frame.cube(20 + i, above(frame, ground, mix(3.05, s * 0.5, q * q)), s * sizeIn(t, 0.27, 0.36), q * 0.7 + i * 0.3, ROLE_HEAVY)
		elif t >= a + 0.22:
			frame.cube(20 + i, above(frame, ground, s * 0.35), s * 0.72 * tail(t, 0.77, 0.96), i * 0.3, ROLE_HEAVY)
		areaDebris(frame, t, a + 0.22, ground, 5, 0.7, 0.075, 0.24, 100 + i * 5, ROLE_RUBBLE)
