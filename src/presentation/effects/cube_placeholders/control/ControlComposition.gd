## Shared bounds policy for the shape and control family: persistent spatial
## states built around a target out of identical cubes.
##
## ONE POLICY, UNIFORM. A body-bound study is drawn around the sketch's
## standard actor. On a real target the whole composition scales by one
## factor, the substrate's body adaptation (`frame.bodyScale`): wide enough to
## enclose the widest horizontal extent, tall enough to clear the head. Cubes
## scale with it and stay cubes; no axis is stretched on its own, so a wide
## and a tall body see the same choreography, only larger.
##
## AREA SPREAD IS HORIZONTAL. When a spell's spec spreads a body-bound shape
## over its footprint (a cage that encircles an area), `around()` spreads the
## ground plan by the frame's target scale and keeps heights and cube sizes at
## the body scale. A spread cage is wider, never taller, so its posts stay
## columns of touching cubes instead of towers of floating ones.

extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const REFERENCE_DURATION_S := 4.8
const BATTLE_DURATION_S := 2.0


func binding() -> String:
	return BINDING_BODY


func referenceDurationSeconds() -> float:
	return REFERENCE_DURATION_S


func battleDurationSeconds() -> float:
	return BATTLE_DURATION_S


## A point `x` forward, `y` up and `z` beside the target, in sketch units:
## ground plan at the target scale, height at the cube scale.
static func around(frame: CubePlaceholderFrame, x: float, y: float, z: float) -> Vector3:
	var planar := frame.targetScale()
	return (
		frame.target
		+ frame.forward * (x * planar)
		+ frame.side * (z * planar)
		+ frame.up * (y * frame.cubeScale())
	)
