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
	turnOrder.sort_custom(func(a, b):
		var spd_a = state.getMonster(a).speed
		for effect in state.getActiveEffects(a):
			spd_a += effect.get("spd_bonus", 0)
			
		var spd_b = state.getMonster(b).speed
		for effect in state.getActiveEffects(b):
			spd_b += effect.get("spd_bonus", 0)
			
		if spd_a == spd_b:
			return a < b
		return spd_a > spd_b
	)


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
