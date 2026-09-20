## One canonical command on a detached state. Timings are diagnostics only;
## policy selection must use deterministic samples and fixed work counts.
class_name BattleForecast
extends RefCounted

const SerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const SimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const ResultScript = preload("res://src/battle_sim/BattleForecastResult.gd")

const DEBUG_EXACT := "debug_exact"
const POLICY_SAMPLE := "policy_sample"
const HORIZON := "one_command"

static func evaluate(simulator: BattleSimulator, actorID: int,
		command: BattleCommand, mode: String = POLICY_SAMPLE,
		sampleID: int = 0) -> ResultScript:
	var forecast: ResultScript = ResultScript.new()
	forecast.actor_id = actorID
	forecast.sample_id = sampleID
	forecast.rng_mode = mode
	if mode not in [DEBUG_EXACT, POLICY_SAMPLE]:
		forecast.reason = "unsupported_rng_mode"
		return forecast
	if simulator == null or command == null:
		forecast.reason = "missing_input"
		return forecast
	var startUsec := Time.get_ticks_usec()
	var exact := mode == DEBUG_EXACT
	var stateData: Dictionary = SerializerScript.serializeForForecast(
		simulator.state, exact)
	var clonedEvents: int = stateData.get("history", []).size()
	var copiedBytes := JSON.stringify(stateData).to_utf8_buffer().size()
	var fork: BattleSimulator = SimulatorScript.new(simulator.state.battleSeed)
	fork.state = SerializerScript.deserialize(stateData)
	if not exact:
		# Identity is explicit and independent of candidate enumeration order,
		# worker completion order, and the hidden live gameplay RNG.
		fork.state.rng.seed = hash([
			simulator.state.battleSeed, simulator.state.roundCount,
			simulator.state.sideTurnCount, simulator.state.activeSideID,
			actorID, sampleID, simulator.state.contentFingerprint,
		])
	fork._rebuildRuntimeDependencies()
	var before: Dictionary = SerializerScript.serializeCore(fork.state)
	var historyStart := fork.state.history.size()
	var forkUsec := Time.get_ticks_usec() - startUsec
	var resolveStart := Time.get_ticks_usec()
	if fork.state.currentMonsterID != actorID:
		var selected := fork.selectUnit(actorID, "forecast")
		if not bool(selected.get("success", false)):
			forecast.reason = str(selected.get("reason", "selection_rejected"))
			forecast.cost = _cost(copiedBytes, clonedEvents, forkUsec,
				Time.get_ticks_usec() - resolveStart)
			return forecast
	var result := fork.executeCommand(actorID, command, "forecast")
	forecast.accepted = result.success
	forecast.resolved = result.resolved
	forecast.reason = result.reason
	forecast.command_result = SerializerScript.jsonSafe(result.to_dictionary())
	forecast.events.assign(SerializerScript.jsonSafe(
		fork.state.history.slice(historyStart)))
	_diff(before, SerializerScript.serializeCore(fork.state), "", forecast.changes)
	forecast.cost = _cost(copiedBytes, clonedEvents, forkUsec,
		Time.get_ticks_usec() - resolveStart)
	return forecast


static func _cost(bytes: int, clonedEvents: int, forkUsec: int,
		resolveUsec: int) -> Dictionary:
	return {"copied_bytes": bytes, "copied_history_events": clonedEvents,
		"fork_usec": forkUsec, "resolve_usec": resolveUsec}


static func _diff(before, after, path: String,
		out: Array[Dictionary]) -> void:
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key in after:
			if not keys.has(key):
				keys.append(key)
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys:
			var child := "%s/%s" % [path, str(key)]
			if not before.has(key) or not after.has(key):
				out.append({"path": child,
					"before": before.get(key), "after": after.get(key)})
			else:
				_diff(before[key], after[key], child, out)
		return
	if before is Array and after is Array:
		for index in range(maxi(before.size(), after.size())):
			var child := "%s/%d" % [path, index]
			if index >= before.size() or index >= after.size():
				out.append({"path": child,
					"before": before[index] if index < before.size() else null,
					"after": after[index] if index < after.size() else null})
			else:
				_diff(before[index], after[index], child, out)
		return
	if before != after:
		out.append({"path": path, "before": before, "after": after})
