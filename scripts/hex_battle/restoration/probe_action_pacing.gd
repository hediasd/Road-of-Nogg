## Proves the queue owns a complete paced action rather than starting the next visual the instant
## its owner's motion tween reaches the last keyframe.
##
## The sequence is deliberately MOVE -> BUMP -> MESSAGE. MOVE must be slowed and settle; BUMP
## must recover; MESSAGE must receive no automatic delay. Using real tweens also proves the queue's
## finished signal observes the appended tail rather than only the owner's original interval.
extends SceneTree

const VisualActionQueueScript = preload("res://src/presentation/VisualActionQueue.gd")
const VisualActionScript = preload("res://src/presentation/VisualAction.gd")

const MOVE_OWNER_DURATION := 0.16
const OTHER_OWNER_DURATION := 0.08
const TOLERANCE_SECONDS := 0.035
const WAIT_TIMEOUT_MSEC := 4000

var failures: Array[String] = []


class ProbeHarness:
	extends RefCounted
	var queue
	var node: Node
	var starts: Dictionary = {}
	var finishes: Dictionary = {}

	func start_action(action) -> bool:
		starts[action.kind_name()] = Time.get_ticks_msec()
		var duration := MOVE_OWNER_DURATION \
			if action.kind == VisualActionScript.Kind.MOVE else OTHER_OWNER_DURATION
		var tween := node.create_tween()
		tween.tween_interval(duration)
		queue.activate(tween, action, duration)
		return true

	func finalize_action(action) -> void:
		finishes[action.kind_name()] = Time.get_ticks_msec()

	func recover_state() -> void:
		pass


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var node := Node.new()
	root.add_child(node)
	var harness := ProbeHarness.new()
	harness.node = node
	var treeProvider := func(): return self
	harness.queue = VisualActionQueueScript.new(
		harness.start_action, harness.finalize_action, harness.recover_state, treeProvider)

	var move = VisualActionScript.new(VisualActionScript.Kind.MOVE)
	move.path = [Vector2i.ZERO]
	harness.queue.enqueue(move)
	harness.queue.enqueue(VisualActionScript.new(VisualActionScript.Kind.BUMP))
	harness.queue.enqueue(VisualActionScript.new(VisualActionScript.Kind.MESSAGE))

	var bound := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	while harness.queue.isBusy() and Time.get_ticks_msec() < bound:
		await process_frame
	_require(not harness.queue.isBusy(), "paced queue did not drain")
	_checkGap(harness, "move", "bump",
		(MOVE_OWNER_DURATION + VisualActionQueueScript.MOVE_SETTLE_SECONDS)
		/ VisualActionQueueScript.MOVE_PLAYBACK_SCALE)
	_checkGap(harness, "bump", "message",
		OTHER_OWNER_DURATION + VisualActionQueueScript.STRIKE_RECOVERY_SECONDS)
	_require(harness.starts.has("message") and harness.finishes.has("message"),
		"message did not run")
	if harness.starts.has("message") and harness.finishes.has("message"):
		var messageElapsed := _elapsed(
			int(harness.starts["message"]), int(harness.finishes["message"]))
		_require(messageElapsed < OTHER_OWNER_DURATION + TOLERANCE_SECONDS,
			"message inherited an automatic pacing tail (%.3fs)" % messageElapsed)

	harness.queue.dispose()
	node.queue_free()
	_finish()


func _checkGap(harness: ProbeHarness, earlier: String, later: String, minimum: float) -> void:
	_require(harness.starts.has(earlier), "%s did not start" % earlier)
	_require(harness.starts.has(later), "%s did not start" % later)
	if not harness.starts.has(earlier) or not harness.starts.has(later):
		return
	var elapsed := _elapsed(int(harness.starts[earlier]), int(harness.starts[later]))
	_require(elapsed + TOLERANCE_SECONDS >= minimum,
		"%s -> %s began after %.3fs, expected at least %.3fs"
		% [earlier, later, elapsed, minimum])


func _elapsed(startMsec: int, endMsec: int) -> float:
	return float(endMsec - startMsec) / 1000.0


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("HPR_ACTION_PACING_OK")
		quit(0)
		return
	for failure in failures:
		printerr("HPR_ACTION_PACING_FAILURE: %s" % failure)
	quit(1)
