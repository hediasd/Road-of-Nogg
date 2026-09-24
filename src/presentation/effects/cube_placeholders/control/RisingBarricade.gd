## Study 13, Rising barricade: a row of cubes rises into a three-layer wall
## between caster and target, holds, then sinks away.
##
## Sketch:
##   for(row<3)for(col<5){a=.07+row*.07+abs(col-2)*.025, q=sizeIn(t,a,a+.19)*tail(t,.8,.98);
##     cube(-.25,(.22+row*.43)*q,(col-2)*.43,.4*q,0);}
##
## Where the wall stands. In the sketch it stands at x = -.25, 57% of the way
## from caster to target. That is where it stands on a two-anchor cast. When
## the anchor is no more than a cell from the caster — a self-cast whose spec
## anchors it in front of the caster, or an adjacent target — the wall stands
## on the anchor itself, one cell in front, because 57% of one cell would put
## it against the caster's own body. Either way the wall runs across the
## source-to-anchor direction and never claims a cell: it is a picture of
## protection, not an obstruction.
extends "res://src/presentation/effects/cube_placeholders/control/ControlComposition.gd"

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")


func profileID() -> String:
	return "cube_rising_barricade"


func displayName() -> String:
	return "Cube Rising Barricade"


func binding() -> String:
	return BINDING_TWO_ANCHOR


func beats() -> Array[Dictionary]:
	return [
		{"name": "Seed line", "start": 0.0, "end": 0.14, "travel": false},
		{"name": "Build upward", "start": 0.14, "end": 0.8, "travel": false},
		{"name": "Withdraw", "start": 0.8, "end": 1.0, "travel": false},
	]


func roles() -> Array[String]:
	return ["wall"]


func peakCubes() -> int:
	return 15


func impactTime() -> float:
	return 0.45


## The wall's ground centre for a frame, as the header describes.
static func wallCentre(frame: CubePlaceholderFrame) -> Vector3:
	if frame.distance <= Profile.CELL_PITCH_U + 0.001:
		return frame.target
	return frame.along(CubePlaceholderFrame.progressOfSketchX(-0.25))


func sample(t: float, frame: CubePlaceholderFrame) -> void:
	var centre := wallCentre(frame)
	var scale := frame.cubeScale()
	for row: int in range(3):
		for col: int in range(5):
			var a := 0.07 + row * 0.07 + absi(col - 2) * 0.025
			var q := sizeIn(t, a, a + 0.19) * tail(t, 0.8, 0.98)
			var position := centre + frame.up * ((0.22 + row * 0.43) * q * scale) + frame.side * ((col - 2) * 0.43 * scale)
			frame.cube(row * 5 + col, position, 0.4 * q, 0.0, 0)
