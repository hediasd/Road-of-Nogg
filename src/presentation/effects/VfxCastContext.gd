## Immutable-by-convention presentation snapshot supplied to every spell VFX.
## Gameplay emits only stable identities and board coordinates; the visual
## adapter resolves those into world-space positions and model-local bounds.
class_name VfxCastContext
extends RefCounted

## Generic monster volume used when a target visual is absent or already freed.
## It is centered on the event impact position by the consuming effect.
const DEFAULT_TARGET_BODY_BOUNDS := AABB(
	Vector3(-0.35, 0.2, -0.35),
	Vector3(0.7, 1.3, 0.7)
)

var source_monster_id: int = -1
var source_world_position: Vector3 = Vector3.ZERO
var impact_world_position: Vector3 = Vector3.ZERO
var target_ids: Array[int] = []
var target_world_positions: Array[Vector3] = []
var target_body_bounds: Array[AABB] = []


static func create(
		sourceMonsterID: int,
		sourceWorldPosition: Vector3,
		impactWorldPosition: Vector3,
		targetIDs: Array[int],
		targetWorldPositions: Array[Vector3],
		targetBodyBounds: Array[AABB]) -> VfxCastContext:
	var context := VfxCastContext.new()
	context.source_monster_id = sourceMonsterID
	context.source_world_position = sourceWorldPosition
	context.impact_world_position = impactWorldPosition
	context.target_ids.assign(targetIDs)
	context.target_world_positions.assign(targetWorldPositions)
	context.target_body_bounds.assign(targetBodyBounds)
	context.assert_valid()
	return context


func assert_valid() -> void:
	assert(
		target_ids.size() == target_world_positions.size(),
		"VFX cast context target IDs and positions must stay aligned."
	)
	assert(
		target_ids.size() == target_body_bounds.size(),
		"VFX cast context target IDs and body bounds must stay aligned."
	)
