## Where the clouds are, where the wind has carried them, and where each one's shadow falls.
##
## Pure derivation, no nodes and no state. It knows nothing about Godot's scene tree, nothing
## about the framing dictionary, and nothing about the cloud catalog -- it takes sizes and a
## count, and returns positions in MAP PIXELS. Everything downstream converts from there, which
## is what lets this be checked without rendering anything.
##
## PLACEMENT IS A GOLDEN-RATIO SCATTER, NOT A GRID, and the reasoning is worth keeping because
## the obvious two answers are both wrong here.
##
## Uniform random is wrong. The visible slice of a plane at altitude is not the visible ground
## shifted: the cloud ray is `camera_height - altitude` long instead of `camera_height`, so at
## altitude 6 it reaches about 60% as far and lands on a different, nearer rectangle of map
## space. Scattering clouds uniformly therefore leaves the SKY empty while the layer still
## measures covered -- 9% coverage with nothing visible.
##
## A JITTERED LATTICE, which is what this was, is also wrong, and it is the defect this replaced.
## Cells were sized from the art so no two clouds could overlap, which sounds harmless and is
## not: for temp2 the cells came out 112 x 43.2 against an 88 x 40 cloud, so the horizontal
## slack was 24 px and **the vertical slack was 3.2 px**. Every cloud was pinned to one of five
## near-exact rows, and the field read as a column of clouds stacked at even spacing -- which is
## exactly what it looked like.
##
## What replaces it is the golden ratio's two-dimensional generalisation, the R2 (Roberts)
## sequence built from the PLASTIC NUMBER -- the constant that does for two dimensions what phi
## does for one. Its prefixes are well distributed for EVERY prefix length, which buys three
## things at once: the coverage guarantee the lattice existed for, with no grid to read; a low
## count that is already scattered, so the shuffled reveal order the lattice needed is gone; and
## a deterministic sequence, so the whole field still reproduces from its seed.
##
## NON-OVERLAP IS STILL A HARD GUARANTEE, because `worldmap_cloud.gdshader` depends on it: it
## draws with `depth_draw_never` and `blend_mix`, so two clouds crossing would double-blend into
## a denser patch and drag their 1 px outlines through one another. Candidates are therefore
## taken from the sequence and REJECTED against what is already placed, toroidally, so a cloud
## that has wrapped cannot land on one that has not.
##
## THE PER-CLOUD MOTION IS A BOUNDED OSCILLATION, NOT A SPEED DIFFERENCE. Every cloud takes the
## same wind, plus its own slow wander on its own periods and phases -- the house "idle that
## never resolves" from `docs/VFX_DESIGN.md`. Giving each cloud a slightly different SPEED
## instead is the obvious way to break up a rigid sheet and it cannot be used here: a faster
## cloud eventually catches a slower one, which breaks the non-overlap guarantee above at some
## unpredictable later time, and it slowly scrambles the scatter back toward uniform random.
## A bounded wander cannot do either, so the rejection test reserves the wander's own amplitude
## and the guarantee then holds for all time rather than only at t = 0.
##
## THE SHADOW IS NOT SCALED FROM THE CLOUD. The artist drew each shadow separately with the
## foreshortening already in it, so this returns the shadow's own rect centred under its cloud
## plus the sun's offset, and there is deliberately no `spread` factor to resample it with.

class_name WorldMapCloudField
extends RefCounted

## Config keys, all required. Stated as constants so a caller that misspells one fails loudly
## rather than silently taking a default that looks plausible.
const K_FIELD := "field"                    ## Vector2i, the region in map pixels
const K_CLOUD := "cloud"                    ## Vector2i, one cloud at native scale, map pixels
const K_SHADOW := "shadow"                  ## Vector2i, its shadow at native scale, map pixels
const K_PIECES := "pieces"                  ## int, how many distinct pairs the set holds
const K_COUNT := "count"                    ## int, how many clouds to place
const K_ALTITUDE := "altitude"              ## float, world units above the ground
const K_WIND_SPEED := "wind_speed"          ## float, world units per second
const K_WIND_ANGLE := "wind_angle"          ## float, degrees
const K_SEED := "seed"                      ## int
const K_PIXELS_PER_UNIT := "pixels_per_unit"  ## float, map pixels per world unit

## The plastic number, which solves `x^3 = x + 1`. It is to two dimensions what the golden ratio
## is to one: the additive recurrence stepping by its reciprocals fills the unit square with the
## lowest discrepancy any such sequence achieves, for every prefix length rather than only at
## favourable counts. Written out rather than derived so the sequence is bit-stable.
const R2_ALPHA_X := 0.7548776662466927   ## 1 / plastic
const R2_ALPHA_Y := 0.5698402909980532   ## 1 / plastic^2

## The golden ratio's own conjugate, for the one-dimensional per-cloud draws -- wander periods,
## phases, and which piece a cloud is. Same family, same reason: an additive recurrence stepping
## by an irrational never revisits a value and never falls into a short cycle.
const GOLDEN_CONJUGATE := 0.6180339887498949

## How far a cloud wanders from its placed position, in MAP pixels, and over what periods. This
## is the idle: it never resolves and it never accumulates.
##
## THE AMPLITUDE IS NOT A FREE NUMBER, because the rejection test has to reserve it and the
## ceiling falls out of what is left. Measured across 64 seeds on temp2's art, the field jams at
## 11 clouds at an amplitude of 3 px and at 7 at an amplitude of 4 -- a cliff, not a slope,
## because what matters is how the reserved rectangle divides into the wrap extent rather than
## how much area it eats. 3 px is the last value on the high side of it.
const WANDER_PIXELS := 3.0
const WANDER_PERIOD_MIN := 9.0
const WANDER_PERIOD_SPAN := 6.0

## How many sequence points may be tried before placement gives up and takes what it has. Also
## the length of the walk `capacity()` measures itself against, so it is a budget rather than a
## tuning value: too small and the ceiling is understated for a large field.
const MAX_CANDIDATES := 4096

## The seed `capacity()` walks with. Fixed rather than the config's own, so the ceiling the
## console reports does not move when the Arrangement slider does -- the renderer sizes its quad
## pool from it once per region, and a ceiling that changed under the pool would be a defect that
## only appeared at certain seeds.
const CAPACITY_SEED := 0

## `capacity()` memoised per field geometry. The walk is exact and cheap, but it is asked for
## once per frame by the debug readout, and there is no reason to re-derive a constant.
static var _capacityByGeometry := {}


## Every cloud in the field at one moment. Each entry is
## `{piece, cloud: Vector2i, shadow: Vector2i, cast: bool, index: int}`, with both positions
## the TOP-LEFT corner in map pixels and already whole numbers -- a sub-pixel position is what
## makes a map-space layer crawl under a panning camera.
static func at(config: Dictionary, sun: Dictionary, clockSeconds: float) -> Array:
	var cloudSize: Vector2i = config[K_CLOUD]
	var shadowSize: Vector2i = config[K_SHADOW]
	var extent := _extent(config)
	if extent.x <= 0 or extent.y <= 0:
		return []

	var seedValue := int(config[K_SEED])
	var wanted: int = clampi(int(config[K_COUNT]), 0, capacity(config))
	var offset := shadowOffset(config, sun)
	var drift := _drift(config, clockSeconds)
	# The field is centred on the region, so a cloud that has wrapped sits off the map's edge
	# rather than in the middle of it. Clouds drifting in from beyond the coast is what a cloud
	# does; a cloud appearing over the middle of the map is a bug the player can see.
	var origin := -Vector2(extent - (config[K_FIELD] as Vector2i)) * 0.5
	var placed := _scatter(seedValue, wanted, extent, _reserve(cloudSize))
	var pieces: int = maxi(1, int(config[K_PIECES]))

	var result: Array = []
	for i in placed.size():
		var base: Vector2 = placed[i]
		var wandered := base + drift + _wander(seedValue, i, clockSeconds)
		var wrapped := Vector2(
			fposmod(wandered.x, float(extent.x)), fposmod(wandered.y, float(extent.y))
		) + origin
		var cloudAt := Vector2i(roundi(wrapped.x), roundi(wrapped.y))
		# Centred, because the two rects differ in height and the artist's foreshortening is
		# already inside the shadow's own shape. Anchoring a corner instead would slide the
		# shadow half its height difference away from the cloud it belongs to.
		var centring := Vector2i((cloudSize.x - shadowSize.x) / 2, (cloudSize.y - shadowSize.y) / 2)
		var shadowAt := cloudAt + centring + Vector2i(roundi(offset.x), roundi(offset.y))
		result.append({
			# From the cloud's own index rather than its position on a grid. The lattice picked
			# the piece by cell parity, which alternated A/B/A/B across the map and was its own
			# small contribution to the mechanical look.
			"piece": int(_unit(seedValue, i, 5) * float(pieces)) % pieces,
			"cloud": cloudAt,
			"shadow": shadowAt,
			"cast": bool(sun.get("up", false)),
			"index": i,
		})
	return result


## The ground offset from a cloud to its shadow, in map pixels.
##
## DO NOT USE `sun["shadow_step"]` FOR THIS. That value is clamped by `sun_reach`, a limit that
## exists so a BUILDING does not become a twenty-tile scratch on the lens. A cloud's shadow is a
## blob, and being far from its cloud is what a low sun actually does to one. The elevation
## floor that keeps `cot` from running away is already baked into `direction`, so recomputing
## from the direction keeps the flattering geometry and drops only the length limit.
static func shadowOffset(config: Dictionary, sun: Dictionary) -> Vector2:
	if not bool(sun.get("up", false)):
		return Vector2.ZERO
	var direction: Vector3 = sun.get("direction", Vector3(0.0, -1.0, 0.0))
	if direction.y <= 0.0001:
		return Vector2.ZERO
	var step := Vector2(-direction.x / direction.y, -direction.z / direction.y)
	return step * float(config[K_ALTITUDE]) * float(config[K_PIXELS_PER_UNIT])


## How many clouds the field can hold without any two overlapping, at any moment of the wander.
##
## MEASURED BY RUNNING THE PLACER, not derived from an area formula, and that is the whole
## reason it can be trusted. A packing fraction looks like the obvious answer and quietly
## over-promises: what decides how many rectangles fit is how the reserved rectangle divides
## into the wrap extent, which is a step function of both. Measured on temp2, reserving 3 px of
## wander fits 11 clouds and reserving 4 px fits 7 -- a 36% drop for 5% more reserved area, and
## no fraction predicts both. Walking the sequence cannot disagree with what `at()` will do,
## because it is the same walk.
##
## This is LOWER than the lattice's ceiling was -- 11 against 15 on temp2 -- and that is the
## trade rather than a regression: a grid reaches a density scattered rectangles cannot, and the
## grid is what read as mechanical.
static func capacity(config: Dictionary) -> int:
	var extent := _extent(config)
	var reserve := _reserve(config[K_CLOUD])
	if extent.x <= 0 or extent.y <= 0 or reserve.x <= 0 or reserve.y <= 0:
		return 0
	var key := "%d,%d/%d,%d" % [extent.x, extent.y, reserve.x, reserve.y]
	if not _capacityByGeometry.has(key):
		_capacityByGeometry[key] = maxi(
			1, _scatter(CAPACITY_SEED, MAX_CANDIDATES, extent, reserve).size()
		)
	return int(_capacityByGeometry[key])


## The centre-to-centre separation two clouds must keep. The cloud's own size, plus the wander's
## full swing on each axis: two clouds can approach each other by `WANDER_PIXELS` from either
## side at once, so reserving the amplitude twice is what makes non-overlap hold at every clock
## value rather than only at the moment they were placed.
static func _reserve(cloudSize: Vector2i) -> Vector2i:
	var guard := int(ceilf(WANDER_PIXELS * 2.0))
	return Vector2i(maxi(1, cloudSize.x + guard), maxi(1, cloudSize.y + guard))


## Placed positions, as unwrapped top-left corners inside `[0, extent)`.
##
## Candidates come from the R2 sequence and are rejected on contact, so what comes out is the
## sequence's even coverage minus anything that would have overlapped. The seed enters as a
## toroidal SHIFT of the whole sequence, which leaves its discrepancy untouched -- shifting a
## low-discrepancy set on the torus gives another one -- so every seed is as well distributed as
## every other, unlike a jitter whose quality varies with the draw.
static func _scatter(seedValue: int, wanted: int, extent: Vector2i, reserve: Vector2i) -> Array:
	var result: Array = []
	if wanted <= 0:
		return result
	var shift := Vector2(_unit(seedValue, 0, 11), _unit(seedValue, 0, 12))
	var candidate := 0
	while result.size() < wanted and candidate < MAX_CANDIDATES:
		var point := Vector2(
			fposmod(shift.x + float(candidate + 1) * R2_ALPHA_X, 1.0),
			fposmod(shift.y + float(candidate + 1) * R2_ALPHA_Y, 1.0)
		)
		candidate += 1
		var at := Vector2(point.x * float(extent.x), point.y * float(extent.y))
		if _clear(at, result, reserve, extent):
			result.append(at)
	return result


## Whether a candidate keeps its distance from everything already placed, measured ON THE TORUS.
## The field wraps, so a cloud near the left edge and one near the right edge are neighbours; a
## plain difference would call them far apart and let them overlap the moment one wrapped.
static func _clear(at: Vector2, placed: Array, reserve: Vector2i, extent: Vector2i) -> bool:
	for other in placed:
		var o: Vector2 = other
		var dx := absf(at.x - o.x)
		dx = minf(dx, float(extent.x) - dx)
		if dx >= float(reserve.x):
			continue
		var dy := absf(at.y - o.y)
		dy = minf(dy, float(extent.y) - dy)
		if dy < float(reserve.y):
			return false
	return true


## The wrap period: the region plus one cloud of margin on each axis. Wrapping over the region
## itself would put a cloud's re-entry at the same edge a viewer is already looking at.
static func _extent(config: Dictionary) -> Vector2i:
	return (config[K_FIELD] as Vector2i) + (config[K_CLOUD] as Vector2i)


static func _drift(config: Dictionary, clockSeconds: float) -> Vector2:
	var travel := float(config[K_WIND_SPEED]) * clockSeconds * float(config[K_PIXELS_PER_UNIT])
	var radians := deg_to_rad(float(config[K_WIND_ANGLE]))
	return Vector2(cos(radians), sin(radians)) * travel


## One cloud's own slow wander about its placed position: two sines on their own periods and
## phases, bounded by `WANDER_PIXELS` on each axis. Every cloud takes the same wind, so without
## this the field translates as one rigid sheet and reads as a painted backdrop being slid past.
##
## Bounded and non-accumulating on purpose -- see the class note on why a per-cloud SPEED is not
## the answer. The periods differ per cloud and between the axes, so no two clouds trace the same
## path and none of them closes a loop the eye can learn.
static func _wander(seedValue: int, index: int, clockSeconds: float) -> Vector2:
	if WANDER_PIXELS <= 0.0:
		return Vector2.ZERO
	var periodX := WANDER_PERIOD_MIN + WANDER_PERIOD_SPAN * _unit(seedValue, index, 6)
	var periodY := WANDER_PERIOD_MIN + WANDER_PERIOD_SPAN * _unit(seedValue, index, 7)
	return Vector2(
		sin(clockSeconds / periodX * TAU + TAU * _unit(seedValue, index, 8)),
		sin(clockSeconds / periodY * TAU + TAU * _unit(seedValue, index, 9))
	) * WANDER_PIXELS


## A stable value in [0, 1) from a seed and two indices. An integer hash rather than
## `RandomNumberGenerator`, so the same cloud yields the same wander and the same piece no matter
## what order the caller asks for them in -- which is what makes the whole field reproducible
## from its seed.
static func _unit(seedValue: int, index: int, salt: int) -> float:
	var h := (seedValue * 0x9E3779B1) ^ (index * 0x85EBCA77) ^ (salt * 0xC2B2AE3D)
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 15)) * 0x2545F491
	h = h & 0x7FFFFFFF
	h = h ^ (h >> 13)
	return float(h & 0xFFFFFF) / float(0x1000000)
