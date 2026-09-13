## The status badge rows carried above hex battle units.
##
## CONTENT IS EVENT-TIME, PLACEMENT IS PER FRAME. A row's effects come only from the adapter's
## displayed state, and only when the adapter says a queued action has reached the screen
## (`refresh`). Nothing here reads `BattleState`: the simulation runs ahead of playback, so polling
## it would show a burn before the hit that applied it. Placement, by contrast, has to follow a
## model through its walk and bump tweens and through camera motion, none of which emit a signal,
## so it runs every frame from this layer's own `_process`. The split is the square donor's
## (`GodotVisualAdapter._refresh_status_icons` / `update_status_badges`); the frame loop lives
## here instead of in the controller because the adapter is a `RefCounted` and the controller is
## not this item's to change.
##
## NATIVE RESOLUTION. The layer sits beside `HexBattleStage`, never under its world root, and every
## anchor goes through `HexBattleStage.projectWorldToScreen`, so a retro preset shrinks the world
## but never the rows. `StatusBadgeRow` draws, hovers and sizes itself unchanged.
##
## NO SECOND GAME-STATE CACHE. `_rows` holds drawn controls. `_leaving` only records which units
## have started their removal playback, which the displayed state does not know yet.
class_name HexBattleUnitBadges
extends CanvasLayer

const StatusBadgeRowScript = preload("res://src/presentation/StatusBadgeRow.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## Above the isolated world image (`CRT_LAYER`) and the default CRT overlay, below `HexBattleHud`
## (layer 1). The donor sat one under the damage numbers and under the game UI; the hex HUD lives
## at layer 1, so a panel covers a row instead of a row drawing over the panel.
const BADGE_LAYER := 0

## Donor anchor, unchanged: the top of the model's own bounds plus a clearance, never lower than
## a short unit's head, and a fixed height when a model has no measurable mesh.
const ANCHOR_CLEARANCE := 0.28
const ANCHOR_MINIMUM := 0.75
const ANCHOR_FALLBACK := 1.25

var _adapter
var _boardRoot: Node3D
var _rowRoot: Control
## monsterID -> StatusBadgeRow, for shown units carrying at least one displayed effect.
var _rows: Dictionary = {}
## monsterID -> true once that unit's removal playback has started.
var _leaving: Dictionary = {}
var _disposed := false
var _createdCount := 0
var _removedCount := 0


func _init(adapter, boardRoot: Node3D) -> void:
	name = "HexStatusBadges"
	layer = BADGE_LAYER
	_adapter = adapter
	_boardRoot = boardRoot
	_rowRoot = Control.new()
	_rowRoot.name = "StatusBadgeRoot"
	_rowRoot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rowRoot.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rowRoot)


## Joins the tree now if the board root is already in it, or as soon as it enters. Separate from
## `_init` so the adapter can finish building what `refreshAll` reads first.
func start() -> void:
	if _disposed or not is_instance_valid(_boardRoot):
		return
	if _boardRoot.is_inside_tree():
		_attach()
	elif not _boardRoot.tree_entered.is_connected(_attach):
		_boardRoot.tree_entered.connect(_attach, CONNECT_ONE_SHOT)


## Parents the layer beside the stage (or under a bare board root with no stage), then catches up
## on anything displayed before it could draw.
func _attach() -> void:
	if _disposed or is_inside_tree() or not is_instance_valid(_boardRoot):
		return
	var parent: Node = _boardRoot
	var stage := _stage()
	if stage != null:
		parent = stage.get_parent() if stage.get_parent() != null else stage
	parent.add_child(self)
	refreshAll()


func _process(delta: float) -> void:
	update(delta, get_viewport().get_mouse_position() if _hoverAllowed() else null)


# --- content ----------------------------------------------------------------

## Rebuilds one unit's row from what the screen has shown. Called by the adapter when a queued
## action starts or finalizes, which is exactly when displayed effects can change.
func refresh(monsterID: int) -> void:
	if _disposed or monsterID < 0:
		return
	var effects: Array = _adapter.displayedEffects(monsterID)
	var model: Node3D = _adapter.modelFor(monsterID)
	if effects.is_empty() or model == null or not is_instance_valid(model) \
			or _leaving.has(monsterID) or _adapter.displayedRemovalReason(monsterID) != "" \
			or not is_inside_tree():
		_removeRow(monsterID)
		return
	var row = _rows.get(monsterID)
	if row == null or not is_instance_valid(row):
		row = StatusBadgeRowScript.new()
		row.name = "StatusBadges_%d" % monsterID
		# Hidden until the first placement pass, so a row never flashes at the origin.
		row.visible = false
		_rowRoot.add_child(row)
		_rows[monsterID] = row
		_createdCount += 1
	row.set_effects(effects)


## Recovery converged the displayed state on the simulation; follow it for every unit.
func refreshAll() -> void:
	if _disposed:
		return
	_leaving.clear()
	var ids: Dictionary = {}
	for value in _rows.keys():
		ids[int(value)] = true
	for value in _adapter.shownModelIDs():
		ids[int(value)] = true
	for monsterID in ids.keys():
		refresh(int(monsterID))


## The unit's collapse or lift-away has begun. Its row goes now, not when the model is freed: a
## row riding a shrinking body would read as the effects outliving the unit.
func beginRemoval(monsterID: int) -> void:
	if _disposed or monsterID < 0:
		return
	_leaving[monsterID] = true
	_removeRow(monsterID)


func _removeRow(monsterID: int) -> void:
	if not _rows.has(monsterID):
		return
	var row = _rows[monsterID]
	_rows.erase(monsterID)
	_removedCount += 1
	if is_instance_valid(row):
		row.queue_free()


# --- placement --------------------------------------------------------------

## Places every row over its model and dispatches pointer hover. `mousePosition` is in host
## viewport coordinates, the space the rows live in; `null` clears hover. Public so a probe can
## drive a frame with a known pointer.
func update(delta: float, mousePosition) -> void:
	if _disposed:
		return
	var bounds := _visibleRect()
	# Rows already placed this pass. Adjacent hexes project close together under the battle
	# camera, and two overlapping rows read worse than one pushed clear.
	var placed: Array = []
	var ids: Array = _rows.keys()
	ids.sort()
	for value in ids:
		var monsterID := int(value)
		var row = _rows[monsterID]
		if not is_instance_valid(row):
			_rows.erase(monsterID)
			continue
		var model: Node3D = _adapter.modelFor(monsterID)
		if model == null or not is_instance_valid(model) or not model.is_inside_tree() \
				or not row.has_entries():
			_removeRow(monsterID)
			continue
		var screenPosition := projectedAnchor(model)
		# Behind the camera or in a letterbox margin: the stage's negative sentinel.
		if screenPosition.x < 0.0 \
				or (bounds.size != Vector2.ZERO
					and not bounds.grow(row.size.x).has_point(screenPosition)):
			row.visible = false
			row.set_hover_point(null)
			row.advance(delta)
			continue
		row.visible = true
		var wanted: Vector2 = (screenPosition
			+ Vector2(-row.size.x * 0.5, -row.size.y - NoggThemeScript.STATUS_BADGE_LIFT)).round()
		row.position = _declutterRow(Rect2(wanted, row.size), placed, bounds)
		placed.append(Rect2(row.position, row.size))
		var local = null
		if mousePosition != null:
			var point: Vector2 = mousePosition
			# The resting rect, as the donor tested: hit-testing the grown size would make a badge
			# harder to leave than to enter.
			if Rect2(row.position, row.size).has_point(point):
				local = point - row.position
		row.set_hover_point(local)
		row.advance(delta)


## Where a model's row hangs, in host viewport coordinates, from its live transform.
func projectedAnchor(model: Node3D) -> Vector2:
	return _projectToScreen(model.global_position + Vector3.UP * anchorHeight(model))


static func anchorHeight(model: Node3D) -> float:
	var accumulated := {"has_bounds": false, "bounds": AABB()}
	MonsterModelFactoryScript.accumulateVisualBounds(model, Transform3D.IDENTITY, accumulated)
	if not accumulated["has_bounds"]:
		return ANCHOR_FALLBACK
	var bounds: AABB = accumulated["bounds"]
	return maxf(bounds.end.y + ANCHOR_CLEARANCE, ANCHOR_MINIMUM)


## The donor's overlap search, unchanged: vertical only so a row stays over its own unit, upward
## first so it never walks into that unit, fixed outward slots so it converges, and off-screen
## counts as blocked so a crowded edge is not "solved" by leaving the screen.
static func _declutterRow(rect: Rect2, placed: Array, bounds: Rect2) -> Vector2:
	if not _rowOverlaps(rect, placed):
		return rect.position.round()
	var step: float = rect.size.y + NoggThemeScript.STATUS_BADGE_GAP
	for slot in range(1, NoggThemeScript.STATUS_BADGE_DECLUTTER_SLOTS + 1):
		for direction in [-1.0, 1.0]:
			var candidate := rect
			candidate.position.y = rect.position.y + direction * float(slot) * step
			if bounds.size != Vector2.ZERO and not bounds.encloses(candidate):
				continue
			if not _rowOverlaps(candidate, placed):
				return candidate.position.round()
	return rect.position.round()


static func _rowOverlaps(rect: Rect2, placed: Array) -> bool:
	for other in placed:
		if other is Rect2 and rect.intersects(other):
			return true
	return false


## A HUD panel covers the rows beneath it by layer; it must also take the pointer, or hovering a
## party row would grow a badge nobody can see.
func _hoverAllowed() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	if viewport.has_method("gui_get_hovered_control"):
		return viewport.call("gui_get_hovered_control") == null
	return true


func _visibleRect() -> Rect2:
	var stage := _stage()
	if stage != null:
		return stage.displayRect()
	var viewport := get_viewport()
	return viewport.get_visible_rect() if viewport != null else Rect2()


## Same boundary the damage numbers use: the stage's projection when there is a stage, the board
## root's own viewport camera when there is not (probes and tools).
func _projectToScreen(worldPosition: Vector3) -> Vector2:
	var stage := _stage()
	if stage != null:
		return stage.projectWorldToScreen(worldPosition)
	if not is_instance_valid(_boardRoot) or not _boardRoot.is_inside_tree():
		return Vector2(-1.0, -1.0)
	var camera := _boardRoot.get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(worldPosition):
		return Vector2(-1.0, -1.0)
	return camera.unproject_position(worldPosition)


func _stage() -> Node:
	if not is_instance_valid(_boardRoot):
		return null
	var node: Node = _boardRoot.get_parent()
	while node != null:
		if node.has_method("projectWorldToScreen"):
			return node
		node = node.get_parent()
	return null


# --- lifetime and diagnostics -----------------------------------------------

func dispose() -> void:
	if _disposed:
		return
	for monsterID in _rows.keys():
		var row = _rows[monsterID]
		if is_instance_valid(row):
			_removedCount += 1
	_rows.clear()
	_leaving.clear()
	_disposed = true
	if is_instance_valid(_boardRoot) and _boardRoot.tree_entered.is_connected(_attach):
		_boardRoot.tree_entered.disconnect(_attach)
	set_process(false)
	queue_free()


func rowFor(monsterID: int) -> Control:
	var row = _rows.get(monsterID)
	return row if row != null and is_instance_valid(row) else null


func rowCount() -> int:
	return _rows.size()


func createdCount() -> int:
	return _createdCount


func removedCount() -> int:
	return _removedCount


func isDisposed() -> bool:
	return _disposed
