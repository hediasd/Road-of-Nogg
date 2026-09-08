extends SceneTree

const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 20260908

var failures: Array[String] = []
var _root: Node3D
var _sim
var _adapter: HexBattleVisualAdapter


func _init() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	if not _build():
		_finish()
		return
	_checkLayersAreIndependent()
	_checkPreviewMatchesTheResolver()
	_checkForecastMatchesCombatResolver()
	_checkForecastStatesItsUncertainty()
	_checkForecastEmitsNoEvents()
	_finish()


func _build() -> bool:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	if not loaded["success"]:
		failures.append("could not load the scenario: %s" % str(loaded.get("error", "")))
		return false
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		failures.append("could not build a hex state")
		return false
	_sim = BattleSimulatorScript.new(SEED)
	_sim.configureHexState(stateResult["state"], loaded["scenario"], {"scenarioPath": SCENARIO})
	_adapter = AdapterScript.new(_root, loaded["scenario"].battleMap, _sim.state)
	_adapter.setCombatResolver(_sim.combatResolver)
	return true


## The layer rule this item exists for: previewing must not delete the reach the player is
## aiming from.
func _checkLayersAreIndependent() -> void:
	var map = _sim.state.battleMap
	var cells: Array = map.validCells()
	var reach: Array = cells.slice(0, 6)
	var preview: Array = cells.slice(2, 5)

	_adapter.show_movement_options(reach, [], [])
	var reachCount := _adapter.layerCellCount(AdapterScript.LAYER_REACH)
	_require(reachCount == reach.size(),
		"reach layer painted %d of %d cells" % [reachCount, reach.size()])

	_adapter.showCommandPreview(preview)
	_require(_adapter.previewCellCount() == preview.size(),
		"preview painted %d of %d cells" % [_adapter.previewCellCount(), preview.size()])
	_require(_adapter.layerCellCount(AdapterScript.LAYER_REACH) == reachCount,
		"showing a preview destroyed the reach overlay underneath it")

	_adapter.clearCommandPreview()
	_require(_adapter.previewCellCount() == 0, "clearing the preview left markers behind")
	_require(_adapter.layerCellCount(AdapterScript.LAYER_REACH) == reachCount,
		"clearing the preview also cleared the reach")

	# Hover and threat are their own layers too, and neither disturbs the others.
	_adapter.show_hover_reach(cells.slice(0, 3))
	_adapter.show_threat_options(cells.slice(3, 7))
	_require(_adapter.layerCellCount(AdapterScript.LAYER_REACH) == reachCount,
		"hover or threat cleared the reach")
	_adapter.clear_hover_reach()
	_require(_adapter.layerCellCount(AdapterScript.LAYER_THREAT) > 0,
		"clearing hover also cleared threat")

	# The port's own clear still means all of them.
	_adapter.clear_tactical_overlays()
	for layer in [
		AdapterScript.LAYER_REACH, AdapterScript.LAYER_HOVER,
		AdapterScript.LAYER_THREAT, AdapterScript.LAYER_TARGET, AdapterScript.LAYER_PREVIEW,
	]:
		_require(_adapter.layerCellCount(layer) == 0,
			"clear_tactical_overlays left the '%s' layer painted" % layer)


## The previewed set must BE the resolver's set, not a shape re-derived from a radius.
func _checkPreviewMatchesTheResolver() -> void:
	var combat = _sim.combatResolver
	var checked := 0
	for monsterIDValue in _sim.state.monsters:
		var monsterID := int(monsterIDValue)
		var monster = _sim.state.getMonster(monsterID)
		if monster == null or not monster.is_alive():
			continue
		var fromPos: Vector2i = _sim.state.getMonsterPosition(monsterID)

		# Basic attack reach.
		var expectedAttack: Array = combat.getBasicAttackTargetPositionsFrom(monsterID, fromPos)
		var previewAttack: Array = _adapter.previewAttackCells(monsterID, fromPos)
		_require(previewAttack == expectedAttack,
			"attack preview for %d differs from the resolver" % monsterID)

		# Every spell the monster has, over several centres -- covering disc, cross and line
		# shapes and centres the cast could not be confirmed on.
		for setIndex in range(monster.spellSets.size()):
			var spellSet: Array = monster.spellSets[setIndex]
			for spellIndex in range(spellSet.size()):
				for centre: Vector2i in _sampleCentres(fromPos):
					var expected: Array = combat.getSpellAffectedPositionsFrom(
						monsterID, setIndex, spellIndex, fromPos, centre, true)
					var preview: Array = _adapter.previewSpellCells(
						monsterID, setIndex, spellIndex, fromPos, centre)
					_require(preview == expected,
						"spell preview (%d, set %d, spell %d, centre %s) differs from the resolver"
						% [monsterID, setIndex, spellIndex, centre])
					checked += 1
	_require(checked > 0, "no spell preview was compared at all")
	print("preview compared against the resolver in %d cases" % checked)


func _sampleCentres(fromPos: Vector2i) -> Array[Vector2i]:
	var centres: Array[Vector2i] = [fromPos]
	for cell: Vector2i in _sim.state.battleMap.validCells():
		if centres.size() >= 6:
			break
		if cell != fromPos:
			centres.append(cell)
	return centres


## The number must be the resolver's own, not a second calculation.
func _checkForecastMatchesCombatResolver() -> void:
	var combat = _sim.combatResolver
	var compared := 0
	for attackerIDValue in _sim.state.monsters:
		var attackerID := int(attackerIDValue)
		var attacker = _sim.state.getMonster(attackerID)
		if attacker == null or not attacker.is_alive():
			continue
		for targetIDValue in _sim.state.monsters:
			var targetID := int(targetIDValue)
			if targetID == attackerID:
				continue
			var target = _sim.state.getMonster(targetID)
			if target == null or not target.is_alive():
				continue
			var targetPos: Vector2i = _sim.state.getMonsterPosition(targetID)
			var forecast := _adapter.forecastAttack(attackerID, targetPos)
			if not bool(forecast.get("available", false)):
				continue
			var expected: int = combat.calculateBasicDamage(attacker, target, true)
			_require(int(forecast["minimum"]) == expected,
				"attack forecast %d vs resolver %d" % [int(forecast["minimum"]), expected])
			_require(int(forecast["maximum"]) == expected,
				"a basic attack has no roll, so its forecast must not span a range")
			_require(bool(forecast["exact"]),
				"a basic attack forecast reported itself uncertain")
			compared += 1
	_require(compared > 0, "no attack forecast was compared")
	print("attack forecasts compared against CombatResolver: %d" % compared)


## The forecast has to say when it does not know.
func _checkForecastStatesItsUncertainty() -> void:
	var attackerID := -1
	var targetID := -1
	for idValue in _sim.state.monsters:
		var monster = _sim.state.getMonster(int(idValue))
		if monster == null or not monster.is_alive():
			continue
		if attackerID == -1:
			attackerID = int(idValue)
		elif targetID == -1 and _sim.state.getMonster(attackerID).team != monster.team:
			targetID = int(idValue)
	if attackerID == -1 or targetID == -1:
		failures.append("could not find two living monsters on opposing teams")
		return

	var targetPos: Vector2i = _sim.state.getMonsterPosition(targetID)
	var forecast := _adapter.forecastAttack(attackerID, targetPos)
	_require(bool(forecast.get("available", false)), "no forecast was available")
	if not bool(forecast.get("available", false)):
		return

	for key in [
		"minimum", "maximum", "critical_chance", "exact", "target_hitpoints",
		"lethal", "possibly_lethal", "reactive_risk",
	]:
		_require(forecast.has(key), "the forecast does not report '%s'" % key)

	_require(int(forecast["minimum"]) <= int(forecast["maximum"]),
		"forecast minimum exceeds its maximum")
	_require(bool(forecast["exact"]) == (int(forecast["minimum"]) == int(forecast["maximum"])),
		"'exact' disagrees with the reported range")

	# Lethality is knowable exactly, because take_damage clamps to remaining hitpoints.
	var target = _sim.state.getMonster(targetID)
	var expectedLethal: bool = int(forecast["minimum"]) >= int(target.hitpoints)
	_require(bool(forecast["lethal"]) == expectedLethal,
		"lethality disagrees with the target's remaining hitpoints")
	_require(not (bool(forecast["lethal"]) and bool(forecast["possibly_lethal"])),
		"a certain kill also reported itself as only possibly lethal")

	# A dead or absent target has no forecast rather than a zero one.
	var empty := Vector2i(-99, -99)
	_require(not bool(_adapter.forecastAttack(attackerID, empty).get("available", true)),
		"a forecast was offered for a cell with nobody on it")

	print("forecast: min %d, max %d, crit %.2f, lethal %s, reactive risk %s" % [
		int(forecast["minimum"]), int(forecast["maximum"]), float(forecast["critical_chance"]),
		bool(forecast["lethal"]), bool(forecast["reactive_risk"]),
	])


## A forecast that fired battle events would change the battle it describes. `is_simulation` is
## what prevents it, and this asserts the whole state is untouched -- history included.
func _checkForecastEmitsNoEvents() -> void:
	var before: int = _sim.state.history.size()
	var beforeState: Dictionary = _sim.state.serialize_state()

	for attackerIDValue in _sim.state.monsters:
		var attackerID := int(attackerIDValue)
		for targetIDValue in _sim.state.monsters:
			var targetPos: Vector2i = _sim.state.getMonsterPosition(int(targetIDValue))
			_adapter.forecastAttack(attackerID, targetPos)
			_adapter.forecastSpell(attackerID, 0, 0, targetPos)

	_require(_sim.state.history.size() == before,
		"forecasting appended %d events to battle history" % [_sim.state.history.size() - before])
	_require(
		BattleSimulatorScript._canonicalJSON(beforeState)
			== BattleSimulatorScript._canonicalJSON(_sim.state.serialize_state()),
		"forecasting changed the battle state")


func _finish() -> void:
	if _adapter != null:
		_adapter.dispose()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_PREVIEW_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_PREVIEW_OK")
	quit(0)
