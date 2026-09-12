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

const DEFAULT_SEED := 42
const MAX_ROUNDS := 30


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: run_battle.gd -- <scenarioPath> [seed] [recordPath] [logPath]")
		quit(1)
		return

	var scenarioPath: String = args[0]
	var seedValue := int(args[1]) if args.size() > 1 else DEFAULT_SEED
	var stem := "%s_seed%d" % [scenarioPath.get_file().get_basename(), seedValue]
	var recordPath: String = args[2] if args.size() > 2 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.BATTLES, "%s.jsonl" % stem)
	var logPath: String = args[3] if args.size() > 3 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.BATTLES, "%s.log.txt" % stem)

	var result := run(scenarioPath, seedValue, recordPath, logPath)
	if not bool(result.get("ok", false)):
		printerr("HEX_BATTLE_RUN_FAILED: %s" % str(result.get("error", "")))
		quit(1)
		return

	print("wrote %s" % recordPath)
	print("wrote %s" % logPath)
	print("winner team %d after %d round(s), %d decision(s)" % [
		int(result["winner_team"]), int(result["rounds"]), int(result["decisions"]),
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
static func run(
	scenarioPath: String, seedValue: int, recordPath: String, logPath: String
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
	var winner: int = sim.runFullBattle(MAX_ROUNDS)

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
		"rounds": int(outcome.get("rounds", 0)),
		"decisions": int(outcome.get("decisions", 0)),
		"scenario_id": str(scenario.scenarioID),
		"seed": seedValue,
	}
