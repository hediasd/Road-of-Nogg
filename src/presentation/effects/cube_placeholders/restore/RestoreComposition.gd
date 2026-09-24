## Shared helpers for the restore and transform family: effects whose meaning
## is a direction — repair, intercept, drain, cleanse, transfer, charge.
##
## Direction must read from motion alone, so every study names its roles in
## terms of the cast: `source` is the caster, `target` the anchor. The drain
## runs target to source, the charge gathers at the source and fires at the
## target, the guard faces its anchor's front.
##
## A SELF-CAST STILL HAS A DIRECTION. When source and anchor coincide the
## substrate gives the frame the anchor's front as its forward (the direction
## to the nearest hostile, or the caster's front), so `forward` and `side` are
## always unit vectors. A two-anchor study played on itself collapses its path
## to zero length and keeps its vertical motion: a drain on oneself loosens
## and falls back, a charge fires in place. Nothing reads a direction that is
## not there, so nothing produces NaN.
##
## Paths between two anchors use the same path scale as the travel family,
## copied here rather than shared: `unit * sqrt(separation / 5.6)`, clamped to
## 0.6-2.0 units, for arc heights and lateral streak offsets.

extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")

const REFERENCE_DURATION_S := 4.8
const BATTLE_DURATION_S := 2.0
const SKETCH_SEPARATION := Profile.SKETCH_T - Profile.SKETCH_C
const PATH_SCALE_MIN := 0.6
const PATH_SCALE_MAX := 2.0


func referenceDurationSeconds() -> float:
	return REFERENCE_DURATION_S


func battleDurationSeconds() -> float:
	return BATTLE_DURATION_S


static func pathScale(frame: CubePlaceholderFrame) -> float:
	var ratio := frame.distance / (SKETCH_SEPARATION * frame.unit)
	return frame.unit * clampf(sqrt(maxf(ratio, 0.0)), PATH_SCALE_MIN, PATH_SCALE_MAX)


## A point `x` along `axis`, `z` across it and `y` up from `origin`, in sketch
## units: ground plan at `planar` world units each, height at the cube scale.
static func local(
		frame: CubePlaceholderFrame, origin: Vector3, axis: Vector3,
		x: float, y: float, z: float, planar: float) -> Vector3:
	var across := axis.cross(Vector3.UP).normalized()
	return origin + axis * (x * planar) + across * (z * planar) + frame.up * (y * frame.cubeScale())
