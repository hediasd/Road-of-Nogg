extends SceneTree

const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")
const HexBattleBoardViewScript = preload("res://src/presentation/battle/HexBattleBoardView.gd")
const HexBattleMeshFactoryScript = preload("res://src/presentation/battle/HexBattleMeshFactory.gd")
const WorldMapHexGridScript = preload(
	"res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

## A top-fan normal round-trips through ArrayMesh's compressed vertex storage,
## so it comes back a few parts in 1e5 off exact Vector3.UP rather than
## bit-identical. This is a storage artifact, not a geometry error, so the
## check below is a direction tolerance rather than exact equality.
const NORMAL_UP_DOT_TOLERANCE := 0.999

var failures: Array[String] = []


func _init() -> void:
	var geometryMap: BattleMapDefinition = _buildGeometryMap()
	var geometryLayout: HexBattleLayout = HexBattleLayoutScript.new(geometryMap)

	_checkCenterParityWithEditor(geometryLayout)
	_checkHeightFormula(geometryLayout, geometryMap)
	_checkSharedEdges(geometryLayout)
	_checkPolygonContainment(geometryLayout)
	_checkSurfaceMeshNormals(geometryLayout)
	_checkBoardViewLifecycleAndMetadata(_buildHoleMap())

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_BOARD_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_BOARD_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## A fully valid 3x3 board at the editor's own 2.0/2.0 cell metrics, so every
## neighbour of the interior cell (1, 1) is itself a real, valid cell -- the
## edge-sharing and containment checks below need genuine adjacent cells, not
## the -1 "off-map" height sentinel BattleMapDefinition returns for a
## coordinate outside the board. Corner (0, 0) carries a raised height and is
## not among (1, 1)'s six neighbours, so it cannot pollute those checks.
func _buildGeometryMap() -> BattleMapDefinition:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(3, 3)
	map.cellWidth = 2.0
	map.cellHeight = 2.0
	map.heightStep = 0.5
	map.terrainDefinitions = {
		"plain": {"traversable": true, "stoppable": true, "movement_cost": 1},
	}
	var cells: Array[Vector2i] = []
	var cellData := {}
	for y in range(3):
		for x in range(3):
			var cell := Vector2i(x, y)
			cells.append(cell)
			var height := 3 if cell == Vector2i(0, 0) else 0
			cellData[cell] = {"terrain": "plain", "height": height}
	map.configureCells(cells, cellData)
	return map


## A 2x2 board with one masked hole, both column parities represented among
## its three valid cells. Used only for HexBattleBoardView's own lifecycle
## contract, which never compares one cell's geometry against another's.
func _buildHoleMap() -> BattleMapDefinition:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(2, 2)
	map.cellWidth = 2.0
	map.cellHeight = 2.0
	map.heightStep = 0.5
	map.terrainDefinitions = {
		"plain": {"traversable": true, "stoppable": true, "movement_cost": 1},
	}
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var cellData := {
		Vector2i(0, 0): {"terrain": "plain", "height": 0},
		Vector2i(1, 0): {"terrain": "plain", "height": 0},
		Vector2i(0, 1): {"terrain": "plain", "height": 0},
	}
	map.configureCells(cells, cellData)
	return map


## HexBattleLayout's X/Z must equal WorldMapHexGrid.cellCentre's X/Y exactly
## at the editor's own cell metrics, for both column parities -- the two
## coordinate spaces describe the same lattice.
func _checkCenterParityWithEditor(layout: HexBattleLayout) -> void:
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var editorCentre: Vector2 = WorldMapHexGridScript.cellCentre(cell)
		var battleCenter: Vector3 = layout.cellCenter(cell)
		_require(is_equal_approx(battleCenter.x, editorCentre.x),
			"cell %s X diverged from editor: %f vs %f" % [cell, battleCenter.x, editorCentre.x])
		_require(is_equal_approx(battleCenter.z, editorCentre.y),
			"cell %s Z diverged from editor: %f vs %f" % [cell, battleCenter.z, editorCentre.y])


## Y has no editor equivalent, so it gets its own direct formula check: zero
## height sits at Y=0, and the raised corner matches height * heightStep.
func _checkHeightFormula(layout: HexBattleLayout, map: BattleMapDefinition) -> void:
	var flatCenter: Vector3 = layout.cellCenter(Vector2i(1, 0))
	_require(is_equal_approx(flatCenter.y, 0.0),
		"zero-height cell did not sit at Y=0: %f" % flatCenter.y)

	var raisedCell := Vector2i(0, 0)
	var raisedCenter: Vector3 = layout.cellCenter(raisedCell)
	var expectedY := float(map.heightAt(raisedCell)) * map.heightStep
	_require(is_equal_approx(raisedCenter.y, expectedY),
		"raised cell Y did not follow height * heightStep: %f vs %f" %
		[raisedCenter.y, expectedY])


## Two cells sharing a lattice edge must share exactly two polygon corners --
## the endpoints of that edge -- or a picked cell's boundary would gap or
## overlap its neighbour's. Rooted at an interior cell so every neighbour
## below is a real, equal-height cell of the same fixture.
func _checkSharedEdges(layout: HexBattleLayout) -> void:
	var origin := Vector2i(1, 1)
	var originPolygon: PackedVector3Array = layout.cellPolygon(origin)
	for neighbour: Vector2i in HexGridScript.neighbours(origin):
		var neighbourPolygon: PackedVector3Array = layout.cellPolygon(neighbour)
		var shared := 0
		for corner: Vector3 in originPolygon:
			for otherCorner: Vector3 in neighbourPolygon:
				if corner.is_equal_approx(otherCorner):
					shared += 1
					break
		_require(shared == 2,
			"cell %s and neighbour %s share %d polygon corners, expected 2" %
			[origin, neighbour, shared])


## A cell's own centre lies inside its polygon; a neighbour's centre and a
## clearly distant point do not.
func _checkPolygonContainment(layout: HexBattleLayout) -> void:
	var cell := Vector2i(1, 1)
	var polygon := _polygonXZ(layout.cellPolygon(cell))
	var center: Vector3 = layout.cellCenter(cell)
	_require(Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), polygon),
		"cell centre is not contained in its own polygon")

	var neighbour: Vector2i = HexGridScript.neighbours(cell)[0]
	var neighbourCenter: Vector3 = layout.cellCenter(neighbour)
	_require(not Geometry2D.is_point_in_polygon(
			Vector2(neighbourCenter.x, neighbourCenter.z), polygon),
		"a neighbour's centre registered inside this cell's polygon")

	var farPoint: Vector2 = Vector2(center.x, center.z) + Vector2(1000.0, 1000.0)
	_require(not Geometry2D.is_point_in_polygon(farPoint, polygon),
		"a distant point registered inside the polygon")


func _polygonXZ(polygon: PackedVector3Array) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for corner: Vector3 in polygon:
		flat.append(Vector2(corner.x, corner.z))
	return flat


## The top fan's normals must all point essentially straight up; anything
## else means a reversed winding order or a fan vertex out of the XZ plane.
## Compared by direction, not exact equality -- see NORMAL_UP_DOT_TOLERANCE.
func _checkSurfaceMeshNormals(layout: HexBattleLayout) -> void:
	var cell := Vector2i(1, 1)
	var mesh: ArrayMesh = HexBattleMeshFactoryScript.createSurfaceMesh(
		layout.cellCenter(cell), layout.cellPolygon(cell))
	_require(mesh.get_surface_count() == 1,
		"surface mesh has %d surfaces, expected 1" % mesh.get_surface_count())

	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_require(vertices.size() == 18,
		"top fan has %d vertices, expected 18 (six triangles)" % vertices.size())
	_require(normals.size() == vertices.size(),
		"normal count %d does not match vertex count %d" % [normals.size(), vertices.size()])
	for normal: Vector3 in normals:
		_require(normal.dot(Vector3.UP) > NORMAL_UP_DOT_TOLERANCE,
			"a top-fan normal is not straight up: %s" % normal)


## HexBattleBoardView builds one pick-able surface per valid cell, none for a
## masked hole, carries the picking contract on each surface's pick body, and
## rebuilding/clearing never leaks or duplicates nodes.
##
## Production clear() detaches and queue_free()s its children, which is the
## right call inside a running game but leaves orphaned nodes pending
## deletion past this one-shot script's lifetime. Each generation this test
## detaches is captured and freed immediately below so the probe process
## exits with nothing left in ObjectDB, on top of the count/reference
## assertions the item itself requires.
func _checkBoardViewLifecycleAndMetadata(map: BattleMapDefinition) -> void:
	var view: HexBattleBoardView = HexBattleBoardViewScript.new()
	view.build(map)

	var expectedCount: int = map.validCells().size()
	_require(view.get_child_count() == expectedCount,
		"board view built %d children for %d valid cells" %
		[view.get_child_count(), expectedCount])

	var hole := Vector2i(1, 1)
	_require(not map.containsCell(hole), "fixture map hole is unexpectedly valid")
	_require(view.getSurface(hole) == null, "a masked hole received a surface")

	var surface: MeshInstance3D = view.getSurface(Vector2i(0, 0))
	_require(surface != null, "expected a surface for a valid cell")
	if surface != null:
		var pickBody: StaticBody3D = surface.get_node_or_null(
			HexBattleBoardViewScript.PICK_BODY_NAME) as StaticBody3D
		_require(pickBody != null, "surface is missing its pick body")
		if pickBody != null:
			_require(pickBody.collision_layer == HexBattleBoardViewScript.PICK_COLLISION_LAYER,
				"pick body collision layer changed")
			_require(pickBody.collision_mask == 0, "pick body collision mask is not zero")
			_require(
				pickBody.get_meta(HexBattleBoardViewScript.BATTLE_COORD_META, null)
					== Vector2i(0, 0),
				"pick body battle_coord metadata missing or wrong")

	var firstGeneration := view.get_children()
	view.build(map)
	_require(view.get_child_count() == expectedCount,
		"rebuilding duplicated board view children: now %d, expected %d" %
		[view.get_child_count(), expectedCount])
	_freeDetachedNodes(firstGeneration)

	var secondGeneration := view.get_children()
	view.clear()
	_require(view.get_child_count() == 0,
		"clear() left %d children behind" % view.get_child_count())
	for cell: Vector2i in map.validCells():
		_require(view.getSurface(cell) == null,
			"clear() left a surface reference for %s behind" % cell)
	_freeDetachedNodes(secondGeneration)

	view.free()


func _freeDetachedNodes(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.free()
