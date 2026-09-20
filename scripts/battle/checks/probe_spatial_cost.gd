extends SceneTree

## Resource evidence for the hex queries the side policy leans on. Assertions
## are structural: cache purity, bounded retention, and agreement with an
## exhaustive oracle at sizes the correctness probe does not reach. Times and
## counts are printed as observations of this host, never as pass conditions --
## a machine-speed gate would make the sweep flake instead of finding defects.

const AStarPathfinderScript = preload("res://src/algorithms/AStarPathfinder.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const HexReachabilityScript = preload("res://src/algorithms/HexReachability.gd")
const LineOfSightScript = preload("res://src/algorithms/LineOfSight.gd")
const BattleEventsScript = preload("res://src/battle_sim/BattleEvents.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const MovementResolverScript = preload("res://src/battle_sim/MovementResolver.gd")
const PassiveSkillResolverScript = preload("res://src/battle_sim/PassiveSkillResolver.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const RAY_RADIUS := 8

var failures: Array[String] = []


func _init() -> void:
	_checkTemplatePurity()
	_checkFrontierAgainstOracle()
	_reportBattleWorkload()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_SPATIAL_COST_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_SPATIAL_COST_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _checkTemplatePurity() -> void:
	## The template table is geometry keyed by axial displacement and source
	## column parity. Dropping it must not change an answer, and no board fact
	## may ever reach it: rays are recomputed identically while a blocker
	## callable reports entirely different terrain.
	var origins: Array[Vector2i] = [Vector2i(4, 5), Vector2i(5, 5)]
	LineOfSightScript.clearRayTemplates()
	var cold: Array = []
	var coldStart := Time.get_ticks_usec()
	for origin: Vector2i in origins:
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			cold.append(LineOfSightScript.supercoverCells(origin, target))
	var coldUsec := Time.get_ticks_usec() - coldStart
	var built: int = int(LineOfSightScript.rayTemplateStats()["templates"])
	var warmStart := Time.get_ticks_usec()
	var warm: Array = []
	for origin: Vector2i in origins:
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			warm.append(LineOfSightScript.supercoverCells(origin, target))
	var warmUsec := Time.get_ticks_usec() - warmStart
	_require(cold == warm, "a cached ray answered differently from a built one")

	var blockedAny := false
	for origin: Vector2i in origins:
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			if not LineOfSightScript.hasHeightAwareLoS(
					origin, target, 1.0, 1.0,
					func(cell: Vector2i) -> float:
						return 9.0 if (cell.x + cell.y) % 3 == 0 else -INF):
				blockedAny = true
	_require(blockedAny, "the terrain sweep never exercised a blocker")
	var afterTerrain: Array = []
	for origin: Vector2i in origins:
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			afterTerrain.append(LineOfSightScript.supercoverCells(origin, target))
	_require(cold == afterTerrain, "terrain queries changed cached ray geometry")

	LineOfSightScript.clearRayTemplates()
	var rebuilt: Array = []
	for origin: Vector2i in origins:
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			rebuilt.append(LineOfSightScript.supercoverCells(origin, target))
	_require(cold == rebuilt, "dropping the template table changed an answer")

	var stats: Dictionary = LineOfSightScript.rayTemplateStats()
	_require(int(stats["templates"]) <= int(stats["capacity"]),
		"ray template retention exceeded its declared capacity")
	var distinct: Dictionary = {}
	for origin: Vector2i in origins:
		var originAxial := HexGridScript.offsetToAxial(origin)
		for target: Vector2i in HexGridScript.disc(origin, RAY_RADIUS):
			if target == origin:
				continue
			var targetAxial := HexGridScript.offsetToAxial(target)
			distinct[Vector3i(targetAxial.x - originAxial.x,
				targetAxial.y - originAxial.y, origin.x & 1)] = true
	_require(built == distinct.size(),
		"built %d templates for %d distinct displacements" % [built, distinct.size()])
	print("AI_SPATIAL_COST rays=%d templates=%d cold_usec=%d warm_usec=%d" %
		[cold.size(), built, coldUsec, warmUsec])


func _checkFrontierAgainstOracle() -> void:
	## Weighted reachability and A* over a board wider than the correctness
	## probe's fixture, against an exhaustive relaxation that has no frontier
	## order at all. Recorded predecessors must also cost what the search charged.
	var lookup: Dictionary = {}
	var costs: Dictionary = {}
	for y in range(18):
		for x in range(18):
			var cell := Vector2i(x, y)
			if (x * 5 + y * 3) % 17 == 0:
				continue
			lookup[cell] = true
			costs[cell] = 1 + ((x * 3 + y * 7) % 4)
	var canEnter := func(_current: Vector2i, next: Vector2i) -> bool: return lookup.has(next)
	var stepCost := func(_current: Vector2i, next: Vector2i) -> int: return int(costs[next])
	var start := Vector2i(1, 1)
	var oracle := _exhaustiveCosts(start, lookup, costs)

	var reachStart := Time.get_ticks_usec()
	var reach: Dictionary = HexReachabilityScript.calculate(
		start, 12, canEnter,
		func(_cell: Vector2i) -> bool: return true,
		func(_cell: Vector2i) -> bool: return true,
		stepCost,
		func(_cell: Vector2i) -> bool: return false)
	var reachUsec := Time.get_ticks_usec() - reachStart
	for cellValue in lookup:
		var position: Vector2i = cellValue
		var expected: int = int(oracle.get(position, -1))
		var reachable := position != start and expected >= 0 and expected <= 12
		_require(reach["positions"].has(position) == reachable,
			"reachability disagreed with the oracle at %s" % position)
		if not reachable:
			continue
		_require(int(reach["costs"][position]) == expected,
			"reachability cost disagreed with the oracle at %s" % position)
		var recorded: Array[Vector2i] = HexReachabilityScript.pathTo(reach, start, position)
		_require(not recorded.is_empty() and recorded.back() == position,
			"recorded predecessors did not lead to %s" % position)
		_require(AStarPathfinderScript.pathCost(recorded, stepCost, start) == expected,
			"the recorded path to %s did not cost what the search charged" % position)

	var pathUsec := 0
	var pathCount := 0
	for cellValue in lookup:
		var position: Vector2i = cellValue
		if position == start or int(oracle.get(position, -1)) < 0:
			continue
		var pathStart := Time.get_ticks_usec()
		var path: Array[Vector2i] = AStarPathfinderScript.findPath(
			start, position, canEnter, 200, stepCost,
			Callable(), Callable(), Callable(), 1)
		pathUsec += Time.get_ticks_usec() - pathStart
		pathCount += 1
		_require(AStarPathfinderScript.pathCost(path, stepCost, start) ==
			int(oracle[position]), "A* did not find a cheapest path to %s" % position)
	print("AI_SPATIAL_COST cells=%d reach_usec=%d paths=%d path_usec=%d" %
		[lookup.size(), reachUsec, pathCount, pathUsec])


func _reportBattleWorkload() -> void:
	## The shape a side policy actually asks for: every unit's reachable set,
	## and from every destination the tiles it could strike.
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	var setup: Dictionary = BattleSetupFactoryScript.createHexState(config)
	if not bool(setup.get("success", false)):
		failures.append("could not construct the workload state")
		return
	var state = setup["state"]
	var events = BattleEventsScript.new()
	var movement = MovementResolverScript.new(state, events)
	var combat = CombatResolverScript.new(state, events)
	combat.passiveSkillResolver = PassiveSkillResolverScript.new(state, events)
	LineOfSightScript.clearRayTemplates()
	var destinations := 0
	var strikes := 0
	var casts := 0
	var started := Time.get_ticks_usec()
	for monsterID in state.monsters:
		var monster = state.getMonster(int(monsterID))
		if monster == null or not monster.is_alive():
			continue
		var reach: Dictionary = movement.getReachability(int(monsterID))
		for destination: Vector2i in reach["positions"]:
			destinations += 1
			strikes += combat.getBasicAttackTargetPositionsFrom(
				int(monsterID), destination).size()
			for setIndex in range(monster.spellSets.size()):
				for spellIndex in range(monster.spellSets[setIndex].size()):
					casts += combat.getSpellTargetPositionsFrom(
						int(monsterID), setIndex, spellIndex, destination).size()
	var elapsed := Time.get_ticks_usec() - started
	_require(destinations > 0, "the workload produced no reachable destinations")
	## Melee is adjacency and height only, so the ray work in a side turn comes
	## from spell targeting; a workload without it would report no rays at all.
	_require(int(LineOfSightScript.rayTemplateStats()["templates"]) > 0,
		"the workload never asked for a line of sight")
	print("AI_SPATIAL_COST scenario=%s units=%d destinations=%d strikes=%d casts=%d templates=%d usec=%d" %
		[SCENARIO_PATH.get_file(), state.monsters.size(), destinations, strikes, casts,
		int(LineOfSightScript.rayTemplateStats()["templates"]), elapsed])


func _exhaustiveCosts(start: Vector2i, lookup: Dictionary, costs: Dictionary) -> Dictionary:
	var best: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor: Vector2i in HexGridScript.neighbours(current):
			if not lookup.has(neighbor):
				continue
			var candidate := int(best[current]) + int(costs[neighbor])
			if best.has(neighbor) and int(best[neighbor]) <= candidate:
				continue
			best[neighbor] = candidate
			frontier.append(neighbor)
	return best
