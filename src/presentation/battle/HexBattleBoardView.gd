## Tactical overlay/picking geometry for a hex battle map: one pick-able
## surface per valid cell, built from BattleMapDefinition and
## HexBattleLayout alone. This is not the terrain players see -- the exported
## map scene is, and `HexBattleStage.loadTerrain` puts it in the battle world --
## and it does no unit picking of its own; it only exposes the hex a raycast
## landed on via each surface's pick-body metadata.
##
## TWO LOOKS, ONE PICK CONTRACT. With no terrain the grey fill remains the fallback board. Over
## terrain the fill is hidden (it would sit coplanar with the ground and cover the art), while the
## battle ground's own shader draws a single screen-stable hairline. The pick bodies are untouched
## either way: hiding a MeshInstance3D does not remove its StaticBody3D child from physics.
##
## A PHYSICAL BOARD UNDER BOTH LOOKS. The lattice sits in a recessed bed inside a broad Mossstone
## rim, outer bevel and deep floating wall. Transparent edge pixels in authored art reveal the bed
## instead of black, and the smooth outer silhouette keeps staggered rows from reading as saw teeth.

class_name HexBattleBoardView
extends Node3D

const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")
const HexBattleMeshFactoryScript = preload("res://src/presentation/battle/HexBattleMeshFactory.gd")

## Distinct from every collision layer the frozen square reference or the
## world-map editor already claims (the square battle's highest tile-pick
## layer is `1 << 6`), so hex picking can never cross-hit either.
const PICK_COLLISION_LAYER := 1 << 19

const PICK_BODY_NAME := "HexPickBody"
const BATTLE_COORD_META := "battle_coord"

const BOARD_NODE_NAME := "BattleBoardSlab"
const BOARD_FIELD_MARGIN := 0.035
const BOARD_INNER_RISE_MARGIN := 0.12
const BOARD_RIM_WIDTH := 0.68
const BOARD_OUTER_BEVEL_WIDTH := 0.16
const BOARD_TOTAL_MARGIN := BOARD_INNER_RISE_MARGIN + BOARD_RIM_WIDTH + BOARD_OUTER_BEVEL_WIDTH
const BOARD_FIELD_CORNER_CUT := 0.04
const BOARD_INNER_CORNER_CUT := 0.14
const BOARD_RIM_CORNER_CUT := 0.46
const BOARD_OUTER_CORNER_CUT := 0.58
const BOARD_FIELD_Y := -0.035
const BOARD_RIM_Y := 0.10
const BOARD_OUTER_EDGE_Y := -0.035
const BOARD_BOTTOM_Y := -0.68

## Mossstone: warmer and less saturated than the cyan/lime/yellow terrain, but lighter than the
## side wall and distinct from the animated blue sky.
const BOARD_FIELD_COLOR := Color("3f4740")
const BOARD_INNER_BEVEL_COLOR := Color("4a5747")
const BOARD_RIM_COLOR := Color("586451")
const BOARD_OUTER_BEVEL_COLOR := Color("3a493b")
const BOARD_SIDE_COLOR := Color("223028")

const HOVER_NODE_NAME := "HexHover"
const HOVER_LIFT := 0.022
const HOVER_FILL := Color(1.0, 0.84, 0.32, 0.10)
const HOVER_RIM := Color(1.0, 0.84, 0.32, 0.72)
const HOVER_RIM_WIDTH := 0.08

var _surfaces: Dictionary = {}  ## Vector2i -> MeshInstance3D
var _map: BattleMapDefinition
var _layout: HexBattleLayout
var _overTerrain := false
var _boardSlab: MeshInstance3D
var _hoverMarker: MeshInstance3D
var _hoveredCell := Vector2i(-1, -1)


## Builds one surface per `map.validCells()`, replacing anything from a prior
## build. Masked-out cells receive no node at all. A view already set over
## terrain stays over terrain.
func build(map: BattleMapDefinition) -> void:
	clear()
	_map = map
	_layout = HexBattleLayoutScript.new(map)
	_buildBoard()
	for cell: Vector2i in map.validCells():
		_buildCell(_layout, cell)
	if _overTerrain:
		_applyOverTerrain()


## Frees every node this view owns and forgets every surface reference, so a
## subsequent build() starts from nothing rather than accumulating.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_surfaces.clear()
	_boardSlab = null
	_hoverMarker = null
	_hoveredCell = Vector2i(-1, -1)
	_layout = null


func getSurface(cell: Vector2i) -> MeshInstance3D:
	return _surfaces.get(cell) as MeshInstance3D


## Switches between the grey board and the outline lattice drawn over terrain.
## Picking is identical in both.
func showOverTerrain(enabled: bool) -> void:
	_overTerrain = enabled
	_applyOverTerrain()


func isOverTerrain() -> bool:
	return _overTerrain


## Compatibility accessor for probes and older callers. The battle ground shader now owns the
## passive lattice, so no world-space outline mesh exists in either look.
func outlineMesh() -> MeshInstance3D:
	return null


func boardSlab() -> MeshInstance3D:
	return _boardSlab


## One quiet pointer affordance when no tactical aim already owns the cell. The marker is reused
## as the pointer moves rather than allocating one mesh per motion event.
func showHover(cell: Vector2i) -> void:
	if _map == null or _layout == null or not _map.containsCell(cell):
		clearHover()
		return
	if _hoverMarker == null:
		_hoverMarker = _buildHoverMarker()
		add_child(_hoverMarker)
	_hoveredCell = cell
	_hoverMarker.position = _layout.cellCenter(cell) + Vector3.UP * HOVER_LIFT
	_hoverMarker.visible = true


func clearHover() -> void:
	_hoveredCell = Vector2i(-1, -1)
	if _hoverMarker != null:
		_hoverMarker.visible = false


func hoveredCell() -> Vector2i:
	return _hoveredCell


func _applyOverTerrain() -> void:
	for cell: Vector2i in _surfaces:
		(_surfaces[cell] as MeshInstance3D).visible = not _overTerrain


func _buildBoard() -> void:
	var cells := _map.validCells()
	if cells.is_empty():
		return
	var firstPolygon := _layout.cellPolygon(cells[0])
	var minX := firstPolygon[0].x
	var maxX := minX
	var minZ := firstPolygon[0].z
	var maxZ := minZ
	for cell: Vector2i in cells:
		for corner: Vector3 in _layout.cellPolygon(cell):
			minX = minf(minX, corner.x)
			maxX = maxf(maxX, corner.x)
			minZ = minf(minZ, corner.z)
			maxZ = maxf(maxZ, corner.z)
	var playfield := _chamferedRect(
		minX - BOARD_FIELD_MARGIN, maxX + BOARD_FIELD_MARGIN,
		minZ - BOARD_FIELD_MARGIN, maxZ + BOARD_FIELD_MARGIN,
		BOARD_FIELD_CORNER_CUT, BOARD_FIELD_Y)
	var innerRim := _chamferedRect(
		minX - BOARD_INNER_RISE_MARGIN, maxX + BOARD_INNER_RISE_MARGIN,
		minZ - BOARD_INNER_RISE_MARGIN, maxZ + BOARD_INNER_RISE_MARGIN,
		BOARD_INNER_CORNER_CUT, BOARD_RIM_Y)
	var rimReach := BOARD_INNER_RISE_MARGIN + BOARD_RIM_WIDTH
	var outerRim := _chamferedRect(
		minX - rimReach, maxX + rimReach,
		minZ - rimReach, maxZ + rimReach,
		BOARD_RIM_CORNER_CUT, BOARD_RIM_Y)
	var outerEdge := _chamferedRect(
		minX - BOARD_TOTAL_MARGIN, maxX + BOARD_TOTAL_MARGIN,
		minZ - BOARD_TOTAL_MARGIN, maxZ + BOARD_TOTAL_MARGIN,
		BOARD_OUTER_CORNER_CUT, BOARD_OUTER_EDGE_Y)
	_boardSlab = MeshInstance3D.new()
	_boardSlab.name = BOARD_NODE_NAME
	_boardSlab.mesh = HexBattleMeshFactoryScript.createRaisedBoard(
		playfield, innerRim, outerRim, outerEdge, BOARD_BOTTOM_Y,
		BOARD_FIELD_COLOR, BOARD_INNER_BEVEL_COLOR, BOARD_RIM_COLOR,
		BOARD_OUTER_BEVEL_COLOR, BOARD_SIDE_COLOR)
	_boardSlab.material_override = HexBattleMeshFactoryScript.createBoardMaterial()
	_boardSlab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boardSlab)


func _chamferedRect(
		minX: float, maxX: float, minZ: float, maxZ: float,
		cut: float, y: float
) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(minX + cut, y, minZ), Vector3(maxX - cut, y, minZ),
		Vector3(maxX, y, minZ + cut), Vector3(maxX, y, maxZ - cut),
		Vector3(maxX - cut, y, maxZ), Vector3(minX + cut, y, maxZ),
		Vector3(minX, y, maxZ - cut), Vector3(minX, y, minZ + cut),
	])


func _buildHoverMarker() -> MeshInstance3D:
	var origin := _layout.cellCenter(Vector2i.ZERO)
	var polygon := PackedVector3Array()
	for corner: Vector3 in _layout.cellPolygon(Vector2i.ZERO):
		polygon.append(corner - origin)
	var marker := MeshInstance3D.new()
	marker.name = HOVER_NODE_NAME
	marker.mesh = HexBattleMeshFactoryScript.createSurfaceMesh(Vector3.ZERO, polygon)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = HOVER_FILL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var rimVertices := PackedVector3Array()
	var rimColors := PackedColorArray()
	HexBattleMeshFactoryScript.appendRingBand(
		rimVertices, rimColors, Vector3.ZERO, polygon, 0.0, HOVER_RIM_WIDTH, HOVER_RIM)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = HexBattleMeshFactoryScript.createColoredMesh(rimVertices, rimColors)
	rim.material_override = HexBattleMeshFactoryScript.createOverlayMaterial(1)
	rim.position.y = 0.001
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(rim)
	return marker


func _buildCell(layout: HexBattleLayout, cell: Vector2i) -> void:
	var center: Vector3 = layout.cellCenter(cell)
	var polygon: PackedVector3Array = layout.cellPolygon(cell)

	var surface := MeshInstance3D.new()
	surface.name = "HexSurface_%d_%d" % [cell.x, cell.y]
	surface.mesh = HexBattleMeshFactoryScript.createSurfaceMesh(center, polygon)
	surface.material_override = HexBattleMeshFactoryScript.createDebugMaterial()
	add_child(surface)
	_surfaces[cell] = surface

	var pickBody := StaticBody3D.new()
	pickBody.name = PICK_BODY_NAME
	pickBody.collision_layer = PICK_COLLISION_LAYER
	pickBody.collision_mask = 0
	pickBody.set_meta(BATTLE_COORD_META, cell)
	var pickShape := CollisionShape3D.new()
	pickShape.shape = HexBattleMeshFactoryScript.createPickShape(center, polygon)
	pickBody.add_child(pickShape)
	surface.add_child(pickBody)
