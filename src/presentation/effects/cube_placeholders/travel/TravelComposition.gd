## Shared coordinate conversion for the travel and delivery family: six
## source-to-target motions translated from the retained sketch.
##
## THE PATH SCALE. The sketch draws every path over a 3.5-unit separation, so
## an arc 1.3 units high reads as a steep lob. Converted at the plain world unit
## the same arc over a real cast, which is longer, reads flatter and flatter;
## scaled by the full separation ratio a long cast lobs off the top of the
## frame. Arc heights and lateral path offsets therefore scale by
## `unit * sqrt(separation / sketch separation)`: a long path lobs higher and
## swings wider than a short one, but slower than it lengthens. Launch heights,
## cube sizes and everything around the target keep their own scales, so the
## size hierarchy against real bodies is untouched. Computed against the
## sketch's own height-to-length ratio: 18% steeper at 2 cells, 16% flatter at
## the 4-cell reference, 25% flatter at 5 cells and 47% flatter at 10, where a
## proportional arc would be over 7 world units high.
##
## A study's x endpoints are the source and the target themselves, so a path
## begins and ends on the live anchors at any distance. A study point given
## relative to `T` (`T + dx`) is placed relative to the target, never by
## extrapolating the path, so it does not drift away as the cast lengthens.

extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")

## The sketch loop is 4.8 seconds at its normal speed.
const REFERENCE_DURATION_S := 4.8
## The battle action queue wants roughly the rituals' pace: the ritual plays
## 2.10s in battle against 5.20s reference.
const BATTLE_DURATION_S := 2.0
const SKETCH_SEPARATION := Profile.SKETCH_T - Profile.SKETCH_C
const PATH_SCALE_MIN := 0.6
const PATH_SCALE_MAX := 2.0


func binding() -> String:
	return BINDING_TWO_ANCHOR


func referenceDurationSeconds() -> float:
	return REFERENCE_DURATION_S


func battleDurationSeconds() -> float:
	return BATTLE_DURATION_S


## World units per sketch unit for arc heights and lateral path offsets.
static func pathScale(frame: CubePlaceholderFrame) -> float:
	var ratio := frame.distance / (SKETCH_SEPARATION * frame.unit)
	return frame.unit * clampf(sqrt(maxf(ratio, 0.0)), PATH_SCALE_MIN, PATH_SCALE_MAX)


## A ground point `z` sketch units to the side of the source.
static func sourcePoint(frame: CubePlaceholderFrame, z: float = 0.0) -> Vector3:
	return frame.source + frame.side * (z * pathScale(frame))


## A ground point at path progress `q` (the sketch's `mix(C, T, q)`), `z`
## sketch units to the side.
static func pathPoint(frame: CubePlaceholderFrame, q: float, z: float = 0.0) -> Vector3:
	return frame.source.lerp(frame.target, q) + frame.side * (z * pathScale(frame))


## A ground point `dx` beyond and `dz` beside the target (the sketch's
## `T + dx`), at the target scale.
static func targetPoint(frame: CubePlaceholderFrame, dx: float = 0.0, dz: float = 0.0) -> Vector3:
	return frame.nearTarget(dx, 0.0, dz)


## The sketch's `throwCube`: a lob from ground point `from` to `to` between
## `start` and `end`, growing in over the 0.08 before it leaves. Launch and
## landing heights (0.8 and 0.7) are body-relative and use the plain unit; the
## arc uses the path scale.
static func throwCube(
		frame: CubePlaceholderFrame, t: float, start: float, end: float,
		from: Vector3, to: Vector3, height: float, size: float, id: int, role: int = 0) -> void:
	if t < start - 0.08 or t > end:
		return
	var q := phase(t, start, end)
	var ground := from.lerp(to, q)
	var lift := mix(0.8, 0.7, q) * frame.unit + 4.0 * height * q * (1.0 - q) * pathScale(frame)
	frame.cube(id, ground + frame.up * lift, size * sizeIn(t, start - 0.08, start), q * 5.0, role)


## A point `y` sketch units above a ground point, at the plain unit.
static func lifted(frame: CubePlaceholderFrame, ground: Vector3, y: float) -> Vector3:
	return ground + frame.up * (y * frame.unit)
