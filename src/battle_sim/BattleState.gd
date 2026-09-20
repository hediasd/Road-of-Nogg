## BattleState — Holds all runtime state for a battle in progress.
## Pure data container, no logic beyond accessors.

class_name BattleState

const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")

var boardSize: Vector2i
var board: Matrix                        # Monster ID layer (0 = empty)
var heightBoard: Matrix                  # Height layer (for future use)
var terrainBoard: Matrix                 # Terrain ID layer
var movementCostBoard: Matrix            # Movement-cost layer (0 = impassable)
var mapName: String = ""
var mapRevision: int = 1
var battleMap: BattleMapDefinition

enum {
	TERRAIN_CLEAR = 0,     # Walkable, allows LoS
	TERRAIN_OBSTACLE = 1,  # Unwalkable, blocks LoS (Trees/Walls)
	TERRAIN_ABYSS = 2      # Unwalkable, allows LoS (Water/Pits)
}

var monsters: Dictionary = {}            # monsterID -> Monster
var monsterPositions: Dictionary = {}    # monsterID -> Vector2i (reverse lookup)
var teamRosters: Dictionary = {}         # team -> Array[monsterID]
var parties: Dictionary = {}             # partyID -> BattleParty
var monsterPartyIDs: Dictionary = {}     # monsterID -> partyID
var teamPartyIDs: Dictionary = {}        # teamID -> Array[partyID]
var partyOrder: Array[int] = []           # Stable authored party order; parties do not schedule turns.
var sideOrder: Array[int] = []            # Frozen team order for the current round
var pendingSideIDs: Array[int] = []       # Sides not yet opened this round
var activeSideID: int = -1
var spentUnitIDs: Dictionary = {}         # monsterID -> true for this side turn
var pendingUnitTurns: Dictionary = {}     # monsterID -> moved-but-unspent turn state
var withdrawnPartyIDs: Dictionary = {}
var withdrawnMonsterIDs: Dictionary = {}
var sideTurnCount: int = 0
var sideTurnPhase: String = "idle"
var battleOutcome: int = -1

# Transitional read surface for the pre-side-turn controller. These values no
# longer schedule play and remain idle until that controller is replaced.
var activePartyID: int = -1
var spentMemberIDs: Dictionary = {}
var pendingPartyIDs: Array[int] = []
var activationCount: int = 0
var activationPhase: String = "idle"

var gridKind: String = ""
var coordinateConvention: String = ""
var rulesetID: String = ""
var scenarioID: String = ""
var scenarioRevision: int = 0
var scenarioPath: String = ""
var contentFingerprint: String = ""

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

## Scheduling identity is deliberately outside serialized gameplay state.
## Restoring an equal position on another branch must retire old AI work.
var mutationRevision: int = 0
var timelineGeneration: int = 0


func _init(seedValue: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	setSeed(seedValue)


func setSeed(seedValue: int) -> void:
	battleSeed = seedValue
	rng.seed = seedValue
	markMutation()


func markMutation() -> void:
	mutationRevision += 1


func allocateMonsterID() -> int:
	var monsterID = nextMonsterID
	nextMonsterID += 1
	markMutation()
	return monsterID

func setup_board(size: Vector2i) -> void:
	markMutation()
	battleMap = null
	boardSize = size
	board = Matrix.new(size.x, size.y)
	heightBoard = Matrix.new(size.x, size.y)
	terrainBoard = Matrix.new(size.x, size.y)
	movementCostBoard = Matrix.new(size.x, size.y)
	for y in range(size.y):
		for x in range(size.x):
			movementCostBoard.set_at(1, Vector2i(x, y))


func setBattleMap(definition: BattleMapDefinition) -> void:
	assert(definition != null, "Battle map definition is required.")
	setup_board(definition.boardSize)
	battleMap = definition
	mapName = definition.mapID
	mapRevision = definition.revision
	gridKind = definition.gridKind
	coordinateConvention = definition.coordinateConvention
	for y in range(boardSize.y):
		for x in range(boardSize.x):
			movementCostBoard.set_at(0, Vector2i(x, y))
	for cell: Vector2i in definition.validCells():
		heightBoard.set_at(definition.heightAt(cell), cell)
		terrainBoard.set_at(definition.terrainStateCodeAt(cell), cell)
		movementCostBoard.set_at(definition.movementCostAt(cell), cell)
	markMutation()


func setTerrainState(pos: Vector2i, terrainCode: int) -> void:
	assert(containsCell(pos), "Terrain change requires a valid hex cell.")
	terrainBoard.set_at(terrainCode, pos)
	markMutation()


func setHeight(pos: Vector2i, height: int) -> void:
	assert(containsCell(pos) and height >= 0 and height <= 8,
		"Height change requires a valid hex cell and height 0-8.")
	heightBoard.set_at(height, pos)
	markMutation()


func setMovementCost(pos: Vector2i, cost: int) -> void:
	assert(containsCell(pos) and cost >= 0,
		"Movement-cost change requires a valid hex cell and nonnegative cost.")
	movementCostBoard.set_at(cost, pos)
	markMutation()


func setMonsterAbilities(monsterID: int, spellSets: Array, passiveSkills: Array) -> void:
	var monster: Monster = getMonster(monsterID)
	assert(monster != null, "Cannot replace abilities for an unknown monster.")
	var copiedSpellSets: Array = []
	for spellSet in spellSets:
		var copiedSet: Array = []
		for spell in spellSet:
			assert(spell is Spell, "Ability loadout contains a non-spell value.")
			var copy = Spell.new({})
			copy.restoreRuntime(spell.serializeRuntime())
			copiedSet.append(copy)
		copiedSpellSets.append(copiedSet)
	var copiedPassives: Array = []
	for passive in passiveSkills:
		assert(passive is PassiveSkill, "Ability loadout contains a non-passive value.")
		var copy = PassiveSkill.new({})
		copy.restoreRuntime(passive.serializeRuntime())
		copiedPassives.append(copy)
	monster.spellSets = copiedSpellSets
	monster.passives = copiedPassives
	markMutation()


func registerParty(party: BattleParty) -> void:
	assert(party != null, "Battle party is required.")
	assert(not parties.has(party.partyID), "Duplicate party ID %d." % party.partyID)
	parties[party.partyID] = party
	partyOrder.append(party.partyID)
	if not teamPartyIDs.has(party.teamID):
		teamPartyIDs[party.teamID] = []
	teamPartyIDs[party.teamID].append(party.partyID)
	for memberID: int in party.memberIDs:
		assert(not monsterPartyIDs.has(memberID), "Monster %d belongs to multiple parties." % memberID)
		monsterPartyIDs[memberID] = party.partyID
	markMutation()


func partyForMember(monsterID: int) -> BattleParty:
	return parties.get(int(monsterPartyIDs.get(monsterID, -1)))


func isMonsterWithdrawn(monsterID: int) -> bool:
	return withdrawnMonsterIDs.has(monsterID)


func isPartyWithdrawn(partyID: int) -> bool:
	return withdrawnPartyIDs.has(partyID)


func isPartySurviving(partyID: int) -> bool:
	var party: BattleParty = parties.get(partyID)
	if party == null or isPartyWithdrawn(partyID):
		return false
	var commander: Monster = getMonster(party.commanderID)
	return commander != null and commander.is_alive() and not isMonsterWithdrawn(party.commanderID)


func eligibleMemberIDs(partyID: int = activePartyID) -> Array[int]:
	var result: Array[int] = []
	var party: BattleParty = parties.get(partyID)
	if party == null or not isPartySurviving(partyID):
		return result
	for memberID: int in party.memberIDs:
		var monster: Monster = getMonster(memberID)
		if (
			monster != null
			and monster.is_alive()
			and monsterPositions.has(memberID)
			and not isMonsterWithdrawn(memberID)
			and not spentMemberIDs.has(memberID)
		):
			result.append(memberID)
	return result


func eligibleUnitIDs(sideID: int = activeSideID) -> Array[int]:
	var result: Array[int] = []
	if sideID < 0 or not teamRosters.has(sideID):
		return result
	for monsterIDValue in teamRosters[sideID]:
		var monsterID := int(monsterIDValue)
		var monster: Monster = getMonster(monsterID)
		if (
			monster != null
			and monster.is_alive()
			and monsterPositions.has(monsterID)
			and not isMonsterWithdrawn(monsterID)
			and not spentUnitIDs.has(monsterID)
		):
			result.append(monsterID)
	result.sort()
	return result


func withdrawMonster(monsterID: int) -> void:
	if withdrawnMonsterIDs.has(monsterID):
		return
	withdrawnMonsterIDs[monsterID] = true
	if monsterPositions.has(monsterID):
		var position: Vector2i = monsterPositions[monsterID]
		board.set_at(0, position)
		monsterPositions.erase(monsterID)
		var monster: Monster = getMonster(monsterID)
		if monster != null:
			monster.position = Vector2i(-1, -1)
	assertValidOccupancy()
	markMutation()



# --- Monster registry ---

func addMonster(monster: Monster, pos: Vector2i, team: int) -> void:
	var id = monster.uniqueID
	if not containsCell(pos):
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
	markMutation()


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
	markMutation()


func getMonster(monsterID: int) -> Monster:
	if monsters.has(monsterID):
		return monsters[monsterID]
	return null


func getMonsterAt(pos: Vector2i) -> Monster:
	if not containsCell(pos):
		return null
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
	if not containsCell(newPos):
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
	markMutation()


func assertValidOccupancy() -> void:
	var occupiedTiles: Dictionary = {}
	for monsterID in monsterPositions:
		var pos: Vector2i = monsterPositions[monsterID]
		assert(containsCell(pos), "Monster %d has invalid position %s." % [monsterID, pos])
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


func containsCell(pos: Vector2i) -> bool:
	if not withinBounds(pos):
		return false
	return battleMap == null or battleMap.containsCell(pos)


func isOccupied(pos: Vector2i) -> bool:
	if not containsCell(pos):
		return false
	return board.at(pos) != 0

func getHeight(pos: Vector2i) -> int:
	if not containsCell(pos):
		return -1
	return int(heightBoard.at(pos))


func getHeightDifference(fromPos: Vector2i, toPos: Vector2i) -> int:
	if not containsCell(fromPos) or not containsCell(toPos):
		return 999
	return abs(getHeight(toPos) - getHeight(fromPos))



func isWalkable(pos: Vector2i) -> bool:
	if not containsCell(pos):
		return false
	if battleMap != null:
		return battleMap.isTraversable(pos)
	var terrain = terrainBoard.at(pos)
	if terrain == TERRAIN_OBSTACLE or terrain == TERRAIN_ABYSS:
		return false
	return true


func isLoSBlocked(pos: Vector2i) -> bool:
	if not containsCell(pos):
		return false
	if battleMap != null:
		return battleMap.blocksLineOfSight(pos)
	return terrainBoard.at(pos) == TERRAIN_OBSTACLE


# --- Team queries ---

func getAliveMonsterIDs(team: int = -1) -> Array:
	var result = []
	for id in monsters:
		var mon = monsters[id]
		if (
			mon.is_alive()
			and not isMonsterWithdrawn(int(id))
			and monsterPositions.has(id)
			and (team == -1 or mon.team == team)
		):
			result.append(id)
	return result


func isTeamDefeated(team: int) -> bool:
	if not parties.is_empty():
		if not teamPartyIDs.has(team):
			return true
		for partyID: int in teamPartyIDs[team]:
			if isPartySurviving(partyID):
				return false
		return true
	if not teamRosters.has(team):
		return true
	for id in teamRosters[team]:
		if monsters[id].is_alive():
			return false
	return true


# --- Status effects ---

## Some effects are authored as permanent by giving them a duration no battle can
## outlast — `Timeoff`'s speed debuff is the current example, at 999. That is a
## real mechanic and the ticking is correct, but the raw number is not something
## to show a player, and it counts down (998, 997, ...) as the battle runs.
## Anything at or above this threshold is a sentinel, not a turn count: authored
## durations are single digits and `runFullBattle` caps well below it.
const PERMANENT_EFFECT_THRESHOLD := 100


static func isPermanentDuration(remainingTurns: int) -> bool:
	return remainingTurns >= PERMANENT_EFFECT_THRESHOLD


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
				effect[key] = mergedEffectValue(effect.get(key), effectData[key])
			markMutation()
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
	markMutation()


static func mergedEffectValue(existingValue, incomingValue):
	## On refresh, a numeric bonus keeps whichever value has the greater
	## magnitude, preserving its sign, so re-casting a weaker buff or debuff
	## cannot downgrade a stronger one already active. Anything non-numeric, or
	## a key applied for the first time, always takes the incoming value.
	## Public and side-effect free so forecasts can model the same merge without
	## copying or mutating the live effect array.
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
	markMutation()


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
	markMutation()

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
	markMutation()
	return expired

func serialize_state() -> Dictionary:
	return BattleStateSerializerScript.serialize(self)
