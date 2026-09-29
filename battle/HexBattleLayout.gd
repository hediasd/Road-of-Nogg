## Value mapper from hex battle-map coordinates to 3D world space.
##
## Holds no scene nodes and mutates nothing; HexBattleBoardView is the only
## caller that turns these numbers into geometry. The X/Z formulas match
## WorldMapHexGrid.cellCentre exactly at the editor's own 2.0/2.0 cell
## metrics -- the editor's region-local (x, y) becomes this layout's (X, Z) --
## so an authored map and its battle view agree on where a cell sits without
## either side duplicating the parity step.

class_name HexBattleLayout
extends RefCounted

var _map: BattleMapDefinition


func _init(map: BattleMapDefinition) -> void:
	_map = map


## World-space centre of `cell`. X/Z follow the map's offset lattice at its
## own cellWidth/cellHeight; Y steps by the cell's authored height, which the
## 2D editor lattice has no equivalent of. Defined for any cell, valid or not
## -- callers that need to restrict to the map's own footprint use
## BattleMapDefinition.containsCell first.
func cellCenter(cell: Vector2i) -> Vector3:
	var width := _map.cellWidth
	var height := _map.cellHeight
	var oddColumnDrop := height * 0.5 if (cell.x & 1) == 1 else 0.0
	var x := 0.75 * width * float(cell.x) + width * 0.5
	var z := height * float(cell.y) + oddColumnDrop + height * 0.5
	var y := float(_map.heightAt(cell)) * _map.heightStep
	return Vector3(x, y, z)


## The six corners of `cell`'s hex, in absolute world space, at the cell's own
## height. Winding order starts at the east point and runs anticlockwise
## around the flat top/bottom edges: `(w/2,0), (w/4,h/2), (-w/4,h/2),
## (-w/2,0), (-w/4,-h/2), (w/4,-h/2)` offset from the centre in XZ. Two cells
## sharing a lattice edge always share exactly two of these points exactly,
## which is what lets HexBattleMeshFactory build a seamless pick surface
## without either cell rounding its shared corner differently.
func cellPolygon(cell: Vector2i) -> PackedVector3Array:
	var center := cellCenter(cell)
	var width := _map.cellWidth
	var height := _map.cellHeight
	var offsets: Array[Vector2] = [
		Vector2(width * 0.5, 0.0),
		Vector2(width * 0.25, height * 0.5),
		Vector2(-width * 0.25, height * 0.5),
		Vector2(-width * 0.5, 0.0),
		Vector2(-width * 0.25, -height * 0.5),
		Vector2(width * 0.25, -height * 0.5),
	]
	var polygon := PackedVector3Array()
	for offset: Vector2 in offsets:
		polygon.append(center + Vector3(offset.x, 0.0, offset.y))
	return polygon
