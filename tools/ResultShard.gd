## One worker's output file, and how several of them become one result set.
##
## Each worker owns a shard and appends one line per finished attempt, flushing
## as it goes. A process that dies mid-write therefore leaves a file whose last
## line may be half a row -- which is recovered by dropping that line, never by
## guessing at it, and never by discarding the whole shard.
##
## Two separations do the real work here:
##
## - **Deterministic bytes and timing live apart.** A row's `result` is the part
##   that must be identical across runs, worker counts and machines; how long it
##   took and which host ran it go in `telemetry` beside it. Merging compares
##   the former and keeps the latter, so a slow machine cannot make an
##   experiment look non-reproducible.
## - **Failures stay visible after a retry.** A crashed attempt is a row, and it
##   is still a row after the retry succeeds. Dropping it would hide exactly the
##   matches that were hardest to finish, and those are never a random sample of
##   the matches being measured.

class_name ResultShard
extends RefCounted

## How a match ended. Kept distinct because a watchdog kill and a lost battle
## are not the same event, and a tally that merges them is measuring the
## machine as much as the policy.
const END_ELIMINATION := "elimination"
const END_DRAW := "draw"
const END_ROUND_CAP := "round_cap"
const END_ILLEGAL_COMMAND := "illegal_command"
const END_INVARIANT := "invariant_violation"
const END_CRASH := "crash"
const END_TIMEOUT := "timeout"
const INFRASTRUCTURE_FAILURES: Array[String] = [END_CRASH, END_TIMEOUT]


static func shardPath(outputDirectory: String, shardIndex: int) -> String:
	return "%s/shard_%02d.jsonl" % [outputDirectory.rstrip("/"), shardIndex]


static func mergedPath(outputDirectory: String) -> String:
	return "%s/results.jsonl" % outputDirectory.rstrip("/")


## Appends one row and flushes it. Opened and closed per row on purpose: a
## worker that is killed between matches must leave every earlier row on disk.
static func append(path: String, row: Dictionary) -> bool:
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
		else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(JSON.stringify(row, "", true))
	file.close()
	return true


## Reads a shard, dropping a trailing partial line rather than failing on it.
## Returns the rows plus what was dropped, because a caller resuming a run needs
## to know that the last attempt did not finish.
static func read(path: String) -> Dictionary:
	var rows: Array[Dictionary] = []
	var recovered := 0
	if not FileAccess.file_exists(path):
		return {"rows": rows, "recovered_partial_lines": recovered}
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n", false)
	## A JSON instance rather than JSON.parse_string: recovering a half-written
	## line is the expected case here, and the static helper reports failure by
	## printing an engine error, which would make every successful recovery look
	## in the logs like something had gone wrong.
	var reader := JSON.new()
	for index in range(lines.size()):
		var parsed = null
		if reader.parse(lines[index]) == OK:
			parsed = reader.data
		if parsed is Dictionary and parsed.has("match_id"):
			rows.append(parsed)
			continue
		## Anything unreadable is only forgivable as the final line, where a
		## killed process is the ordinary explanation. Earlier in the file it is
		## corruption, and pretending otherwise would silently drop results.
		if index == lines.size() - 1:
			recovered += 1
			continue
		rows.append({"match_id": "", "corrupt_line": index})
	return {"rows": rows, "recovered_partial_lines": recovered}


## Rewrites a shard containing only its complete rows.
##
## A resumed worker must do this before it appends anything. A process killed
## mid-write leaves a file whose last line has no newline, so appending to it
## joins the new row onto the broken one and destroys both -- the recovered
## attempt is lost and the retry is unreadable, which shows up much later as a
## match that simply went missing from a run nobody thought had failed.
static func compact(path: String, rows: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	for rowValue in rows:
		var row: Dictionary = rowValue
		if str(row.get("match_id", "")).is_empty():
			continue
		file.store_line(JSON.stringify(row, "", true))
	file.close()
	return true


## Which matches a resume may skip: those with a successful attempt already on
## disk. A match whose only attempts failed is retried, and its failed rows stay.
static func completedMatchIDs(rows: Array) -> Dictionary:
	var completed: Dictionary = {}
	for rowValue in rows:
		var row: Dictionary = rowValue
		if str(row.get("match_id", "")).is_empty():
			continue
		if INFRASTRUCTURE_FAILURES.has(str(row.get("end_reason", ""))):
			continue
		completed[str(row["match_id"])] = true
	return completed


## Merges shards into one file in canonical match order, keeping the last
## successful attempt per match and every failed attempt beside it.
##
## A match that somehow has two *successful* attempts is a defect, not something
## to average: it means a resume double-counted, and the merge says so rather
## than quietly picking one.
static func merge(shardPaths: Array, orderedMatchIDs: Array) -> Dictionary:
	var successes: Dictionary = {}
	var duplicates: Array[String] = []
	var failures: Array[Dictionary] = []
	var corrupt := 0
	var recovered := 0
	for pathValue in shardPaths:
		var shard := read(str(pathValue))
		recovered += int(shard["recovered_partial_lines"])
		for rowValue in shard["rows"]:
			var row: Dictionary = rowValue
			var matchIdentifier := str(row.get("match_id", ""))
			if matchIdentifier.is_empty():
				corrupt += 1
				continue
			if INFRASTRUCTURE_FAILURES.has(str(row.get("end_reason", ""))):
				failures.append(row)
				continue
			if successes.has(matchIdentifier):
				if not duplicates.has(matchIdentifier):
					duplicates.append(matchIdentifier)
				continue
			successes[matchIdentifier] = row
	var ordered: Array[Dictionary] = []
	var missing: Array[String] = []
	for matchIdentifierValue in orderedMatchIDs:
		var matchIdentifier := str(matchIdentifierValue)
		if successes.has(matchIdentifier):
			ordered.append(successes[matchIdentifier])
		else:
			missing.append(matchIdentifier)
	return {
		"rows": ordered,
		"failures": failures,
		"duplicate_match_ids": duplicates,
		"missing_match_ids": missing,
		"corrupt_rows": corrupt,
		"recovered_partial_lines": recovered,
	}


## The bytes that must be identical across runs: everything except how long it
## took and where it ran.
static func deterministicBytes(rows: Array) -> String:
	var stripped: Array = []
	for rowValue in rows:
		var row: Dictionary = (rowValue as Dictionary).duplicate(true)
		row.erase("telemetry")
		row.erase("attempt_id")
		stripped.append(row)
	return JSON.stringify(stripped, "", true)
