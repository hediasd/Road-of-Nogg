## BattleSimulator — Main orchestrator for the battle simulation.
## Initializes all subsystems, spawns monsters, runs the game loop.
## Pure logic — can run without Godot visuals.

class_name BattleSimulator

var state: BattleState
var events: BattleEvents
var turnManager: TurnManager
var movementResolver: MovementResolver
var combatResolver: CombatResolver
var passiveSkillResolver: PassiveSkillResolver
var visualAdapter: IBattleVisualAdapter

var brains: Dictionary = {}  # monsterID -> EntityBrain


func _init(boardSize: Vector2i) -> void:
	events = BattleEvents.new()
	state = BattleState.new(boardSize)
	turnManager = TurnManager.new(state, events)
	movementResolver = MovementResolver.new(state, events)
	combatResolver = preload("res://src/battle_sim/CombatResolver.gd").new(state, events)
	passiveSkillResolver = preload("res://src/battle_sim/PassiveSkillResolver.gd").new(state, events)
	print("DEBUG: passiveSkillResolver created? ", passiveSkillResolver)
	# Inject passiveSkillResolver into CombatResolver
	combatResolver.passiveSkillResolver = passiveSkillResolver


func setVisualAdapter(adapter: IBattleVisualAdapter) -> void:
	visualAdapter = adapter
	adapter.connectToEvents(events)


func setSeed(seedValue: int) -> void:
	## Forces the battle state RNG to use a specific seed for deterministic outcomes.
	state.rng.seed = seedValue



func spawnMonster(referenceName: String, team: int, pos: Vector2i) -> Monster:
	## Creates a monster from references and places it on the board.
	var monster = MonsterFactory.createMonster(referenceName)
	var ref = MonsterReferences.getReference(referenceName)

	# Resolve brain class
	var brainClassName = ref.get("BRAIN", "MeleeBrain")
	var brainClass = _resolveBrainClass(brainClassName)
	
	# Fatal checks: Do not allow spawning on invalid/occupied tiles
	assert(state.withinBounds(pos), "Fatal Error: Spawning monster out of bounds at %s" % str(pos))
	assert(state.isWalkable(pos), "Fatal Error: Attempting to spawn monster on an unwalkable tile at %s" % str(pos))
	assert(not state.isOccupied(pos), "Fatal Error: Attempting to spawn monster on an already occupied tile at %s" % str(pos))

	# Create and assign brain
	var brain = brainClass.new(state, movementResolver, combatResolver)
	monster.brain = brain
	brains[monster.uniqueID] = brain

	# Place on board
	state.addMonster(monster, pos, team)

	# Emit event
	var stats = {
		"hp": monster.hitpoints,
		"atk": monster.atk,
		"def": monster.def,
		"spd": monster.speed,
		"move": monster.move
	}
	events.monster_spawned.emit(monster.uniqueID, monster.name, team, pos, stats)

	return monster


func _resolveBrainClass(name: String):
	match name:
		"BerserkBrain": return load("res://src/entity_ai/BerserkBrain.gd")
		"TacticalBrain": return load("res://src/entity_ai/TacticalBrain.gd")
		"MageBrain":    return load("res://src/entity_ai/MageBrain.gd")
		"SupportBrain": return load("res://src/entity_ai/SupportBrain.gd")
		_:              return load("res://src/entity_ai/TacticalBrain.gd")


func startBattle() -> void:
	## Emits battle_started and begins the first round.
	var monsterList = []
	for id in state.monsters:
		monsterList.append(id)
	events.battle_started.emit(state.boardSize, monsterList)


func runFullBattle(maxRounds: int = 50) -> int:
	## Runs the entire battle automatically (AI vs AI).
	## Returns the winning team number.
	startBattle()

	for round in range(maxRounds):
		turnManager.startNewRound()
		var actions_this_round = 0

		while turnManager.hasNextTurn():
			var monsterID = turnManager.startNextTurn()
			if monsterID == -1:
				break

			var acted = executeTurn(monsterID)
			if acted:
				actions_this_round += 1

			turnManager.endTurn(monsterID)

			# Check win condition after each turn
			var winner = checkWinCondition()
			if winner != -1:
				events.battle_ended.emit(winner)
				return winner
		
		events.round_ended.emit(state.roundCount)
		
		# Loop detector
		if actions_this_round == 0:
			print("Loop detector: No actions taken this round. Ending battle early.")
			break

	# If we hit max rounds or loop detected, the team with more alive monsters wins
	var winner = _determineWinnerByNumbers()
	events.battle_ended.emit(winner)
	return winner


func executeTurn(monsterID: int) -> bool:
	## Executes a single monster's turn using its brain.
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return false
		
	var brain = brains.get(monsterID)
	if brain == null:
		return false

	if state.hasEffect(monsterID, "petrify"):
		events.monster_skipped_turn.emit(monsterID, "petrify")
		# Phase 3: Apply status effect damage (even if skipped)
		combatResolver.executeStatusEffectDamage(monsterID)
		return false

	var decision = brain.decideTurn(monsterID)
	var acted = false

	# Phase 1: Move
	if decision.has("move_path") and not decision["move_path"].is_empty():
		movementResolver.executeMove(monsterID, decision["move_path"])
		acted = true

	# Phase 2: Act
	var action = decision.get("action", "wait")
	var targetID = decision.get("target_id", -1)

	if action == "attack" and targetID != -1:
		combatResolver.executeBasicAttack(monsterID, targetID)
		acted = true

	elif action == "spell" and targetID != -1:
		var spellSetIdx = decision.get("spell_set_index", 0)
		var spellIdx = decision.get("spell_index", 0)
		combatResolver.executeCastSpell(monsterID, targetID, spellSetIdx, spellIdx)
		acted = true
		
	# Phase 3: Fire ON_TURN_END event (status effect damage ticks + passive hooks)
	passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
	
	return acted


func checkWinCondition() -> int:
	## Returns the winning team number, or -1 if the battle continues.
	var aliveTeams = []
	for team in state.teamRosters:
		if not state.isTeamDefeated(team):
			aliveTeams.append(team)

	if aliveTeams.size() == 1:
		return aliveTeams[0]
	if aliveTeams.is_empty():
		return 0  # Draw (shouldn't happen normally)

	return -1


func _determineWinnerByNumbers() -> int:
	## Fallback: team with most alive monsters wins.
	var bestTeam = -1
	var bestCount = -1
	for team in state.teamRosters:
		var alive = state.getAliveMonsterIDs(team)
		if alive.size() > bestCount:
			bestCount = alive.size()
			bestTeam = team
	return bestTeam
