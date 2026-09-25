## Shared elevation arithmetic for direct attacks, spells, and AI estimates.

class_name DirectDamageRules
extends RefCounted


static func elevationPercent(state: BattleState, attackerID: int, targetID: int) -> int:
	return elevationPercentFromPositions(
		state,
		state.getMonsterPosition(attackerID),
		state.getMonsterPosition(targetID)
	)


static func applyElevation(
		state: BattleState,
		rawDamage: int,
		attackerID: int,
		targetID: int) -> int:
	var percent = elevationPercent(state, attackerID, targetID)
	return maxi(1, int(floor(float(rawDamage * percent + 50) / 100.0)))
static func elevationPercentFromPositions(
		state: BattleState,
		attackerPos: Vector2i,
		targetPos: Vector2i) -> int:
	var attackerHeight = state.getHeight(attackerPos)
	var targetHeight = state.getHeight(targetPos)
	if attackerHeight > targetHeight:
		return 110
	if attackerHeight < targetHeight:
		return 90
	return 100


static func applyElevationFromPositions(
		state: BattleState,
		rawDamage: int,
		attackerPos: Vector2i,
		targetPos: Vector2i) -> int:
	var percent = elevationPercentFromPositions(state, attackerPos, targetPos)
	return maxi(1, int(floor(float(rawDamage * percent + 50) / 100.0)))
