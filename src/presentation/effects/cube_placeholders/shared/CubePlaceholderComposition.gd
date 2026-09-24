## One cube placeholder choreography: the translation of one sketch study.
##
## A strategy, not a playback. It knows its beats, its peak population and how
## to emit the cubes visible at a sketch-normalized time through a
## `CubePlaceholderFrame`; everything else — lifecycle, timeline warping,
## anchors, palettes, rendering — belongs to `CubePlaceholderEffect`, so every
## family shares it and none reimplements it.
##
## `sample()` must be a pure function of `t` and the frame: no state carried
## between calls, no allocation, and the same cubes in the same order every
## time. That is what makes seek, reverse scrub and pause reproduce exactly.
## Compositions are instanced per playback, so a subclass may cache values it
## derives from the frame in `prepare()`, which runs before any sampling.

class_name CubePlaceholderComposition
extends RefCounted

const Spec = preload("res://src/presentation/effects/SpellVfxSpec.gd")

## How a profile is bound to a cast. Data the catalog and bridge read, so no
## caller needs a profile-name conditional.
## `two_anchor`: travels between caster and target.
## `body`: wraps the target's body bounds.
## `area`: covers the affected footprint.
## `volume`: a target-centred volume that is neither body-sized nor an area.
const BINDING_TWO_ANCHOR := "two_anchor"
const BINDING_BODY := "body"
const BINDING_AREA := "area"
const BINDING_VOLUME := "volume"


func profileID() -> String:
	assert(false, "CubePlaceholderComposition.profileID() must be implemented.")
	return ""


func displayName() -> String:
	return profileID().capitalize()


func binding() -> String:
	return BINDING_TWO_ANCHOR


## Named beats in sketch-normalized time, covering 0-1 in order:
## `{"name": String, "start": float, "end": float, "travel": bool}`.
## Travel beats stretch with range under `RANGE_SCALING: travel`; the rest keep
## their length.
func beats() -> Array[Dictionary]:
	return [{"name": "play", "start": 0.0, "end": 1.0, "travel": false}]


## Layer names, one per cube role, in role-index order. The debug scene shows
## each as a toggle.
func roles() -> Array[String]:
	return ["cubes"]


## The most cubes one anchor ever shows at once, measured by sampling. The
## playback allocates at least this many per anchor.
func peakCubes() -> int:
	return 0


## The half-extent, in sketch units, of the area the study was authored over.
## Zero for a composition that never spreads over a footprint.
func areaReferenceRadius() -> float:
	return 0.0


func isBodyBound() -> bool:
	return binding() == BINDING_BODY


func defaultAreaScaling() -> String:
	return Spec.AREA_SPREAD if binding() == BINDING_AREA else Spec.AREA_NONE


func hasTravelBeats() -> bool:
	for beat: Dictionary in beats():
		if bool(beat.get("travel", false)):
			return true
	return false


func defaultRangeScaling() -> String:
	return Spec.RANGE_TRAVEL if hasTravelBeats() else Spec.RANGE_FIXED


## Wall-clock length of the whole choreography at the reference distance.
func referenceDurationSeconds() -> float:
	return 4.0


func battleDurationSeconds() -> float:
	return 2.0


## Sketch-normalized time the hit lands, which is where a battle caller holds
## the action queue.
func impactTime() -> float:
	return 0.7


## Sketch-normalized time `skip_to_settle()` jumps to: the resolved pose.
func settleTime() -> float:
	return impactTime()


## Runs once per playback preparation, before any sampling.
func prepare(_frames: Array) -> void:
	pass


## Emits every cube visible at sketch-normalized time `t` through `frame`.
func sample(_t: float, _frame: CubePlaceholderFrame) -> void:
	assert(false, "CubePlaceholderComposition.sample() must be implemented.")


## The sketch's helpers, kept under their sketch names so a translated study
## reads like its source.
static func clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)


static func phase(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


static func mix(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func sizeIn(t: float, a: float, b: float) -> float:
	return smooth(phase(t, a, b))


static func tail(t: float, a: float = 0.83, b: float = 0.97) -> float:
	return 1.0 - smooth(phase(t, a, b))


## The sketch's `debris(t, start, x, z, n, reach, s, duration)`: `n` chips
## bursting from a ground point over `duration`. `center` is that ground point
## in world space; `reach` and `s` are sketch units at `scale` (default: the
## frame's target scale, since debris is almost always an impact). Ids run
## from `idBase`, so a composition keeps each burst's palette stable.
static func debris(
		frame: CubePlaceholderFrame, t: float, start: float, center: Vector3,
		n: int = 12, reach: float = 1.2, s: float = 0.09, duration: float = 0.27,
		idBase: int = 1000, role: int = 0, scale: float = -1.0) -> void:
	if t < start or t > start + duration:
		return
	var q := phase(t, start, start + duration)
	var sc := frame.targetScale() if scale < 0.0 else scale
	for i: int in range(n):
		var a := frame.rnd(i + 42) * TAU
		var r := q * reach * (0.4 + frame.rnd(i + 120))
		var lift := 0.08 + sin(q * PI) * (0.2 + frame.rnd(i + 80) * 0.5)
		var position := (
			center
			+ frame.forward * (cos(a) * r * sc)
			+ frame.up * (lift * sc)
			+ frame.side * (sin(a) * r * sc)
		)
		# Chips keep cube scale: an area spread throws them further, never
		# makes them bigger.
		frame.cube(idBase + i, position, s * (1.0 - q * 0.9), q * 6.0 + i, role)


## The sketch's `ballistic(q, x0, x1, z0, z1, height, y0, y1)` with its x ends
## given as path progress (`progressOfSketchX` converts a sketch x).
static func ballistic(
		frame: CubePlaceholderFrame, q: float, p0: float, p1: float, z0: float, z1: float,
		height: float, y0: float = 0.8, y1: float = 0.7) -> Vector3:
	return frame.along(
		mix(p0, p1, q), mix(y0, y1, q) + 4.0 * height * q * (1.0 - q), mix(z0, z1, q)
	)
