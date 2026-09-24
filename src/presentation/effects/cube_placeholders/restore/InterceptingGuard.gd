## Study 20, Intercepting guard: six guard cubes orbit the target, pivot to
## meet an incoming cube, absorb it, and return to their orbit.
##
## Sketch:
##   engage=smooth(phase(t,.25,.49))*(1-smooth(phase(t,.66,.84)));
##   for(i<6){a=i*TAU/6+t*3, ox=T+cos(a)*.85, oz=sin(a)*.85;
##     cube(mix(ox,T-.78,engage),mix(.8,.43+floor(i/2)*.4,engage),mix(oz,(i%2-.5)*.39,engage),
##       .25*sizeIn(t,0,.1)*tail(t,.9,1),a*.3);}
##   throwCube(t,.23,.55,C,T-.9,0,0,.1,.3); debris(t,.55,T-.9,0,9,.5,.065,.18);
##
## Where the threat comes from. In the sketch the hostile seventh cube comes
## from `C`. A shield cast by an ally has no hostile caster, so the threat
## axis is the anchor's own front — the direction to its nearest hostile,
## which the battle supplies per protected ally — and the guards form their
## 2x3 wall on that side. The incoming cube travels in along the same axis
## from the sketch's own distance, 3.5 units out. Without a supplied front the
## axis is the frame's forward, so the threat comes from beyond the anchor.
extends "res://src/presentation/effects/cube_placeholders/restore/RestoreComposition.gd"

const ORBIT_RADIUS := 0.85


func profileID() -> String:
	return "cube_intercepting_guard"


func displayName() -> String:
	return "Cube Intercepting Guard"


func binding() -> String:
	return BINDING_BODY


func beats() -> Array[Dictionary]:
	return [
		{"name": "Orbit", "start": 0.0, "end": 0.25, "travel": false},
		{"name": "Intercept", "start": 0.25, "end": 0.66, "travel": false},
		{"name": "Recover", "start": 0.66, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["guards", "incoming", "chips"]


func peakCubes() -> int:
	return 15


func areaReferenceRadius() -> float:
	return ORBIT_RADIUS


func impactTime() -> float:
	return 0.55


static func engagement(t: float) -> float:
	return smooth(phase(t, 0.25, 0.49)) * (1.0 - smooth(phase(t, 0.66, 0.84)))


## The unit horizontal direction the threat comes from.
static func threatAxis(frame: CubePlaceholderFrame) -> Vector3:
	return frame.front


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var axis := threatAxis(frame)
	var planar := frame.targetScale()
	var engage := engagement(t)
	for i: int in range(6):
		var a := i * TAU / 6.0 + t * 3.0
		var orbit := local(frame, frame.target, axis, cos(a) * ORBIT_RADIUS, 0.8, sin(a) * ORBIT_RADIUS, planar)
		var wall := local(frame, frame.target, axis, 0.78, 0.43 + floorf(i / 2.0) * 0.4, (i % 2 - 0.5) * 0.39, planar)
		frame.cube(i, orbit.lerp(wall, engage), 0.25 * sizeIn(t, 0.0, 0.1) * tail(t, 0.9, 1.0), a * 0.3, 0)
	# The incoming cube: the sketch's throwCube from C to T-.9, on the threat
	# axis. It gives way to its chips at .55 rather than sharing that instant
	# with them: it is absorbed there.
	if t >= 0.23 - 0.08 and t < 0.55:
		var q := phase(t, 0.23, 0.55)
		var ground := frame.target + axis * (mix(SKETCH_SEPARATION, 0.9, q) * planar)
		var lift := (mix(0.8, 0.7, q) + 0.4 * q * (1.0 - q)) * frame.cubeScale()
		frame.cube(10, ground + frame.up * lift, 0.3 * sizeIn(t, 0.15, 0.23), q * 5.0, 1)
	debris(frame, t, 0.55, frame.target + axis * (0.9 * planar), 9, 0.5, 0.065, 0.18, 100, 2)
