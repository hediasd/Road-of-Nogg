extends SceneTree

## FHB-10: a battle that reaches the round cap ends honestly.
##
## Three promises, each on a real battle state built from a small authored scenario rather than a
## hand-made one, and each cheap enough to run without a championship:
##
## - EQUAL ROUNDS. The cap counts whole rounds, so every party still standing at the end has
##   activated exactly once per round. The old loop stopped after the first party of the last round.
## - A TIE IS A DRAW. Equal survivor counts at the cap give team 0, never the first-listed team, and
##   the record says `draw`.
## - NO ZERO-VALUE HEAL. At the start of a battle nobody has lost HP, so no heal can restore
##   anything. The support brain must not choose one, and no heal may outscore waiting on the same
##   cell. The Oracle of Ages used to pick Timeoff here, because its self-inflicted slow counted as
##   a benefit. And a heal on a hurt ally counts only when that ally could fall before acting again.

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const RecordAdapterScript = preload("res://src/presentation/BattleRecordAdapter.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 42
## Short enough that nobody is eliminated, long enough that a one-sided last round shows.
const CAP_ROUNDS := 2
## The support-brain member in the scenario whose spell list holds Timeoff.
const ORACLE_ID := 200

var failures: Array[String] = []
var _scenario


func _init() -> void:
	_checkCapGivesEqualRounds()
	_checkTieIsADraw()
	_checkNoZeroValueHeal()

	if not failures.is_empty():
		for failure in failures:
			printerr("HEX_ROUND_CAP_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX_ROUND_CAP_OK")
	quit(0)


func _buildSim():
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	if not loaded["success"]:
		_require(false, "could not load %s: %s" % [SCENARIO, str(loaded.get("error", ""))])
		return null
	_scenario = loaded["scenario"]
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	if not config.validate().success:
		_require(false, "invalid setup for %s" % SCENARIO)
		return null
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		_require(false, "could not build state: %s" % str(stateResult.get("error", "")))
		return null
	var sim = BattleSimulatorScript.new(SEED)
	sim.configureHexState(stateResult["state"], _scenario, {"scenarioPath": SCENARIO})
	return sim


func _checkCapGivesEqualRounds() -> void:
	var sim = _buildSim()
	if sim == null:
		return
	var recorder = RecordAdapterScript.new(sim)
	recorder.connectToEvents(sim.events)
	sim.emitInitialBoard()
	var winner: int = sim.runFullBattle(CAP_ROUNDS)
	var state = sim.state

	_require(sim.checkWinCondition() == -1,
		"the battle was decided by elimination inside %d rounds, so it never tested the cap" % CAP_ROUNDS)
	_require(int(state.roundCount) == CAP_ROUNDS,
		"the battle stopped at round %d, not the cap of %d" % [int(state.roundCount), CAP_ROUNDS])

	var activations: Dictionary = {}
	var roundEnds: Array[int] = []
	for event: Dictionary in state.history:
		match str(event.get("type", "")):
			"party_activation_start":
				var partyID := int(event.get("actor_id", -1))
				activations[partyID] = int(activations.get(partyID, 0)) + 1
			"round_end":
				roundEnds.append(int((event.get("data", {}) as Dictionary).get("round", -1)))

	var partyIDs: Array = state.parties.keys()
	partyIDs.sort()
	var perTeam: Dictionary = {}
	for partyIDValue in partyIDs:
		var partyID := int(partyIDValue)
		if not state.isPartySurviving(partyID):
			continue
		var count := int(activations.get(partyID, 0))
		_require(count == CAP_ROUNDS,
			"party %d is standing at the cap but activated %d time(s) in %d rounds" % [
				partyID, count, CAP_ROUNDS])
		var team := int((state.parties[partyIDValue] as BattleParty).teamID)
		perTeam[team] = int(perTeam.get(team, 0)) + count
	_require(perTeam.size() >= 2, "fewer than two teams were standing at the cap")
	var totals: Array = perTeam.values()
	for total in totals:
		_require(int(total) == int(totals[0]),
			"the teams standing at the cap had unequal activations: %s" % str(perTeam))
	_require(roundEnds.has(CAP_ROUNDS), "the capped last round was never announced as ended")

	# The tally itself, and what the record says about it.
	var t1: int = state.getAliveMonsterIDs(1).size()
	var t2: int = state.getAliveMonsterIDs(2).size()
	var expected := 0 if t1 == t2 else (1 if t1 > t2 else 2)
	_require(winner == expected, "survivors %d v %d scored as team %d, expected %d" % [t1, t2, winner, expected])
	var outcome: Dictionary = recorder.buildRecord(_scenario).get("outcome", {})
	_require(str(outcome.get("end_reason", "")) == RecordAdapterScript.END_ROUND_LIMIT,
		"the record does not say the battle ended at the round limit: %s" % str(outcome))
	_require(bool(outcome.get("draw", not (expected == 0))) == (expected == 0),
		"the record's draw flag disagrees with the tally: %s" % str(outcome))


## A tie must be a draw whichever team the rosters list first, and a real lead must still win.
func _checkTieIsADraw() -> void:
	var sim = _buildSim()
	if sim == null:
		return
	var state = sim.state
	_require(state.getAliveMonsterIDs(1).size() == state.getAliveMonsterIDs(2).size(),
		"the scenario does not start level, so it cannot test a tie")
	_require(sim._determineWinnerByNumbers() == BattleSimulatorScript.DRAW_TEAM,
		"a level tally at the cap was scored as team %d, not a draw" % sim._determineWinnerByNumbers())

	# Take one non-commander off team 1: team 2 now leads and must win.
	var fallen := _nonCommander(state, 1)
	_require(fallen != -1, "team 1 has no non-commander member to remove")
	if fallen == -1:
		return
	state.getMonster(fallen).hitpoints = 0
	_require(sim._determineWinnerByNumbers() == 2,
		"team 2 led on survivors but was scored as team %d" % sim._determineWinnerByNumbers())

	# And level again, now with team 2 the one listed second: still a draw.
	var fallen2 := _nonCommander(state, 2)
	if fallen2 == -1:
		_require(false, "team 2 has no non-commander member to remove")
		return
	state.getMonster(fallen2).hitpoints = 0
	_require(sim._determineWinnerByNumbers() == BattleSimulatorScript.DRAW_TEAM,
		"a level tally after losses was scored as team %d, not a draw" % sim._determineWinnerByNumbers())


func _nonCommander(state, team: int) -> int:
	var partyIDs: Array = state.parties.keys()
	partyIDs.sort()
	for partyIDValue in partyIDs:
		var party: BattleParty = state.parties[partyIDValue]
		if int(party.teamID) != team:
			continue
		for memberID: int in party.memberIDs:
			if memberID != party.commanderID and state.getMonster(memberID).is_alive():
				return memberID
	return -1


func _checkNoZeroValueHeal() -> void:
	var sim = _buildSim()
	if sim == null:
		return
	var state = sim.state
	for monsterID in state.monsters:
		var monster: Monster = state.getMonster(int(monsterID))
		_require(monster.hitpoints == monster.max_hitpoints,
			"monster %d starts below full HP, so a heal could restore something" % int(monsterID))
	var oracle: Monster = state.getMonster(ORACLE_ID)
	_require(oracle != null and str(sim.brains.get(ORACLE_ID).get_script().get_global_name()) == "SupportBrain",
		"member %d is not a support brain" % ORACLE_ID)
	if oracle == null:
		return
	var hasHeal := false
	for spellSet in oracle.spellSets:
		for spell in spellSet:
			hasHeal = hasHeal or bool(spell.heals)
	_require(hasHeal, "member %d has no heal, so this check proves nothing" % ORACLE_ID)

	var deliberation = sim.beginTurnDeliberation(ORACLE_ID)
	var chosen: BattleCommand = deliberation.run()
	_require(not _isHeal(oracle, chosen),
		"the support brain chose a heal with every monster at full HP: %s" % str(chosen.to_dictionary()))

	# Stronger than the one choice: on every cell, every heal scores below waiting there.
	var waitByCell: Dictionary = {}
	for candidate: Dictionary in deliberation._candidates:
		if (candidate["command"] as BattleCommand).action == "wait":
			waitByCell[_cellKey(candidate)] = int(candidate["score"])
	var heals := 0
	for candidate: Dictionary in deliberation._candidates:
		var command: BattleCommand = candidate["command"]
		if not _isHeal(oracle, command):
			continue
		heals += 1
		var cell := _cellKey(candidate)
		_require(int(candidate["score"]) < int(waitByCell.get(cell, -2147483648)),
			"a heal that restores nothing outscores waiting on cell %s: %s scores %d" % [
				cell, str(candidate["tie_key"]), int(candidate["score"])])
	_require(heals > 0, "the support brain was offered no heal at all, so this check proves nothing")

	# The sign, directly: a harmful effect is a benefit on an enemy and a cost on an ally. A fix
	# that simply ignored harmful effects would pass the checks above and break Chill.
	var timeoff: Spell = null
	for spellSet in oracle.spellSets:
		for spell in spellSet:
			if str(spell.name) == "Timeoff":
				timeoff = spell
	_require(timeoff != null, "the Oracle of Ages no longer carries Timeoff")
	if timeoff == null:
		return
	var evaluator = sim.brains.get(ORACLE_ID).commandEvaluator
	var ally := _nonCommander(state, 2)
	var enemy := _nonCommander(state, 1)
	_require(evaluator._declaredEffectUtility(oracle, timeoff, ally) < 0,
		"Timeoff's slow on an ally is not scored as a cost")
	_require(evaluator._declaredEffectUtility(oracle, timeoff, enemy) > 0,
		"Timeoff's slow on an enemy is not scored as a benefit")

	# A heal on a hurt ally is worth its HP only when the ally could fall before acting again.
	# Without that, a support brain heals back chip damage forever and never attacks.
	var hurt: Monster = state.getMonster(ally)
	var cell: Vector2i = state.getMonsterPosition(ally)
	var oracleCell: Vector2i = state.getMonsterPosition(ORACLE_ID)
	hurt.hitpoints = hurt.max_hitpoints - 5
	_require(evaluator.healWorth(oracle, timeoff, hurt, oracleCell, {}) == 0,
		"a heal on a hurt but unthreatened ally is still worth something")
	_require(evaluator.healWorth(oracle, timeoff, hurt, oracleCell, {cell: hurt.hitpoints}) > 0,
		"a heal on an ally that could fall this round is worth nothing")
	hurt.hitpoints = hurt.max_hitpoints


func _isHeal(actor: Monster, command: BattleCommand) -> bool:
	if command == null or command.action != "spell":
		return false
	if command.spell_set_index >= actor.spellSets.size():
		return false
	var spellSet: Array = actor.spellSets[command.spell_set_index]
	if command.spell_index >= spellSet.size():
		return false
	return bool(spellSet[command.spell_index].heals)


## The destination a candidate acts from, as the evaluator's own tie key spells it ("yy:xx:").
func _cellKey(candidate: Dictionary) -> String:
	return str(candidate["tie_key"]).substr(0, 5)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
