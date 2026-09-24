## Study 09, Expanding shockwave: a small core compresses, then a broad ring of
## cubes rushes outward low across the ground.
##
## Sketch:
##   if(t<.3)cube(T,.2,0,mix(.45,.09,phase(t,.07,.29))*sizeIn(t,0,.07),t*2);
##   if(t>=.3){q=phase(t,.3,.85), r=.2+q*2.2;
##     ring(T,.15+sin(q*PI)*.23,r,24,.17*tail(t,.63,.9),q*.25,t);}
##   ring(x,y,r,n,s,angle,t): cube(x+cos(a)*r,y,sin(a)*r,s,t*5+i*.3), a=i*TAU/n+angle
##
## Each ring cube is projected like any area point, so the ring takes the
## footprint's outline as it grows: round on a disc, reaching down the arms
## of a cross.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_CORE := 0
const ROLE_RING := 1
const RING_COUNT := 24


func profileID() -> String:
	return "cube_expanding_shockwave"


func displayName() -> String:
	return "Cube Expanding Shockwave"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Compress", "start": 0.0, "end": 0.3, "travel": false},
		{"name": "Expanding ring", "start": 0.3, "end": 0.63, "travel": false},
		{"name": "Scatter", "start": 0.63, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["core", "ring"]


func peakCubes() -> int:
	return RING_COUNT


## The ring's radius at the end of its growth.
func areaReferenceRadius() -> float:
	return 2.4


func impactTime() -> float:
	return 0.3


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	if t < 0.3:
		var size := mix(0.45, 0.09, phase(t, 0.07, 0.29)) * sizeIn(t, 0.0, 0.07)
		frame.cube(0, above(frame, areaOrigin(frame), 0.2), size, t * 2.0, ROLE_CORE)
		return
	var q := phase(t, 0.3, 0.85)
	var r := 0.2 + q * 2.2
	var height := 0.15 + sin(q * PI) * 0.23
	var size := 0.17 * tail(t, 0.63, 0.9)
	for i: int in range(RING_COUNT):
		var a := i * TAU / float(RING_COUNT) + q * 0.25
		var ground := areaPoint(frame, cos(a) * r, sin(a) * r)
		frame.cube(1 + i, above(frame, ground, height), size, t * 5.0 + i * 0.3, ROLE_RING)
