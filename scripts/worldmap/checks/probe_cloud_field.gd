## The cloud field places clouds where they can be seen, keeps them apart, moves them with the
## wind, and puts each shadow where the sun says.
##
## Everything here is decidable without rendering, which is the point of the field being pure.
## The one measurement the plan listed that is NOT here is parallax -- a cloud moving less on
## screen than the ground is a property of the camera, not of this module, so it belongs to the
## clouds' own probe where there is something to look through.
##
## THE GRID CHECK IS WRITTEN SO IT CAN FAIL. It reproduces the jittered lattice this module used
## to use, runs the identical metric over it, and requires the old arrangement to score badly on
## the same test the new one passes. A "clouds are scattered" check that has never been shown a
## grid is a check that measures nothing.

extends SceneTree

const CloudField = preload("res://src/presentation/worldmap/WorldMapCloudField.gd")
const Sun = preload("res://src/presentation/worldmap/WorldMapSun.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## temp2: 248x176 map pixels, 8 px tiles, and the cloud art at its native 88x40.
const FIELD := Vector2i(248, 176)
const CLOUD := Vector2i(88, 40)
const SHADOW := Vector2i(88, 40)
const PIXELS_PER_UNIT := 8.0
const EXTENT := Vector2i(336, 216)

## What the shipped framing actually asks for. The ceiling matters, but this is the number that
## has to look right.
const SHIPPED_COUNT := 6

## Two clouds are "in the same row" if their tops sit within this many map pixels of each other.
## The lattice's vertical slack was 3.2 px, so its rows land well inside this.
const ROW_EPSILON := 5.0

## How far a cloud may sit from where it was at t = 0, once its idle is running. The wander is
## bounded by `WANDER_PIXELS` per axis, and t = 0 is not the centre of that swing -- each cloud
## starts at its own phase -- so the excursion from the t = 0 sample is twice the amplitude on
## each axis: `2 * 3 * sqrt(2)` = 8.49 px, plus a pixel of rounding.
const WANDER_EXCURSION := 10.0

var _failures: Array[String] = []


func _check(label: String, ok: bool, detail: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label + "  " + detail)
	if not ok:
		_failures.append(label)


func _config(count: int, altitude: float, wind: float) -> Dictionary:
	return {
		CloudField.K_FIELD: FIELD,
		CloudField.K_CLOUD: CLOUD,
		CloudField.K_SHADOW: SHADOW,
		CloudField.K_PIECES: 2,
		CloudField.K_COUNT: count,
		CloudField.K_ALTITUDE: altitude,
		CloudField.K_WIND_SPEED: wind,
		CloudField.K_WIND_ANGLE: 250.0,
		CloudField.K_SEED: 20260903,
		CloudField.K_PIXELS_PER_UNIT: PIXELS_PER_UNIT,
	}


func _seeded(count: int, seedValue: int) -> Dictionary:
	var config := _config(count, 6.0, 0.0)
	config[CloudField.K_SEED] = seedValue
	return config


func _sunAt(hour: float) -> Dictionary:
	return Sun.at({Uniforms.K_TIME_OF_DAY: hour})


## Toroidal, because the field wraps: a cloud near one edge and one near the other are
## neighbours, and a plain difference would call them comfortably apart.
func _toroidal(a: Vector2i, b: Vector2i) -> Vector2:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	return Vector2(minf(dx, float(EXTENT.x) - dx), minf(dy, float(EXTENT.y) - dy))


func _overlap(a: Vector2i, b: Vector2i) -> bool:
	var d := _toroidal(a, b)
	return d.x < float(CLOUD.x) and d.y < float(CLOUD.y)


func _overlapCount(field: Array) -> int:
	var overlaps := 0
	for i in field.size():
		for j in range(i + 1, field.size()):
			if _overlap(field[i]["cloud"], field[j]["cloud"]):
				overlaps += 1
	return overlaps


## How many pairs of clouds sit in the same horizontal band. This is the metric that names the
## defect: the old lattice pinned every cloud to one of five rows with 3.2 px of slack, so its
## clouds stacked into visible columns of even spacing.
func _rowCollisions(positions: Array) -> int:
	var collisions := 0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if _toroidal(positions[i], positions[j]).y < ROW_EPSILON:
				collisions += 1
	return collisions


func _positionsOf(field: Array) -> Array:
	var out: Array = []
	for c in field:
		out.append(c["cloud"] as Vector2i)
	return out


## The placement this module used to use, reproduced so the grid check has something to fail on.
## A 3 x 5 lattice of 112 x 43.2 cells, each cloud jittered inside its cell's leftover slack --
## 24 px across and 3.2 px down.
func _oldLattice(seedValue: int, count: int) -> Array:
	var lattice := Vector2i(EXTENT.x / CLOUD.x, EXTENT.y / CLOUD.y)
	var cells := lattice.x * lattice.y
	var cellSize := Vector2(EXTENT) / Vector2(lattice)
	var slack := Vector2(
		maxf(0.0, cellSize.x - float(CLOUD.x)), maxf(0.0, cellSize.y - float(CLOUD.y))
	)
	var order: Array = []
	for i in cells:
		order.append(i)
	for i in range(cells - 1, 0, -1):
		var j := int(CloudField._unit(seedValue, i, 3) * float(i + 1)) % (i + 1)
		var swap = order[i]
		order[i] = order[j]
		order[j] = swap
	var origin := -Vector2(EXTENT - FIELD) * 0.5
	var out: Array = []
	for i in mini(count, cells):
		var cell: int = order[i]
		var cx := cell % lattice.x
		var cy := cell / lattice.x
		var jitter := Vector2(
			CloudField._unit(seedValue, cell, 1) * slack.x,
			CloudField._unit(seedValue, cell, 2) * slack.y
		)
		var placed := Vector2(float(cx) * cellSize.x, float(cy) * cellSize.y) + jitter + origin
		out.append(Vector2i(roundi(placed.x), roundi(placed.y)))
	return out


func _initialize() -> void:
	print("probe_cloud_field")

	var noon := _sunAt(12.0)
	var capacity := CloudField.capacity(_config(0, 6.0, 0.0))
	print("    capacity %d clouds  (was 15 on the jittered lattice)" % capacity)
	# The ceiling dropped when placement stopped being a grid, which is the trade rather than a
	# regression -- a lattice reaches a density scattered rectangles cannot. What has to hold is
	# that it still clears what the shipped framing asks for, with room to raise it.
	_check("capacity clears the shipped count", capacity > SHIPPED_COUNT,
		"%d available, %d asked for by DEFAULTS" % [capacity, SHIPPED_COUNT])

	var full := CloudField.at(_config(capacity, 6.0, 0.0), noon, 0.0)
	_check("capacity places every cloud", full.size() == capacity, "%d placed" % full.size())

	# --- the arrangement is not a grid -------------------------------------------------

	var scatterRows := _rowCollisions(_positionsOf(full))
	var latticeRows := _rowCollisions(_oldLattice(20260903, capacity))
	print("    row collisions: scatter %d, old lattice %d (same metric, same count)"
		% [scatterRows, latticeRows])
	_check("the old lattice fails the grid check", latticeRows > scatterRows,
		"lattice %d vs scatter %d shared rows" % [latticeRows, scatterRows])
	# Some coincidental sharing is expected and correct -- a scatter that forbade it would be a
	# grid by another name. What must not happen is clouds stacking into rows.
	_check("clouds do not stack into rows", scatterRows <= 2,
		"%d shared rows at capacity" % scatterRows)

	var shipped := CloudField.at(_config(SHIPPED_COUNT, 6.0, 0.0), noon, 0.0)
	_check("the shipped count is scattered too", _rowCollisions(_positionsOf(shipped)) <= 1,
		"%d shared rows at %d clouds" % [_rowCollisions(_positionsOf(shipped)), SHIPPED_COUNT])

	# --- nothing overlaps, at any moment ------------------------------------------------

	_check("no two clouds overlap at capacity", _overlapCount(full) == 0,
		"%d overlapping pairs" % _overlapCount(full))

	# The wander is what makes this a claim about all time rather than about t = 0. Wind is held
	# at zero so the only thing moving a cloud RELATIVE to its neighbours is its own oscillation.
	var stillConfig := _config(capacity, 6.0, 0.0)
	var worstOverlap := 0
	var maxWander := 0.0
	var atRest := CloudField.at(stillConfig, noon, 0.0)
	var t := 0.0
	while t <= 240.0:
		var now := CloudField.at(stillConfig, noon, t)
		worstOverlap = maxi(worstOverlap, _overlapCount(now))
		for i in now.size():
			maxWander = maxf(maxWander, _toroidal(now[i]["cloud"], atRest[i]["cloud"]).length())
		t += 0.5
	_check("the wander never lets two clouds cross", worstOverlap == 0,
		"%d overlapping pairs over 240 s, worst excursion %.1f px" % [worstOverlap, maxWander])
	_check("the wander is bounded, not a drift", maxWander < WANDER_EXCURSION,
		"%.1f px worst excursion from rest, bound %.1f" % [maxWander, WANDER_EXCURSION])

	# Every seed must reach the ceiling the console reports, or the ceiling is a promise the
	# arrangement cannot keep. This is what sets PACKING_FRACTION.
	var shortfalls := 0
	var worstSeed := 0
	for s in range(0, 33):
		var got := CloudField.at(_seeded(capacity, s), noon, 0.0).size()
		if got < capacity:
			shortfalls += 1
			worstSeed = s
	_check("every seed reaches capacity", shortfalls == 0,
		"%d of 33 seeds short (worst seed %d)" % [shortfalls, worstSeed])

	var seedOverlaps := 0
	for s in range(0, 33):
		seedOverlaps += _overlapCount(CloudField.at(_seeded(capacity, s), noon, 0.0))
	_check("no seed produces an overlap", seedOverlaps == 0,
		"%d overlapping pairs across 33 seeds" % seedOverlaps)

	# --- pieces ------------------------------------------------------------------------

	# The lattice chose the piece by cell parity, which alternated A/B/A/B across the map. Both
	# shapes must still appear, and not in lockstep with position.
	var pieceTally := {}
	for c in full:
		pieceTally[int(c["piece"])] = int(pieceTally.get(int(c["piece"]), 0)) + 1
	_check("both cloud shapes are used", pieceTally.size() == 2, "%s" % pieceTally)

	# --- determinism -------------------------------------------------------------------

	var again := CloudField.at(_config(capacity, 6.0, 0.0), noon, 0.0)
	_check("same seed and clock give the same field", str(again) == str(full), "identical")
	var different := CloudField.at(_seeded(capacity, 7), noon, 0.0)
	_check("a different seed moves the clouds", str(different) != str(full), "differs")

	# --- The sun ---

	var night := CloudField.at(_config(4, 6.0, 0.0), _sunAt(2.0), 0.0)
	var casting := 0
	for c in night:
		if bool(c["cast"]):
			casting += 1
	_check("no shadow with the sun down", casting == 0, "%d casting at 02:00" % casting)
	_check("no offset with the sun down",
		CloudField.shadowOffset(_config(4, 6.0, 0.0), _sunAt(2.0)) == Vector2.ZERO, "zero")

	var offsets := {}
	for altitude in [4.0, 8.0, 16.0]:
		var off := CloudField.shadowOffset(_config(4, altitude, 0.0), noon)
		offsets[altitude] = off
		print("    altitude %5.1f -> offset %s map px (%.2f tiles)"
			% [altitude, off, off.length() / PIXELS_PER_UNIT])
	var at4: Vector2 = offsets[4.0]
	var at8: Vector2 = offsets[8.0]
	var at16: Vector2 = offsets[16.0]
	var linear: bool = (at8 - at4 * 2.0).length() < 0.001 and (at16 - at4 * 4.0).length() < 0.001
	_check("offset is linear in altitude", linear, "4 : 8 : 16 = 1 : 2 : 4")

	var before := CloudField.shadowOffset(_config(4, 6.0, 0.0), _sunAt(9.0))
	var after := CloudField.shadowOffset(_config(4, 6.0, 0.0), _sunAt(15.0))
	_check("offset mirrors about noon",
		absf(before.x + after.x) < 0.001 and absf(before.y - after.y) < 0.001,
		"09:00 %s vs 15:00 %s" % [before, after])

	# Every shadow through the whole lit day must lean AWAY from the viewer. The camera looks
	# along -Z, so a shadow in front of its caster is a positive Y offset in map space, and a
	# single positive sample anywhere in the day is the failure.
	var inFront := 0
	var maxReach := 0.0
	var hour := 6.1
	while hour < 17.9:
		var off := CloudField.shadowOffset(_config(4, 6.0, 0.0), _sunAt(hour))
		if off.y > 0.0:
			inFront += 1
		maxReach = maxf(maxReach, off.length() / PIXELS_PER_UNIT)
		hour += 0.1
	_check("shadows never fall in front of their cloud", inFront == 0,
		"%d samples in front, longest %.2f tiles" % [inFront, maxReach])

	# --- The wind ---

	var moving := _config(SHIPPED_COUNT, 6.0, 0.9)
	var start := CloudField.at(moving, noon, 0.0)
	var later := CloudField.at(moving, noon, 40.0)
	var moved := 0
	for i in start.size():
		if start[i]["cloud"] != later[i]["cloud"]:
			moved += 1
	_check("the wind moves every cloud", moved == start.size(), "%d of %d" % [moved, start.size()])

	# With the wind off a cloud must stay put -- bounded by its wander, not translating away.
	# The old check compared two clock values for equality, which the idle now legitimately
	# breaks; the invariant it was protecting is that zero wind means zero TRANSPORT.
	var stillFar := CloudField.at(_config(SHIPPED_COUNT, 6.0, 0.0), noon, 600.0)
	var stillNear := CloudField.at(_config(SHIPPED_COUNT, 6.0, 0.0), noon, 0.0)
	var maxStill := 0.0
	for i in stillFar.size():
		maxStill = maxf(maxStill, _toroidal(stillFar[i]["cloud"], stillNear[i]["cloud"]).length())
	_check("zero wind carries them nowhere", maxStill < WANDER_EXCURSION,
		"%.1f px from rest after 600 s, bound %.1f" % [maxStill, WANDER_EXCURSION])

	# Wrap continuity: over a long run each cloud either creeps by the per-step drift or jumps
	# by exactly one field extent. A jump of anything else is a wrap that loses or gains ground,
	# which shows only when a cloud is straddling an edge -- so walk one all the way around.
	# The tolerance carries the wander's own top speed (amplitude * TAU / shortest period)
	# on top of the wind's, since both move a cloud between samples.
	var stepSeconds := 1.0
	var perStep := 0.9 * stepSeconds * PIXELS_PER_UNIT + 3.0 * TAU / 9.0 + 2.0
	var badJumps := 0
	var wraps := 0
	var previous := CloudField.at(moving, noon, 0.0)
	var walk := stepSeconds
	while walk <= 600.0:
		var now := CloudField.at(moving, noon, walk)
		for i in now.size():
			var d: Vector2i = (now[i]["cloud"] as Vector2i) - (previous[i]["cloud"] as Vector2i)
			var dx := absi(d.x)
			var dy := absi(d.y)
			var creptX := float(dx) <= perStep
			var creptY := float(dy) <= perStep
			var wrappedX := absf(float(dx) - float(EXTENT.x)) <= perStep
			var wrappedY := absf(float(dy) - float(EXTENT.y)) <= perStep
			if not ((creptX or wrappedX) and (creptY or wrappedY)):
				badJumps += 1
			if wrappedX or wrappedY:
				wraps += 1
		previous = now
		walk += stepSeconds
	_check("wrap is continuous", badJumps == 0 and wraps > 0,
		"%d bad jumps, %d wraps observed over 600 s" % [badJumps, wraps])

	# The wrap band must sit centred on the region, so the seam is as far past the coast as the
	# margin allows and is equally far on both sides. The margin is half a cloud each way -- the
	# extent is the region plus one cloud, split evenly by the centring.
	#
	# The bound here is the BAND, not "within one cloud of the map", which is what this checked
	# before. That older bound passed only by an accident of the lattice: its rightmost column
	# started at 224 and could jitter just 24 px, so no cloud ever reached the top of the extent.
	# A free scatter does reach it, legitimately -- a cloud at x = 280 is entirely off the right
	# coast, which is exactly where a wrapping cloud belongs.
	var margin := (EXTENT - FIELD) / 2
	var outOfBand := 0
	for c in CloudField.at(_config(capacity, 6.0, 0.0), noon, 0.0):
		var p: Vector2i = c["cloud"]
		if p.x < -margin.x or p.x >= FIELD.x + margin.x:
			outOfBand += 1
		elif p.y < -margin.y or p.y >= FIELD.y + margin.y:
			outOfBand += 1
	_check("the field is centred on the region", outOfBand == 0,
		"%d clouds outside the centred band (margin %d x %d px)"
			% [outOfBand, margin.x, margin.y])

	print("probe_cloud_field: %s (%d failures)"
		% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	if _failures.is_empty():
		print("WORLD MAP CLOUD FIELD OK")
	quit(0 if _failures.is_empty() else 1)
