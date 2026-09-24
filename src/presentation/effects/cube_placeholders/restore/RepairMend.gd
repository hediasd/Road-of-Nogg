## Study 19, Repair / mend: scattered cubes gently converge and rise, becoming
## four larger cubes in a stable vertical arrangement beside the target.
##
## Sketch:
##   if(t<.61)for(i<12){q=smooth(phase(t,.04+i*.011,.57)), a=i*2.4, r=1.35*(1-q);
##     cube(T+cos(a)*r,.1+q*(.3+(i%4)*.36),sin(a)*r,.11*sizeIn(t,0,.09),q*2+i);}
##   if(t>=.53)for(i<4)cube(T,.34+i*.38,0,.27*sizeIn(t,.53,.65)*tail(t,.8,.97),0);
##
## Beside, not inside. The sketch draws the stack at `T` itself; in its 2D
## painter's order that paints over the reference actor, but in the world it
## would bury the four blocks inside the target's body. Its own description
## says "beside the target", so the stack stands just clear of the body on
## the side axis, and the fragments converge on the stack, not on the body.
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"

## The standard actor's half-width plus half a block, in sketch units.
const BESIDE := 0.225 + 0.135


func profileID() -> String:
	return "cube_repair_mend"


func displayName() -> String:
	return "Cube Repair Mend"


func binding() -> String:
	return BINDING_BODY


func beats() -> Array[Dictionary]:
	return [
		{"name": "Gather fragments", "start": 0.0, "end": 0.3, "travel": false},
		{"name": "Rise inward", "start": 0.3, "end": 0.57, "travel": false},
		{"name": "Reassemble", "start": 0.57, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["fragments", "blocks"]


func peakCubes() -> int:
	return 16


func impactTime() -> float:
	return 0.65


static func stackBase(frame: CubePlaceholderFrame) -> Vector3:
	return frame.target + frame.side * (BESIDE * frame.targetScale())


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var base := stackBase(frame)
	var planar := frame.targetScale()
	if t < 0.61:
		for i: int in range(12):
			var q := smooth(phase(t, 0.04 + i * 0.011, 0.57))
			var a := i * 2.4
			var r := 1.35 * (1.0 - q)
			var position := local(frame, base, frame.forward, cos(a) * r, 0.1 + q * (0.3 + (i % 4) * 0.36), sin(a) * r, planar)
			frame.cube(i, position, 0.11 * sizeIn(t, 0.0, 0.09), q * 2.0 + i, 0)
	if t >= 0.53:
		for i: int in range(4):
			var size := 0.27 * sizeIn(t, 0.53, 0.65) * tail(t, 0.8, 0.97)
			frame.cube(20 + i, base + frame.up * ((0.34 + i * 0.38) * frame.cubeScale()), size, 0.0, 1)
