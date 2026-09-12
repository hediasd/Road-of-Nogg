extends SceneTree

## FHB-5: runs one scenario across a range of seeds and writes one corpus plus one summary.
##
##     Godot_v4.4-stable_win64.exe --headless --path . --script scripts/battle/run_championship.gd \
##         -- <scenarioPath> <firstSeed> <count> [recordPath] [summaryPath]
##
## The corpus is the same JSONL `run_battle.gd` writes, appended battle by battle -- same schema,
## same writer, no second format. See that file's note for why line-delimited rather than a
## directory of files.
##
## DELIBERATELY NOT A SCHEDULER. One loop, one process, seeds in order. Parallelism, resumption,
## matchmaking and pairing policies are all real things a championship eventually wants, and all of
## them are cheaper to add once the record schema has survived contact with an actual learner --
## building them now would be committing to a shape before the thing that consumes it exists.
##
## THE SUMMARY IS A RUN REPORT, NOT TRAINING DATA, and it is the one output here that is
## deliberately NOT deterministic: it carries wall-clock durations, which are the whole point of
## having it. The corpus lines beside it are byte-identical across runs at the same seeds --
## `probe_battle_runner.gd` asserts exactly that, and asserts it on the corpus rather than on this.
##
## NO HUMAN LOG PER BATTLE. `ConsoleVisualAdapter` prints every line it writes, so a thousand
## battles of prose is not a log. Run one seed through `run_battle.gd` when a battle needs reading.

const RunBattleScript = preload("res://scripts/battle/run_battle.gd")

const DEFAULT_ROOT := "user://battles"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: run_championship.gd -- <scenarioPath> <firstSeed> <count> [recordPath] [summaryPath]")
		quit(1)
		return

	var scenarioPath: String = args[0]
	var firstSeed := int(args[1])
	var count := int(args[2])
	if count < 1:
		printerr("HEX_CHAMPIONSHIP_FAILED: count must be at least 1")
		quit(1)
		return

	var stem := "%s_%d_x%d" % [scenarioPath.get_file().get_basename(), firstSeed, count]
	var recordPath: String = args[3] if args.size() > 3 else "%s/%s.jsonl" % [DEFAULT_ROOT, stem]
	var summaryPath: String = args[4] if args.size() > 4 else "%s/%s.summary.json" % [DEFAULT_ROOT, stem]

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(recordPath.get_base_dir())
	)
	var corpus := FileAccess.open(recordPath, FileAccess.WRITE)
	if corpus == null:
		printerr("HEX_CHAMPIONSHIP_FAILED: could not write %s" % recordPath)
		quit(1)
		return

	var battles: Array = []
	var winners: Dictionary = {}
	var totalRounds := 0
	var totalDecisions := 0
	var startedAt := Time.get_ticks_msec()

	for offset in range(count):
		var seedValue := firstSeed + offset
		var battleStarted := Time.get_ticks_msec()
		# Record path empty: this loop owns the corpus file and appends the line itself, rather
		# than having each battle open, write and close a file of its own.
		var result := RunBattleScript.run(scenarioPath, seedValue, "", "")
		if not bool(result.get("ok", false)):
			corpus.close()
			printerr("HEX_CHAMPIONSHIP_FAILED: seed %d: %s" % [seedValue, str(result.get("error", ""))])
			quit(1)
			return
		corpus.store_line(str(result["line"]))
		var winnerTeam := int(result["winner_team"])
		winners[winnerTeam] = int(winners.get(winnerTeam, 0)) + 1
		totalRounds += int(result["rounds"])
		totalDecisions += int(result["decisions"])
		battles.append({
			"seed": seedValue,
			"winner_team": winnerTeam,
			"rounds": int(result["rounds"]),
			"decisions": int(result["decisions"]),
			"elapsed_ms": Time.get_ticks_msec() - battleStarted,
		})
		print("seed %d -> team %d in %d round(s)" % [seedValue, winnerTeam, int(result["rounds"])])

	corpus.close()
	var elapsed := Time.get_ticks_msec() - startedAt

	var winnerSummary: Dictionary = {}
	for team in winners:
		winnerSummary[str(team)] = winners[team]

	var summary := {
		"scenario": scenarioPath,
		"first_seed": firstSeed,
		"count": count,
		"corpus": recordPath,
		"winners": winnerSummary,
		"distinct_outcomes": winners.size(),
		"mean_rounds": float(totalRounds) / float(count),
		"mean_decisions": float(totalDecisions) / float(count),
		"elapsed_ms": elapsed,
		"battles": battles,
	}
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(summaryPath.get_base_dir())
	)
	var summaryFile := FileAccess.open(summaryPath, FileAccess.WRITE)
	if summaryFile == null:
		printerr("HEX_CHAMPIONSHIP_FAILED: could not write %s" % summaryPath)
		quit(1)
		return
	summaryFile.store_line(JSON.stringify(summary, "\t", true))
	summaryFile.close()

	print("wrote %s" % recordPath)
	print("wrote %s" % summaryPath)
	print("%d battle(s) in %d ms; winners %s" % [count, elapsed, str(winnerSummary)])
	print("HEX_CHAMPIONSHIP_OK %s" % stem)
	quit(0)
