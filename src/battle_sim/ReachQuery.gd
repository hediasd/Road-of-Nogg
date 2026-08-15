## Where a unit can move this turn, and everything it could strike from there.
##
## Pure composition over `MovementResolver` and `CombatResolver`: it reads their
## existing queries and mutates nothing. It exists so the player's own move
## preview and the hover reach overlay cannot drift apart — both are answering
## the same question about a unit, and the answer should have one definition
## rather than two similar loops in two files.
##
## Headless by the same rule as the rest of `src/battle_sim/`: no node types, no
## presentation dependency. Callers decide how to draw the result.

class_name ReachQuery
extends RefCounted


## `{"reachable": Array[Vector2i], "attackable": Array[Vector2i]}`.
##
## Reachable always contains the unit's current tile — staying put is a legal
## outcome of a move phase, and a preview that omitted the tile the unit is
## standing on would read as "you cannot remain here".
##
## Attackable is the union of basic-attack targets from every reachable
## destination, deduplicated. It deliberately still contains tiles that are also
## reachable; separating the two tints is the drawing layer's decision, and
## `GodotVisualAdapter.show_movement_options` already excludes the overlap so
## movement stays the stronger signal.
static func forMonster(sim, monsterID: int) -> Dictionary:
	var empty := {"reachable": [], "attackable": []}
	if sim == null or monsterID == -1:
		return empty
	var monster = sim.state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return empty

	var reachable: Array = sim.movementResolver.getReachablePositions(monsterID)
	var currentPos: Vector2i = sim.state.getMonsterPosition(monsterID)
	if not reachable.has(currentPos):
		reachable.append(currentPos)

	var attackable: Array = []
	var seen: Dictionary = {}
	for fromPos in reachable:
		for targetPos in sim.combatResolver.getBasicAttackTargetPositionsFrom(
			monsterID, fromPos
		):
			if seen.has(targetPos):
				continue
			seen[targetPos] = true
			attackable.append(targetPos)

	return {"reachable": reachable, "attackable": attackable}
