## BattleInvariants: a whole battle breaks none of them, and a broken state is caught.
##
## The second half is the point. A checker that reports nothing on a corrupted board looks exactly
## like a checker on a healthy one, and `docs/WORLDMAP_DESIGN.md` section 11 records three probes
## that passed for weeks while measuring nothing. So every invariant family here is shown failing
## on a state broken on purpose, and the clean run is only the other half of the proof.

extends SceneTree

const BattleInvariantsScript = preload("res://src/battle_sim/BattleInvariants.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const RunBattleScript = preload("res://scripts/battle/run_battle.gd")

const SCENARIO := "res://data/battle/scenarios/proving_ground_cpu_cpu.json"
const SEED := 42

var failures: Array[String] = []


func _init() -> void:
	_checkCleanStateHasNoViolations()
	_checkWholeBattleHasNoViolations()
	_checkTwoUnitsOnOneCellIsCaught()
	_checkBoardLayerDisagreementIsCaught()
	_checkImpossibleHitpointsAreCaught()
	_checkUnplacedLivingUnitIsCaught()
	_checkSpentUnitWithAnUnfinishedTurnIsCaught()
	_checkMagicAfterMovingIsCaught()
	_checkNegativeEffectDurationIsCaught()
	_checkImpossibleWinnerIsCaught()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("BATTLE_INVARIANTS_FAILURE: %s" % failure)
		quit(1)
		return
	print("BATTLE_INVARIANTS_OK")
	quit(0)


## --- The clean cases -------------------------------------------------------

func _checkCleanStateHasNoViolations() -> void:
	var state := _freshState()
	if state == null:
		return
	var violations: Array[String] = BattleInvariantsScript.violations(state)
	if not violations.is_empty():
		failures.append("a freshly deployed scenario already violates: %s" % [violations])


func _checkWholeBattleHasNoViolations() -> void:
	var result: Dictionary = RunBattleScript.run(SCENARIO, SEED, "", "")
	if not bool(result.get("ok", false)):
		failures.append("the battle did not run: %s" % str(result.get("error", "")))
		return
	var violations: Array = result.get("invariant_violations", [])
	if not violations.is_empty():
		failures.append("a whole battle at seed %d violated %d time(s), first: %s" % [
			SEED, violations.size(), str(violations[0])])
	if int(result.get("decisions", 0)) <= 0:
		failures.append("the battle resolved no decisions, so it proves nothing")


## --- The negative controls, one per invariant family -----------------------

func _checkTwoUnitsOnOneCellIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.size() < 2:
		failures.append("the scenario deployed fewer than two units")
		return
	var victim: Vector2i = state.monsterPositions[ids[0]]
	state.monsterPositions[ids[1]] = victim
	_requireCaught(state, "share cell", "two units standing on one cell")


func _checkBoardLayerDisagreementIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	var pos: Vector2i = state.monsterPositions[ids[0]]
	state.board.set_at(0, pos)
	_requireCaught(state, "board layer", "a unit the board layer has forgotten")


func _checkImpossibleHitpointsAreCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	var monster: Monster = state.monsters[ids[0]]
	monster.hitpoints = monster.max_hitpoints + 1
	_requireCaught(state, "hitpoints", "a unit healed past its maximum")


func _checkUnplacedLivingUnitIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	var pos: Vector2i = state.monsterPositions[ids[0]]
	state.board.set_at(0, pos)
	state.monsterPositions.erase(ids[0])
	_requireCaught(state, "holds no cell", "a living unit that is on no cell at all")


func _checkSpentUnitWithAnUnfinishedTurnIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	state.activeSideID = state.monsters[ids[0]].team
	state.spentUnitIDs[ids[0]] = true
	state.pendingUnitTurns[ids[0]] = {"has_moved": false, "has_acted": false, "action": ""}
	_requireCaught(state, "unfinished turn", "a spent unit still holding a turn")


func _checkMagicAfterMovingIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	state.activeSideID = state.monsters[ids[0]].team
	state.pendingUnitTurns[ids[0]] = {
		"has_moved": true, "has_acted": true, "action": "spell",
	}
	_requireCaught(state, "magic after moving", "a spell resolved after a move")


func _checkNegativeEffectDurationIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	var ids := _placedIDs(state)
	if ids.is_empty():
		return
	state.addEffect(ids[0], "poison", 2)
	state.activeEffects[ids[0]][0]["remainingTurns"] = -1
	_requireCaught(state, "turns remaining", "an effect counted past zero")


func _checkImpossibleWinnerIsCaught() -> void:
	var state := _freshState()
	if state == null:
		return
	state.battleOutcome = 99
	_requireCaught(state, "never fought", "a winner that never fought")


## --- Helpers ---------------------------------------------------------------

## A deployed scenario, freshly built, so one control's corruption never reaches the next.
func _freshState() -> BattleState:
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	var validation := config.validate()
	if not validation.success:
		failures.append("the scenario's setup no longer validates")
		return null
	var built := BattleSetupFactoryScript.createHexState(config)
	if not bool(built.get("success", false)):
		failures.append("could not deploy the scenario: %s" % str(built.get("error", "")))
		return null
	return built["state"]


func _placedIDs(state: BattleState) -> Array[int]:
	var ids: Array[int] = []
	for monsterID in state.monsterPositions:
		ids.append(int(monsterID))
	ids.sort()
	return ids


## The corrupted state must be reported, and reported as the thing that is wrong with it -- a
## checker that answers every corruption with the same unrelated violation is not measuring either.
func _requireCaught(state: BattleState, expectedFragment: String, description: String) -> void:
	var violations: Array[String] = BattleInvariantsScript.violations(state)
	if violations.is_empty():
		failures.append("%s went unreported" % description)
		return
	for violation: String in violations:
		if violation.findn(expectedFragment) != -1:
			return
	failures.append("%s was reported as %s, which does not name '%s'" % [
		description, [violations], expectedFragment])
