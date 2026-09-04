## Where the clouds are, where the wind has carried them, and where each one's shadow falls.
##
## Pure derivation, no nodes and no state. It knows nothing about Godot's scene tree, nothing
## about the framing dictionary, and nothing about the cloud catalog -- it takes sizes and a
## count, and returns positions in MAP PIXELS. Everything downstream converts from there, which
## is what lets this be checked without rendering anything.
##
## PLACEMENT IS A JITTERED GRID, NOT RANDOM, and that is the one decision here that is not
## obvious. The visible slice of a plane at altitude is not the visible ground shifted: the
## cloud ray is `camera_height - altitude` long instead of `camera_height`, so at altitude 6 it
## reaches about 60% as far and lands on a different, nearer rectangle of map space. Scattering
## clouds uniformly over the map therefore leaves the SKY empty while the layer still measures
## covered -- 9% coverage with nothing visible, which is what the sketch did before this. A
## lattice guarantees that any window of roughly one cell contains a cloud, wherever the slice
## happens to fall.
##
## THE LATTICE IS SIZED FROM THE ART, not fixed at 5x5. A temp2 cloud is 88x40 map pixels
## against a 248x176 map -- 11 tiles of 31 -- so barely two fit across. Cells smaller than a
## cloud would overlap every neighbour; cells derived from the cloud's own size cannot, because
## the jitter is confined to the slack the cell has left over.
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


## Every cloud in the field at one moment. Each entry is
## `{piece, cloud: Vector2i, shadow: Vector2i, cast: bool, cell: Vector2i}`, with both positions
## the TOP-LEFT corner in map pixels and already whole numbers -- a sub-pixel position is what
## makes a map-space layer crawl under a panning camera.
static func at(config: Dictionary, sun: Dictionary, clockSeconds: float) -> Array:
	var cloudSize: Vector2i = config[K_CLOUD]
	var shadowSize: Vector2i = config[K_SHADOW]
	var extent := _extent(config)
	var lattice := _lattice(config)
	var cells := lattice.x * lattice.y
	if cells <= 0:
		return []

	var wanted: int = clampi(int(config[K_COUNT]), 0, cells)
	var order := _order(int(config[K_SEED]), cells)
	var offset := shadowOffset(config, sun)
	var drift := _drift(config, clockSeconds)
	var cellSize := Vector2(extent) / Vector2(lattice)
	var slack := Vector2(
		maxf(0.0, cellSize.x - float(cloudSize.x)), maxf(0.0, cellSize.y - float(cloudSize.y))
	)
	# The field is centred on the region, so a cloud that has wrapped sits off the map's edge
	# rather than in the middle of it. Clouds drifting in from beyond the coast is what a cloud
	# does; a cloud appearing over the middle of the map is a bug the player can see.
	var origin := -Vector2(extent - config[K_FIELD]) * 0.5

	var result: Array = []
	for i in wanted:
		var cell: int = order[i]
		var cx := cell % lattice.x
		var cy := cell / lattice.x
		var jitter := Vector2(
			_unit(int(config[K_SEED]), cell, 1) * slack.x,
			_unit(int(config[K_SEED]), cell, 2) * slack.y
		)
		var placed := Vector2(float(cx) * cellSize.x, float(cy) * cellSize.y) + jitter + drift
		var wrapped := Vector2(
			fposmod(placed.x, float(extent.x)), fposmod(placed.y, float(extent.y))
		) + origin
		var cloudAt := Vector2i(roundi(wrapped.x), roundi(wrapped.y))
		# Centred, because the two rects differ in height and the artist's foreshortening is
		# already inside the shadow's own shape. Anchoring a corner instead would slide the
		# shadow half its height difference away from the cloud it belongs to.
		var centring := Vector2i((cloudSize.x - shadowSize.x) / 2, (cloudSize.y - shadowSize.y) / 2)
		var shadowAt := cloudAt + centring + Vector2i(roundi(offset.x), roundi(offset.y))
		result.append({
			"piece": cell % maxi(1, int(config[K_PIECES])),
			"cloud": cloudAt,
			"shadow": shadowAt,
			"cast": bool(sun.get("up", false)),
			"cell": Vector2i(cx, cy),
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


## How many clouds the field can hold without any two overlapping.
static func capacity(config: Dictionary) -> int:
	var lattice := _lattice(config)
	return lattice.x * lattice.y


## The lattice, in cells. Sized from the cloud rather than fixed, so cells are never smaller
## than the thing they hold.
static func _lattice(config: Dictionary) -> Vector2i:
	var cloudSize: Vector2i = config[K_CLOUD]
	var extent := _extent(config)
	return Vector2i(
		maxi(1, extent.x / maxi(1, cloudSize.x)), maxi(1, extent.y / maxi(1, cloudSize.y))
	)


## The wrap period: the region plus one cloud of margin on each axis. Wrapping over the region
## itself would put a cloud's re-entry at the same edge a viewer is already looking at.
static func _extent(config: Dictionary) -> Vector2i:
	return (config[K_FIELD] as Vector2i) + (config[K_CLOUD] as Vector2i)


static func _drift(config: Dictionary, clockSeconds: float) -> Vector2:
	var travel := float(config[K_WIND_SPEED]) * clockSeconds * float(config[K_PIXELS_PER_UNIT])
	var radians := deg_to_rad(float(config[K_WIND_ANGLE]))
	return Vector2(cos(radians), sin(radians)) * travel


## Cell indices in a deterministic shuffled order. The shuffle is not cosmetic: with cells taken
## in lattice order, lowering the count empties the map from the bottom up and reads as a
## placement bug rather than as fewer clouds.
static func _order(seedValue: int, cells: int) -> Array:
	var list: Array = []
	for i in cells:
		list.append(i)
	for i in range(cells - 1, 0, -1):
		var j := int(_unit(seedValue, i, 3) * float(i + 1)) % (i + 1)
		var swap = list[i]
		list[i] = list[j]
		list[j] = swap
	return list


## A stable value in [0, 1) from a seed and two indices. An integer hash rather than
## `RandomNumberGenerator`, so the same cell yields the same jitter no matter what order the
## caller asks for cells in -- which is what makes the whole field reproducible from its seed.
static func _unit(seedValue: int, index: int, salt: int) -> float:
	var h := (seedValue * 0x9E3779B1) ^ (index * 0x85EBCA77) ^ (salt * 0xC2B2AE3D)
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 15)) * 0x2545F491
	h = h & 0x7FFFFFFF
	h = h ^ (h >> 13)
	return float(h & 0xFFFFFF) / float(0x1000000)
