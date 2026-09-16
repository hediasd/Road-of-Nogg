extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"


func _init() -> void:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 4242
	var built := BattleSetupFactoryScript.createHexState(config)
	if not built["success"]:
		_fail("setup failed: %s" % built.get("error", ""))
		return
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(built["state"], built["scenario"], config.serialize())
	simulator.startBattle()
	var opened := simulator.startNextSideTurn("activation_probe")
	if not opened["success"] or int(opened["side_id"]) != 1:
		_fail("first side turn did not open")
		return
	var units := simulator.eligibleSideUnitIDs()
	if units.is_empty():
		_fail("first side had no eligible units")
		return
	var selected := simulator.selectUnit(int(units.back()), "activation_probe")
	if not selected["success"]:
		_fail("out-of-order unit selection failed")
		return
	if not simulator.executeCommand(int(units.back()), BattleCommand.wait(), "activation_probe").success:
		_fail("selected unit did not resolve Wait")
		return
	var ended := simulator.endSideTurn("activation_probe")
	if not ended["success"] or simulator.state.activeSideID != -1:
		_fail("side turn did not close")
		return
	print("HXB_ACTIVATION_OK")
	quit(0)


func _fail(message: String) -> void:
	printerr("HXB_ACTIVATION_FAILURE: %s" % message)
	quit(1)
