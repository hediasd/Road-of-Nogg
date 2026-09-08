extends SceneTree

const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")

const MAP_PATH := "res://data/battle/maps/technical_hxb_contract_map.json"
const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const CPU_SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"

var failures: Array[String] = []


func _init() -> void:
	_checkValidContracts()
	_checkMapFailures()
	_checkScenarioFailures()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_MAP_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_MAP_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expectError(result: Dictionary, code: String, label: String) -> void:
	_require(not bool(result.get("success", false)), "%s unexpectedly succeeded" % label)
	_require(str(result.get("error", "")) == code,
		"%s returned %s instead of %s" % [label, result.get("error", ""), code])


func _checkValidContracts() -> void:
	var mapResult := BattleMapFactoryScript.loadFromPath(MAP_PATH)
	_require(mapResult["success"], "valid map failed: %s" % mapResult.get("error", ""))
	if not mapResult["success"]:
		return
	var map = mapResult["definition"]
	_require(map.boardSize == Vector2i(7, 5), "board size changed")
	_require(map.cellWidth == 2.0 and map.cellHeight == 2.0 and map.heightStep == 0.5,
		"board-view cell metrics changed")
	_require(map.validCells().size() == 34, "valid mask did not preserve one hole")
	_require(map.validCells()[0] == Vector2i(0, 0) and map.validCells()[-1] == Vector2i(6, 4),
		"valid cells are not row-major")
	_require(not map.containsCell(Vector2i(3, 2)), "mask hole became a valid cell")
	_require(not map.isTraversable(Vector2i(3, 1)), "obstacle became traversable")
	_require(map.heightAt(Vector2i(2, 2)) == 2, "height override was lost")
	_require(map.movementCostAt(Vector2i(3, 3)) == 4, "weighted terrain cost was lost")
	_require(BattleMapFactoryScript.fromDictionary(map.toDictionary())["success"],
		"map dictionary did not round-trip")

	var scenarioResult := BattleScenarioFactoryScript.loadFromPath(SCENARIO_PATH)
	_require(scenarioResult["success"],
		"valid scenario failed: %s" % scenarioResult.get("error", ""))
	if not scenarioResult["success"]:
		return
	var scenario = scenarioResult["scenario"]
	_require(scenario.parties.size() == 4, "scenario did not load four parties")
	_require(BattleScenarioFactoryScript.fromDictionary(scenario.toDictionary())["success"],
		"scenario dictionary did not round-trip")
	var cpuResult := BattleScenarioFactoryScript.loadFromPath(CPU_SCENARIO_PATH)
	_require(cpuResult["success"], "CPU-only scenario failed to load")
	if cpuResult["success"]:
		for party in cpuResult["scenario"].parties:
			_require(party.controller == "cpu", "CPU-only scenario retained a player party")

	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 777
	_require(config.validate().success, "hex setup config did not validate")
	var restored = BattleSetupConfigScript.fromDictionary(config.serialize())
	_require(restored.scenarioPath == SCENARIO_PATH and restored.seed == 777,
		"hex setup config did not round-trip")
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "hex state construction failed")
	if stateResult["success"]:
		var state = stateResult["state"]
		_require(state.parties.size() == 4 and state.monsters.size() == 8,
			"hex state lost parties or members")
		_require(not state.containsCell(Vector2i(3, 2)), "state accepted the mask hole")
		_require(state.nextMonsterID == 204, "explicit ID allocation did not advance")
		_require(state.teamRosters[1].size() == 4 and state.teamRosters[2].size() == 4,
			"legacy roster projection did not reflect parties")


func _checkMapFailures() -> void:
	var loaded := BattleMapFactoryScript.loadFromPath(MAP_PATH)
	if not loaded["success"]:
		failures.append("cannot run map rejection cases: %s" % loaded["error"])
		return
	var base: Dictionary = loaded["definition"].toDictionary()
	var value: Dictionary = base.duplicate(true)
	value["FORMAT_VERSION"] = 2
	_expectError(BattleMapFactoryScript.fromDictionary(value), "unsupported_map_version", "map version")
	value = base.duplicate(true)
	value["DEFAULT_SURFACE"]["TERRAIN"] = "bogus"
	_expectError(BattleMapFactoryScript.fromDictionary(value), "unknown_terrain", "unknown terrain")
	value = base.duplicate(true)
	value["VALID_MASK"][2] = "111x111"
	_expectError(BattleMapFactoryScript.fromDictionary(value), "malformed_valid_mask", "malformed mask")
	value = base.duplicate(true)
	value["SIZE"] = [-1, 5]
	_expectError(BattleMapFactoryScript.fromDictionary(value), "invalid_map_size", "invalid dimensions")
	value = base.duplicate(true)
	value["CELL_OVERRIDES"].append(value["CELL_OVERRIDES"][0].duplicate(true))
	_expectError(BattleMapFactoryScript.fromDictionary(value), "duplicate_cell_override", "duplicate override")
	value = base.duplicate(true)
	value["SOURCE"]["HEADLESS_ONLY"] = false
	_expectError(BattleMapFactoryScript.fromDictionary(value), "missing_visual_resource", "missing visual resource")
	value = base.duplicate(true)
	value["SURFACE_MODEL"] = "stacked"
	_expectError(BattleMapFactoryScript.fromDictionary(value), "unsupported_surface_model", "surface model")
	value = base.duplicate(true)
	value["CELL_OVERRIDES"][0]["SURFACES"] = []
	_expectError(BattleMapFactoryScript.fromDictionary(value), "unsupported_stacked_surfaces", "stacked cell")


func _checkScenarioFailures() -> void:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO_PATH)
	if not loaded["success"]:
		failures.append("cannot run scenario rejection cases: %s" % loaded["error"])
		return
	var base: Dictionary = loaded["scenario"].toDictionary()
	var value: Dictionary = base.duplicate(true)
	value["FORMAT_VERSION"] = 2
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "unsupported_scenario_version", "scenario version")
	value = base.duplicate(true)
	value["PARTIES"][1]["PARTY_ID"] = value["PARTIES"][0]["PARTY_ID"]
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "duplicate_party_id", "duplicate party")
	value = base.duplicate(true)
	value["PARTIES"][1]["MEMBERS"][0]["MEMBER_ID"] = value["PARTIES"][0]["MEMBERS"][0]["MEMBER_ID"]
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "duplicate_member_id", "duplicate member")
	value = base.duplicate(true)
	value["PARTIES"][0]["COMMANDER_ID"] = 200
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "commander_not_in_party", "wrong-party commander")
	value = base.duplicate(true)
	value["PARTIES"][1]["MEMBERS"][0]["CELL"] = value["PARTIES"][0]["MEMBERS"][0]["CELL"].duplicate()
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "overlapping_deployment", "overlap")
	value = base.duplicate(true)
	value["MAP"]["PATH"] = "res://data/battle/maps/does_not_exist.json"
	_expectError(BattleScenarioFactoryScript.fromDictionary(value), "map_load_failed", "missing map resource")
