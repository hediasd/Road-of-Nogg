## demo_battle — Headless console demo of a full seeded battle. Run manually via Godot's -s flag;
## not a test and not part of any check.
##
## RUNS THE PARTY RUNTIME, same as the playable scene. It used to compose a battle by hand --
## `loadMap("Forest")` plus eight `spawnMonster` calls on a square board -- which after the hex
## migration would have been the one place still exercising a battle model nothing else uses. It
## now loads an authored scenario and lets `runFullBattle` dispatch to the party loop, so what the
## console prints is the same runtime the scene plays.
##
## CPU vs CPU, necessarily: a headless demo has nobody to choose party members, and the player
## path is the one thing a console cannot exercise.
extends SceneTree

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const ConsoleVisualAdapterScript = preload("res://src/presentation/ConsoleVisualAdapter.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 42


func _init() -> void:
	print("Starting simulation script...")

	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	if not loaded["success"]:
		printerr("Could not load %s: %s" % [SCENARIO, str(loaded.get("error", ""))])
		quit(1)
		return
	var scenario: BattleScenario = loaded["scenario"]

	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		printerr("Could not build hex state: %s" % str(stateResult.get("error", "")))
		quit(1)
		return

	var sim = BattleSimulatorScript.new(SEED)
	sim.configureHexState(stateResult["state"], scenario, {"scenarioPath": SCENARIO})

	var console = ConsoleVisualAdapterScript.new(sim.state)
	sim.setVisualAdapter(console)

	print("Running full party battle on %s..." % scenario.mapID)
	var outcome := sim.runFullBattle(30)
	print("Battle complete (outcome %d). Check docs/battle_log.txt" % outcome)
	quit()
