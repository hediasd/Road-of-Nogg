extends SceneTree

## The danger contract: three labelled answers that bracket the truth, checked
## against an exhaustive sweep of what the enemy side can legally do.

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const DecisionContextScript = preload("res://src/entity_ai/DecisionContext.gd")
const DangerQueryScript = preload("res://src/entity_ai/DangerQuery.gd")
const AssessmentScript = preload("res://src/entity_ai/DangerAssessment.gd")
const EnumeratorScript = preload("res://src/entity_ai/LegalActionEnumerator.gd")
const ThreatMapScript = preload("res://src/algorithms/ThreatMap.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const SpellScript = preload("res://src/entities/Spell.gd")

const CASES_PATH := "res://scripts/battle/fixtures/ai/danger_cases.json"

var failures: Array[String] = []
var cases: Dictionary = {}


func _init() -> void:
	cases = _loadCases()
	_checkReplyAgainstExhaustive()
	_checkBracketing()
	_checkPreMoveMagic()
	_checkOccupancyFeasibility()
	_checkSoundPruning()
	_checkBudgetAndCost()
	_checkConsumers()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_DANGER_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_DANGER_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _loadCases() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))
	if not parsed is Dictionary:
		failures.append("danger fixture is not an object")
		return {}
	return parsed


func _simulator(seed: int) -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = str(cases.get("scenario", ""))
	config.seed = seed
	var setup := BattleSetupFactoryScript.createHexState(config)
	if not bool(setup.get("success", false)):
		failures.append("setup failed: %s" % str(setup.get("error", "")))
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(setup["state"], setup["scenario"], config.serialize())
	simulator.startBattle()
	if not bool(simulator.startNextSideTurn("probe").get("success", false)):
		failures.append("no side opened")
		return null
	return simulator


## The most this one enemy could deal at `tile`, found by walking every legal
## action it has and asking what each would do. Structurally unlike DangerQuery,
## which starts from the tile and works outwards.
func _exhaustiveReply(context: DecisionContext, enemyID: int, tile: Vector2i) -> int:
	var state := context.state()
	var victim: Monster = state.getMonsterAt(tile)
	var enemy: Monster = state.getMonster(enemyID)
	var resolver := context.resolver()
	var best := 0
	for candidate in EnumeratorScript.forActor(context, enemyID):
		if candidate.action_class == "wait":
			continue
		if candidate.action_class == "attack":
			if candidate.target_pos != tile:
				continue
			var damage := enemy.atk if victim == null else \
				resolver.calculateBasicDamage(enemy, victim, true, candidate.destination)
			best = maxi(best, damage)
			continue
		var affected: Array = resolver.getSpellAffectedPositionsFrom(
			enemyID, candidate.spell_set_index, candidate.spell_index,
			candidate.destination, candidate.target_pos, true)
		if not affected.has(tile):
			continue
		var spell: Spell = enemy.spellSets[candidate.spell_set_index][candidate.spell_index]
		if spell.heals:
			continue
		var total := 0
		if victim == null:
			total = enemy.atk + spell.damage
		else:
			for line in spell.damage_lines:
				var base := int(line.get("damage", 0))
				if base <= 0:
					continue
				total += resolver.calculateSpellDamage(enemy, victim, base,
					str(line.get("element", "none")), true, candidate.destination)
		best = maxi(best, total)
	return best


func _checkReplyAgainstExhaustive() -> void:
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := DecisionContextScript.forSimulator(simulator)
	var checked := 0
	for defenderIDValue in simulator.state.getAliveMonsterIDs():
		var defenderID := int(defenderIDValue)
		var defender: Monster = simulator.state.getMonster(defenderID)
		var tile: Vector2i = simulator.state.getMonsterPosition(defenderID)
		for enemyIDValue in simulator.state.getAliveMonsterIDs():
			var enemyID := int(enemyIDValue)
			var enemy: Monster = simulator.state.getMonster(enemyID)
			if enemy.team == defender.team:
				continue
			var assessment := DangerQueryScript.reply(context, enemyID, tile)
			var expected := _exhaustiveReply(context, enemyID, tile)
			_require(assessment.value == expected,
				"reply for enemy %d at %s was %d, exhaustive sweep says %d" %
				[enemyID, tile, assessment.value, expected])
			_require(assessment.mode == AssessmentScript.REPLY,
				"a reply was not labelled as one")
			checked += 1
	_require(checked > 0, "no reply was checked against the exhaustive sweep")
	print("AI_DANGER replies_checked=%d" % checked)
	context.close()


func _checkBracketing() -> void:
	## feasible <= bound, always, and the bound never falls below any single
	## enemy's own reply.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := DecisionContextScript.forSimulator(simulator)
	for defenderIDValue in simulator.state.getAliveMonsterIDs():
		var defenderID := int(defenderIDValue)
		var defender: Monster = simulator.state.getMonster(defenderID)
		var tile: Vector2i = simulator.state.getMonsterPosition(defenderID)
		var bound := DangerQueryScript.conservativeBound(context, defender.team, tile)
		var feasible := DangerQueryScript.feasibleContinuation(context, defender.team, tile)
		_require(bound.mode == AssessmentScript.BOUND
			and feasible.mode == AssessmentScript.FEASIBLE,
			"the bracketing answers were not labelled")
		_require(feasible.value <= bound.value,
			"a feasible continuation at %s exceeded the bound: %d > %d" %
			[tile, feasible.value, bound.value])
		for enemyID in bound.contributors:
			var single := DangerQueryScript.reply(context, int(enemyID), tile)
			_require(single.value <= bound.value,
				"one enemy's reply exceeded the whole bound at %s" % tile)
		_require(not bound.approximations.is_empty(),
			"a bound reported no blind spots at all")
	context.close()


func _checkPreMoveMagic() -> void:
	## A caster that walks cannot cast. Danger must credit its spells from where
	## it stands and nowhere else, which is what separates this contract from
	## the influence map it replaces.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var state := simulator.state
	var caster: Monster = null
	var casterID := -1
	for monsterIDValue in state.getAliveMonsterIDs():
		var monster: Monster = state.getMonster(int(monsterIDValue))
		if monster.team == 2 and not monster.spellSets.is_empty() \
				and not monster.spellSets[0].is_empty():
			caster = monster
			casterID = int(monsterIDValue)
			break
	if caster == null:
		failures.append("the fixture has no enemy caster")
		return
	var reachSpell := SpellScript.new({})
	reachSpell.restoreRuntime(caster.spellSets[0][0].serializeRuntime())
	reachSpell.range = 2
	reachSpell.radius = 0
	reachSpell.bypass_los = true
	reachSpell.damage = 30
	reachSpell.damage_lines = [{"damage": 30, "element": "none"}]
	reachSpell.heals = false
	reachSpell.targetType = "single"
	state.setMonsterAbilities(casterID, [[reachSpell]], caster.passives)
	caster.move = 6

	var context := DecisionContextScript.forSimulator(simulator)
	var origin: Vector2i = state.getMonsterPosition(casterID)
	## A tile outside the spell's range from the caster's own cell, but well
	## inside it from somewhere the caster could walk to.
	var target := Vector2i(-1, -1)
	for candidate: Vector2i in HexGridScript.disc(origin, 6):
		if not state.isWalkable(candidate) or state.isOccupied(candidate):
			continue
		if HexGridScript.distance(origin, candidate) <= reachSpell.range + 1:
			continue
		target = candidate
		break
	if target == Vector2i(-1, -1):
		failures.append("the fixture had no tile beyond the caster's reach")
		context.close()
		return
	## The check is only worth anything if the illegal option is actually
	## tempting: there must be somewhere the caster could walk to from which the
	## spell would reach. Without that, crediting nothing proves nothing.
	var temptingCells := 0
	for destination: Vector2i in context.reachability(casterID)["destinations"]:
		if destination == origin:
			continue
		if HexGridScript.distance(destination, target) <= reachSpell.range:
			temptingCells += 1
	_require(temptingCells > 0,
		"no walked-to cell could have reached the target, so the check was vacuous")
	var assessment := DangerQueryScript.reply(context, casterID, target)
	for enemyID in assessment.contributors:
		_require(str(assessment.contributors[enemyID]["kind"]) != "spell",
			"danger credited a cast from a tile the caster would have to walk to")
	print("AI_DANGER premove_tempting_cells=%d credited=%d" %
		[temptingCells, assessment.contributors.size()])
	context.close()


func _checkOccupancyFeasibility() -> void:
	## Two enemies that can only strike from the same cell cannot both strike.
	## The bound may count them both; a feasible continuation may not.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := DecisionContextScript.forSimulator(simulator)
	for defenderIDValue in simulator.state.getAliveMonsterIDs():
		var defenderID := int(defenderIDValue)
		var defender: Monster = simulator.state.getMonster(defenderID)
		var tile: Vector2i = simulator.state.getMonsterPosition(defenderID)
		var feasible := DangerQueryScript.feasibleContinuation(
			context, defender.team, tile)
		var usedCells: Dictionary = {}
		for enemyID in feasible.contributors:
			var from: Vector2i = feasible.contributors[enemyID]["from"]
			_require(not usedCells.has(from),
				"a feasible continuation put two enemies on %s" % from)
			usedCells[from] = true
			_require(from != tile,
				"a feasible continuation stood an enemy on the defended tile")
	context.close()


func _checkSoundPruning() -> void:
	## The cheap geometric rejection must never drop something legal. An ability
	## that declares no reach at all is the case a careless bound gets wrong, so
	## it is built here on purpose and must survive.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var state := simulator.state
	var enemyID := -1
	for monsterIDValue in state.getAliveMonsterIDs():
		var monster: Monster = state.getMonster(int(monsterIDValue))
		if monster.team == 2 and not monster.spellSets.is_empty() \
				and not monster.spellSets[0].is_empty():
			enemyID = int(monsterIDValue)
			break
	if enemyID == -1:
		failures.append("the fixture has no enemy caster for the pruning check")
		return
	var enemy: Monster = state.getMonster(enemyID)
	var oddSpell := SpellScript.new({})
	oddSpell.restoreRuntime(enemy.spellSets[0][0].serializeRuntime())
	oddSpell.range = 0
	oddSpell.radius = 0
	oddSpell.min_range = 0
	oddSpell.targetType = "single"
	oddSpell.heals = false
	state.setMonsterAbilities(enemyID, [[oddSpell]], enemy.passives)
	var context := DecisionContextScript.forSimulator(simulator)
	var noted := false
	for defenderIDValue in state.getAliveMonsterIDs():
		var defender: Monster = state.getMonster(int(defenderIDValue))
		if defender.team == enemy.team:
			continue
		var tile: Vector2i = state.getMonsterPosition(int(defenderIDValue))
		var assessment := DangerQueryScript.reply(context, enemyID, tile)
		var expected := _exhaustiveReply(context, enemyID, tile)
		_require(assessment.value == expected,
			"an ability with no declared reach was mispriced at %s: %d against %d" %
			[tile, assessment.value, expected])
		if assessment.approximations.has(DangerQueryScript.APPROX_UNBOUNDED_ABILITY):
			noted = true
	_require(noted, "an ability with no declared reach was pruned without a note")
	context.close()


func _checkBudgetAndCost() -> void:
	## A budget produces a truncated answer, not a stall, and says so. Costs are
	## reported for a sparse question and a dense one; they are observations of
	## this host, never pass conditions.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := DecisionContextScript.forSimulator(simulator)
	var defenderID := int(simulator.state.getAliveMonsterIDs()[0])
	var defender: Monster = simulator.state.getMonster(defenderID)
	var tile: Vector2i = simulator.state.getMonsterPosition(defenderID)

	var full := DangerQueryScript.conservativeBound(context, defender.team, tile)
	_require(not full.truncated, "an unbudgeted query reported truncation")
	var starved := DangerQueryScript.conservativeBound(context, defender.team, tile, 1)
	_require(starved.truncated, "a starved query did not report truncation")
	_require(starved.value <= full.value,
		"a truncated query claimed more danger than the complete one")

	var sparseStart := Time.get_ticks_usec()
	var sparseQueries := 0
	for monsterIDValue in simulator.state.getAliveMonsterIDs():
		var monster: Monster = simulator.state.getMonster(int(monsterIDValue))
		var assessment := DangerQueryScript.conservativeBound(context, monster.team,
			simulator.state.getMonsterPosition(int(monsterIDValue)))
		sparseQueries += assessment.queries
	var sparseUsec := Time.get_ticks_usec() - sparseStart

	var denseStart := Time.get_ticks_usec()
	var denseQueries := 0
	var denseTiles := 0
	var reach := context.reachability(defenderID)
	for destination: Vector2i in reach["destinations"]:
		var assessment := DangerQueryScript.conservativeBound(
			context, defender.team, destination)
		denseQueries += assessment.queries
		denseTiles += 1
	var denseUsec := Time.get_ticks_usec() - denseStart

	var mapStart := Time.get_ticks_usec()
	ThreatMapScript.generate(simulator.state, defender.team,
		simulator.movementResolver, simulator.combatResolver)
	var mapUsec := Time.get_ticks_usec() - mapStart
	print("AI_DANGER sparse_tiles=%d sparse_queries=%d sparse_usec=%d dense_tiles=%d dense_queries=%d dense_usec=%d full_map_usec=%d" %
		[simulator.state.getAliveMonsterIDs().size(), sparseQueries, sparseUsec,
		denseTiles, denseQueries, denseUsec, mapUsec])
	context.close()


func _checkConsumers() -> void:
	## Commander safety and heal worth ask the same contract, so they cannot
	## disagree about what dangerous means.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := DecisionContextScript.forSimulator(simulator)
	var defenderID := int(simulator.state.getAliveMonsterIDs()[0])
	var defender: Monster = simulator.state.getMonster(defenderID)
	var tile: Vector2i = simulator.state.getMonsterPosition(defenderID)

	defender.hitpoints = defender.max_hitpoints
	var safe := DangerQueryScript.couldBeDefeatedAt(context, defenderID, tile)
	_require(not bool(safe["at_risk"]) or int(safe["danger"]) >= defender.hitpoints,
		"commander safety called a unit at risk below the incoming damage")
	_require(DangerQueryScript.healWorth(context, defenderID, tile, 10) == 0
		or bool(safe["at_risk"]),
		"a heal was worth something on a unit in no danger")

	defender.hitpoints = 1
	var exposed := DangerQueryScript.couldBeDefeatedAt(context, defenderID, tile)
	if int(exposed["danger"]) >= 1:
		_require(bool(exposed["at_risk"]),
			"a unit on one hit point with incoming damage was called safe")
		_require(DangerQueryScript.healWorth(context, defenderID, tile, 7) == 7,
			"a heal that saves a unit was worth nothing")
	context.close()
