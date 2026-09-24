## One anchor's coordinate frame: how a composition written in the sketch's
## diagram units lands in the world for one cast.
##
## THE SKETCH'S AXES. x runs from the caster reference `C` toward the target
## reference `T`, y is up from the ground, z is lateral. Here x becomes the
## horizontal source-to-anchor direction (`forward`), y is world up, and z is
## `side = forward x up`, which keeps the sketch's handedness.
##
## THREE SCALES, BECAUSE THE SKETCH MIXES THREE KINDS OF DISTANCE.
## - Along a source-to-target path the live anchors decide: `along(q, ...)`
##   interpolates between them, so a path always starts at the caster and ends
##   at the target whatever the separation.
## - Offsets around an anchor use `targetScale`: world units per sketch unit
##   (`UNIT_U`), times the uniform body adaptation for a body-bound composition,
##   times the area spread when the spell's spec spreads it over a footprint.
## - Cube edges use `cubeScale`: the unit times the body adaptation only. Area
##   spread moves cubes apart; it never makes them bigger.
## Lateral and vertical offsets along a path use the plain unit.
##
## A frame holds no nodes and allocates nothing after it is built; sampling
## only reads it and writes into the shared pose buffer.

class_name CubePlaceholderFrame
extends RefCounted

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")
const PoseBuffer = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderPoseBuffer.gd")

var anchorIndex: int = 0
## Ground point the effect is cast from.
var source: Vector3 = Vector3.ZERO
## Ground point of this anchor: the target, the cast centre, or a point in
## front of the caster, depending on the spell's spec.
var target: Vector3 = Vector3.ZERO
## Horizontal unit from source to anchor. Falls back to `front` when the two
## coincide, so a self-cast still has a direction.
var forward: Vector3 = Vector3.RIGHT
var side: Vector3 = Vector3.BACK
var up: Vector3 = Vector3.UP
## The anchor's own facing: toward its nearest hostile when the caller
## supplied one, otherwise `forward`.
var front: Vector3 = Vector3.RIGHT
## Horizontal source-to-anchor distance in world units.
var distance: float = 0.0
var unit: float = Profile.UNIT_U
var bodyScale: float = 1.0
var areaScale: float = 1.0
var bodyBounds: AABB = VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
## Null unless the cast has an area and the effect was handed one.
var footprint: HexVfxFootprint = null
var seedShift: float = 0.0
var buffer: PoseBuffer = null
## True when the anchor stands exactly where the cast was aimed and a unit is
## there; false for an empty centre cell.
var hasBody: bool = true


## World units per sketch unit for offsets around the anchor.
func targetScale() -> float:
	return unit * bodyScale * areaScale


## World units per sketch unit of cube edge.
func cubeScale() -> float:
	return unit * bodyScale


## The sketch's `rnd(i)`, shifted by the playback seed. Seed 0 reproduces the
## sketch's own values exactly.
func rnd(i: float) -> float:
	var x := sin((i + seedShift) * 127.1 + 311.7) * 43758.5453
	return x - floor(x)


## A point on the source-to-anchor path at progress `q` (0 at the source, 1 at
## the anchor, extrapolating beyond), lifted `y` and offset `z` sketch units.
## Ground height interpolates between the two anchors.
func along(q: float, y: float = 0.0, z: float = 0.0) -> Vector3:
	return source.lerp(target, q) + up * (y * unit) + side * (z * unit)


## A point `dx` forward, `y` up and `dz` sideways of the anchor, in sketch
## units at `scale` world units each (default: `targetScale()`).
func nearTarget(dx: float, y: float = 0.0, dz: float = 0.0, scale: float = -1.0) -> Vector3:
	var s := targetScale() if scale < 0.0 else scale
	return target + forward * (dx * s) + up * (y * s) + side * (dz * s)


func nearSource(dx: float, y: float = 0.0, dz: float = 0.0, scale: float = -1.0) -> Vector3:
	var s := unit if scale < 0.0 else scale
	return source + forward * (dx * s) + up * (y * s) + side * (dz * s)


## The sketch's `x` coordinate as path progress: `C` is 0 and `T` is 1.
static func progressOfSketchX(x: float) -> float:
	return (x - Profile.SKETCH_C) / (Profile.SKETCH_T - Profile.SKETCH_C)


## Ground height under a world point, interpolated along the path.
func groundYAt(point: Vector3) -> float:
	if distance <= 0.001:
		return target.y
	var offset := point - source
	var progress := clampf(offset.dot(forward) / distance, 0.0, 1.0)
	return lerpf(source.y, target.y, progress)


## Emits one cube, the sketch's `cube(x, y, z, s, yaw)`: `sizeSketch` is its
## edge in sketch units at `sizeScale` world units each (default:
## `cubeScale()`). Like the sketch, a cube never sinks below the ground: its
## centre is held at least half an edge above it. Cubes too small or too
## faint to see are not emitted at all, which is the sketch's own cull.
func cube(
		id: int, position: Vector3, sizeSketch: float, yaw: float = 0.0,
		role: int = 0, opacity: float = 1.0, sizeScale: float = -1.0) -> void:
	if sizeSketch <= Profile.MIN_VISIBLE_SIZE or opacity <= Profile.MIN_VISIBLE_OPACITY:
		return
	var edge := sizeSketch * (cubeScale() if sizeScale < 0.0 else sizeScale)
	var placed := position
	placed.y = maxf(placed.y, groundYAt(position) + edge * 0.5)
	buffer.push(id, placed, edge, yaw, role, clampf(opacity, 0.0, 1.0), anchorIndex)
