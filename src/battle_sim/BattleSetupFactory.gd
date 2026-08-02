class_name BattleSetupFactory
extends RefCounted

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")


static func createSimulator(
		config: BattleSetupConfig,
		adapterFactory: Callable = Callable()) -> BattleSimulator:
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
