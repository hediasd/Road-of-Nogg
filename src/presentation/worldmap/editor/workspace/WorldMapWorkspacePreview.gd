## The editor-only highlight of the cells a gesture is about to change.
##
## WHY A MESH RATHER THAN A SHADER PARAMETER. The ground's own material already highlights ONE
## cursor cell through `WorldMapSurfacePick.applyGrid`, and a footprint is many cells whose shape
## changes per gesture. Widening that uniform means editing the shipping ground shader, which this
## work may not do. A separate editor-only `MeshInstance3D` costs the shared rendering path
## nothing, is deleted with the editor, and -- because it is real world geometry rather than a
## screen overlay -- follows the camera and the terrain for free instead of needing to be
## re-projected whenever either moves.
##
## NOTHING HERE REACHES THE DOCUMENT. These are lines in the world, not pixels in the bake: no
## preview geometry can end up in the authored source, in the generated texture or in an export,
## because it never touches any of them. That is the whole reason the highlight is drawn instead
## of painted.
##
## HEIGHTS ARE SAMPLED, NOT ASSUMED. Each hex outline is lifted onto the terrain by the SAME
## `WorldMapHeightField.sample` the surface mesh was built from, so a footprint on a hill sits on
## the hill rather than through it, and the highlight cannot disagree with the ground about where
## the ground is.

class_name WorldMapWorkspacePreview
extends MeshInstance3D

const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")

## Just above the surface. Small enough to read as "on the ground", large enough to survive the
## depth precision of a dollied-out camera without stitching in and out of the terrain.
const LIFT := 0.06
const FOOTPRINT_COLOR := Color(1.0, 0.95, 0.78, 0.95)
const BLOCKED_COLOR := Color(1.0, 0.51, 0.46, 0.95)

var _shownCells: Array[Vector2i] = []
var _shownBlocked := false
var _shownOrigin := Vector2.ZERO


func _init() -> void:
	name = "EditorFootprintPreview"
	mesh = ImmediateMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn over the terrain it sits on rather than fighting it: the highlight is chrome, and a
	# footprint that disappears into a slope is worse than one that is always legible.
	material.no_depth_test = true
	material.disable_receive_shadows = true
	material_override = material


## `cells` are offset lattice cells; `regionOrigin` is where the lattice's bounding box starts in
## world units. `blocked` draws the same footprint in the refusal colour -- a locked or hidden
## layer still shows WHERE the gesture would land, which is what makes the refusal legible instead
## of the tool just doing nothing.
##
## Redraws only when the request actually changed. A pointer moving within one cell arrives many
## times a second and must not rebuild geometry each time.
func showCells(
	cells: Array[Vector2i], document: WorldMapTileData, regionOrigin: Vector2, blocked: bool
) -> void:
	if cells == _shownCells and blocked == _shownBlocked and regionOrigin == _shownOrigin:
		return
	_shownCells = cells.duplicate()
	_shownBlocked = blocked
	_shownOrigin = regionOrigin
	_rebuild(document)


func clear() -> void:
	if _shownCells.is_empty():
		return
	_shownCells.clear()
	(mesh as ImmediateMesh).clear_surfaces()
	visible = false


func shownCellCount() -> int:
	return _shownCells.size()


func _rebuild(document: WorldMapTileData) -> void:
	var immediate := mesh as ImmediateMesh
	immediate.clear_surfaces()
	if _shownCells.is_empty() or document == null:
		visible = false
		return
	var colour := BLOCKED_COLOR if _shownBlocked else FOOTPRINT_COLOR
	var hasHeights := HeightField.has(document)
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell in _shownCells:
		var centre := WorldMapHexGrid.cellCentre(cell)
		var previous := _corner(centre, 5, document, hasHeights)
		for corner in 6:
			var current := _corner(centre, corner, document, hasHeights)
			immediate.surface_set_color(colour)
			immediate.surface_add_vertex(previous)
			immediate.surface_set_color(colour)
			immediate.surface_add_vertex(current)
			previous = current
	immediate.surface_end()
	visible = true


## A flat-top hex corner in world space. The hex is two units across and two tall in the project's
## deliberately stretched geometry, so the corners are at the same six points
## `docs/HEX_TILESET_AUTHORING.md` documents for the art, scaled from its 32 px frame to 2 units.
func _corner(
	centre: Vector2, index: int, document: WorldMapTileData, hasHeights: bool
) -> Vector3:
	var offsets := [
		Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
		Vector2(-1.0, 0.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
	]
	# Pulled very slightly inward so neighbouring cells in one footprint read as separate hexes
	# rather than as one solid blob of overlapping edges.
	var local: Vector2 = centre + (offsets[index] as Vector2) * 0.94
	var height := HeightField.sample(document, local) if hasHeights else 0.0
	return Vector3(_shownOrigin.x + local.x, height + LIFT, _shownOrigin.y + local.y)
