## A composition that exists only for the substrate probe. It exercises every
## frame helper, two roles, a travel beat and exactly 48 simultaneous cubes at
## its peak, without being any real study.
extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const PEAK := 48


func profileID() -> String:
	return "probe_cube_test"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Gather", "start": 0.0, "end": 0.2, "travel": false},
		{"name": "Travel", "start": 0.2, "end": 0.6, "travel": true},
		{"name": "Impact", "start": 0.6, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["orbit", "chips"]


func peakCubes() -> int:
	return PEAK


func impactTime() -> float:
	return 0.6


func settleTime() -> float:
	return 0.8


func referenceDurationSeconds() -> float:
	return 3.0


func battleDurationSeconds() -> float:
	return 1.5


## 40 orbiters gather at the source, travel along the path and fade at the
## target; eight chips burst at the target from 0.5 until 0.7, so the peak of
## 48 falls between 0.5 and 0.6.
func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var travel := phase(t, 0.2, 0.6)
	for i: int in range(40):
		var angle := i * TAU / 40.0 + t * 4.0
		var size := 0.12 * sizeIn(t, 0.0, 0.1) * tail(t, 0.85, 0.97)
		var position := frame.along(travel, 0.8 + sin(angle) * 0.3, cos(angle) * 0.3)
		frame.cube(i, position, size, angle, 0)
	if t >= 0.5 and t < 0.7:
		for i: int in range(8):
			var r := phase(t, 0.5, 0.7) * (0.4 + frame.rnd(i))
			frame.cube(100 + i, frame.nearTarget(cos(i) * r, 0.2, sin(i) * r), 0.08, i * 0.3, 1)
