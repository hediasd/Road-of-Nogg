## Tactical overlay/picking geometry for a hex battle map: one pick-able
## surface per valid cell, built from BattleMapDefinition and
## HexBattleLayout alone. This is not the terrain players see -- HXB-13
## supplies the visible exported ground and controls this view's visibility
## -- and it does no unit picking of its own; it only exposes the hex a
## raycast landed on via each surface's pick-body metadata.

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

var _surfaces: Dictionary = {}  ## Vector2i -> MeshInstance3D


## Builds one surface per `map.validCells()`, replacing anything from a prior
## build. Masked-out cells receive no node at all.
func build(map: BattleMapDefinition) -> void:
	clear()
	var layout := HexBattleLayoutScript.new(map)
	for cell: Vector2i in map.validCells():
		_buildCell(layout, cell)


## Frees every node this view owns and forgets every surface reference, so a
## subsequent build() starts from nothing rather than accumulating.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_surfaces.clear()


func getSurface(cell: Vector2i) -> MeshInstance3D:
	return _surfaces.get(cell) as MeshInstance3D


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
