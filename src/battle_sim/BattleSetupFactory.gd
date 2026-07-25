class_name BattleSetupFactory
extends RefCounted

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")


static func createSimulator(config, adapterFactory: Callable = Callable()):
	var validation = config.validate()
	assert(validation["success"], "Invalid battle setup: %s" % str(validation["errors"]))

	var simulator = BattleSimulatorScript.new(config.seed)
	simulator.loadMap(config.mapName)
	simulator.setSeed(config.seed)
	simulator.setSetupSnapshot(config.serialize())

	if adapterFactory.is_valid():
		simulator.setVisualAdapter(adapterFactory.call(simulator.state))

	for team in [1, 2]:
		var roster: Array = config.team1 if team == 1 else config.team2
		var slots = MapReferencesScript.getDeploymentSlots(config.mapName, team)
		for index in range(roster.size()):
			simulator.spawnMonster(roster[index], team, slots[index])

	return simulator
