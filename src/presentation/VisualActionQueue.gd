## VisualActionQueue — Owns the FIFO of pending visual actions, the tween
## currently playing, and the watchdog that recovers a stalled one.
##
## Extracted from GodotVisualAdapter. The queue was already a distinct
## conceptual unit with its own invariants — docs/LEARNINGS.md treats it as
## one — but it shared a file with event handling, mesh construction, and
## cursor wiring, so those invariants were easy to break by accident while
## editing something unrelated.
##
## The invariants this class exists to hold:
##
## - Exactly one action animates at a time; the rest wait in order.
## - Every activated tween completes exactly once. A tween that never fires its
##   `finished` signal is recovered by a watchdog timer instead of wedging the
##   queue forever, and the serial number makes the losing path a no-op rather
##   than a double completion.
## - A queue that overflows drops to authoritative state rather than growing
##   without bound.
## - After disposal nothing schedules further work.
##
## Owner-supplied callables keep this class free of any knowledge of monsters,
## meshes, or the board: it schedules opaque action dictionaries.

class_name VisualActionQueue
extends RefCounted

## Emitted when the queue empties and nothing is animating.
signal drained

const MAX_QUEUED_ACTIONS := 4096
const WATCHDOG_MARGIN := 0.75

## (action: Dictionary) -> bool — begin the action; return true if it activated
## a tween (via activate()) and false if it resolved instantly, in which case
## the queue moves straight on to the next action.
var _startAction: Callable
## (action: Dictionary) -> void — snap whatever the action was animating to its
## final state. Runs on normal completion, watchdog recovery, and overflow.
var _finalizeAction: Callable
## () -> void — re-derive visuals from authoritative state after a recovery.
var _recoverState: Callable
## () -> SceneTree — supplies the tree used for watchdog timers; may return null
## once the owner has left the tree.
var _treeProvider: Callable

var _queue: Array = []
var _isAnimating: bool = false
var _tween: Tween
var _activeAction: Dictionary = {}
## Bumped on every activation, recovery, and disposal so that a late `finished`
## signal or watchdog timeout from a superseded tween is ignored.
var _serial: int = 0
var _disposed: bool = false

var _paused: bool = false
var _watchdogDuration: float = 0.0

func _init(
		startAction: Callable,
		finalizeAction: Callable,
		recoverState: Callable,
		treeProvider: Callable) -> void:
	_startAction = startAction
	_finalizeAction = finalizeAction
	_recoverState = recoverState
	_treeProvider = treeProvider


func isBusy() -> bool:
	return _isAnimating or not _queue.is_empty()


func activeActionKind() -> String:
	return str(_activeAction.get("kind", ""))


func queuedCount() -> int:
	return _queue.size()


func isPaused() -> bool:
	return _paused


func setPaused(paused: bool) -> void:
	## Freezes playback without touching the simulation. Deliberately does NOT
	## bump `_serial`: the active tween's `finished` connection is bound to the
	## serial it was activated with, and that connection is the only one that
	## ever fires. Invalidating it here would leave every resumed action to be
	## finished by the watchdog instead — a driver-visible three-quarter-second
	## stall plus a spurious "stalled action" warning on every resume.
	if _disposed or _paused == paused:
		return
	_paused = paused
	if _isAnimating and _tween != null and _tween.is_valid():
		if _paused:
			_tween.pause()
		else:
			_tween.play()
			# The watchdog armed at activation has very likely already come and
			# gone during the pause, refused by the guard in _complete(). Arm a
			# fresh one under the same serial so a tween that cannot finish —
			# one killed from outside, which still reports is_valid() — is still
			# recovered rather than wedging the queue.
			_armWatchdog(_serial)
	if not _paused and not _isAnimating:
		startNext()


func _armWatchdog(serial: int) -> void:
	var tree: SceneTree = _treeProvider.call()
	if tree and not _paused:
		tree.create_timer(_watchdogDuration).timeout.connect(
			_complete.bind(serial, true),
			CONNECT_ONE_SHOT
		)

func enqueue(action: Dictionary) -> void:
	if _disposed:
		return
	if _queue.size() >= MAX_QUEUED_ACTIONS:
		push_error("Visual animation queue overflow; recovering to authoritative positions.")
		recover()
	_queue.append(action.duplicate(true))
	startNext()


func startNext() -> void:
	if _disposed or _paused or _isAnimating:
		return
	while not _queue.is_empty():
		var action: Dictionary = _queue.pop_front()
		if _startAction.call(action):
			return
	drained.emit()


func activate(tween: Tween, action: Dictionary, duration: float) -> void:
	## Called by the owner's start handler once it has built a tween for the
	## action. Arms both completion paths: the tween's own `finished` signal and
	## a watchdog timer sized to the expected duration plus a margin.
	_isAnimating = true
	_tween = tween
	_activeAction = action
	_serial += 1
	var serial := _serial
	tween.finished.connect(_complete.bind(serial, false), CONNECT_ONE_SHOT)
	_watchdogDuration = duration + WATCHDOG_MARGIN
	_armWatchdog(serial)


func recover() -> void:
	## Abandons the in-flight action and everything queued behind it, then hands
	## back to the owner to re-derive visuals from authoritative state.
	_serial += 1
	var interrupted := _activeAction
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not interrupted.is_empty():
		_finalizeAction.call(interrupted)
	_queue.clear()
	_isAnimating = false
	_tween = null
	_activeAction = {}
	_recoverState.call()


func dispose() -> void:
	_disposed = true
	_serial += 1
	_queue.clear()
	_isAnimating = false
	_activeAction = {}
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _complete(serial: int, timedOut: bool) -> void:
	## The single completion path. `serial` makes whichever of the two racing
	## sources arrives second a no-op instead of finalizing the action twice.
	if _disposed or not _isAnimating or serial != _serial:
		return
	# Load-bearing, not defensive: pause deliberately leaves the serial alone,
	# so the watchdog armed before the pause still matches and would otherwise
	# finalize an action the player has deliberately frozen mid-frame.
	if timedOut and _paused:
		return
	var completed := _activeAction
	if timedOut:
		push_warning("Visual animation watchdog recovered a stalled %s action." % completed.get("kind", "unknown"))
		if _tween != null and _tween.is_valid():
			_tween.kill()
	_finalizeAction.call(completed)
	_isAnimating = false
	_tween = null
	_activeAction = {}
	## Deferred so a completion that fires mid-frame does not start the next
	## action inside the previous one's signal emission.
	startNext.call_deferred()
