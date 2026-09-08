## The gate between the simulation running ahead and the screen catching up, and the single place
## that decides whether the battle may take another step.
##
## WHY A SEPARATE OBJECT. The failure this item names is "duplicate end-turn calls ... or input
## into a stale party", and every version of that failure is two things believing they own the
## schedule -- a timer that fires while a drain callback is also resuming, an input handler that
## starts a member's turn while CPU deliberation is mid-flight. Making the gate one object with
## one boolean answer means there is somewhere to put that rule, rather than the same three
## conditions being re-checked slightly differently at four call sites.
##
## IT OWNS NO TIMER AND STARTS NOTHING. It answers `canAdvance()` and it records who currently
## holds the schedule. The controller is what acts; this is what it asks.

class_name HexBattlePlayback
extends RefCounted

## Nobody holds the schedule; the controller may start the next thing.
const OWNER_NONE := ""
## A party activation is open and a member is mid-turn under player control.
const OWNER_PLAYER := "player"
## CPU deliberation is in flight for a member.
const OWNER_CPU := "cpu"
## The battle has ended; nothing may start.
const OWNER_FINISHED := "finished"

## How far the simulation may outrun playback before it stops queueing more. Without a bound a
## paused or slow queue would run the battle to its end and overflow, discarding exactly the
## animations someone paused to watch.
const RUN_AHEAD_LIMIT := 180

var _owner := OWNER_NONE
var _ownerMemberID := -1
var _adapter: IPlayerTurnVisualAdapter


func _init(adapter: IPlayerTurnVisualAdapter) -> void:
	_adapter = adapter


func owner() -> String:
	return _owner


func ownerMemberID() -> int:
	return _ownerMemberID


func isIdle() -> bool:
	return _owner == OWNER_NONE


func isFinished() -> bool:
	return _owner == OWNER_FINISHED


## Claims the schedule. Refuses rather than overwrites when someone already holds it -- an
## overwrite is precisely how two turns end up running at once, and a refusal is visible where a
## silent replacement is not.
func claim(newOwner: String, memberID: int = -1) -> bool:
	if _owner != OWNER_NONE and _owner != OWNER_FINISHED:
		return false
	if _owner == OWNER_FINISHED:
		return false
	_owner = newOwner
	_ownerMemberID = memberID
	return true


## Releases the schedule. Only the holder may release it, so a stale callback arriving after the
## battle moved on cannot open the gate for something that is no longer current.
func release(expectedOwner: String, memberID: int = -1) -> bool:
	if _owner != expectedOwner:
		return false
	if memberID != -1 and _ownerMemberID != memberID:
		return false
	_owner = OWNER_NONE
	_ownerMemberID = -1
	return true


## Ends the battle for scheduling purposes. Deliberately one-way: nothing after this can claim.
func finish() -> void:
	_owner = OWNER_FINISHED
	_ownerMemberID = -1


## Whether the controller may start the next member or activation right now.
##
## Three independent reasons not to, and all three have to be false: someone holds the schedule,
## the battle is over, or playback is too far behind. The backpressure check is a count rather
## than "is busy", because waiting for a fully drained queue between every member would make the
## battle play at the speed of its animations rather than merely be watchable.
func canAdvance() -> bool:
	if _owner != OWNER_NONE:
		return false
	if _adapter == null:
		return true
	return _adapter.queuedAnimationCount() < RUN_AHEAD_LIMIT


## Whether the screen has finished everything queued. What a party boundary waits for, so a new
## activation does not open over the previous one's last animation.
func isDrained() -> bool:
	if _adapter == null:
		return true
	return not _adapter.isAnimationBusy() and _adapter.queuedAnimationCount() == 0
