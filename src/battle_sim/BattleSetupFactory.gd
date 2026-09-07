class_name BattleSetupFactory
extends RefCounted

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleStateScript = preload("res://src/battle_sim/BattleState.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")


static func createSimulator(
		config: BattleSetupConfig,
		adapterFactory: Callable = Callable()) -> BattleSimulator:
	assert(not config.isHexScenario(),
		"Hex battle runtime is pending party activation and spatial resolvers.")
	var validation := config.validate()
	assert(validation.success, "Invalid battle setup: %s" % validation.errorText())

	var simulator = BattleSimulatorScript.new(config.seed)
	simulator.loadMap(config.mapName)
	simulator.setSeed(config.seed)
	simulator.setSetupSnapshot(config.serialize())

	if adapterFactory.is_valid():
		var adapter = adapterFactory.call(simulator.state)
		assert(
			adapter is IBattleVisualAdapter,
			"adapterFactory must return an IBattleVisualAdapter."
		)
		simulator.setVisualAdapter(adapter)

	for team in [1, 2]:
		var roster: Array = config.team1 if team == 1 else config.team2
		var slots = MapReferencesScript.getDeploymentSlots(config.mapName, team)
		for index in range(roster.size()):
			simulator.spawnMonster(roster[index], team, slots[index])

	return simulator


## Builds validated hex state without advertising a playable simulator. HXB-6
## and HXB-7 attach activation and spatial execution to this state contract.
static func createHexState(config: BattleSetupConfig) -> Dictionary:
	if not config.isHexScenario():
		return {"success": false, "state": null, "scenario": null,
			"error": "missing_hex_scenario"}
	var scenarioResult := BattleScenarioFactoryScript.loadFromPath(config.scenarioPath)
	if not scenarioResult["success"]:
		return {"success": false, "state": null, "scenario": null,
			"error": scenarioResult["error"]}
	var scenario: BattleScenario = scenarioResult["scenario"]
	var state: BattleState = BattleStateScript.new(config.seed)
	state.setBattleMap(scenario.battleMap)
	var largestID := state.nextMonsterID - 1
	for party: BattleParty in scenario.parties:
		state.registerParty(party)
		for memberID: int in party.memberIDs:
			var monster: Monster = MonsterFactoryScript.createMonster(
				party.monsterNameFor(memberID), memberID, party.memberLevel(memberID))
			state.addMonster(monster, party.startingCellFor(memberID), party.teamID)
			largestID = maxi(largestID, memberID)
	state.nextMonsterID = largestID + 1
	return {"success": true, "state": state, "scenario": scenario, "error": ""}
