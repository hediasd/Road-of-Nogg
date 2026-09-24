## The staged world the VFX debug scene plays effects into: two terrain islands,
## a caster and a target anchor, the target-body proxy, the footprint guide, and
## the camera framing that holds them.
##
## Separated from the controller because it answers one question — what does the
## effect stand on, and where is the camera looking — and because the cast
## context handed to every effect is derived from exactly this geometry. Keeping
## the two together means the context cannot describe a world the scene is not
## actually showing.

class_name VfxDebugWorld
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const VfxCastContextScript = preload("res://src/presentation/effects/VfxCastContext.gd")
const HexVfxFootprintScript = preload("res://src/presentation/battle/effects/HexVfxFootprint.gd")
const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")
const ShapeCasterScript = preload("res://src/algorithms/ShapeCaster.gd")

## The synthetic hex lattice's centre cell. Well inside positive offset space so
## no shape at the UI's largest radius reaches a negative column, where the
## odd-column parity would need thinking about.
const HEX_CENTRE_CELL := Vector2i(16, 16)

const CAMERA_OFFSET := Vector3(6.0, 15.0, 14.0)
## Meadow and Forest are 16 cells across with two elevation steps, producing
## 16 * 0.95 + (2 * 0.5) * 0.35 through the shipping camera-size formula.
const REPRESENTATIVE_CAMERA_SIZE := 15.55
const DEFAULT_FOOTPRINT_RADIUS := 4
const DEFAULT_SOURCE_DISTANCE := 4.0
const DEFAULT_CAMERA_YAW_DEGREES := 0.0
const DEBUG_CASTER_ID := -1001
const DEBUG_TARGET_ID := -1002
const TARGET_BODY_PRESETS: Array[Dictionary] = [
	{
		"id": "standard",
		"label": "Standard (0.70 x 1.30 x 0.70)",
		"bounds": VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS,
	},
	{
		"id": "wide",
		"label": "Short / wide (1.20 x 0.90 x 0.95)",
		"bounds": AABB(Vector3(-0.6, 0.2, -0.475), Vector3(1.2, 0.9, 0.95)),
	},
	{
		"id": "tall",
		"label": "Tall / narrow (0.55 x 1.85 x 0.55)",
		"bounds": AABB(Vector3(-0.275, 0.2, -0.275), Vector3(0.55, 1.85, 0.55)),
	},
]
const _UNEVEN_HEIGHTS := [[0, 1, 0], [1, 2, 1], [0, 1, 2]]
const _CASTER_TERRAIN_COLOR := Color(0.22, 0.58, 0.28)
const _TARGET_TERRAIN_COLOR := Color(0.34, 0.48, 0.68)

var casterAnchor: Node3D
var targetAnchor: Node3D
var targetBodyBounds: AABB = VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
## Matches `data/spells.json`'s `AREA_SHAPE`. Drives both the effect's own
## footprint and the on-screen guide, so the two cannot disagree about which
## tiles a spell claims.
var areaShape: String = "circle"
var footprintRadius: int = DEFAULT_FOOTPRINT_RADIUS
var sourceDistance: float = DEFAULT_SOURCE_DISTANCE
var cameraYawDegrees: float = DEFAULT_CAMERA_YAW_DEGREES
## Framing overrides. Zero keeps the distance-derived size, and "midpoint"
## keeps the established two-island composition.
var cameraSizeOverride: float = 0.0
var cameraFocus: String = "midpoint"
## Which guide the footprint draws. Effects that take a hex footprint are shown
## the hex cells they receive; everything else keeps the legacy tile outline,
## so an effect that never reads a footprint captures exactly as it always has.
var hexGuide: bool = false
## A self-cast: the spell lands on the caster, as a spell with `TARGET_TYPE: self` does in battle.
## The caster is then the cast's target and footprint centre; the target anchor stays in the scene
## as the nearest hostile, which is what "in front of the caster" points at.
var castOnCaster: bool = false

var _worldRoot: Node3D
var _camera: BattleCameraController
var _ground: MeshInstance3D
var _casterTerrainIsland: Node3D
var _targetTerrainIsland: Node3D
var _targetBodyVisual: MeshInstance3D
var _footprintRing: MeshInstance3D
var _comparisonIsolation := false


func _init(
		worldRoot: Node3D,
		camera: BattleCameraController,
		ground: MeshInstance3D,
		caster: Node3D,
		target: Node3D) -> void:
	_worldRoot = worldRoot
	_camera = camera
	_ground = ground
	casterAnchor = caster
	targetAnchor = target


func build() -> void:
	_buildTerrainSamples()
	_buildContextAnchors()
	_buildTargetGuides()
	_applyComparisonIsolation()


## Removes every authored debug prop except the neutral target body. The aura
## still plays at the real world-space target anchor; only the comparison plate
## changes. Normal terrain remains the default and the separate transfer check.
func setComparisonIsolation(enabled: bool) -> void:
	_comparisonIsolation = enabled
	_applyComparisonIsolation()


func _applyComparisonIsolation() -> void:
	if _ground != null:
		_ground.visible = not _comparisonIsolation
	if _casterTerrainIsland != null:
		_casterTerrainIsland.visible = not _comparisonIsolation
	if _targetTerrainIsland != null:
		_targetTerrainIsland.visible = not _comparisonIsolation
	if casterAnchor != null:
		casterAnchor.visible = not _comparisonIsolation
	if targetAnchor == null:
		return
	for child: Node in targetAnchor.get_children():
		if child is VisualInstance3D:
			(child as VisualInstance3D).visible = (
				not _comparisonIsolation or child == _targetBodyVisual
			)


## Repositions both islands, both anchors, and the body proxy for the current
## separation and target-body preset, then reframes the camera.
func apply() -> void:
	if (
		casterAnchor == null
		or targetAnchor == null
		or _casterTerrainIsland == null
		or _targetTerrainIsland == null
		or _targetBodyVisual == null
	):
		return
	var halfSeparation := sourceDistance * 0.5
	_casterTerrainIsland.position = Vector3(-halfSeparation, 0.0, 0.0)
	_targetTerrainIsland.position = Vector3(halfSeparation, 0.0, 0.0)
	casterAnchor.position = Vector3(-halfSeparation, surfaceY(0), 0.0)
	targetAnchor.position = Vector3(halfSeparation, surfaceY(2), 0.0)
	_targetBodyVisual.position = targetBodyBounds.get_center()
	# BattleMeshFactory's authored capsule is 0.6 x 0.8 x 0.6. Scaling that
	# visual to the selected AABB keeps the original capsule proxy while making
	# standard, wide, and tall context presets truthful.
	_targetBodyVisual.scale = targetBodyBounds.size / Vector3(0.6, 0.8, 0.6)
	# A line footprint starts at the caster, so the hex guide follows the
	# separation. The legacy outline never read the anchors and is left alone.
	if hexGuide:
		updateFootprintRing()
	updateCameraFraming()


## The point the composition is built around.
func focusPoint() -> Vector3:
	var focus := (casterAnchor.position + targetAnchor.position) * 0.5
	match cameraFocus:
		"caster":
			focus = casterAnchor.position
		"target":
			focus = targetAnchor.position
	focus.y += targetBodyBounds.get_center().y * 0.5
	return focus


## Orthographic size the current separation asks for, unless an explicit
## override was requested. The default two-island composition is deliberately
## wide, which is right for delivery paths and wrong for judging the geometry of
## one effect standing on one tile.
func defaultZoom() -> float:
	return (
		cameraSizeOverride
		if cameraSizeOverride > 0.0
		else maxf(REPRESENTATIVE_CAMERA_SIZE, sourceDistance + 5.0)
	)


## `CAMERA_OFFSET` expressed as the orbit the camera controller actually stores.
## Reproduces the previous fixed framing exactly: `atan2(x, z)` and
## `asin(y / radius)` invert the spherical-to-Cartesian conversion the camera
## does every frame, and the yaw control adds to the base angle the same way the
## old offset rotation did.
static func baseOrbitRadius() -> float:
	return CAMERA_OFFSET.length()


static func baseOrbitYaw() -> float:
	return atan2(CAMERA_OFFSET.x, CAMERA_OFFSET.z)


static func baseOrbitPitch() -> float:
	return asin(CAMERA_OFFSET.y / baseOrbitRadius())


## Re-centres the view without touching yaw, pitch, or zoom.
##
## Separation and target-body changes move what the camera looks at; they must
## never rotate or zoom it. That is `BattleCameraController`'s own settled rule
## — the camera may guarantee visibility but never take authorship of the view —
## and it is what lets an orbit survive a change of source distance.
func updateCameraFraming() -> void:
	_camera.focus_point = focusPoint()


## Full framing, orbit and zoom included. For initial setup, the `--camera-*`
## flags, and the explicit Reset — the three cases where taking authorship of
## the view is what was actually asked for.
func frameCamera(pitchRadians: float, zoom: float) -> void:
	_camera.focus_point = focusPoint()
	_camera.radius = baseOrbitRadius()
	_camera.current_yaw = baseOrbitYaw() + deg_to_rad(cameraYawDegrees)
	_camera.current_pitch = pitchRadians
	_camera.size = zoom
	_camera.default_focus_point = _camera.focus_point
	_camera.default_yaw = _camera.current_yaw
	_camera.default_pitch = _camera.current_pitch
	_camera.default_size = zoom


func buildCastContext() -> VfxCastContext:
	if castOnCaster:
		var selfIDs: Array[int] = [DEBUG_CASTER_ID]
		var selfPositions: Array[Vector3] = [casterAnchor.position]
		var selfBounds: Array[AABB] = [VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS]
		return VfxCastContextScript.create(
			DEBUG_CASTER_ID, casterAnchor.position, casterAnchor.position,
			selfIDs, selfPositions, selfBounds
		)
	var targetIDs: Array[int] = [DEBUG_TARGET_ID]
	var targetPositions: Array[Vector3] = [targetAnchor.position]
	var targetBounds: Array[AABB] = [targetBodyBounds]
	return VfxCastContextScript.create(
		DEBUG_CASTER_ID,
		casterAnchor.position,
		targetAnchor.position,
		targetIDs,
		targetPositions,
		targetBounds,
		_buildSurfacePath()
	)


## Samples the two authored islands and the lower ground plane between them so
## delivery geometry proves both plateaus and the empty middle corridor.
func _buildSurfacePath() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var source := casterAnchor.position
	var target := targetAnchor.position
	var sampleCount := 17
	for sampleIndex: int in range(sampleCount):
		var progress := float(sampleIndex) / float(sampleCount - 1)
		var point := source.lerp(target, progress)
		if sampleIndex == 0:
			point.y = source.y
		elif sampleIndex == sampleCount - 1:
			point.y = target.y
		elif absf(point.x - source.x) <= 1.5:
			point.y = surfaceY(0)
		elif absf(point.x - target.x) <= 1.5:
			var localX := clampi(roundi(point.x - target.x), -1, 1)
			point.y = surfaceY(int(_UNEVEN_HEIGHTS[1][localX + 1]))
		else:
			point.y = _ground.position.y + 0.01
		result.append(point)
	return result


func _buildTerrainSamples() -> void:
	_casterTerrainIsland = Node3D.new()
	_casterTerrainIsland.name = "CasterTerrainIsland"
	_worldRoot.add_child(_casterTerrainIsland)
	_targetTerrainIsland = Node3D.new()
	_targetTerrainIsland.name = "TargetTerrainIsland"
	_worldRoot.add_child(_targetTerrainIsland)
	for zIndex in range(3):
		for xIndex in range(3):
			_addTerrainColumn(
				_casterTerrainIsland, Vector2i(xIndex - 1, zIndex - 1), 0,
				_CASTER_TERRAIN_COLOR
			)
			_addTerrainColumn(
				_targetTerrainIsland, Vector2i(xIndex - 1, zIndex - 1),
				int(_UNEVEN_HEIGHTS[zIndex][xIndex]), _TARGET_TERRAIN_COLOR
			)


func _addTerrainColumn(
		parent: Node3D,
		coord: Vector2i,
		height: int,
		baseColor: Color) -> void:
	var column := Node3D.new()
	column.name = "Terrain_%d_%d" % [coord.x, coord.y]
	column.position = Vector3(coord.x, 0.0, coord.y)
	parent.add_child(column)
	for layerIndex in range(height + 1):
		var depth := height - layerIndex
		var blockColor := baseColor.darkened(minf(float(depth) * 0.08, 0.24))
		var block := BattleMeshFactoryScript.createMesh("terrain_block", blockColor)
		block.name = "Layer_%d" % layerIndex
		block.position.y = float(layerIndex) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		column.add_child(block)


func _buildContextAnchors() -> void:
	assert(
		casterAnchor != null and targetAnchor != null,
		"VFX anchors must be reparented first."
	)
	casterAnchor.name = "CasterAnchor"
	targetAnchor.name = "TargetAnchor"
	_addAnchorMarker(casterAnchor, "CasterMarker", Color(0.18, 0.72, 1.0, 0.85))
	_addAnchorMarker(targetAnchor, "TargetMarker", Color(1.0, 0.55, 0.3, 0.85))

	var casterBase := BattleMeshFactoryScript.createModelBase(Color(0.18, 0.42, 0.95), 0)
	casterAnchor.add_child(casterBase)
	var casterBody := BattleMeshFactoryScript.createMesh("shape_capsule", Color(0.62, 0.9, 0.95))
	casterBody.name = "CasterBody"
	casterBody.position.y = BattleMeshFactoryScript.BASE_TOTAL_HEIGHT + 0.4
	casterAnchor.add_child(casterBody)

	var targetBase := BattleMeshFactoryScript.createModelBase(Color(0.9, 0.2, 0.16), 1)
	targetAnchor.add_child(targetBase)
	_targetBodyVisual = BattleMeshFactoryScript.createMesh(
		"shape_capsule", Color(0.82, 0.45, 0.2))
	_targetBodyVisual.name = "TargetBodyBounds"
	targetAnchor.add_child(_targetBodyVisual)


func _addAnchorMarker(anchor: Node3D, markerName: String, color: Color) -> void:
	var marker := BattleMeshFactoryScript.createMesh("cursor", color)
	marker.name = markerName
	marker.position.y = 0.02
	marker.scale = Vector3(0.18, 0.18, 0.18)
	anchor.add_child(marker)


func _buildTargetGuides() -> void:
	var targetMarker := BattleMeshFactoryScript.createMesh(
		"cursor", Color(0.2, 0.85, 1.0, 0.8)
	)
	targetMarker.name = "TargetCentreMarker"
	targetMarker.position.y = 0.02
	targetMarker.scale = Vector3(0.22, 0.22, 0.22)
	targetAnchor.add_child(targetMarker)
	_footprintRing = MeshInstance3D.new()
	_footprintRing.name = "FootprintGuide"
	_footprintRing.position.y = 0.035
	# Far more translucent than the outline band this replaced: it now fills the
	# whole footprint rather than tracing its edge, so it has to sit under the
	# effect without competing with it.
	_footprintRing.material_override = BattleMeshFactoryScript.createMaterial(
		Color(0.42, 0.82, 1.0, 0.16), true, 0.6
	)
	targetAnchor.add_child(_footprintRing)
	updateFootprintRing()


## A flat translucent polygon covering exactly the tiles the spell affects.
##
## Filled rather than an outline band because the guide must now follow any
## `AREA_SHAPE`, and offsetting a non-convex outline (the cross) into a clean
## band is far more work than triangulating the region itself. Built
## double-sided — each triangle added in both windings — so it reads regardless
## of the camera's orbit, without depending on the material's cull mode.
func updateFootprintRing() -> void:
	if _footprintRing == null:
		return
	if hexGuide:
		_updateHexFootprintGuide()
		return
	var polygon := footprintPolygon(footprintRadius, areaShape)
	var indices := Geometry2D.triangulate_polygon(polygon)
	var surfaceTool := SurfaceTool.new()
	surfaceTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle: int in range(0, indices.size(), 3):
		var a := _groundPoint(polygon[indices[triangle]])
		var b := _groundPoint(polygon[indices[triangle + 1]])
		var c := _groundPoint(polygon[indices[triangle + 2]])
		surfaceTool.add_vertex(a)
		surfaceTool.add_vertex(b)
		surfaceTool.add_vertex(c)
		surfaceTool.add_vertex(a)
		surfaceTool.add_vertex(c)
		surfaceTool.add_vertex(b)
	_footprintRing.mesh = surfaceTool.commit()


## Draws exactly the cells `hexFootprint()` hands an effect, as a fan per hex,
## so the guide and the effect's footprint are one computation rather than two
## that could disagree.
func _updateHexFootprintGuide() -> void:
	var footprint := hexFootprint()
	var surfaceTool := SurfaceTool.new()
	surfaceTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var halfWidth := footprint.cell_width * 0.5
	var halfHeight := footprint.cell_height * 0.5
	var offsets: Array[Vector3] = [
		Vector3(halfWidth, 0.0, 0.0),
		Vector3(halfWidth * 0.5, 0.0, halfHeight),
		Vector3(-halfWidth * 0.5, 0.0, halfHeight),
		Vector3(-halfWidth, 0.0, 0.0),
		Vector3(-halfWidth * 0.5, 0.0, -halfHeight),
		Vector3(halfWidth * 0.5, 0.0, -halfHeight),
	]
	for centre: Vector3 in footprint.world_positions:
		var local := centre - targetAnchor.position
		local.y = 0.0
		for corner: int in range(offsets.size()):
			var a := local
			var b := local + offsets[corner]
			var c := local + offsets[(corner + 1) % offsets.size()]
			surfaceTool.add_vertex(a)
			surfaceTool.add_vertex(b)
			surfaceTool.add_vertex(c)
			surfaceTool.add_vertex(a)
			surfaceTool.add_vertex(c)
			surfaceTool.add_vertex(b)
	_footprintRing.mesh = surfaceTool.commit()


## The affected cells a battle cast with this scene's radius and shape would
## resolve, on the battle's own hex lattice, placed so the centre cell sits on
## the target anchor. Empty cells are included: nothing stands on any of them
## but the target, which is the case area effects most need to be truthful in.
func hexFootprint() -> HexVfxFootprint:
	if castOnCaster:
		return buildHexFootprint(
			areaShape, footprintRadius, casterAnchor.position, targetAnchor.position
		)
	return buildHexFootprint(
		areaShape, footprintRadius, targetAnchor.position, casterAnchor.position
	)


## "In front of" each unit of the cast, by the rule the battle adapter applies
## (`SpellVfxSpec.frontToward`): the caster faces the target anchor, its only
## hostile, and each cast target faces the caster. On a self-cast the caster is
## the target and still faces the target anchor.
func fronts() -> Dictionary:
	var hostileOfCaster: Array[Vector3] = [targetAnchor.position]
	var hostileOfCasterIDs: Array[int] = [DEBUG_TARGET_ID]
	var sourceFront := SpellVfxSpec.frontToward(
		casterAnchor.position, hostileOfCaster, hostileOfCasterIDs,
		targetAnchor.position - casterAnchor.position
	)
	var targetFronts: Array[Vector3] = []
	if castOnCaster:
		targetFronts.append(sourceFront)
	else:
		var hostileOfTarget: Array[Vector3] = [casterAnchor.position]
		var hostileOfTargetIDs: Array[int] = [DEBUG_CASTER_ID]
		targetFronts.append(SpellVfxSpec.frontToward(
			targetAnchor.position, hostileOfTarget, hostileOfTargetIDs,
			casterAnchor.position - targetAnchor.position
		))
	return {"source": sourceFront, "targets": targetFronts}


## Static so a headless probe can check the footprint without a scene.
##
## `circle` and `cross` resolve around the centre exactly as `CombatResolver`
## does. `line` runs from the caster's cell toward the centre, excluding the
## caster, which is how a line spell resolves in battle. `single` is the one
## target cell.
static func buildHexFootprint(
		shape: String,
		radius: int,
		centreWorld: Vector3,
		casterWorld: Vector3) -> HexVfxFootprint:
	var map := BattleMapDefinition.new()
	var layout: HexBattleLayout = HexBattleLayoutScript.new(map)
	var centre := HEX_CENTRE_CELL
	var cells: Array[Vector2i] = []
	match shape:
		"single":
			cells = [centre]
		"cross":
			cells = ShapeCasterScript.getCross(centre, radius)
		"line":
			var casterCell := _nearestLatticeCell(
				map, layout, layout.cellCenter(centre) + (casterWorld - centreWorld)
			)
			cells = ShapeCasterScript.getLine(casterCell, centre, radius)
		_:
			cells = ShapeCasterScript.getCircle(centre, radius)
	# Height 0 everywhere, so every cell's centre lands on one plane that the
	# offset below lifts onto the target's own surface.
	var cellData := {}
	for cell: Vector2i in cells:
		cellData[cell] = {"height": 0}
	map.configureCells(cells, cellData)
	var footprint: HexVfxFootprint = HexVfxFootprintScript.fromCells(cells, map)
	# The centre's lattice position with the height zero every affected cell
	# has. A line need not contain the centre, and an unconfigured cell reports
	# height -1, so the centre's own height cannot be read back here.
	var lattice := layout.cellCenter(centre)
	var offset := centreWorld - Vector3(lattice.x, 0.0, lattice.z)
	for index: int in range(footprint.world_positions.size()):
		footprint.world_positions[index] += offset
	footprint.bounds.position += offset
	return footprint


## Brute force over a window around the point's estimated column and row: the
## lattice is small and this runs on a control change, so exactness beats
## cleverness.
static func _nearestLatticeCell(
		map: BattleMapDefinition, layout: HexBattleLayout, point: Vector3) -> Vector2i:
	var width := map.cellWidth
	var height := map.cellHeight
	var column := roundi((point.x - width * 0.5) / (0.75 * width))
	var row := roundi((point.z - height * 0.5) / height)
	var best := Vector2i(column, row)
	var bestDistance := INF
	for dx: int in range(-2, 3):
		for dz: int in range(-2, 3):
			var cell := Vector2i(column + dx, row + dz)
			var centre := layout.cellCenter(cell)
			var distance := Vector2(centre.x - point.x, centre.z - point.z).length_squared()
			if distance < bestDistance:
				bestDistance = distance
				best = cell
	return best


func _groundPoint(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


## The tiles each `AREA_SHAPE` actually covers, in world units with tile = 1.0.
## A radius-R footprint reaches R + 0.5 from centre because the outermost tile
## contributes its own half-width — the same `radius + 0.5` the effects use for
## their own boundaries, so guide and effect agree by construction.
static func footprintPolygon(radius: int, shape: String) -> PackedVector2Array:
	var extent := float(radius) + 0.5
	match shape:
		"single":
			return PackedVector2Array([
				Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
				Vector2(-0.5, -0.5), Vector2(0.5, -0.5),
			])
		"cross":
			# Twelve corners tracing a plus: arms one tile wide (half-width 0.5)
			# reaching `extent` along each axis. Matches ShapeCaster.getCross.
			var arm := 0.5
			return PackedVector2Array([
				Vector2(extent, arm), Vector2(arm, arm), Vector2(arm, extent),
				Vector2(-arm, extent), Vector2(-arm, arm), Vector2(-extent, arm),
				Vector2(-extent, -arm), Vector2(-arm, -arm), Vector2(-arm, -extent),
				Vector2(arm, -extent), Vector2(arm, -arm), Vector2(extent, -arm),
			])
		"line":
			# Direction-dependent in play and unknown here, so the guide shows
			# the reachable band rather than claiming a specific orientation.
			return PackedVector2Array([
				Vector2(extent, 0.5), Vector2(-extent, 0.5),
				Vector2(-extent, -0.5), Vector2(extent, -0.5),
			])
		_:
			# Legacy Manhattan-diamond debug outline. `ShapeCaster.getCircle` has
			# returned a hex disc since HXB-7; this donor visualization is unchanged.
			return PackedVector2Array([
				Vector2(extent, 0.0), Vector2(0.0, extent),
				Vector2(-extent, 0.0), Vector2(0.0, -extent),
			])


static func surfaceY(height: int) -> float:
	return (
		float(height) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		+ BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y * 0.5
	)
