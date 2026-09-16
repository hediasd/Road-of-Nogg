## FHB-14: a paused action finalizes when its tween actually finishes, not when a watchdog armed
## before the pause happens to expire.
##
## Drives VisualActionQueue directly with a real Tween on a scratch Node, in real time. No battle
## is needed: the queue's owner-supplied callables are the only surface it talks through.
##
## Cases:
##   1  pause: a 2s tween is paused at 0.5s for 1.2s, then resumed. The action must finalize no
##      earlier than 3.1s after start. Finalizing earlier means the pre-pause watchdog, not the
##      tween's own finish, closed it out.
##   2  killed tween: a tween is killed from outside the queue (no `finished` signal will ever
##      fire). The watchdog must still finalize the action.
extends SceneTree

const VisualActionQueueScript = preload("res://src/presentation/VisualActionQueue.gd")
const VisualActionScript = preload("res://src/presentation/VisualAction.gd")

## Real-time bound per wait. Watchdog timing is timer-driven, so a frame count would mean nothing.
const WAIT_TIMEOUT_MSEC := 8000

var failures: Array[String] = []


## Bundles the queue with the scratch Tween it drives, so the three owner-supplied callables
## the queue calls back into can reach both without relying on closures over not-yet-assigned
## locals (GDScript lambdas capture locals by value at creation time).
class ProbeHarness:
	extends RefCounted
	var queue
	var node: Node
	var duration: float = 0.0
	var tween: Tween
	var finalize_count: int = 0
	var finalize_time_msec: int = -1

	func start_action(action) -> bool:
		tween = node.create_tween()
		tween.tween_interval(duration)
		queue.activate(tween, action, duration)
		return true

	func finalize_action(_action) -> void:
		finalize_count += 1
		finalize_time_msec = Time.get_ticks_msec()

	func recover_state() -> void:
		pass


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	await _casePause()
	await _caseKilledTween()
	_finish()


func _makeHarness(duration: float) -> ProbeHarness:
	var node := Node.new()
	root.add_child(node)
	var harness := ProbeHarness.new()
	harness.node = node
	harness.duration = duration
	var treeProvider := func(): return self
	harness.queue = VisualActionQueueScript.new(
		harness.start_action, harness.finalize_action, harness.recover_state, treeProvider)
	return harness


func _waitUntilElapsed(startMsec: int, targetSeconds: float) -> void:
	var targetMsec := startMsec + int(targetSeconds * 1000.0)
	while Time.get_ticks_msec() < targetMsec:
		await process_frame


func _waitForFinalize(harness: ProbeHarness, startMsec: int) -> bool:
	var boundMsec := startMsec + WAIT_TIMEOUT_MSEC
	while harness.finalize_count == 0 and Time.get_ticks_msec() < boundMsec:
		await process_frame
	return harness.finalize_count > 0


# --- 1: pause -----------------------------------------------------------------

func _casePause() -> void:
	var harness := _makeHarness(2.0)
	var action = VisualActionScript.new(VisualActionScript.Kind.MESSAGE)
	var startMsec := Time.get_ticks_msec()
	harness.queue.enqueue(action)

	await _waitUntilElapsed(startMsec, 0.5)
	harness.queue.setPaused(true)
	await _waitUntilElapsed(startMsec, 0.5 + 1.2)
	harness.queue.setPaused(false)

	if not await _waitForFinalize(harness, startMsec):
		failures.append("pause case: action never finalized within %.1fs"
			% (WAIT_TIMEOUT_MSEC / 1000.0))
		harness.node.queue_free()
		return
	var elapsedSeconds := (harness.finalize_time_msec - startMsec) / 1000.0
	if elapsedSeconds < 3.1:
		failures.append(
			("pause case: action finalized at %.2fs, expected no earlier than 3.1s " +
			"(the pre-pause watchdog cut it short instead of the tween finishing)")
			% elapsedSeconds)
	if harness.finalize_count != 1:
		failures.append("pause case: action finalized %d times, expected exactly 1"
			% harness.finalize_count)
	harness.node.queue_free()


# --- 2: killed tween ------------------------------------------------------------

func _caseKilledTween() -> void:
	var harness := _makeHarness(0.5)
	var action = VisualActionScript.new(VisualActionScript.Kind.MESSAGE)
	var startMsec := Time.get_ticks_msec()
	harness.queue.enqueue(action)
	await process_frame
	harness.tween.kill()

	if not await _waitForFinalize(harness, startMsec):
		failures.append("killed-tween case: the watchdog never finalized the action")
		harness.node.queue_free()
		return
	if harness.finalize_count != 1:
		failures.append("killed-tween case: action finalized %d times, expected exactly 1"
			% harness.finalize_count)
	harness.node.queue_free()


# --- reporting -------------------------------------------------------------

func _finish() -> void:
	if failures.is_empty():
		print("HPR_QUEUE_PAUSE_OK")
		quit(0)
		return
	for failure in failures:
		printerr("HPR_QUEUE_PAUSE_FAILURE: %s" % failure)
	quit(1)
