## The road drawn on the world map: a segment between each pair of points, a disc at every stop
## coloured by its state, a ring around the selected stop, and the company token standing where
## the company is.
##
## PLACEMENT. Positions are world-map tiles, which are world units (WORLDMAP_DESIGN.md section 1,
## the tile law), so a stop authored at [3.5, 5.4] stands at x 3.5, z 5.4. Everything sits a hair
## above the ground plane so it never fights the ground for depth.
##
## LOOK. Unshaded flat colours: the world map is unlit art, and a lit marker would read as a
## different kind of object from the ground it stands on. The token is the only thing that moves:
## an entrance that drops it into place and settles, over an idle bob that never resolves, each on
## its own constants (docs/VFX_DESIGN.md, the house motion style). A journey walks it along the
## road before a battle opens.
##
## Presentation only: it is told what to draw and owns no road state.

extends Node3D

const GROUND_LIFT := 0.04
const SEGMENT_WIDTH := 0.16
const STOP_RADIUS := 0.42
const STOP_HEIGHT := 0.06
const RING_RADIUS := 0.62
const RING_WIDTH := 0.08
const TOKEN_SIZE := 0.42
const TOKEN_HOVER := 0.55

## Token entrance: drops from ENTRANCE_DROP above its rest height and settles over
## ENTRANCE_SECONDS with an ease-out, then the idle takes over.
const ENTRANCE_DROP := 1.4
const ENTRANCE_SECONDS := 0.45
## Token idle: a slow bob and a slower turn, never resolving.
const IDLE_BOB_HEIGHT := 0.08
const IDLE_BOB_SECONDS := 1.9
const IDLE_TURN_SECONDS := 7.0
## Journey: seconds per world unit walked, clamped so a short hop still reads and a long one
## does not keep the player waiting.
const JOURNEY_SECONDS_PER_UNIT := 0.22
const JOURNEY_MIN_SECONDS := 0.35
const JOURNEY_MAX_SECONDS := 1.6

const COLOR_ROAD_CLEARED := Color(0.96, 0.78, 0.30)
const COLOR_ROAD_AHEAD := Color(0.35, 0.33, 0.30)
const COLOR_STOP_CLEARED := Color(0.96, 0.78, 0.30)
const COLOR_STOP_NEXT := Color(0.95, 0.30, 0.22)
const COLOR_STOP_LOCKED := Color(0.42, 0.40, 0.38)
const COLOR_START := Color(0.85, 0.85, 0.82)
const COLOR_RING := Color(1.0, 1.0, 1.0)
const COLOR_TOKEN := Color(0.25, 0.50, 1.0)

var _points: Array[Vector2] = []
var _stopNodes: Array[MeshInstance3D] = []
var _segmentNodes: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _token: MeshInstance3D
var _tokenRest := Vector2.ZERO
var _clock := 0.0
var _entranceAge := 0.0
var _journey: Array[Vector2] = []
var _journeyAge := 0.0
var _journeySeconds := 0.0
var _journeyDone: Callable = Callable()


## `start` and `stops` are world-map tile positions. Rebuilds everything.
func build(start: Vector2, stops: Array[Vector2]) -> void:
	for child in get_children():
		child.queue_free()
	_stopNodes.clear()
	_segmentNodes.clear()
	_points = [start]
	_points.append_array(stops)
	for index in range(_points.size() - 1):
		var segment := _segment(_points[index], _points[index + 1])
		add_child(segment)
		_segmentNodes.append(segment)
	var startDisc := _disc(STOP_RADIUS * 0.6, COLOR_START)
	startDisc.position = _world(start, GROUND_LIFT)
	add_child(startDisc)
	for stop in stops:
		var disc := _disc(STOP_RADIUS, COLOR_STOP_LOCKED)
		disc.position = _world(stop, GROUND_LIFT)
		add_child(disc)
		_stopNodes.append(disc)
	_ring = _ringMesh()
	_ring.visible = false
	add_child(_ring)
	_token = MeshInstance3D.new()
	_token.name = "CompanyToken"
	var prism := PrismMesh.new()
	prism.size = Vector3(TOKEN_SIZE, TOKEN_SIZE * 1.4, TOKEN_SIZE)
	_token.mesh = prism
	_token.material_override = _flat(COLOR_TOKEN)
	_token.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	add_child(_token)
	placeToken(-1)


## `clearedCount` stops are cleared; the next one is open; the rest are locked. `selected` is a
## stop index or -1.
func showState(clearedCount: int, selected: int) -> void:
	for index in range(_stopNodes.size()):
		var color := COLOR_STOP_LOCKED
		if index < clearedCount:
			color = COLOR_STOP_CLEARED
		elif index == clearedCount:
			color = COLOR_STOP_NEXT
		_stopNodes[index].material_override = _flat(color)
	for index in range(_segmentNodes.size()):
		_segmentNodes[index].material_override = _flat(
			COLOR_ROAD_CLEARED if index < clearedCount else COLOR_ROAD_AHEAD)
	_ring.visible = selected >= 0 and selected < _stopNodes.size()
	if _ring.visible:
		_ring.position = _world(_points[selected + 1], GROUND_LIFT * 0.5)


## Stands the token at a stop (-1 is the start) and replays its entrance.
func placeToken(stopIndex: int) -> void:
	_journey.clear()
	_tokenRest = _points[clampi(stopIndex + 1, 0, _points.size() - 1)]
	_entranceAge = 0.0


## Walks the token along the road from where it stands to `stopIndex`, then calls `done`.
func journeyTo(stopIndex: int, done: Callable) -> void:
	var target := clampi(stopIndex + 1, 0, _points.size() - 1)
	var from := _nearestPointIndex(_tokenRest)
	_journey = [_tokenRest]
	var step := 1 if target >= from else -1
	var index := from
	while index != target:
		index += step
		_journey.append(_points[index])
	var length := 0.0
	for leg in range(_journey.size() - 1):
		length += _journey[leg].distance_to(_journey[leg + 1])
	_journeySeconds = clampf(length * JOURNEY_SECONDS_PER_UNIT, JOURNEY_MIN_SECONDS, JOURNEY_MAX_SECONDS)
	_journeyAge = 0.0
	_journeyDone = done
	if _journey.size() < 2:
		_finishJourney()


func isTravelling() -> bool:
	return _journey.size() >= 2


## World positions of each stop, for the controller's screen-space picking.
func stopWorldPositions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for index in range(1, _points.size()):
		positions.append(_world(_points[index], GROUND_LIFT))
	return positions


func _process(delta: float) -> void:
	if _token == null:
		return
	_clock += delta
	var ground := _tokenRest
	if _journey.size() >= 2:
		_journeyAge += delta
		var t := clampf(_journeyAge / maxf(_journeySeconds, 0.001), 0.0, 1.0)
		ground = _alongJourney(t)
		if t >= 1.0:
			_tokenRest = _journey.back()
			_finishJourney()
	_entranceAge += delta
	var settle := clampf(_entranceAge / ENTRANCE_SECONDS, 0.0, 1.0)
	var drop := ENTRANCE_DROP * pow(1.0 - settle, 3.0)
	var bob := sin(_clock * TAU / IDLE_BOB_SECONDS) * IDLE_BOB_HEIGHT
	_token.position = _world(ground, TOKEN_HOVER + drop + bob)
	_token.rotation_degrees.y = fmod(_clock * 360.0 / IDLE_TURN_SECONDS, 360.0)


func _finishJourney() -> void:
	_journey.clear()
	var done := _journeyDone
	_journeyDone = Callable()
	if done.is_valid():
		done.call()


## The point a fraction `t` of the way along the journey, by distance.
func _alongJourney(t: float) -> Vector2:
	var total := 0.0
	for leg in range(_journey.size() - 1):
		total += _journey[leg].distance_to(_journey[leg + 1])
	var wanted := total * (1.0 - pow(1.0 - t, 2.0))
	for leg in range(_journey.size() - 1):
		var length := _journey[leg].distance_to(_journey[leg + 1])
		if wanted <= length or leg == _journey.size() - 2:
			return _journey[leg].lerp(_journey[leg + 1], clampf(wanted / maxf(length, 0.001), 0.0, 1.0))
		wanted -= length
	return _journey.back()


func _nearestPointIndex(point: Vector2) -> int:
	var best := 0
	for index in range(_points.size()):
		if _points[index].distance_to(point) < _points[best].distance_to(point):
			best = index
	return best


func _segment(from: Vector2, to: Vector2) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "RoadSegment"
	var box := BoxMesh.new()
	box.size = Vector3(SEGMENT_WIDTH, 0.02, from.distance_to(to))
	node.mesh = box
	var middle := (from + to) * 0.5
	node.position = _world(middle, GROUND_LIFT * 0.5)
	node.rotation.y = atan2(to.x - from.x, to.y - from.y)
	node.material_override = _flat(COLOR_ROAD_AHEAD)
	return node


func _disc(radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "RoadStop"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = STOP_HEIGHT
	cylinder.radial_segments = 24
	node.mesh = cylinder
	node.material_override = _flat(color)
	return node


func _ringMesh() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SelectedRing"
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - RING_WIDTH
	torus.outer_radius = RING_RADIUS
	torus.rings = 32
	node.mesh = torus
	node.material_override = _flat(COLOR_RING)
	return node


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


static func _world(tile: Vector2, height: float) -> Vector3:
	return Vector3(tile.x, height, tile.y)
