extends SceneTree

const ConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const SetupScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const SimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const ForecastScript = preload("res://src/battle_sim/BattleForecast.gd")
const SerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const EstimatorScript = preload("res://src/entity_ai/OutcomeEstimator.gd")
const OutputPathsScript = preload("res://src/presentation/BattleOutputPaths.gd")
const FIXTURE := "res://scripts/battle/fixtures/ai/forecast_cases.json"
const OUTPUT_NAME := "ai_forecast_sample.json"

var failures: Array[String] = []


func _init() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var config = ConfigScript.new()
	config.scenarioPath = str(fixture["scenario"])
	config.seed = int(fixture["seed"])
	var setup: Dictionary = SetupScript.createHexState(config)
	_check(bool(setup.get("success", false)), "setup failed")
	if not bool(setup.get("success", false)):
		_finish()
		return
	var sim: BattleSimulator = SimulatorScript.new(config.seed)
	sim.configureHexState(setup["state"], setup["scenario"], config.serialize())
	sim.startBattle()
	_check(bool(sim.startNextSideTurn("probe").get("success", false)), "side did not open")
	var actorID: int = sim.eligibleSideUnitIDs()[0]
	var before := sim.state.serialize_state()
	var rngBefore := sim.state.rng.state
	var historyBefore := sim.state.history.size()
	var eventCount := [0]
	sim.events.unit_selected.connect(func(_side, _actor): eventCount[0] += 1)
	var command := BattleCommand.wait()
	var sample = ForecastScript.evaluate(sim, actorID, command,
		ForecastScript.POLICY_SAMPLE, int(fixture["sample_id"]))
	_check(sample.accepted and sample.resolved, "wait forecast failed")
	_check(sample.horizon == "one_command" and not sample.changes.is_empty(),
		"forecast did not report horizon and deltas")
	_check(sim.state.history.size() == historyBefore and sim.state.rng.state == rngBefore
		and eventCount[0] == 0 and _same(before, sim.state.serialize_state()),
		"forecast touched live state, RNG, history or signals")
	var repeated = ForecastScript.evaluate(sim, actorID, command,
		ForecastScript.POLICY_SAMPLE, int(fixture["sample_id"]))
	_check(_same(sample.command_result, repeated.command_result) and
		_same(sample.changes, repeated.changes), "same sample identity diverged")
	sim.state.rng.state = 123456789
	var hiddenChanged = ForecastScript.evaluate(sim, actorID, command,
		ForecastScript.POLICY_SAMPLE, int(fixture["sample_id"]))
	_check(_same(sample.command_result, hiddenChanged.command_result) and
		_same(sample.changes, hiddenChanged.changes), "policy sample read hidden RNG")
	var exactA = ForecastScript.evaluate(sim, actorID, command,
		ForecastScript.DEBUG_EXACT)
	var exactB = ForecastScript.evaluate(sim, actorID, command,
		ForecastScript.DEBUG_EXACT)
	_check(_same(exactA.command_result, exactB.command_result) and
		_same(exactA.changes, exactB.changes), "debug exact stream was unstable")
	var invalid = ForecastScript.evaluate(sim, actorID,
		BattleCommand.new([], "spell", -1, 999, 999), ForecastScript.POLICY_SAMPLE, 1)
	_check(not invalid.accepted, "illegal command forecast was accepted")
	var samples: Array = [sample, ForecastScript.evaluate(sim, actorID,
		command, ForecastScript.POLICY_SAMPLE, int(fixture["sample_id"]) + 1)]
	var summary: Dictionary = EstimatorScript.summarize(samples)
	_check(int(summary.get("sample_count", 0)) == 2 and
		int(summary.get("accepted_count", 0)) == 2, "sample aggregation failed")
	var randomCaster: Monster = sim.state.getMonster(101)
	var randomSpell := Spell.new({})
	randomSpell.restoreRuntime(randomCaster.spellSets[0][0].serializeRuntime())
	randomSpell.range = 8
	randomSpell.bypass_los = true
	sim.state.setMonsterAbilities(101, [[randomSpell]], randomCaster.passives)
	var randomCommand := BattleCommand.new([], "spell", 201, 0, 0,
		"move_first", Vector2i(5, 1))
	var randomSampleA = ForecastScript.evaluate(sim, 101, randomCommand,
		ForecastScript.POLICY_SAMPLE, 23)
	var sampleRecord := {"probe_revision": int(fixture["probe_revision"]),
		"sample_id": randomSampleA.sample_id,
		"command_result": randomSampleA.command_result,
		"changes": randomSampleA.changes, "events": randomSampleA.events}
	var sampleText := JSON.stringify(sampleRecord, "\t", true)
	var outputPath: String = OutputPathsScript.pathFor(OutputPathsScript.BATTLES, OUTPUT_NAME)
	if FileAccess.file_exists(outputPath):
		var previousText := FileAccess.get_file_as_string(outputPath)
		var previous = JSON.parse_string(previousText)
		if previous is Dictionary and int(previous.get("probe_revision", 0)) == \
			int(fixture["probe_revision"]):
			_check(_same(sampleRecord, previous) and previousText == sampleText,
				"policy sample changed across fresh processes")
	var sampleFile := FileAccess.open(outputPath, FileAccess.WRITE)
	_check(sampleFile != null, "policy sample artifact could not be written")
	if sampleFile != null:
		sampleFile.store_string(sampleText)
		sampleFile.close()
	sim.state.rng.state = 987654321
	var randomSampleB = ForecastScript.evaluate(sim, 101, randomCommand,
		ForecastScript.POLICY_SAMPLE, 23)
	_check(randomSampleA.accepted and randomSampleA.resolved and
		_same(randomSampleA.command_result, randomSampleB.command_result) and
		_same(randomSampleA.changes, randomSampleB.changes),
		"random-consuming policy forecast depended on hidden gameplay RNG")
	var randomExact = ForecastScript.evaluate(sim, 101, randomCommand,
		ForecastScript.DEBUG_EXACT)
	_check(not _same(randomExact.changes, randomSampleA.changes),
		"debug-exact RNG stream was confused with policy samples")
	var actor: Monster = sim.state.getMonster(actorID)
	var areaSpell := Spell.new({})
	areaSpell.restoreRuntime(actor.spellSets[0][1].serializeRuntime())
	areaSpell.range = 8
	areaSpell.bypass_los = true
	sim.state.setMonsterAbilities(actorID, [[areaSpell]], actor.passives)
	var center := Vector2i(5, 1)
	var area = ForecastScript.evaluate(sim, actorID,
		BattleCommand.new([], "spell", 201, 0, 0, "move_first", center),
		ForecastScript.POLICY_SAMPLE, 3)
	var damagedTargets: Dictionary = {}
	for event in area.events:
		if str(event.get("type", "")) == "damage":
			damagedTargets[int(event.get("target_id", -1))] = true
	_check(area.accepted and area.resolved and damagedTargets.size() >= 2,
		"area forecast did not resolve multiple targets")
	var reverseSpell := Spell.new({})
	reverseSpell.restoreRuntime(sim.state.getMonster(200).spellSets[0][1].serializeRuntime())
	reverseSpell.range = 8
	reverseSpell.bypass_los = true
	reverseSpell.element = "light"
	reverseSpell.damage_lines = []
	reverseSpell.resonance_element = "light"
	sim.state.setMonsterAbilities(actorID, [[reverseSpell]], actor.passives)
	for _eventIndex in range(80):
		sim.state.add_event("diagnostic_padding", -1, -1)
	for monsterID in sim.state.monsters:
		sim.state.last_turn_start_index[monsterID] = sim.state.history.size()
	var victim: Monster = sim.state.getMonster(101)
	victim.hitpoints -= 10
	sim.state.add_event("damage", 201, 101, {"damage": 10})
	var reversal = ForecastScript.evaluate(sim, actorID,
		BattleCommand.new([], "spell", 201, 0, 0, "move_first", center),
		ForecastScript.POLICY_SAMPLE, 4)
	var healed := false
	for change in reversal.changes:
		if change.get("path", "") == "/monsters/101/hitpoints":
			healed = int(change["after"]) == int(change["before"]) + 10
	_check(reversal.accepted and reversal.resolved and healed and
		int(reversal.cost.get("copied_history_events", -1)) == 1,
		"damage reversal lost rule-relevant history")
	var retaliation := PassiveSkill.new({
		"NAME": "Probe Retaliation", "TRIGGER": "ON_TARGETED",
		"EFFECT_TYPE": "retaliate_damage", "VALUE": 999,
		"ELEMENT": "none", "RADIUS": 0,
	})
	var target: Monster = sim.state.getMonster(201)
	sim.state.setMonsterAbilities(201, target.spellSets, [retaliation])
	sim.state.setMonsterAbilities(actorID, [[areaSpell]], actor.passives)
	var fizzle = ForecastScript.evaluate(sim, actorID,
		BattleCommand.new([], "spell", 201, 0, 0, "move_first", center),
		ForecastScript.POLICY_SAMPLE, 5)
	_check(fizzle.accepted and not fizzle.resolved and
		str(fizzle.command_result.get("actionResult", {}).get("reason", "")) == \
		"caster_died_to_passive", "reactive fizzle was misclassified")
	var copied: Array[int] = []
	var byteCounts: Array[int] = []
	var fullByteCounts: Array[int] = []
	var elapsedUsec: Array[int] = []
	for lengthValue in fixture["history_lengths"]:
		var length := int(lengthValue)
		while sim.state.history.size() < length:
			sim.state.add_event("diagnostic_padding", -1, -1)
		for monsterID in sim.state.monsters:
			sim.state.last_turn_start_index[monsterID] = sim.state.history.size()
		var measuredStart := Time.get_ticks_usec()
		var compact: Dictionary = SerializerScript.serializeForForecast(sim.state, false)
		elapsedUsec.append(Time.get_ticks_usec() - measuredStart)
		copied.append(compact["history"].size())
		byteCounts.append(JSON.stringify(compact).to_utf8_buffer().size())
		fullByteCounts.append(JSON.stringify(sim.state.serialize_state()).to_utf8_buffer().size())
		_check(int(compact["historyBaseIndex"]) == length and
			compact["history"].is_empty(), "forecast copied diagnostic history")
	print("AI_FORECAST_COST history=%s copied=%s forecast_bytes=%s full_bytes=%s usec=%s" % [
		str(fixture["history_lengths"]), str(copied), str(byteCounts),
		str(fullByteCounts), str(elapsedUsec)])
	_finish()


func _same(a, b) -> bool:
	return SimulatorScript._canonicalJSON(SerializerScript.normalizeSemanticNumbers(
		SerializerScript.jsonSafe(a))) == \
		SimulatorScript._canonicalJSON(SerializerScript.normalizeSemanticNumbers(
			SerializerScript.jsonSafe(b)))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("AI_FORECAST_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_FORECAST_OK")
	quit(0)
