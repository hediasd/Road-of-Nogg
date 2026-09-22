## One read-only view of the board, shared by every ready actor in a decision.
##
## Scoped to a revision. Anything it hands out was computed from the state as it
## stood when the context opened, so a caller that keeps the context past a
## mutation would be reading answers to an older question. `isCurrent()` says
## whether that has happened; every query refuses once it has, rather than
## quietly serving a stale reachable set.
##
## It is deliberately not a cache that outlives a decision. One context serves
## one side's deliberation and is dropped; the memoizing resolver inside it has
## the same lifetime, which is what makes memoizing line of sight safe.
##
## Keyed by the cheap mutation revision and timeline generation, not by
## serializing every actor. That is only sound while every supported mutation
## goes through a `BattleState` method -- direct writes to a `Monster`'s fields
## bypass it. `debugFingerprint()` is the expensive answer, used by probes to
## prove the cheap key catches what the supported API can do.

class_name DecisionContext
extends RefCounted

const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

var _simulator
var _state: BattleState
var _movementResolver: MovementResolver
var _resolver: CombatResolver
var _revision: Vector2i
var _reachability: Dictionary = {}
var _enemyPositions: Dictionary = {}
var _strikeReach: Dictionary = {}
var _closed: bool = false


## The ordinary way in. A restore replaces the simulator's whole state object
## rather than editing it, so a context that held only the old object would go
## on answering happily about a timeline nobody is playing any more. Holding the
## simulator lets the context see that the board underneath it was swapped.
static func forSimulator(simulator) -> DecisionContext:
	var context := DecisionContext.new(simulator.state, simulator.movementResolver,
		simulator.combatResolver)
	context._simulator = simulator
	return context


## For a detached state with its own resolvers, such as a forecast fork. Such a
## state is never swapped underneath the caller -- the caller owns it -- so
## object identity is not watched here.
static func forState(state: BattleState, movementResolver: MovementResolver,
		combatResolver: CombatResolver) -> DecisionContext:
	return DecisionContext.new(state, movementResolver, combatResolver)


func _init(state: BattleState, movementResolver: MovementResolver,
		combatResolver: CombatResolver) -> void:
	_state = state
	_movementResolver = movementResolver
	_resolver = combatResolver.forDeliberation()
	_revision = revisionOf(state)


## The whole key: which timeline, and how many mutations into it.
static func revisionOf(state: BattleState) -> Vector2i:
	if state == null:
		return Vector2i(-1, -1)
	return Vector2i(state.timelineGeneration, state.mutationRevision)


func revision() -> Vector2i:
	return _revision


func isCurrent() -> bool:
	if _closed:
		return false
	if _simulator != null and _simulator.state != _state:
		return false
	return revisionOf(_state) == _revision


func state() -> BattleState:
	return _state


## The memoizing resolver. Legal questions are asked of the authoritative
## resolver, never re-implemented here.
func resolver() -> CombatResolver:
	return _resolver


func movementResolver() -> MovementResolver:
	return _movementResolver


## Drops the memo. A context is finished explicitly so its line-of-sight memo
## cannot outlive the window in which the board is fixed.
func close() -> void:
	_closed = true
	_resolver = null
	_reachability.clear()
	_enemyPositions.clear()
	_strikeReach.clear()


## Where this actor can stand, computed once per actor per revision. The origin
## is included: standing still is a legal outcome of a move phase.
func reachability(actorID: int) -> Dictionary:
	assert(isCurrent(), "A decision context cannot answer after its revision moved on.")
	if _reachability.has(actorID):
		return _reachability[actorID]
	var computed: Dictionary = _movementResolver.getReachability(actorID)
	var destinations: Array[Vector2i] = []
	for position: Vector2i in computed["positions"]:
		destinations.append(position)
	var origin: Vector2i = _state.getMonsterPosition(actorID)
	if not destinations.has(origin):
		destinations.append(origin)
	destinations.sort_custom(rowMajorLess)
	var entry := {
		"origin": origin,
		"destinations": destinations,
		"costs": computed["costs"],
		"predecessors": computed["predecessors"],
	}
	_reachability[actorID] = entry
	return entry


## The walked path to a destination, from the one search that produced it.
## Empty for the origin; empty as well for a destination no predecessor chain
## reaches, which callers must treat as unreachable rather than as standing put.
func pathTo(actorID: int, destination: Vector2i) -> Array[Vector2i]:
	var entry := reachability(actorID)
	var origin: Vector2i = entry["origin"]
	var path: Array[Vector2i] = []
	if destination == origin:
		return path
	var predecessors: Dictionary = entry["predecessors"]
	var cursor := destination
	while cursor != origin:
		if not predecessors.has(cursor):
			return [] as Array[Vector2i]
		path.append(cursor)
		cursor = predecessors[cursor]
	path.reverse()
	return path


func enemyPositions(actorID: int) -> Array[Vector2i]:
	assert(isCurrent(), "A decision context cannot answer after its revision moved on.")
	if _enemyPositions.has(actorID):
		return _enemyPositions[actorID]
	var actor: Monster = _state.getMonster(actorID)
	var positions: Array[Vector2i] = []
	if actor != null:
		for candidateID in _state.getAliveMonsterIDs():
			if _state.getMonster(candidateID).team != actor.team:
				positions.append(_state.getMonsterPosition(candidateID))
		positions.sort_custom(rowMajorLess)
	_enemyPositions[actorID] = positions
	return positions


## Where one unit could strike, computed once and shared.
##
## A tile-by-tile danger question re-derives this every time it is asked, and a
## side policy asks about dozens of tiles with the same handful of enemies --
## which made re-deriving it the most expensive thing in a decision. The
## **geometry** is cached here because it does not depend on who is standing on
## the tile; the **damage** is not, because it does.
##
## `{"melee": {tile: from_cell}, "spells": {tile: {"set", "index", "from"}}}`.
## Melee records a cell the unit could stand on to reach that tile. Spells are
## recorded only from the unit's own cell, because magic is pre-move.
func strikeReach(monsterID: int) -> Dictionary:
	assert(isCurrent(), "A decision context cannot answer after its revision moved on.")
	if _strikeReach.has(monsterID):
		return _strikeReach[monsterID]
	var monster: Monster = _state.getMonster(monsterID)
	var reach := {"melee": {}, "spells": {}}
	if monster == null or not monster.is_alive():
		_strikeReach[monsterID] = reach
		return reach
	var origin: Vector2i = _state.getMonsterPosition(monsterID)

	var melee: Dictionary = reach["melee"]
	for destination: Vector2i in reachability(monsterID)["destinations"]:
		for neighbour: Vector2i in HexGridScript.neighbours(destination):
			if melee.has(neighbour):
				continue
			if not _resolver.canBasicAttackPositionFrom(monsterID, destination, neighbour):
				continue
			melee[neighbour] = destination

	var spells: Dictionary = reach["spells"]
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell: Spell = monster.spellSets[setIndex][spellIndex]
			if spell.heals or not monster.can_cast(spell):
				continue
			for centerPos: Vector2i in _resolver.getSpellTargetPositionsFrom(
					monsterID, setIndex, spellIndex, origin, true):
				for affected: Vector2i in _resolver.getSpellAffectedPositionsFrom(
						monsterID, setIndex, spellIndex, origin, centerPos, true):
					## Every ability that reaches the tile is kept, not just the
					## one with the largest declared damage: what a spell
					## actually deals depends on the element and the unit
					## standing there, so the hardest-hitting on paper is not
					## always the hardest-hitting here. Recorded once per
					## ability per tile, in ability order.
					if not spells.has(affected):
						spells[affected] = []
					var ways: Array = spells[affected]
					var seen := false
					for way in ways:
						if int(way["set"]) == setIndex and int(way["index"]) == spellIndex:
							seen = true
							break
					if not seen:
						ways.append({"set": setIndex, "index": spellIndex, "from": origin})
	_strikeReach[monsterID] = reach
	return reach


func nearestEnemyDistance(actorID: int, from: Vector2i) -> int:
	var nearest := 999
	for position: Vector2i in enemyPositions(actorID):
		nearest = mini(nearest, HexGridScript.distance(from, position))
	return 0 if nearest == 999 else nearest


## Expensive and for diagnosis only: the full token that also reads every
## actor's fields. A probe compares it against the cheap revision to show that
## supported mutations move both.
func debugFingerprint() -> String:
	return StateRevisionScript.capture(_state)


static func rowMajorLess(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
