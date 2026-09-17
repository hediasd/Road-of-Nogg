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
const BattleOutputPathsScript = preload("res://src/presentation/BattleOutputPaths.gd")


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
	var recordPath: String = args[3] if args.size() > 3 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.CHAMPIONSHIPS, "%s.jsonl" % stem)
	var summaryPath: String = args[4] if args.size() > 4 else BattleOutputPathsScript.pathFor(BattleOutputPathsScript.CHAMPIONSHIPS, "%s.summary.json" % stem)

	BattleOutputPathsScript.ensureParent(recordPath)
	var corpus := FileAccess.open(recordPath, FileAccess.WRITE)
	if corpus == null:
		printerr("HEX_CHAMPIONSHIP_FAILED: could not write %s" % recordPath)
		quit(1)
		return

	var battles: Array = []
	var winners: Dictionary = {}
	var endReasons: Dictionary = {}
	var totalRounds := 0
	var totalDecisions := 0
	var totalSideTurns := 0
	var totalSideDeliberationMsec := 0.0
	var maxSideDeliberationMsec := 0.0
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
		# A violated invariant stops the run rather than adding another line. Every finished
		# battle before it is already flushed and keeps its place in the corpus; what must not
		# happen is a thousand more records produced from a state the rules say is impossible.
		var violations: Array = result.get("invariant_violations", [])
		if not violations.is_empty():
			corpus.store_line(str(result["line"]))
			corpus.flush()
			corpus.close()
			for violation in violations:
				printerr("BATTLE_INVARIANT_VIOLATION: %s" % str(violation))
			printerr("HEX_CHAMPIONSHIP_FAILED: seed %d violated %d invariant(s) after %d battle(s); corpus kept at %s" % [
				seedValue, violations.size(), offset, recordPath,
			])
			quit(1)
			return
		corpus.store_line(str(result["line"]))
		# Flushed per battle so a run that dies partway really does leave every completed line
		# on disk, as the corpus format promises. FHB-6 found it did not: twenty minutes into a
		# twenty-seed run the file held seven whole lines and half of an eighth.
		corpus.flush()
		var winnerTeam := int(result["winner_team"])
		var isDraw := bool(result["draw"])
		var endReason := str(result["end_reason"])
		# A draw is winner_team 0, which is no team. Tallied under "draw" so the summary never
		# reads it as a win for a team "0" (FHB-6 second pass).
		var outcomeKey := "draw" if isDraw else str(winnerTeam)
		winners[outcomeKey] = int(winners.get(outcomeKey, 0)) + 1
		endReasons[endReason] = int(endReasons.get(endReason, 0)) + 1
		totalRounds += int(result["rounds"])
		totalDecisions += int(result["decisions"])
		totalSideTurns += int(result["side_turns"])
		totalSideDeliberationMsec += float(result["mean_side_deliberation_ms"]) \
			* float(result["side_turns"])
		maxSideDeliberationMsec = maxf(
			maxSideDeliberationMsec, float(result["max_side_deliberation_ms"]))
		battles.append({
			"seed": seedValue,
			"winner_team": winnerTeam,
			"draw": isDraw,
			"end_reason": endReason,
			"rounds": int(result["rounds"]),
			"decisions": int(result["decisions"]),
			"side_turns": int(result["side_turns"]),
			"mean_side_deliberation_ms": float(result["mean_side_deliberation_ms"]),
			"max_side_deliberation_ms": float(result["max_side_deliberation_ms"]),
			"elapsed_ms": Time.get_ticks_msec() - battleStarted,
		})
		print("seed %d -> %s by %s in %d round(s)" % [
			seedValue, "draw" if isDraw else "team %d" % winnerTeam, endReason, int(result["rounds"]),
		])

	corpus.close()
	var elapsed := Time.get_ticks_msec() - startedAt

	var summary := {
		"scenario": scenarioPath,
		"first_seed": firstSeed,
		"count": count,
		"corpus": recordPath,
		"winners": winners,
		"end_reasons": endReasons,
		"distinct_outcomes": winners.size(),
		"mean_rounds": float(totalRounds) / float(count),
		"mean_decisions": float(totalDecisions) / float(count),
		"mean_side_deliberation_ms": totalSideDeliberationMsec / float(maxi(1, totalSideTurns)),
		"max_side_deliberation_ms": maxSideDeliberationMsec,
		"elapsed_ms": elapsed,
		"battles": battles,
	}
	BattleOutputPathsScript.ensureParent(summaryPath)
	var summaryFile := FileAccess.open(summaryPath, FileAccess.WRITE)
	if summaryFile == null:
		printerr("HEX_CHAMPIONSHIP_FAILED: could not write %s" % summaryPath)
		quit(1)
		return
	summaryFile.store_line(JSON.stringify(summary, "\t", true))
	summaryFile.close()

	print("wrote %s" % recordPath)
	print("wrote %s" % summaryPath)
	print("%d battle(s) in %d ms; winners %s; end reasons %s" % [count, elapsed, str(winners), str(endReasons)])
	print("HEX_CHAMPIONSHIP_OK %s" % stem)
	quit(0)
