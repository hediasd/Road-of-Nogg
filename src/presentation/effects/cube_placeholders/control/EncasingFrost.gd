## Study 18, Encasing frost: cubes accumulate around the target from the feet
## upward into a rigid shell, then chip away at release.
##
## Sketch:
##   for(i<18){row=floor(i/6), a=i*TAU/6, st=.02+row*.15+(i%6)*.022,
##     s=(.28+rnd(i)*.11)*sizeIn(t,st,st+.13)*tail(t,.83,.98);
##     cube(T+cos(a)*.54,.22+row*.52,sin(a)*.54,s,0);}
##   debris(t,.85,T,0,12,1,.07,.14);
##
## Three rings of six, feet first. The shell's radius is tight to the standard
## body (0.54 sketch units against a 0.225 half-width) and grows uniformly
## with it, so it occludes a lot of the target: that is the point of a freeze.
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const SHELL_RADIUS := 0.54


func profileID() -> String:
	return "cube_encasing_frost"


func displayName() -> String:
	return "Cube Encasing Frost"


func beats() -> Array[Dictionary]:
	return [
		{"name": "Seed crystals", "start": 0.0, "end": 0.17, "travel": false},
		{"name": "Build shell", "start": 0.17, "end": 0.56, "travel": false},
		{"name": "Lock", "start": 0.56, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["shell", "chips"]


func peakCubes() -> int:
	return 30


func areaReferenceRadius() -> float:
	return SHELL_RADIUS


func impactTime() -> float:
	return 0.56


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	for i: int in range(18):
		var row := i / 6
		var a := i * TAU / 6.0
		var start := 0.02 + row * 0.15 + (i % 6) * 0.022
		var size := (0.28 + frame.rnd(i) * 0.11) * sizeIn(t, start, start + 0.13) * tail(t, 0.83, 0.98)
		frame.cube(i, around(frame, cos(a) * SHELL_RADIUS, 0.22 + row * 0.52, sin(a) * SHELL_RADIUS), size, 0.0, 0)
	debris(frame, t, 0.85, frame.target, 12, 1.0, 0.07, 0.14, 100, 1)
