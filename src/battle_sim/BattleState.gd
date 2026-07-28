## BattleState — Holds all runtime state for a battle in progress.
## Pure data container, no logic beyond accessors.

class_name BattleState

const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")

var boardSize: Vector2i
var board: Matrix                        # Monster ID layer (0 = empty)
var heightBoard: Matrix                  # Height layer (for future use)
var terrainBoard: Matrix                 # Terrain ID layer
var mapName: String = ""
var mapRevision: int = 1

enum {
	TERRAIN_CLEAR = 0,     # Walkable, allows LoS
	TERRAIN_OBSTACLE = 1,  # Unwalkable, blocks LoS (Trees/Walls)
	TERRAIN_ABYSS = 2      # Unwalkable, allows LoS (Water/Pits)
}

var monsters: Dictionary = {}            # monsterID -> Monster
var monsterPositions: Dictionary = {}    # monsterID -> Vector2i (reverse lookup)
var teamRosters: Dictionary = {}         # team -> Array[monsterID]

var roundCount: int = 0
var turnCount: int = 0
var currentMonsterID: int = -1

# monsterID -> Array[StatusEffect dict]
# Each effect: { "name", "remainingTurns", "sourceMonsterID", "sourceSpellName", "damagePerTurn" }
var activeEffects: Dictionary = {}

var rng: RandomNumberGenerator
var battleSeed: int = 0
var nextMonsterID: int = 100

var history: Array[Dictionary] = []
var last_turn_start_index: Dictionary = {}


func _init(seedValue: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	setSeed(seedValue)


func setSeed(seedValue: int) -> void:
	battleSeed = seedValue
	rng.seed = seedValue


func allocateMonsterID() -> int:
	var monsterID = nextMonsterID
	nextMonsterID += 1
	return monsterID

func setup_board(size: Vector2i) -> void:
	boardSize = size
	board = Matrix.new(size.x, size.y)
	heightBoard = Matrix.new(size.x, size.y)
	terrainBoard = Matrix.new(size.x, size.y)



# --- Monster registry ---

func addMonster(monster: Monster, pos: Vector2i, team: int) -> void:
	var id = monster.uniqueID
	if not withinBounds(pos):
		push_error("Cannot add monster %d outside the board at %s." % [id, pos])
		return
	if isOccupied(pos):
		push_error("Cannot add monster %d to occupied tile %s." % [id, pos])
		return
	monsters[id] = monster
	monsterPositions[id] = pos
	monster.team = team
	monster.position = pos
	board.set_at(id, pos)

	if not teamRosters.has(team):
		teamRosters[team] = []
	teamRosters[team].append(id)
	assertValidOccupancy()


func removeMonster(monsterID: int) -> void:
	if not monsters.has(monsterID):
		return
	var mon = monsters[monsterID]
	var pos = monsterPositions[monsterID]
	board.set_at(0, pos)
	monsterPositions.erase(monsterID)
	activeEffects.erase(monsterID)
	if teamRosters.has(mon.team):
		teamRosters[mon.team].erase(monsterID)
	# Keep the monster in the monsters dict for reference, but mark as defeated
	# (is_alive will return false)
	assertValidOccupancy()


func getMonster(monsterID: int) -> Monster:
	if monsters.has(monsterID):
		return monsters[monsterID]
	return null


func getMonsterAt(pos: Vector2i) -> Monster:
	var id = board.at(pos)
	if id != 0 and monsters.has(id):
		return monsters[id]
	return null


func getMonsterPosition(monsterID: int) -> Vector2i:
	if monsterPositions.has(monsterID):
		return monsterPositions[monsterID]
	return Vector2i(-1, -1)


func moveMonsterTo(monsterID: int, newPos: Vector2i) -> void:
	if not monsterPositions.has(monsterID):
		push_error("Cannot move unplaced monster %d." % monsterID)
		return
	if not withinBounds(newPos):
		push_error("Cannot move monster %d outside the board to %s." % [monsterID, newPos])
		return
	var destinationOccupant = board.at(newPos)
	if destinationOccupant != 0 and destinationOccupant != monsterID:
		push_error(
			"Tile %s is occupied by monster %d; monster %d cannot enter it." %
			[newPos, destinationOccupant, monsterID]
		)
		return
	var oldPos = monsterPositions[monsterID]
	board.set_at(0, oldPos)
	board.set_at(monsterID, newPos)
	monsterPositions[monsterID] = newPos
	monsters[monsterID].position = newPos
	assertValidOccupancy()


func assertValidOccupancy() -> void:
	var occupiedTiles: Dictionary = {}
	for monsterID in monsterPositions:
		var pos: Vector2i = monsterPositions[monsterID]
		assert(withinBounds(pos), "Monster %d has out-of-bounds position %s." % [monsterID, pos])
		assert(
			not occupiedTiles.has(pos),
			"Monsters %d and %d share forbidden tile %s." %
			[occupiedTiles.get(pos, -1), monsterID, pos]
		)
		assert(
			board.at(pos) == monsterID,
			"Board/position mismatch for monster %d at %s." % [monsterID, pos]
		)
		occupiedTiles[pos] = monsterID

	for y in range(boardSize.y):
		for x in range(boardSize.x):
			var pos = Vector2i(x, y)
			var occupant = board.at(pos)
			if occupant == 0:
				continue
			assert(
				monsterPositions.has(occupant) and monsterPositions[occupant] == pos,
				"Board occupant %d at %s has no matching position." % [occupant, pos]
			)


# --- Board queries ---

func withinBounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < boardSize.x and pos.y >= 0 and pos.y < boardSize.y


func isOccupied(pos: Vector2i) -> bool:
	return board.at(pos) != 0

func getHeight(pos: Vector2i) -> int:
	if not withinBounds(pos):
		return -1
	return int(heightBoard.at(pos))


func getHeightDifference(fromPos: Vector2i, toPos: Vector2i) -> int:
	if not withinBounds(fromPos) or not withinBounds(toPos):
		return 999
	return abs(getHeight(toPos) - getHeight(fromPos))



func isWalkable(pos: Vector2i) -> bool:
	var terrain = terrainBoard.at(pos)
	if terrain == TERRAIN_OBSTACLE or terrain == TERRAIN_ABYSS:
		return false
	return true


func isLoSBlocked(pos: Vector2i) -> bool:
	return terrainBoard.at(pos) == TERRAIN_OBSTACLE


# --- Team queries ---

func getAliveMonsterIDs(team: int = -1) -> Array:
	var result = []
	for id in monsters:
		var mon = monsters[id]
		if mon.is_alive() and (team == -1 or mon.team == team):
			result.append(id)
	return result


func isTeamDefeated(team: int) -> bool:
	if not teamRosters.has(team):
		return true
	for id in teamRosters[team]:
		if monsters[id].is_alive():
			return false
	return true


# --- Status effects ---

func addEffect(monsterID: int, effectName: String, duration: int,
		sourceMonsterID: int = -1, sourceSpellName: String = "",
		damagePerTurn: int = 0, effectData: Dictionary = {}) -> void:
	## Applies a status effect. Rich struct includes source and damage info.
	if not activeEffects.has(monsterID):
		activeEffects[monsterID] = []

	# Prevent duplicate effect stacking — refresh duration instead
	for effect in activeEffects[monsterID]:
		if effect["name"] == effectName:
			effect["remainingTurns"] = max(effect["remainingTurns"], duration)
			effect["sourceMonsterID"] = sourceMonsterID
			effect["sourceSpellName"] = sourceSpellName
			effect["damagePerTurn"] = damagePerTurn
			for key in effectData:
				effect[key] = _mergedEffectValue(effect.get(key), effectData[key])
			return

	var newEffect = {
		"name": effectName,
		"remainingTurns": duration,
		"sourceMonsterID": sourceMonsterID,
		"sourceSpellName": sourceSpellName,
		"damagePerTurn": damagePerTurn
	}
	for key in effectData:
		newEffect[key] = effectData[key]
	activeEffects[monsterID].append(newEffect)


func _mergedEffectValue(existingValue, incomingValue):
	## On refresh, a numeric bonus keeps whichever value has the greater
	## magnitude, preserving its sign, so re-casting a weaker buff or debuff
	## cannot downgrade a stronger one already active. Anything non-numeric, or
	## a key applied for the first time, always takes the incoming value.
	var existingIsNumeric = existingValue is int or existingValue is float
	var incomingIsNumeric = incomingValue is int or incomingValue is float
	if not existingIsNumeric or not incomingIsNumeric:
		return incomingValue
	return incomingValue if absf(float(incomingValue)) >= absf(float(existingValue)) else existingValue


func removeEffect(monsterID: int, effectName: String) -> void:
	if not activeEffects.has(monsterID):
		return

	var remaining = []
	for effect in activeEffects[monsterID]:
		if effect["name"] != effectName:
			remaining.append(effect)

	activeEffects[monsterID] = remaining


func hasEffect(monsterID: int, effectName: String) -> bool:
	if not activeEffects.has(monsterID):
		return false

	for effect in activeEffects[monsterID]:
		if effect["name"] == effectName:
			return true

	return false


func getActiveEffects(monsterID: int) -> Array:
	## Returns the full effect list for a monster (empty array if none).
	return activeEffects.get(monsterID, [])

# --- Event Ledger (History) ---

func add_event(type: String, actor_id: int, target_id: int, data: Dictionary = {}) -> void:
	history.append({
		"round": roundCount,
		"turn": turnCount,
		"type": type,
		"actor_id": actor_id,
		"target_id": target_id,
		"data": data
	})

func get_events_for_actor_since_last_turn(actor_id: int, event_type: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var start_idx = last_turn_start_index.get(actor_id, 0)

	for i in range(start_idx, history.size()):
		var ev = history[i]
		if ev["type"] == event_type and ev["actor_id"] == actor_id:
			results.append(ev)

	return results


func tickEffects(monsterID: int) -> Array:
	## Decrements all effects on this monster by 1 turn.
	## Returns an array of FULL expired effect dicts (for logging).
	var expired = []
	if not activeEffects.has(monsterID):
		return expired

	var remaining = []
	for effect in activeEffects[monsterID]:
		effect["remainingTurns"] -= 1
		if effect["remainingTurns"] <= 0:
			expired.append(effect)
		else:
			remaining.append(effect)

	activeEffects[monsterID] = remaining
	return expired

func serialize_state() -> Dictionary:
	return BattleStateSerializerScript.serialize(self)
