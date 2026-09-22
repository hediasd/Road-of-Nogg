extends SceneTree

## The separated decision stream: one shared context, complete legal
## enumeration, filters that collapse only duplicates, named policies, and the
## legacy side policy frozen so the rework has a baseline to be measured against.

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const DecisionContextScript = preload("res://src/entity_ai/DecisionContext.gd")
const EnumeratorScript = preload("res://src/entity_ai/LegalActionEnumerator.gd")
const FilterScript = preload("res://src/entity_ai/CandidateFilter.gd")
const CandidateScript = preload("res://src/entity_ai/ActionCandidate.gd")
const PolicyCatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")
const LegacyPolicyScript = preload("res://src/entity_ai/legacy/LegacySidePolicy.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

const CASES_PATH := "res://scripts/battle/fixtures/ai/candidate_cases.json"
const LEGACY_PATH := "res://scripts/battle/fixtures/ai/legacy_decisions.json"

var failures: Array[String] = []
var cases: Dictionary = {}


func _init() -> void:
	cases = _loadJSON(CASES_PATH)
	_checkEnumerationCompleteness()
	_checkContextSharingAndStaleness()
	_checkPurity()
	_checkEquivalence()
	_checkCapAllowance()
	_checkPolicyIdentity()
	_checkSamplingCoverage()
	_checkLegacyDecisions()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_CANDIDATES_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_CANDIDATES_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _loadJSON(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("fixture could not be opened: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("fixture is not an object: %s" % path)
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
	var opened := simulator.startNextSideTurn("probe")
	if not bool(opened.get("success", false)):
		failures.append("no side opened")
		return null
	return simulator


func _context(simulator: BattleSimulator) -> DecisionContext:
	return DecisionContextScript.forSimulator(simulator)


func _checkEnumerationCompleteness() -> void:
	## An independent sweep: ask the resolvers directly, cell by cell, for every
	## legal thing this actor could do, and require the enumerator to have found
	## exactly that set. It is the same question asked without the enumerator's
	## loop structure, so a destination the enumerator forgets to visit shows up.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := _context(simulator)
	for actorIDValue in simulator.eligibleSideUnitIDs():
		var actorID := int(actorIDValue)
		var found: Dictionary = {}
		for candidate in EnumeratorScript.forActor(context, actorID):
			_require(not found.has(candidate.tie_key),
				"enumerator produced two candidates with tie key %s" % candidate.tie_key)
			found[candidate.tie_key] = candidate
		var expected := _exhaustiveLegalKeys(simulator, context, actorID)
		for key in expected:
			_require(found.has(key),
				"actor %d: enumeration missed the legal action %s" % [actorID, key])
		for key in found:
			_require(expected.has(key),
				"actor %d: enumeration invented the action %s" % [actorID, key])
		var coverage := EnumeratorScript.classCoverage(found.values())
		for actionClass: String in CandidateScript.ALL_CLASSES:
			_require(coverage.has(actionClass),
				"class coverage omitted %s entirely" % actionClass)
	context.close()


func _exhaustiveLegalKeys(simulator: BattleSimulator, context: DecisionContext,
		actorID: int) -> Dictionary:
	var state := simulator.state
	var resolver := simulator.combatResolver
	var actor: Monster = state.getMonster(actorID)
	var origin: Vector2i = state.getMonsterPosition(actorID)
	var expected: Dictionary = {}
	var reachable: Dictionary = {origin: true}
	for position in simulator.movementResolver.getReachability(actorID)["positions"]:
		reachable[position] = true
	for destinationValue in reachable:
		var destination: Vector2i = destinationValue
		if destination != origin and context.pathTo(actorID, destination).is_empty():
			continue
		expected[_key(destination, "wait", 0, 0, Vector2i(-1, -1))] = true
		for targetPos: Vector2i in HexGridScript.disc(destination, 1):
			if targetPos == destination:
				continue
			if resolver.canBasicAttackPositionFrom(actorID, destination, targetPos):
				expected[_key(destination, "attack", 0, 0, targetPos)] = true
		if destination != origin:
			continue
		for spellSetIndex in range(actor.spellSets.size()):
			for spellIndex in range(actor.spellSets[spellSetIndex].size()):
				var spell: Spell = actor.spellSets[spellSetIndex][spellIndex]
				for centerPos: Vector2i in HexGridScript.disc(destination, spell.range):
					if not resolver.canSpellTargetPositionFrom(
							actorID, spellSetIndex, spellIndex, destination, centerPos):
						continue
					expected[_key(destination, "spell", spellSetIndex,
						spellIndex, centerPos)] = true
	return expected


func _key(destination: Vector2i, action: String, spellSetIndex: int,
		spellIndex: int, targetPos: Vector2i) -> String:
	return "%02d:%02d:%s:%02d:%02d:%02d:%02d" % [
		destination.y, destination.x, action, spellSetIndex, spellIndex,
		targetPos.y + 1, targetPos.x + 1,
	]


func _checkContextSharingAndStaleness() -> void:
	## One context answers for every ready actor, and stops answering the moment
	## the board it was built from moves on.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := _context(simulator)
	var actors := simulator.eligibleSideUnitIDs()
	_require(actors.size() > 1, "the fixture has too few ready actors to share a context")
	var perActor: Dictionary = {}
	for actorIDValue in actors:
		var actorID := int(actorIDValue)
		perActor[actorID] = context.reachability(actorID)["destinations"].duplicate()
	for actorIDValue in actors:
		var actorID := int(actorIDValue)
		_require(context.reachability(actorID)["destinations"] == perActor[actorID],
			"a shared context answered differently the second time for actor %d" % actorID)
	_require(context.isCurrent(), "a context went stale without a mutation")
	var beforeDebug := context.debugFingerprint()
	var beforeRevision := context.revision()

	simulator.state.setMovementCost(Vector2i(0, 0),
		1 + int(simulator.state.movementCostBoard.at(Vector2i(0, 0))))
	_require(not context.isCurrent(), "a board mutation did not retire the context")
	_require(DecisionContextScript.revisionOf(simulator.state) != beforeRevision,
		"a board mutation did not advance the cheap revision")
	_require(context.debugFingerprint() != beforeDebug,
		"a board mutation did not change the debug fingerprint")

	## A restored timeline is a different branch even at an equal position: the
	## generation moves even when nothing else does.
	var restoredSimulator := _simulator(int(cases.get("seed", 1)))
	if restoredSimulator == null:
		return
	var branchContext := _context(restoredSimulator)
	var branchBefore := branchContext.revision()
	var restored := restoredSimulator.restoreSideTurn()
	_require(bool(restored.get("success", false)),
		"the probe could not restore a side turn: %s" % str(restored))
	_require(DecisionContextScript.revisionOf(restoredSimulator.state).x != branchBefore.x,
		"restoring a side turn did not advance the generation")
	_require(not branchContext.isCurrent(),
		"a context survived a restore onto an equal position")
	branchContext.close()
	context.close()


func _checkPurity() -> void:
	## Enumeration is a question, not a move: no events, no RNG draw, no state.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var historyBefore := simulator.state.history.size()
	var rngBefore := simulator.state.rng.state
	var revisionBefore := DecisionContextScript.revisionOf(simulator.state)
	var fingerprintBefore := BattleSimulatorScript.semanticFingerprint(simulator.state)
	var events := [0]
	simulator.events.unit_selected.connect(func(_side, _actor): events[0] += 1)
	simulator.events.monster_attacked.connect(
		func(_a, _b, _c, _d, _e): events[0] += 1)
	var context := _context(simulator)
	var total := 0
	for actorIDValue in simulator.eligibleSideUnitIDs():
		total += EnumeratorScript.forActor(context, int(actorIDValue)).size()
	context.close()
	_require(total > 0, "enumeration produced nothing to check for purity")
	_require(simulator.state.history.size() == historyBefore
		and simulator.state.rng.state == rngBefore
		and DecisionContextScript.revisionOf(simulator.state) == revisionBefore
		and events[0] == 0
		and BattleSimulatorScript.semanticFingerprint(simulator.state) == fingerprintBefore,
		"enumeration touched live state, RNG, history or signals")


func _checkEquivalence() -> void:
	## Collapsing keeps one candidate per distinguishable outcome and no fewer.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := _context(simulator)
	for actorIDValue in simulator.eligibleSideUnitIDs():
		var actorID := int(actorIDValue)
		var candidates := EnumeratorScript.forActor(context, actorID)
		var collapsed := FilterScript.collapseEquivalent(candidates)
		var keys: Dictionary = {}
		for candidate in collapsed:
			_require(not keys.has(candidate.equivalence_key),
				"collapse left two candidates with the same equivalence key")
			keys[candidate.equivalence_key] = true
		var distinct: Dictionary = {}
		for candidate in candidates:
			distinct[candidate.equivalence_key] = true
		_require(collapsed.size() == distinct.size(),
			"collapse dropped a distinguishable candidate for actor %d" % actorID)
		## Two spells that catch different units are never the same move, even
		## cast from the same tile at the same range.
		for candidate in candidates:
			for other in candidates:
				if candidate.equivalence_key != other.equivalence_key:
					continue
				_require(candidate.affected_targets == other.affected_targets
					and candidate.action_class == other.action_class
					and candidate.destination == other.destination,
					"two candidates with different effects shared an equivalence key")
	context.close()


func _checkCapAllowance() -> void:
	## A cap may make a policy look at less. It may not make a whole class of
	## action invisible.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := _context(simulator)
	var pooled: Array = []
	for actorIDValue in simulator.eligibleSideUnitIDs():
		pooled.append_array(EnumeratorScript.forActor(context, int(actorIDValue)))
	var present := EnumeratorScript.classCoverage(pooled)
	var limit := int(cases.get("cap_limit", 6))
	var capped := FilterScript.capWithAllowance(pooled, limit)
	_require(capped.size() <= maxi(limit, _presentClassCount(present)
		* FilterScript.DEFAULT_CLASS_ALLOWANCE),
		"the cap kept more than its limit and allowance permit")
	var keptClasses := EnumeratorScript.classCoverage(capped)
	for actionClass: String in CandidateScript.ALL_CLASSES:
		if int(present[actionClass]) == 0:
			continue
		_require(int(keptClasses[actionClass]) > 0,
			"the cap starved the action class %s" % actionClass)
	## The legacy destination budget is a filter, and still reaches the origin.
	for actorIDValue in simulator.eligibleSideUnitIDs():
		var actorID := int(actorIDValue)
		var limited := FilterScript.nearestDestinations(context, actorID, 10)
		_require(limited.size() <= 10, "the destination budget exceeded its limit")
		_require(limited.has(context.reachability(actorID)["origin"]),
			"the destination budget dropped the actor's own tile")
	context.close()


func _presentClassCount(coverage: Dictionary) -> int:
	var present := 0
	for actionClass in coverage:
		if int(coverage[actionClass]) > 0:
			present += 1
	return present


func _checkPolicyIdentity() -> void:
	_require(PolicyCatalogScript.has(PolicyCatalogScript.LEGACY_SIDE),
		"the catalog lost the legacy side policy")
	_require(not PolicyCatalogScript.has("no_such_policy_v9"),
		"the catalog accepted an unknown policy id")
	_require(PolicyCatalogScript.fingerprint("no_such_policy_v9").begins_with("unknown:"),
		"an unknown policy id did not fingerprint as unknown")
	var first := PolicyCatalogScript.fingerprint(PolicyCatalogScript.LEGACY_SIDE)
	var altered := PolicyCatalogScript.fingerprint(
		PolicyCatalogScript.LEGACY_SIDE, {"max_side_destinations": 4})
	_require(first != altered,
		"the same policy under a different configuration fingerprinted the same")
	_require(first == PolicyCatalogScript.fingerprint(PolicyCatalogScript.LEGACY_SIDE),
		"a policy fingerprint was not stable")


func _checkSamplingCoverage() -> void:
	## A uniform draw over the action abstraction, with what it actually reached
	## reported by class. The claim is about this finite candidate set, not about
	## every path on the board.
	var simulator := _simulator(int(cases.get("seed", 1)))
	if simulator == null:
		return
	var context := _context(simulator)
	var pooled: Array = []
	for actorIDValue in simulator.eligibleSideUnitIDs():
		pooled.append_array(EnumeratorScript.forActor(context, int(actorIDValue)))
	pooled.sort_custom(CandidateScript.tieKeyLess)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cases.get("sample_seed", 7))
	var drawn: Array = []
	var sampleCount := int(cases.get("sample_count", 400))
	for _draw in range(sampleCount):
		drawn.append(pooled[rng.randi_range(0, pooled.size() - 1)])
	var reached := EnumeratorScript.classCoverage(drawn)
	var present := EnumeratorScript.classCoverage(pooled)
	for actionClass: String in CandidateScript.ALL_CLASSES:
		if int(present[actionClass]) == 0:
			continue
		_require(int(reached[actionClass]) > 0,
			"uniform sampling never reached the action class %s" % actionClass)
	print("AI_CANDIDATES coverage legal=%s sampled=%s of %d draws" %
		[str(present), str(reached), sampleCount])
	context.close()


func _checkLegacyDecisions() -> void:
	## The shipped policy, frozen. A decision that moves fails here whether the
	## change was deliberate or not; a deliberate one updates the fixture in the
	## same commit and says so.
	var frozen := _loadJSON(LEGACY_PATH)
	if frozen.is_empty():
		return
	_require(str(frozen.get("policy_fingerprint", "")) ==
		LegacyPolicyScript.policyFingerprint(),
		"the legacy policy's identity changed without its fixture")
	for recordValue in frozen.get("decisions", []):
		var record: Dictionary = recordValue
		var simulator := _simulator(int(record["seed"]))
		if simulator == null:
			continue
		var actual := LegacyPolicyScript.decisionRecord(simulator)
		_require(_same(actual, record["decision"]),
			"legacy decision changed at seed %d:\n  frozen %s\n  actual %s" %
			[int(record["seed"]), JSON.stringify(record["decision"]),
			JSON.stringify(actual)])
		## Spending the same decision in different slice sizes must not move it.
		for sliceCount in [1, 3, 64]:
			var sliced := _simulator(int(record["seed"]))
			if sliced == null:
				continue
			_require(_same(LegacyPolicyScript.decisionRecord(sliced, sliceCount),
				record["decision"]),
				"legacy decision at seed %d depended on a slice size of %d" %
				[int(record["seed"]), sliceCount])


func _same(a, b) -> bool:
	return JSON.stringify(_normalize(a), "", true) == \
		JSON.stringify(_normalize(b), "", true)


func _normalize(value):
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var ordered: Dictionary = {}
		for key in keys:
			ordered[str(key)] = _normalize(value[key])
		return ordered
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_normalize(item))
		return items
	if value is float and value == floor(value) and absf(value) < 9007199254740992.0:
		return int(value)
	return value
