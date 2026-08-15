## IPlayerTurnVisualAdapter — the narrow visual contract an *interactive* turn
## needs, layered on top of the general IBattleVisualAdapter event surface.
##
## IBattleVisualAdapter is enough to *watch* a battle: it observes events and
## draws them. Driving a player turn needs more — the controller has to know
## when the animation queue is busy, own and release the cursor, and paint
## movement/target overlays. Those are the only additions declared here.
##
## ConsoleVisualAdapter deliberately does not implement this: it is
## non-interactive, and a console battle never enters a player turn.
##
## The drain signal lives here rather than on the general adapter because
## waiting for the queue to empty is an interaction concern. Implementations
## inherit it and must not redeclare it — a redeclared signal is a *different*
## signal, and a controller connected to the parent's would never fire.
class_name IPlayerTurnVisualAdapter
extends IBattleVisualAdapter

## Emitted when the visual queue empties. The player-turn controller waits on
## this before reopening the command menu, so a phase never resolves under a
## still-playing animation.
signal animation_queue_drained


## True while the visual queue still has work to play.
func isAnimationBusy() -> bool:
	return false


## Move the player's selection cursor to a board coordinate.
func show_player_cursor(_coord: Vector2i) -> void: pass


## Move the targeting cursor to a board coordinate.
func show_target_cursor(_coord: Vector2i) -> void: pass


## Show the status panel for the monster under the targeting cursor; -1 clears.
func show_target_status(_monsterID: int) -> void: pass


## Give the cursor back to the scene controller at the end of a player turn.
func release_player_cursor() -> void: pass


## Paint reachable movement tiles, optionally with the path to the hovered tile.
## Attackable tiles are the union of basic-attack targets from every reachable
## destination; the adapter keeps that second tint out of reachable tiles.
func show_movement_options(
		_reachable: Array,
		_path: Array = [],
		_attackable: Array = []) -> void: pass


## Paint the union of tiles threatened by living enemies. This is a separate
## layer so holding the threat key cannot destroy the player's current aim.
func show_threat_options(_threatened: Array) -> void: pass


## Remove only the held threat overlay, leaving the current movement/target
## overlay intact for the player's phase.
func clear_threat_options() -> void: pass


## Paint the reach of the unit under the pointer — where it can move, and what
## it could strike from there. A third independent layer for the same reason
## the threat overlay is a second one: inspecting a unit is additive over the
## player's current aim and must never destroy it.
func show_hover_reach(_reachable: Array, _attackable: Array = []) -> void: pass


## Remove only the hover reach overlay.
func clear_hover_reach() -> void: pass


## Paint legal target tiles plus the area a confirmed action would affect.
func show_target_options(
		_targetPositions: Array,
		_affectedPositions: Array = [],
		_beneficial: bool = false) -> void: pass


## Remove every movement/target overlay.
func clear_tactical_overlays() -> void: pass
