## Study 10, Implosion: eighteen suspended cubes accelerate inward from a broad
## sphere, compress into one core, and vanish.
##
## Sketch:
##   if(t<.69){q=phase(t,.29,.69), r=1.8*(1-q*q*q);
##     for(i<18){a=i*2.4; cube(T+cos(a)*r,.75+sin(a*1.7)*r*.4,sin(a)*r,.19*sizeIn(t,.03,.2),t*3+i);}}
##   if(t>=.65)cube(T,.75,0,.55*sizeIn(t,.65,.7)*tail(t,.74,.91),t*9);
##
## A target-centred volume, not an area: under `AREA_SCALING: spread` the
## sphere's radius grows with the footprint's reach (through the frame's
## target scale), and it is not projected onto the cells.
extends "res://src/presentation/effects/cube_placeholders/impact/ImpactComposition.gd"

const ROLE_SHELL := 0
const ROLE_CORE := 1


func profileID() -> String:
	return "cube_implosion"


func displayName() -> String:
	return "Cube Implosion"


func binding() -> String:
	return BINDING_VOLUME


func beats() -> Array[Dictionary]:
	return [
		{"name": "Hang", "start": 0.0, "end": 0.29, "travel": false},
		{"name": "Snap inward", "start": 0.29, "end": 0.69, "travel": false},
		{"name": "Collapse", "start": 0.69, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["shell", "core"]


func peakCubes() -> int:
	return 19


func areaReferenceRadius() -> float:
	return 1.8


func impactTime() -> float:
	return 0.69


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var spread := frame.targetScale()
	var centre := frame.target + frame.up * (0.75 * frame.cubeScale())
	if t < 0.69:
		var q := phase(t, 0.29, 0.69)
		var r := 1.8 * (1.0 - q * q * q)
		for i: int in range(18):
			var a := i * 2.4
			var offset := (
				frame.forward * (cos(a) * r)
				+ frame.up * (sin(a * 1.7) * r * 0.4)
				+ frame.side * (sin(a) * r)
			)
			frame.cube(i, centre + offset * spread, 0.19 * sizeIn(t, 0.03, 0.2), t * 3.0 + i, ROLE_SHELL)
	if t >= 0.65:
		frame.cube(100, centre, 0.55 * sizeIn(t, 0.65, 0.7) * tail(t, 0.74, 0.91), t * 9.0, ROLE_CORE)
