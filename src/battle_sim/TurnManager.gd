## TurnManager — Manages turn order, round transitions, and effect ticking.
## Pure logic, no Node dependency.

class_name TurnManager

var state: BattleState
var events: BattleEvents
var turnOrder: Array = []


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


func startNewRound() -> void:
	state.roundCount += 1
	turnOrder = state.getAliveMonsterIDs()
	sortBySpeed()
	var orderIDs = turnOrder.duplicate()
	events.round_started.emit(state.roundCount, orderIDs)


func sortBySpeed() -> void:
	turnOrder = speedSortedIDs(state, turnOrder)


## Effective speed descending, ties broken by ascending id.
##
## Static and side-effect free so presentation can ask what the *next* round will
## look like without a turn manager and without mutating this one. The turn-order
## rail projects the coming round by calling this on the living set; running the
## same function the simulator runs is what stops a forecast from disagreeing
## with the order that actually resolves — a preview that lies is worse than no
## preview.
static func speedSortedIDs(
		state: BattleState,
		ids: Array,
		pendingEffectsByMonster: Dictionary = {}) -> Array:
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a, b):
		var spd_a = effectiveSpeed(
			state, a, pendingEffectsByMonster.get(int(a), [])
		)
		var spd_b = effectiveSpeed(
			state, b, pendingEffectsByMonster.get(int(b), [])
		)
		if spd_a == spd_b:
			return a < b
		return spd_a > spd_b
	)
	return sorted


static func effectiveSpeed(
		state: BattleState,
		monsterID: int,
		pendingEffectDefinitions: Array = []) -> int:
	var monster = state.getMonster(monsterID)
	if monster == null:
		return 0
	var speed: int = monster.speed
	var speedBonusesByEffect: Dictionary = {}
	for effect in state.getActiveEffects(monsterID):
		var bonus := int(effect.get("spd_bonus", 0))
		speed += bonus
		if bonus != 0:
			speedBonusesByEffect[str(effect.get("name", ""))] = bonus
	for definition in pendingEffectDefinitions:
		if not definition is Dictionary or not definition.has("SPD_BONUS"):
			continue
		var effectName := str(definition.get("NAME", ""))
		if effectName.is_empty():
			continue
		var previousBonus := int(speedBonusesByEffect.get(effectName, 0))
		var mergedBonus := int(BattleState.mergedEffectValue(
			previousBonus if speedBonusesByEffect.has(effectName) else null,
			int(definition["SPD_BONUS"])
		))
		speed += mergedBonus - previousBonus
		speedBonusesByEffect[effectName] = mergedBonus
	return speed


func hasNextTurn() -> bool:
	# Remove any dead monsters that died mid-round
	while not turnOrder.is_empty():
		var nextID = turnOrder.front()
		var mon = state.getMonster(nextID)
		if mon != null and mon.is_alive():
			return true
		turnOrder.pop_front()
	return false


func startNextTurn() -> int:
	## Returns the monster ID whose turn it is.
	## Returns -1 if the round is over.
	if not hasNextTurn():
		return -1

	var monsterID = turnOrder.pop_front()
	state.turnCount += 1
	state.currentMonsterID = monsterID
	state.last_turn_start_index[monsterID] = state.history.size()
	state.add_event("turn_start", monsterID, -1, {"round": state.roundCount, "turn": state.turnCount})
	events.turn_started.emit(monsterID, state.roundCount, state.turnCount)
	return monsterID


func endTurn(monsterID: int) -> void:
	## Called after a monster has finished acting.
	## Ticks durations, and emits events.
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		events.turn_ended.emit(monsterID)
		state.currentMonsterID = -1
		return

	# Phase 1: Tick down remaining durations and collect expired effects
	var expiredEffects = state.tickEffects(monsterID)
	mon.tick_cooldowns()

	for expiredEffect in expiredEffects:
		events.effect_removed.emit(monsterID, expiredEffect["name"])

	# Phase 2: Emit remaining active effects
	for effect in state.getActiveEffects(monsterID):
		events.effect_ticked.emit(monsterID, effect["name"], effect["remainingTurns"])

	events.turn_ended.emit(monsterID)
	state.currentMonsterID = -1
