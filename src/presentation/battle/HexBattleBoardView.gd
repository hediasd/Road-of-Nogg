## Tactical overlay/picking geometry for a hex battle map: one pick-able
## surface per valid cell, built from BattleMapDefinition and
## HexBattleLayout alone. This is not the terrain players see -- the exported
## map scene is, and `HexBattleStage.loadTerrain` puts it in the battle world --
## and it does no unit picking of its own; it only exposes the hex a raycast
## landed on via each surface's pick-body metadata.
##
## TWO LOOKS, ONE PICK CONTRACT. With no terrain the grey fill is the board, as it
## always was. Over terrain the fill is hidden (it would sit coplanar with the
## ground and z-fight while covering the art) and one merged mesh of thin banded
## cell outlines is drawn instead. The pick bodies are untouched either way:
## hiding a MeshInstance3D does not remove its StaticBody3D child from physics,
## which is why the bodies sit on their own collision layer.

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

const OUTLINE_NODE_NAME := "HexCellOutlines"
## Above the ground, below the lowest marker layer (the adapter's threat layer
## at 0.012), so a marker always draws over the lattice it sits in.
const OUTLINE_LIFT := 0.006
## Two bands per cell, as fractions from the hex edge toward its centre. A dark
## edge reads over light art and a pale inner line over dark art, so the lattice
## survives any palette without choosing one. Neighbouring dark bands meet to
## make one line; the pale bands face into their own cells.
const OUTLINE_DARK := Color(0.03, 0.03, 0.05, 0.5)
const OUTLINE_DARK_WIDTH := 0.035
const OUTLINE_LIGHT := Color(1.0, 1.0, 0.94, 0.24)
const OUTLINE_LIGHT_WIDTH := 0.025
## Behind the adapter's markers when transparent sorting would otherwise tie.
const OUTLINE_RENDER_PRIORITY := -1

var _surfaces: Dictionary = {}  ## Vector2i -> MeshInstance3D
var _map: BattleMapDefinition
var _overTerrain := false
var _outlines: MeshInstance3D


## Builds one surface per `map.validCells()`, replacing anything from a prior
## build. Masked-out cells receive no node at all. A view already set over
## terrain stays over terrain.
func build(map: BattleMapDefinition) -> void:
	clear()
	_map = map
	var layout := HexBattleLayoutScript.new(map)
	for cell: Vector2i in map.validCells():
		_buildCell(layout, cell)
	if _overTerrain:
		_applyOverTerrain()


## Frees every node this view owns and forgets every surface reference, so a
## subsequent build() starts from nothing rather than accumulating.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_surfaces.clear()
	_outlines = null


func getSurface(cell: Vector2i) -> MeshInstance3D:
	return _surfaces.get(cell) as MeshInstance3D


## Switches between the grey board and the outline lattice drawn over terrain.
## Picking is identical in both.
func showOverTerrain(enabled: bool) -> void:
	_overTerrain = enabled
	_applyOverTerrain()


func isOverTerrain() -> bool:
	return _overTerrain


## The merged outline mesh, or null while the view is not over terrain.
func outlineMesh() -> MeshInstance3D:
	return _outlines


func _applyOverTerrain() -> void:
	for cell: Vector2i in _surfaces:
		(_surfaces[cell] as MeshInstance3D).visible = not _overTerrain
	if _outlines != null:
		remove_child(_outlines)
		_outlines.queue_free()
		_outlines = null
	if _overTerrain and _map != null and not _surfaces.is_empty():
		_outlines = _buildOutlines()
		add_child(_outlines)


func _buildOutlines() -> MeshInstance3D:
	var layout := HexBattleLayoutScript.new(_map)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var lift := Vector3(0.0, OUTLINE_LIFT, 0.0)
	for cell: Vector2i in _surfaces:
		var center: Vector3 = layout.cellCenter(cell) + lift
		var polygon := PackedVector3Array()
		for corner: Vector3 in layout.cellPolygon(cell):
			polygon.append(corner + lift)
		HexBattleMeshFactoryScript.appendRingBand(
			vertices, colors, center, polygon, 0.0, OUTLINE_DARK_WIDTH, OUTLINE_DARK)
		HexBattleMeshFactoryScript.appendRingBand(
			vertices, colors, center, polygon, OUTLINE_DARK_WIDTH,
			OUTLINE_DARK_WIDTH + OUTLINE_LIGHT_WIDTH, OUTLINE_LIGHT)
	var outlines := MeshInstance3D.new()
	outlines.name = OUTLINE_NODE_NAME
	outlines.mesh = HexBattleMeshFactoryScript.createColoredMesh(vertices, colors)
	outlines.material_override = HexBattleMeshFactoryScript.createOverlayMaterial(
		OUTLINE_RENDER_PRIORITY)
	outlines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return outlines


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
