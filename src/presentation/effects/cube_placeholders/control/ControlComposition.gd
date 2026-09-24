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
## AREA SPREAD IS HORIZONTAL, AND STAYS ON THE CELLS. When a spell's spec
## spreads a body-bound shape over its footprint (a cage that encircles an
## area), `around()` spreads the ground plan by the frame's target scale and
## keeps heights and cube sizes at the body scale, so a spread cage is wider,
## never taller. Each point is then held within the footprint's reach in its
## own direction (85% of it), so a footprint clipped by the board edge or
## shaped like a cross never gets a post on a cell the spell did not hit. The
## hold never pulls a point inside the unspread, body-sized shape: spreading
## can only widen it. (Found in the cycle's live-battle validation: scaled
## uniformly to the farthest cell, a spread cage near the board edge put posts
## off the board.)

extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const FootprintReach = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderFootprintReach.gd")

const REFERENCE_DURATION_S := 4.8
const BATTLE_DURATION_S := 2.0
const SPREAD_FILL := 0.85

## Per anchor; null where the shape is not spread over a footprint.
var _reaches: Array = []


func binding() -> String:
	return BINDING_BODY


func referenceDurationSeconds() -> float:
	return REFERENCE_DURATION_S


func battleDurationSeconds() -> float:
	return BATTLE_DURATION_S


func prepare(frames: Array) -> void:
	_reaches.clear()
	for frame: CubePlaceholderFrame in frames:
		_reaches.append(
			FootprintReach.measure(frame.footprint, frame.target) if frame.areaScale > 1.0 else null
		)


## A point `x` forward, `y` up and `z` beside the target, in sketch units:
## ground plan at the target scale, held on the footprint when spread; height
## at the cube scale.
func around(frame: CubePlaceholderFrame, x: float, y: float, z: float) -> Vector3:
	var planar := frame.forward * (x * frame.targetScale()) + frame.side * (z * frame.targetScale())
	var reach: FootprintReach = _reaches[frame.anchorIndex] if frame.anchorIndex < _reaches.size() else null
	if reach != null:
		var radius := planar.length()
		if radius > 0.0001:
			var unspread := radius / frame.areaScale
			var held := maxf(unspread, minf(radius, reach.toward(planar) * SPREAD_FILL))
			planar = planar / radius * held
	return frame.target + planar + frame.up * (y * frame.cubeScale())
