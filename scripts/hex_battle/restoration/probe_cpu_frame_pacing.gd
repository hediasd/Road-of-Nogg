## Regression gate for the interactive CPU/render boundary.
##
## Total decision time is deliberately not the assertion: a brain may think for seconds. This
## samples the real HexBattleController while both sides are CPU-driven and asserts that no one
## render frame inherits that work. Before the worker split this exact 900-frame sample reached
## 824 ms, with CPU-thinking frames at 508 ms p95.

extends SceneTree

const ControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const SCENARIO := "res://data/battle/scenarios/hexmap_cpu_cpu.json"
const SEED := 14
const SAMPLE_FRAMES := 900
const THIRTY_FPS_FRAME_MSEC := 33.3

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller = ControllerScript.new()
	root.add_child(controller)
	await process_frame
	var started: Dictionary = controller.startBattle(SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "CPU battle did not start: %s" % str(started))
	if not _failures.is_empty():
		await _report(controller, [], [])
		return

	var gaps: Array[float] = []
	var thinkingGaps: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _index in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		var gap := float(now - previous) / 1000.0
		previous = now
		gaps.append(gap)
		if controller._deliberation != null:
			thinkingGaps.append(gap)

	gaps.sort()
	thinkingGaps.sort()
	_require(thinkingGaps.size() >= 100, "sample did not include sustained CPU deliberation")
	_require(gaps[-1] < THIRTY_FPS_FRAME_MSEC,
		"CPU deliberation blocked one frame for %.3f ms" % gaps[-1])
	await _report(controller, gaps, thinkingGaps)


func _report(controller, gaps: Array[float], thinkingGaps: Array[float]) -> void:
	if not gaps.is_empty():
		print("HXB_CPU_FRAME_PACING frames=%d thinking=%d median_ms=%.3f p95_ms=%.3f max_ms=%.3f thinking_p95_ms=%.3f" % [
			gaps.size(), thinkingGaps.size(), _percentile(gaps, 0.5),
			_percentile(gaps, 0.95), gaps[-1], _percentile(thinkingGaps, 0.95)])
	controller.teardownBattle()
	var cleanupFrames := 0
	while not controller._retiredDeliberationTaskIDs.is_empty() and cleanupFrames < 600:
		cleanupFrames += 1
		await process_frame
	_require(controller._retiredDeliberationTaskIDs.is_empty(),
		"retired CPU worker did not finish during teardown")
	controller.queue_free()
	await process_frame
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("HXB_CPU_FRAME_PACING_OK")
	quit(0)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(int((values.size() - 1) * fraction), 0, values.size() - 1)]


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
