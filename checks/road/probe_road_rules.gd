extends SceneTree

## What this proves: the road's headless model. The catalog loads and refuses bad records; Belief,
## levels and ascension follow the stated defaults exactly; the company can be fielded, commanded
## and ascended only legally; progress round-trips through a save and refuses a save made for
## something else; every stop composes into a battle the scenario factory accepts; and one real
## road battle, played by the CPU on both sides, is tallied and paid onto the company.
##
## What it cannot prove: how the road looks or plays. That is the road scene probe's structure
## check and Henri's playthrough.

const RoadReferencesScript = preload("res://content/RoadReferences.gd")
const RoadRulesScript = preload("res://road/RoadRules.gd")
const RoadStateScript = preload("res://road/RoadState.gd")
const RoadBattleScript = preload("res://road/RoadBattle.gd")
const RoadSaveScript = preload("res://road/RoadSave.gd")
const RunBattleScript = preload("res://tools/run_battle.gd")
const BattleScenarioFactoryScript = preload("res://content/BattleScenarioFactory.gd")
const BattleSetupConfigScript = preload("res://simulation/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://simulation/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://simulation/BattleSimulator.gd")

const ROAD := "first_road"
const SCRATCH := "user://road_rules_probe"
const MARKER := "ROAD_RULES_OK"

var failures: Array[String] = []
var road: Dictionary = {}


func _init() -> void:
	_checkCatalog()
	if road.is_empty():
		_finish()
		return
	_checkRules()
	_checkFielding()
	_checkAscension()
	_checkApplyBattle()
	_checkSave()
	_checkComposition()
	_checkPlayedBattle()
	_finish()


func _finish() -> void:
	var scratch := ProjectSettings.globalize_path(SCRATCH)
	for fileName in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(fileName))
	DirAccess.remove_absolute(scratch)
	for failure in failures:
		printerr("ROAD_RULES_FAILURE: %s" % failure)
	if failures.is_empty():
		print(MARKER)
	quit(0 if failures.is_empty() else 1)


func _checkCatalog() -> void:
	_require(RoadReferencesScript.names().has(ROAD), "data/roads.json has no '%s'" % ROAD)
	var loaded := RoadReferencesScript.loadRoad(ROAD)
	_require(bool(loaded["success"]), "the road did not load: %s" % str(loaded["error"]))
	if not loaded["success"]:
		return
	road = loaded["road"]
	_require((road["stops"] as Array).size() == 4, "expected four stops")
	_require((road["company"] as Array).size() == 6, "expected a company of six")
	_require(int(road["field_size"]) == 4, "expected a field of four")
	_require(str(road["region"]) == "temp2", "expected the road on temp2")

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RoadReferencesScript.JSON_PATH))[0]
	_refused(raw, func(r): r["COMPANY"][0]["MONSTER"] = "Nobody At All", "unknown company monster")
	_refused(raw, func(r): r["COMMANDER"] = 5, "COMMANDER must be a fielded slot")
	_refused(raw, func(r): r["FIELDED"] = [0, 0], "invalid or repeated slot")
	_refused(raw, func(r): r["STOPS"][0]["PLAYER_CELLS"][1] = [2, 2], "is already taken")
	_refused(raw, func(r): r["STOPS"][0]["ENEMIES"][0]["MEMBERS"][0]["CELL"] = [2, 2], "is already taken")
	_refused(raw, func(r): r["STOPS"][0]["PLAYER_CELLS"][0] = [99, 99], "is not on the map")
	_refused(raw, func(r): r["STOPS"][1]["ID"] = "stop_1", "duplicate stop id")
	_refused(raw, func(r): r["STOPS"][0]["ENEMIES"][0]["COMMANDER"] = 7, "COMMANDER is not one of its members")


func _refused(raw: Dictionary, edit: Callable, expected: String) -> void:
	var copy: Dictionary = raw.duplicate(true)
	edit.call(copy)
	var result := RoadReferencesScript.fromDictionary(copy)
	_require(not bool(result["success"]) and str(result["error"]).contains(expected),
		"a bad record was not refused with '%s' (got success=%s, '%s')" % [expected, str(result["success"]), str(result["error"])])


func _checkRules() -> void:
	var expectedTotals := [0, 3, 9, 18, 30, 45, 63, 84, 108, 135]
	for level in range(1, 11):
		_require(RoadRulesScript.beliefForLevel(level) == expectedTotals[level - 1],
			"level %d should cost %d Belief, costs %d" % [level, expectedTotals[level - 1], RoadRulesScript.beliefForLevel(level)])
	for pair in [[0, 1], [2, 1], [3, 2], [8, 2], [9, 3], [17, 3], [18, 4], [134, 9], [135, 10], [10000, 10]]:
		_require(RoadRulesScript.levelForBelief(pair[0]) == pair[1],
			"%d Belief should be level %d, is %d" % [pair[0], pair[1], RoadRulesScript.levelForBelief(pair[0])])
	_require(RoadRulesScript.beliefToNextLevel(4) == 5, "from 4 Belief, level 3 is 5 away")
	_require(RoadRulesScript.beliefToNextLevel(500) == 0, "at the cap nothing is left to earn")

	var benched := {"standing": false, "felled": 0, "commanders_felled": 0}
	_require(RoadRulesScript.beliefEarned(benched, false) == 1, "fielding alone pays 1")
	_require(RoadRulesScript.beliefEarned({"standing": true, "felled": 0, "commanders_felled": 0}, false) == 2,
		"standing at the end pays 1 more")
	_require(RoadRulesScript.beliefEarned({"standing": true, "felled": 2, "commanders_felled": 1}, true) == 1 + 1 + 2 + 2 + 1,
		"two felled, one a commander, standing, on a win pays 7")

	_require(RoadRulesScript.ascendedFormOf("Lesser Bigua") == "Sunshower Bigua", "Lesser Bigua ascends into Sunshower Bigua")
	_require(RoadRulesScript.ascendedFormOf("Sunshower Bigua") == "Suncrowned Bigua", "Sunshower Bigua ascends into Suncrowned Bigua")
	_require(RoadRulesScript.ascendedFormOf("Suncrowned Bigua").is_empty(), "Suncrowned Bigua is the end of its line")
	_require(RoadRulesScript.ascendedFormOf("Paper Cat") == "Samarkand Stalker", "Paper Cat ascends into Samarkand Stalker")
	_require(RoadRulesScript.ascensionThreshold("Lesser Bigua") == 18, "the first ascension needs 18 Belief")
	_require(RoadRulesScript.ascensionThreshold("Sunshower Bigua") == 63, "the second ascension needs 63 Belief")
	_require(RoadRulesScript.ascensionThreshold("Samarkand Stalker") == -1, "Samarkand Stalker has nowhere to ascend")
	_require(RoadRulesScript.ascensionThreshold("Healer Mage") == -1, "Healer Mage has no ascended form")


func _checkFielding() -> void:
	var state = RoadStateScript.fromRoad(road)
	_require(state.fielded == [0, 1, 2, 3] and state.commander == 0, "a fresh road fields its first four under slot 0")
	_require(not bool(state.toggleFielded(4)["ok"]), "a fifth monster cannot be fielded")
	_require(bool(state.toggleFielded(0)["ok"]) and state.commander == 1,
		"benching the commander hands command to the first slot still fielded")
	_require(bool(state.toggleFielded(4)["ok"]) and state.fielded == [1, 2, 3, 4], "a freed place takes a new monster")
	_require(not bool(state.setCommander(5)["ok"]), "a benched monster cannot command")
	_require(bool(state.setCommander(4)["ok"]) and state.commander == 4, "a fielded monster can command")
	for slot in [1, 2, 3]:
		state.toggleFielded(slot)
	_require(state.fielded == [4], "benching down to one leaves one")
	_require(not bool(state.toggleFielded(4)["ok"]), "the last fielded monster cannot be benched")


func _checkAscension() -> void:
	var state = RoadStateScript.fromRoad(road)
	_require(state.monsterOf(1) == "Lesser Bigua", "slot 1 should be Lesser Bigua")
	state.company[1]["belief"] = 17
	_require(not state.canAscend(1) and not bool(state.ascend(1)["ok"]), "17 Belief is short of the first ascension")
	state.company[1]["belief"] = 18
	var ascended: Dictionary = state.ascend(1)
	_require(bool(ascended["ok"]) and state.monsterOf(1) == "Sunshower Bigua", "18 Belief ascends Lesser Bigua")
	_require(state.beliefOf(1) == 18 and state.levelOf(1) == 4, "ascension keeps Belief and level")
	_require(not state.canAscend(1), "the second ascension waits for 63 Belief")
	_require(not state.canAscend(3), "Healer Mage never ascends")


func _checkApplyBattle() -> void:
	var state = RoadStateScript.fromRoad(road)
	var summary := {"outcome": "won", "units": {
		0: {"standing": true, "felled": 1, "commanders_felled": 1},
		1: {"standing": false, "felled": 0, "commanders_felled": 0},
	}}
	var report: Dictionary = state.applyBattle(0, summary)
	_require(state.beliefOf(0) == 1 + 1 + 1 + 2 + 1, "the commander-felling survivor earned 6")
	_require(state.beliefOf(1) == 1 + 1, "a fallen fielded monster on a win earned 2")
	_require(state.beliefOf(4) == 0, "a benched monster earned nothing")
	_require(state.clearedCount == 1, "winning the next stop clears it")
	_require(int(report["units"][0]["level_after"]) == 2, "6 Belief is level 2")
	state.applyBattle(0, summary)
	_require(state.clearedCount == 1, "winning a cleared stop again does not skip ahead")
	state.applyBattle(1, {"outcome": "lost", "units": {0: {"standing": false, "felled": 0, "commanders_felled": 0}}})
	_require(state.clearedCount == 1 and state.beliefOf(0) == 12 + 1, "a loss pays what was earned and stays put")
	_require(state.isStopOpen(1, 4) and not state.isStopOpen(2, 4), "only the next stop past the cleared ones is open")


func _checkSave() -> void:
	var state = RoadStateScript.fromRoad(road)
	state.company[2]["belief"] = 20
	state.toggleFielded(3)
	state.toggleFielded(5)
	state.setCommander(5)
	state.beginAttempt(0)
	state.beginAttempt(0)
	state.clearedCount = 1
	var written := RoadSaveScript.write(state, SCRATCH)
	_require(bool(written["ok"]), "the save was not written: %s" % str(written["error"]))
	var read := RoadSaveScript.read(road, SCRATCH)
	_require(bool(read["ok"]) and bool(read["found"]), "the save did not read back: %s" % str(read["error"]))
	if read["ok"] and read["found"]:
		_require(read["state"].toDictionary() == state.toDictionary(), "the save did not round-trip exactly")

	var older: Dictionary = state.toDictionary()
	older["ROAD_REVISION"] = 0
	_require(not bool(RoadStateScript.fromDictionary(older, road)["ok"]), "a save for another revision was accepted")
	var other: Dictionary = state.toDictionary()
	other["ROAD"] = "some_other_road"
	_require(not bool(RoadStateScript.fromDictionary(other, road)["ok"]), "a save for another road was accepted")
	var benchedCommander: Dictionary = state.toDictionary()
	benchedCommander["COMMANDER"] = 3
	_require(not bool(RoadStateScript.fromDictionary(benchedCommander, road)["ok"]), "a save whose commander is benched was accepted")
	RoadSaveScript.erase(ROAD, SCRATCH)
	_require(not bool(RoadSaveScript.read(road, SCRATCH)["found"]), "an erased save was still found")


func _checkComposition() -> void:
	var state = RoadStateScript.fromRoad(road)
	state.company[0]["belief"] = 9
	for stopIndex in range((road["stops"] as Array).size()):
		var composed := RoadBattleScript.compose(state, road, stopIndex, 1)
		_require(bool(composed["ok"]), "stop %d did not compose: %s" % [stopIndex, str(composed["error"])])
		if not composed["ok"]:
			continue
		_require(int(composed["seed"]) == int(road["seed"]) + 1000 * stopIndex + 1, "stop %d's seed is not the road formula" % stopIndex)
		var player: Dictionary = composed["scenario"]["PARTIES"][0]
		_require(int(player["COMMANDER_ID"]) == RoadBattleScript.memberIDFor(0), "the company's commander does not command")
		_require(int(player["MEMBERS"][0]["LEVEL"]) == 3, "9 Belief should field slot 0 at level 3")
		_require((player["MEMBERS"] as Array).size() == 4, "stop %d did not field four" % stopIndex)
	_require(RoadBattleScript.compose(state, road, 1, 1)["seed"] != RoadBattleScript.compose(state, road, 1, 2)["seed"],
		"a retry should be a different battle")


## One stop, played to the end by the CPU for both sides, tallied from real events and paid.
func _checkPlayedBattle() -> void:
	var state = RoadStateScript.fromRoad(road)
	var attempt: int = state.beginAttempt(0)
	var composed := RoadBattleScript.compose(state, road, 0, attempt, RoadBattleScript.CONTROLLER_CPU)
	if not composed["ok"]:
		failures.append("the played stop did not compose: %s" % str(composed["error"]))
		return
	var path := SCRATCH.path_join("battle.json")
	var written := RoadBattleScript.writeScenario(composed["scenario"], path)
	_require(bool(written["ok"]), "the scenario was not written: %s" % str(written["error"]))
	var loaded := BattleScenarioFactoryScript.loadFromPath(path)
	_require(bool(loaded["success"]), "the written scenario did not load: %s" % str(loaded.get("error", "")))
	if not loaded["success"]:
		return
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = path
	config.seed = int(composed["seed"])
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(bool(stateResult["success"]), "the road battle's state did not build: %s" % str(stateResult.get("error", "")))
	if not stateResult["success"]:
		return
	var sim = BattleSimulatorScript.new(int(composed["seed"]))
	sim.configureHexState(stateResult["state"], loaded["scenario"], {"scenarioPath": path})
	var tally = RoadBattleScript.Tally.new()
	tally.attach(sim.events, sim.state)
	sim.emitInitialBoard()
	var played: Dictionary = RunBattleScript._runCpuSides(sim, 30)
	_require(bool(played.get("ok", false)), "the road battle did not play: %s" % str(played.get("error", "")))
	var summary := RoadBattleScript.summarize(sim.state, tally.defeats)
	_require(str(summary["outcome"]) in ["won", "lost", "draw"], "the battle did not finish: %s" % str(summary["outcome"]))
	_require((summary["units"] as Dictionary).size() == 4, "the summary should cover the four fielded slots")
	_require(not tally.defeats.is_empty(), "a played battle recorded no defeats")
	var felledTotal := 0
	for slot in summary["units"]:
		felledTotal += int(summary["units"][slot]["felled"])
	var enemyDefeats := 0
	for defeat: Dictionary in tally.defeats:
		if int(defeat["monster"]) >= RoadBattleScript.ENEMY_MEMBER_BASE and int(defeat["killer"]) < RoadBattleScript.ENEMY_MEMBER_BASE \
				and int(defeat["killer"]) >= RoadBattleScript.PLAYER_MEMBER_BASE:
			enemyDefeats += 1
	_require(felledTotal == enemyDefeats, "felled counts (%d) disagree with the company's recorded kills (%d)" % [felledTotal, enemyDefeats])
	var before := 0
	for slot in state.fielded:
		before += state.beliefOf(slot)
	var report: Dictionary = state.applyBattle(0, summary)
	var after := 0
	for slot in state.fielded:
		after += state.beliefOf(slot)
	_require(after > before, "a played battle paid no Belief")
	_require((report["units"] as Dictionary).size() == 4, "the report should cover the four fielded slots")
	print("road battle at stop 0: %s after %d rounds, %d defeats, %d Belief paid" % [
		summary["outcome"], int(sim.state.roundCount), tally.defeats.size(), after - before])


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
