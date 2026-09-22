extends SceneTree

## FHB-5: runs one scenario at one seed, headlessly, and writes both outputs -- the readable log a
## person follows and the machine record a model trains on.
##
##     Godot_v4.4-stable_win64.exe --headless --path . --script scripts/battle/run_battle.gd \
##         -- <scenarioPath> [seed] [recordPath] [logPath]
##
## Everything after the scenario is optional; the defaults land under `battle_output/battles/` at
## the project root, the one gitignored folder every battle output goes to. See `BattleOutputPaths`.
##
## THE CORPUS IS JSONL: ONE BATTLE PER LINE. Three reasons, and the third is the one that settled
## it. A training pipeline streams, shuffles and shards line-delimited JSON natively, where a
## directory of N files needs a manifest before it can do any of that. A run that dies partway
## leaves every completed line intact and readable, where a half-written pretty-printed file is
## not parseable at all. And it makes the single-battle case free: this script writes exactly one
## line, so a single battle is simply a one-line corpus rather than a second format that a reader
## would have to branch on. `run_championship.gd` appends the same lines from the same writer.
##
## The cost of that choice, stated plainly: one battle's record is not human-readable at rest. That
## is what the log beside it is for, and why this script writes both rather than choosing.
##
## A PLAYER PARTY IS REFUSED, NOT QUIETLY PLAYED BY THE CPU. A console has nobody to choose a
## member or a command, so a scenario with a player party would be recorded as though a policy
## made decisions that a fallback actually made -- which is worse than not recording it, because
## the corpus would look complete. Use the `_cpu_cpu` scenario of a pair.

const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const ConsoleVisualAdapterScript = preload("res://src/presentation/ConsoleVisualAdapter.gd")
const RecordAdapterScript = preload("res://src/presentation/BattleRecordAdapter.gd")
const BattleOutputPathsScript = preload("res://src/presentation/BattleOutputPaths.gd")
const BattlePartyScript = preload("res://src/entities/BattleParty.gd")
const SideDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")

const DEFAULT_SEED := 42
const MAX_ROUNDS := 30


func _init() -> void:
	var args := parseFlags(OS.get_cmdline_user_args())
	var positional: Array = args["positional"]
	if positional.is_empty():
		printerr("usage: run_battle.gd -- <scenarioPath> [seed] [recordPath] [logPath] "
			+ "[--brain=<BrainName>] [--brain-team=<teamID>]")
		quit(1)
		return

	if not str(args["error"]).is_empty():
		printerr("HEX_BATTLE_RUN_FAILED: %s" % str(args["error"]))
		quit(1)
		return

	var scenarioPath: String = positional[0]
	var seedValue := int(positional[1]) if positional.size() > 1 else DEFAULT_SEED
	var stem := "%s_seed%d" % [scenarioPath.get_file().get_basename(), seedValue]
	var recordPath: String = positional[2] if positional.size() > 2 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.BATTLES, "%s.jsonl" % stem)
	var logPath: String = positional[3] if positional.size() > 3 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.BATTLES, "%s.log.txt" % stem)

	var result := run(
		scenarioPath, seedValue, recordPath, logPath, true,
		str(args["brain"]), int(args["brain_team"])
	)
	if not bool(result.get("ok", false)):
		printerr("HEX_BATTLE_RUN_FAILED: %s" % str(result.get("error", "")))
		quit(1)
		return

	# A battle that broke its own rules is not a battle this script reports as run, however
	# complete the record looks. The outputs stay on disk: they are the evidence.
	var violations: Array = result.get("invariant_violations", [])
	if not violations.is_empty():
		for violation in violations:
			printerr("BATTLE_INVARIANT_VIOLATION: %s" % str(violation))
		printerr("HEX_BATTLE_RUN_FAILED: %d invariant violation(s); see %s" % [
			violations.size(), recordPath,
		])
		quit(1)
		return

	print("wrote %s" % recordPath)
	print("wrote %s" % logPath)
	print("%s by %s after %d round(s), %d decision(s)" % [
		"draw" if bool(result["draw"]) else "winner team %d" % int(result["winner_team"]),
		str(result["end_reason"]), int(result["rounds"]), int(result["decisions"]),
	])
	print("HEX_BATTLE_RUN_OK %s" % stem)
	quit(0)


## One battle, start to finish. Returns the outcome and the record line rather than only writing,
## so `run_championship.gd` and the probe can use the same path without re-reading a file they
## just produced.
##
## `logPath` empty means no human log at all -- which is what a championship wants, since
## `ConsoleVisualAdapter` also prints every line it writes to stdout and a thousand battles of that
## is not a log, it is a wall.
## Splits `--flag=value` arguments out of the positional ones, so a brain override can be passed
## without pushing the optional output paths around. Unknown flags are refused rather than
## ignored: a mistyped flag that silently does nothing is how a fuzz run gets mistaken for a
## policy run.
static func parseFlags(args: Array) -> Dictionary:
	var parsed := {"positional": [], "brain": "", "brain_team": -1, "error": ""}
	for argument in args:
		var text := str(argument)
		if not text.begins_with("--"):
			parsed["positional"].append(text)
			continue
		if text.begins_with("--brain="):
			parsed["brain"] = text.substr("--brain=".length())
		elif text.begins_with("--brain-team="):
			parsed["brain_team"] = int(text.substr("--brain-team=".length()))
		else:
			parsed["error"] = "unknown flag %s" % text
	return parsed


static func run(
	scenarioPath: String, seedValue: int, recordPath: String, logPath: String,
	checkInvariants: bool = true, brainName: String = "", brainTeam: int = -1
) -> Dictionary:
	var loaded := BattleScenarioFactoryScript.loadFromPath(scenarioPath)
	if not loaded["success"]:
		return {"ok": false, "error": "could not load %s: %s" % [
			scenarioPath, str(loaded.get("error", "")),
		]}
	var scenario: BattleScenario = loaded["scenario"]

	for party in scenario.parties:
		if str(party.controller) == BattlePartyScript.CONTROLLER_PLAYER:
			return {"ok": false, "error": (
				"scenario %s has a player-controlled party (party %d) and cannot be simulated "
				+ "headlessly -- a console has nobody to choose. Use its cpu_cpu counterpart."
			) % [scenario.scenarioID, int(party.partyID)]}

	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = scenarioPath
	config.seed = seedValue
	var validation := config.validate()
	if not validation.success:
		return {"ok": false, "error": "invalid setup for %s at seed %d" % [scenarioPath, seedValue]}

	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		return {"ok": false, "error": "could not build state: %s" % str(stateResult.get("error", ""))}

	var sim = BattleSimulatorScript.new(seedValue)
	sim.configureHexState(stateResult["state"], scenario, {"scenarioPath": scenarioPath})
	# On by default here and in the championship: a console has nobody to notice that a unit
	# stood on two cells, so the check is the only reader of the board a headless run has.
	sim.setInvariantChecks(checkInvariants)
	# Before any adapter connects: rebuilding the runtime replaces the event bus they subscribe to.
	if not brainName.is_empty():
		sim.overrideBrains(brainName, brainTeam)

	# The console adapter takes the one `visualAdapter` slot; the recorder attaches to the same
	# event bus directly beside it. Neither knows about the other, and the slot is only consulted
	# by the replay-restore path, which this run never takes.
	if not logPath.is_empty():
		BattleOutputPathsScript.ensureParent(logPath)
		var console = ConsoleVisualAdapterScript.new(sim.state)
		console.logFile = logPath
		sim.setVisualAdapter(console)

	var recorder = RecordAdapterScript.new(sim)
	recorder.connectToEvents(sim.events)

	# Announces the starting board to both adapters before the loop opens -- the same call
	# `HexBattleController` makes, so a recorded battle and a played one begin identically.
	sim.emitInitialBoard()
	var sideRun := _runCpuSides(sim, MAX_ROUNDS)
	if not sideRun.get("ok", false):
		return sideRun
	var winner := int(sideRun["winner"])

	var line: String = recorder.recordLine(scenario)
	if not recordPath.is_empty():
		BattleOutputPathsScript.ensureParent(recordPath)
		var file := FileAccess.open(recordPath, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "error": "could not write %s" % recordPath}
		file.store_line(line)
		file.close()

	var record: Dictionary = recorder.buildRecord(scenario)
	var outcome: Dictionary = record.get("outcome", {})
	return {
		"ok": true,
		"line": line,
		"winner_team": winner,
		"invariant_violations": sim.invariantViolations(),
		# Passed through from the record so a caller never reads winner_team 0 as a team.
		"draw": bool(outcome.get("draw", false)),
		"end_reason": str(outcome.get("end_reason", "")),
		"rounds": int(outcome.get("rounds", 0)),
		"decisions": int(outcome.get("decisions", 0)),
		"scenario_id": str(scenario.scenarioID),
		"seed": seedValue,
		"side_turns": int(sideRun["side_turns"]),
		"mean_side_deliberation_ms": float(sideRun["mean_side_deliberation_ms"]),
		"max_side_deliberation_ms": float(sideRun["max_side_deliberation_ms"]),
	}


static func _runCpuSides(sim: BattleSimulator, maxRounds: int) -> Dictionary:
	sim.startBattle()
	var sideTimes: Array[float] = []
	while sim.state.battleOutcome == -1:
		if (
			sim.state.roundCount >= maxRounds
			and sim.state.activeSideID == -1
			and sim.state.pendingSideIDs.is_empty()
		):
			sim.state.add_event("round_end", -1, -1, {"round": sim.state.roundCount})
			sim.events.round_ended.emit(sim.state.roundCount)
			break
		var opened := sim.startNextSideTurn("headless_cpu")
		if not opened["success"]:
			if opened["reason"] in ["battle_ended", "round_complete"]:
				continue
			return {"ok": false, "error": "could not open CPU side: %s" % opened["reason"]}
		var deliberationUsec := 0
		while sim.state.activeSideID != -1 and sim.state.battleOutcome == -1:
			var started := Time.get_ticks_usec()
			var proposal = sim.beginSideDeliberation().run(32)
			deliberationUsec += Time.get_ticks_usec() - started
			if proposal == null:
				var ended := sim.endSideTurn("cpu_no_proposal")
				if not ended["success"]:
					return {"ok": false, "error": "CPU side stalled: %s" % ended["reason"]}
				break
			var selection := sim.selectUnit(proposal.actor_id, "headless_cpu")
			if not selection["success"]:
				return {"ok": false, "error": "CPU selected invalid unit: %s" % selection["reason"]}
			var result := sim.executeCommand(proposal.actor_id, proposal.command, "headless_cpu")
			if not result.success:
				return {"ok": false, "error": "CPU command rejected: %s" % result.reason}
		sideTimes.append(float(deliberationUsec) / 1000.0)
	if sim.state.battleOutcome == -1:
		sim.state.battleOutcome = sim._determineWinnerByNumbers()
		sim.events.battle_ended.emit(sim.state.battleOutcome)
	var total := 0.0
	var maximum := 0.0
	for elapsed: float in sideTimes:
		total += elapsed
		maximum = maxf(maximum, elapsed)
	return {
		"ok": true,
		"winner": sim.state.battleOutcome,
		"side_turns": sideTimes.size(),
		"mean_side_deliberation_ms": total / float(maxi(1, sideTimes.size())),
		"max_side_deliberation_ms": maximum,
	}
