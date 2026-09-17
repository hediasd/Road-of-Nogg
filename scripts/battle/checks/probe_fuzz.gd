## Random legal play, across every CPU-vs-CPU scenario, must not break the rules.
##
## What this asserts about a fuzz run, per battle:
##
## 1. It ends -- by elimination or at the round cap. A fight that neither resolves nor caps is a
##    stall, and a stall in a headless runner is indistinguishable from a hang.
## 2. It violates no invariant (`BattleInvariants`, on in the runner).
## 3. Nothing in it is a script error. `run_probe.ps1` fails the probe on one anyway; this states
##    it, because a random run is exactly how an untested branch gets reached.
## 4. The same seed replays it byte for byte, so a failure found here is reproducible from the
##    seed alone -- the whole reason the draw comes from the battle's own RNG.
##
## And once, separately: a move undone before acting leaves the unit where it started and the turn
## still resolvable. Nothing in the command path can reach `undoMovePhase()` -- `executeCommand()`
## resolves a whole turn -- so the phase API is driven directly here. Undo is a player affordance
## with no CPU caller at all, which makes it the least exercised mutation in the simulator.

extends SceneTree

const BattleCommandScript = preload("res://src/battle_sim/BattleCommand.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const ReachQueryScript = preload("res://src/battle_sim/ReachQuery.gd")
const RunBattleScript = preload("res://scripts/battle/run_battle.gd")
const SideDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")

const BRAIN := "RandomLegalBrain"
const SCENARIOS: Array[String] = [
	"res://data/battle/scenarios/proving_ground_cpu_cpu.json",
	"res://data/battle/scenarios/hexmap_cpu_cpu.json",
	"res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json",
]
## Four seeds per scenario keeps the whole probe inside a two-minute budget on this host. It is a
## smoke-sized fuzz run, not a campaign: a long hunt belongs in a championship.
const SEEDS: Array[int] = [1, 2, 3, 4]
const END_REASONS: Array[String] = ["elimination", "round_limit_survivor_count"]

var failures: Array[String] = []
var decisions := 0
var lines: Dictionary = {}
var actionKinds: Dictionary = {}
var movesTaken := 0


func _init() -> void:
	for scenario: String in SCENARIOS:
		for seedValue: int in SEEDS:
			_fuzzOne(scenario, seedValue)
	_checkEveryKindOfTurnGetsPlayed()
	_checkSameSeedReplaysIdentically()
	_checkRandomPlayDiffersFromPolicyPlay()
	_checkUndoLeavesTheTurnResolvable()

	if decisions <= 0:
		failures.append("no decision was made in any fuzz battle")

	if not failures.is_empty():
		for failure: String in failures:
			printerr("BATTLE_FUZZ_FAILURE: %s" % failure)
		quit(1)
		return
	print("fuzzed %d battle(s), %d decision(s), %d with a move; kinds %s" % [
		lines.size(), decisions, movesTaken, actionKinds])
	print("BATTLE_FUZZ_OK")
	quit(0)


func _fuzzOne(scenario: String, seedValue: int) -> void:
	var result: Dictionary = RunBattleScript.run(scenario, seedValue, "", "", true, BRAIN, -1)
	var label := "%s at seed %d" % [scenario.get_file(), seedValue]
	if not bool(result.get("ok", false)):
		failures.append("%s did not run: %s" % [label, str(result.get("error", ""))])
		return
	var violations: Array = result.get("invariant_violations", [])
	if not violations.is_empty():
		failures.append("%s violated %d invariant(s), first: %s" % [
			label, violations.size(), str(violations[0])])
	var endReason := str(result.get("end_reason", ""))
	if not END_REASONS.has(endReason):
		failures.append("%s ended as '%s', which is neither elimination nor the round cap" % [
			label, endReason])
	decisions += int(result.get("decisions", 0))
	lines["%s|%d" % [scenario, seedValue]] = str(result.get("line", ""))
	_tallyOperations(str(result.get("line", "")))


## What the run actually did, read back out of the record rather than trusted.
func _tallyOperations(line: String) -> void:
	if line.is_empty():
		return
	var battle = JSON.parse_string(line)
	if not battle is Dictionary:
		failures.append("a battle's record line did not parse")
		return
	for decision in battle.get("decisions", []):
		var chosen: Dictionary = decision.get("chosen", {})
		var action := str(chosen.get("action", ""))
		actionKinds[action] = int(actionKinds.get(action, 0)) + 1
		var path = chosen.get("move_path", [])
		if path is Array and not path.is_empty():
			movesTaken += 1


## THE CHECK THIS PROBE WAS MISSING. Its first version asserted that battles end, break no
## invariant and replay -- all of which a brain that waits with every unit, every round, satisfies
## perfectly. And that is exactly what the first RandomLegalBrain did: 100 battles, 24,000
## decisions, every one a wait, every battle a draw at the round cap. The side deliberation was
## ranking each unit's random pick by score, and a wait scores 0 while a random real move often
## scores below it, so the best-scored proposal was a wait nearly every time.
##
## A fuzzer that only ever waits reaches less of the simulator than the authored brains do. So the
## coverage itself is asserted: several kinds of turn, and real movement among them.
func _checkEveryKindOfTurnGetsPlayed() -> void:
	var kinds: Array = actionKinds.keys()
	if kinds.size() < 2:
		failures.append("random play produced only %s turns: %s" % [
			"one kind of" if kinds.size() == 1 else "no", actionKinds])
	if int(actionKinds.get("attack", 0)) + int(actionKinds.get("spell", 0)) == 0:
		failures.append("random play never attacked and never cast: %s" % actionKinds)
	if movesTaken == 0:
		failures.append("random play never moved a unit")


func _checkSameSeedReplaysIdentically() -> void:
	var scenario: String = SCENARIOS[0]
	var seedValue: int = SEEDS[0]
	var again: Dictionary = RunBattleScript.run(scenario, seedValue, "", "", true, BRAIN, -1)
	if not bool(again.get("ok", false)):
		failures.append("the repeat run did not run: %s" % str(again.get("error", "")))
		return
	var first := str(lines.get("%s|%d" % [scenario, seedValue], ""))
	if str(again.get("line", "")) != first:
		failures.append("random play at one seed produced two different records")


## A random brain that quietly fell back to the scored decision would pass everything above. It
## would also produce the policy run's record, so comparing the two is what rules that out.
func _checkRandomPlayDiffersFromPolicyPlay() -> void:
	var scenario: String = SCENARIOS[0]
	var seedValue: int = SEEDS[0]
	var policy: Dictionary = RunBattleScript.run(scenario, seedValue, "", "", true, "", -1)
	if not bool(policy.get("ok", false)):
		failures.append("the policy run did not run: %s" % str(policy.get("error", "")))
		return
	if str(policy.get("line", "")) == str(lines.get("%s|%d" % [scenario, seedValue], "")):
		failures.append("the random brain produced the same battle the authored brains do")


func _checkUndoLeavesTheTurnResolvable() -> void:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIOS[0])
	if not bool(loaded.get("success", false)):
		failures.append("could not load %s" % SCENARIOS[0])
		return
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIOS[0]
	config.seed = SEEDS[0]
	if not config.validate().success:
		failures.append("the undo scenario's setup no longer validates")
		return
	var built := BattleSetupFactoryScript.createHexState(config)
	if not bool(built.get("success", false)):
		failures.append("could not deploy the undo scenario")
		return

	var sim = BattleSimulatorScript.new(SEEDS[0])
	sim.configureHexState(built["state"], loaded["scenario"], {"scenarioPath": SCENARIOS[0]})
	sim.setInvariantChecks(true)
	sim.overrideBrains(BRAIN, -1)
	sim.startBattle()
	var opened := sim.startNextSideTurn("fuzz")
	if not bool(opened.get("success", false)):
		failures.append("could not open a side: %s" % str(opened.get("reason", "")))
		return

	var undone := 0
	for unitID: int in sim.eligibleSideUnitIDs():
		var selection := sim.selectUnit(unitID, "fuzz")
		if not bool(selection.get("success", false)):
			failures.append("could not select unit %d: %s" % [
				unitID, str(selection.get("reason", ""))])
			return
		var origin: Vector2i = sim.state.getMonsterPosition(unitID)
		var destination := _stepAwayFrom(sim, unitID, origin)
		if destination == origin:
			continue
		var moved := sim.executeMovePhase(unitID, [destination], "fuzz")
		if not bool(moved.get("success", false)):
			failures.append("unit %d could not take a legal step: %s" % [
				unitID, str(moved.get("reason", ""))])
			return
		var rewound := sim.undoMovePhase(unitID)
		if not bool(rewound.get("success", false)):
			failures.append("unit %d could not undo its move: %s" % [
				unitID, str(rewound.get("reason", ""))])
			return
		if sim.state.getMonsterPosition(unitID) != origin:
			failures.append("unit %d stands at %s after undoing a move from %s" % [
				unitID, sim.state.getMonsterPosition(unitID), origin])
			return
		var resolved = sim.executeCommand(unitID, BattleCommandScript.wait(), "fuzz")
		if not resolved.success:
			failures.append("unit %d could not wait after undoing: %s" % [unitID, resolved.reason])
			return
		undone += 1
		if undone >= 2:
			break

	if undone == 0:
		failures.append("no unit had anywhere to step, so undo was never exercised")
	var violations: Array = sim.invariantViolations()
	if not violations.is_empty():
		failures.append("undo violated %d invariant(s), first: %s" % [
			violations.size(), str(violations[0])])


## Any reachable empty cell that is not where the unit already stands.
func _stepAwayFrom(sim, unitID: int, origin: Vector2i) -> Vector2i:
	var reach: Dictionary = ReachQueryScript.forMonster(sim, unitID)
	for cell: Vector2i in reach["reachable"]:
		if cell != origin and not sim.state.isOccupied(cell):
			return cell
	return origin
